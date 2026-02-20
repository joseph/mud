Image embedding research: is `mud-asset:` necessary?
===============================================================================

We investigated whether the `mud-asset:` custom URL scheme is necessary for
loading local images in WKWebView, or whether setting `<base href>` to the
document's directory and using plain relative paths would suffice.

**Conclusion:** `mud-asset:` is necessary. It solves real WKWebView file-access
limitations, provides security benefits, and is essential for any future
sandboxed build.


## How `mud-asset:` works today

The pipeline for local images in web mode:

1. `UpHTMLVisitor` walks the Markdown AST. For each image node, it calls a
   `resolveImageSource` callback.
2. `DocumentContentView.mudAssetResolver` resolves the relative path against
   the document's base URL, validates the file extension against a whitelist
   (png, jpg, jpeg, gif, svg, webp), checks that the file exists, and returns a
   `mud-asset:///absolute/path` URL.
3. `HTMLTemplate.wrap()` emits a Content Security Policy restricting image
   sources to `mud-asset: data: https:`.
4. `WebView` loads the HTML via `loadHTMLString(_:baseURL:)`.
5. When WKWebView encounters a `mud-asset:` URL, the registered
   `LocalFileSchemeHandler` intercepts the request, reads the file from disk in
   the app's process, validates the extension, and serves the data with the
   correct MIME type.

For browser export ("Open in Browser"), a separate code path uses
`ImageDataURI.encode()` to convert local images to `data:` URIs instead.

Key files:

- `App/LocalFileSchemeHandler.swift` -- scheme handler
- `App/DocumentContentView.swift` -- `mudAssetResolver` callback
- `App/WebView.swift` -- WKWebView configuration and `loadHTMLString` call
- `Core/Rendering/UpHTMLVisitor.swift` -- `visitImage` applies the callback
- `Core/Rendering/HTMLTemplate.swift` -- CSP and `<base>` tag
- `Core/Rendering/ImageDataURI.swift` -- shared MIME whitelist, data-URI
  encoding, `isExternal` check


## WKWebView's local file access model

WKWebView offers three ways to load local content, each with different
file-access semantics:


### `loadHTMLString(_:baseURL:)` with a `file://` base URL

This is what Mud uses today. The base URL is set to the document's file URL.
However, WKWebView's out-of-process architecture means that the web content
process applies its own file-access restrictions independent of the host app.
`loadHTMLString` with a `file://` base URL does not reliably grant the web
content process access to sibling files (images, CSS, etc.) in the same
directory. This is a well-documented limitation — it works inconsistently
across platforms and macOS versions.


### `loadFileURL(_:allowingReadAccessTo:)`

This method loads an HTML file from disk and explicitly grants the web content
process read access to a specified directory. It is the most reliable way to
load local HTML with local assets. However, it requires writing the HTML to a
temporary file first (since Mud generates HTML in memory), and in a sandboxed
app the granted directory must be within the app's sandbox or covered by a
security-scoped bookmark.


### Custom URL scheme handler

A `WKURLSchemeHandler` registered via
`WKWebViewConfiguration.setURLSchemeHandler(_:forURLScheme:)` intercepts
requests for a custom scheme. The handler runs in the app's main process, not
the web content process, so it has full access to whatever files the app can
read. This is what `mud-asset:` implements.


## Non-sandboxed analysis

Mud is not currently sandboxed (no `com.apple.security.app-sandbox` in the
entitlements file). Even so, removing `mud-asset:` and relying on `<base href>`
alone would face two problems:

1. **`loadHTMLString` file access is unreliable.** The WKWebView web content
   process does not consistently resolve relative `file://` paths to local
   images, even when the base URL is a `file://` URL pointing at the document's
   directory. This has been reported across many projects and macOS versions.
2. **CSP would need to allow `file:`.** The current Content Security Policy
   restricts `img-src` to `mud-asset: data: https:`. To load images via
   `file://` paths, we would need to add `file:` to the CSP, which is a much
   broader grant — it would allow the page to load any local file as an image,
   not just whitelisted image types in the document's directory.


## Sandboxed analysis

If Mud were sandboxed (as the App Store build is), `mud-asset:` becomes
essential:

- **WKWebView runs out-of-process.** The web content process does not inherit
  the sandbox extensions that the app process receives when the user opens a
  file via NSOpenPanel or the Finder.
- **The scheme handler runs in the app process.** Because
  `LocalFileSchemeHandler` executes in the app's own process, it has access to
  files covered by sandbox extensions. It reads the image data and serves it to
  the web content process over the custom scheme.
- **`loadFileURL` has limited sandbox reach.** Even with
  `allowingReadAccessTo:` set to the document's parent directory, the sandbox
  extension may not cover that directory — it typically covers only the
  specific file the user selected.

The "Open in Browser" feature is also blocked by sandboxing. Mud writes the
exported HTML to its container's temp directory
(`~/Library/Containers/org.josephpearson.Mud/Data/tmp/`), but Safari is a
separate process with its own sandbox and cannot read from Mud's container.
Safari reports `NSURLErrorDomain:-3,001` ("Cannot open file"). Even if Mud
tried writing to the system `/tmp`, the sandbox would prevent that write in the
first place.

The existing `sandbox-limitations.md` guide documents the user-facing
implications. These are inherent to sandboxing — even `mud-asset:` cannot help
if the app process itself lacks permission to read the image files.


## Security benefits of `mud-asset:`

Beyond solving file-access problems, the custom scheme provides a security
boundary:

- **Extension whitelist.** Only files with recognized image extensions (png,
  jpg, jpeg, gif, svg, webp) are served. The whitelist is shared between
  `ImageDataURI.mimeTypes` and `LocalFileSchemeHandler`.
- **File-exists validation.** The `mudAssetResolver` checks that the file
  exists before rewriting the URL. Missing images get a clean 404 from the
  handler rather than a silent WKWebView failure.
- **Tight CSP.** The Content Security Policy allows `mud-asset:` but not
  `file:`, preventing the page from loading arbitrary local files. Scripts are
  blocked entirely (`script-src 'none'`); JavaScript runs only via
  `WKUserScript` injection.


## The only alternative that could work

If we switched from `loadHTMLString` to writing HTML to a temporary file and
loading it with `loadFileURL(_:allowingReadAccessTo: documentDirectory)`, the
web content process would gain explicit read access to the document's
directory. Relative image paths would then resolve directly, and `mud-asset:`
could be removed.

However, this would require:

- Temp file management (write HTML to disk, clean up on reload/close)
- Adding `file:` to the CSP, losing the extension-whitelist security boundary
- Accepting that sandboxed builds would still fail (the temp file approach
  doesn't help when the sandbox doesn't grant access to the image directory)

This is not worth pursuing. The current `mud-asset:` approach is cleaner, more
secure, and works in both sandboxed and non-sandboxed configurations (within
the limits of the sandbox itself).
