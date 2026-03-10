Plan: Render Extensions
===============================================================================

> Status: Planning


## Context

Mermaid diagram support is currently hard-wired across three layers:

- **HTMLTemplate** — CDN URL constant, `embedMermaid` conditional in `wrapUp`
  that appends scripts and CSP sources, resource accessors for `mermaidJS` and
  `mermaidInitJS`.
- **WebView.Coordinator** — `needsMermaid` flag, `injectMermaid()` method that
  chains two `evaluateJavaScript` calls, detection via
  `html.contains("language-mermaid")`.
- **RenderOptions** — `embedMermaid: Bool` field.

Adding MathJax (or any future client-side library) would duplicate this exact
pattern: detect a marker in the HTML, conditionally inject scripts for
standalone export, and conditionally inject scripts at runtime in WKWebView.

This plan introduces a `RenderExtension` type that encapsulates the full
lifecycle of a client-side rendering feature, so that adding a new one means
defining an instance — not threading logic through three files.


## The pattern each extension follows

Every client-side rendering extension has the same shape:

1. **Detection** — is the feature's content present? (Check for a marker string
   in the rendered HTML body.)
2. **Embedded export** (CLI `--browser`, Open in Browser) — add `<script>` tags
   to the HTML document; update the CSP to allow them.
3. **Live rendering** (WKWebView) — inject JS resources via
   `evaluateJavaScript` after page load; scripts may need to be chained
   sequentially (each depends on the previous one being loaded).

A `RenderExtension` captures all three:

```swift
struct RenderExtension {
    let name: String
    let marker: String
    let cspSources: [String]
    let embeddedScripts: [HTMLDocument.Script]
    let runtimeResources: [String]  // resource names, loaded and injected in order
}
```

`runtimeResources` are _names_ of resources loaded via
`HTMLTemplate.loadResource`. This keeps the type value-friendly (no closures)
and lets both the Core embed path and the App runtime path reference the same
underlying files.


## Design question: where do extensions live?

Extensions reference bundled resources (`mermaid.min.js`, `mermaid-init.js`)
which live in Core's `Bundle.module`. They also need to be consumed by:

- **HTMLTemplate** (Core) — for embedded export, reading resource contents to
  inline or referencing CDN URLs.
- **WebView** (App) — for runtime injection, reading resource contents to pass
  to `evaluateJavaScript`.

Three options for where to define them:


### Option A: extensions defined in Core, accessed from App

Extensions are static properties on `RenderExtension`, defined in Core
alongside the resources they reference. `HTMLTemplate.loadResource` becomes
`internal` (or the extension stores pre-resolved resource content).

```swift
// Core/Sources/Core/RenderExtension.swift
extension RenderExtension {
    static let mermaid = RenderExtension(
        name: "mermaid",
        marker: "language-mermaid",
        cspSources: ["https://cdn.jsdelivr.net", "'unsafe-inline'"],
        embeddedScripts: [
            .src("https://cdn.jsdelivr.net/npm/mermaid@11.12.3/dist/mermaid.min.js"),
            .inline(HTMLTemplate.mermaidInitJS),
        ],
        runtimeResources: ["mermaid.min", "mermaid-init"]
    )
}
```

App's WebView looks up the runtime resources by name via a Core-provided method
(e.g. `HTMLTemplate.loadResource` made internal to the package, or a new
`RenderExtension.runtimeJS()` method that returns the loaded strings).

**Pros:** single source of truth in Core; App just iterates. **Cons:**
`loadResource` visibility needs adjusting; `embeddedScripts` eagerly captures
`mermaidInitJS` at definition time (fine since it's a static computed property,
but worth noting).


### Option B: extensions defined in App, resources loaded from Core

Extensions are defined in App where both WebView and HTMLTemplate are
accessible. Core exposes resource loading as a public API, and `HTMLDocument`/
`HTMLTemplate` accept extensions as parameters.

```swift
// App/RenderExtensions.swift
extension RenderExtension {
    static let mermaid = RenderExtension(
        name: "mermaid",
        marker: "language-mermaid",
        cspSources: ["https://cdn.jsdelivr.net", "'unsafe-inline'"],
        embeddedScripts: [
            .src("https://cdn.jsdelivr.net/npm/mermaid@11.12.3/dist/mermaid.min.js"),
            .inline(HTMLTemplate.mermaidInitJS),
        ],
        runtimeScripts: [HTMLTemplate.mermaidJS, HTMLTemplate.mermaidInitJS]
    )
}
```

Here `runtimeScripts` stores the actual JS strings (already loaded), since App
has access to `HTMLTemplate`'s public properties.

**Pros:** no visibility changes needed in Core; the App owns the full wiring.
**Cons:** extension definitions live far from the resources they reference; the
CLI target also needs access, so the definitions would need to be shared or
duplicated.


### Option C: `RenderExtension` type in Core, instances registered via `RenderOptions`

The type lives in Core. Instances are defined as static properties in Core
(like Option A). `RenderOptions` replaces `embedMermaid: Bool` with a richer
field:

```swift
public struct RenderOptions: Sendable, Equatable {
    // ...
    public var extensions: Set<String> = []  // extension names to enable
}
```

`RenderExtension` has a static registry:

```swift
public struct RenderExtension: Sendable {
    // ...
    public static let all: [String: RenderExtension] = [
        "mermaid": .mermaid,
        // future: "mathjax": .mathjax,
    ]
}
```

HTMLTemplate looks up active extensions from the registry by name. WebView does
the same. Neither needs to know the details — they just iterate.

**Pros:** clean separation; adding an extension is adding a static instance and
a registry entry; `RenderOptions` stays value-friendly (just a set of strings).
**Cons:** the registry is a bit of indirection; runtime resource loading needs
a method on `RenderExtension` that calls into `HTMLTemplate.loadResource`.

**Recommendation:** Option C. The registry gives both Core and App a single
lookup table. `RenderOptions.extensions` is a clean, extensible field. The
indirection is minimal and pays for itself when the second extension arrives.


## Proposed `RenderExtension` type (Option C)

```swift
public struct RenderExtension: Sendable {
    public let name: String
    public let marker: String
    public let cspSources: [String]
    public let embeddedScripts: [HTMLDocument.Script]
    let runtimeResources: [String]

    func runtimeJS() -> [String] {
        runtimeResources.compactMap { HTMLTemplate.loadResource($0, type: "js") }
    }

    static let mermaid = RenderExtension(
        name: "mermaid",
        marker: "language-mermaid",
        cspSources: ["https://cdn.jsdelivr.net", "'unsafe-inline'"],
        embeddedScripts: [
            .src("https://cdn.jsdelivr.net/npm/mermaid@11.12.3/dist/mermaid.min.js"),
            .inline(HTMLTemplate.mermaidInitJS),
        ],
        runtimeResources: ["mermaid.min", "mermaid-init"]
    )

    public static let registry: [String: RenderExtension] = [
        mermaid.name: mermaid,
    ]
}
```


## How each layer changes

### RenderOptions

```swift
// Replace:
public var embedMermaid: Bool = false

// With:
public var extensions: Set<String> = []
```

Call sites change from `opts.embedMermaid = true` to
`opts.extensions.insert("mermaid")`. `contentIdentity` includes the sorted
extension set.


### HTMLTemplate.wrapUp

The mermaid-specific conditional becomes a generic loop:

```swift
for name in options.extensions {
    guard let ext = RenderExtension.registry[name],
          body.contains(ext.marker) else { continue }
    doc.cspScriptSrc.append(contentsOf: ext.cspSources)
    doc.bodyScripts.append(contentsOf: ext.embeddedScripts)
}
```

The `mermaidCDN` constant and the mermaid-specific block in `wrapUp` are
removed.


### HTMLTemplate resource accessors

`loadResource` becomes `internal` (not `private`) so `RenderExtension` can call
it. The public `mermaidJS` and `mermaidInitJS` computed properties remain (used
by the `mermaid` extension definition and still useful for the WKWebView
runtime path until that's also generalized).


### WebView.Coordinator

The `needsMermaid` flag and `injectMermaid()` method are replaced by a generic
mechanism:

```swift
// In updateNSView:
context.coordinator.activeExtensions = RenderExtension.registry.values
    .filter { html.contains($0.marker) }

// In didFinish:
for ext in activeExtensions {
    injectExtension(ext, into: webView)
}
```

`injectExtension` chains the runtime JS calls sequentially:

```swift
private func injectExtension(_ ext: RenderExtension, into webView: WKWebView) {
    let scripts = ext.runtimeJS()
    injectSequentially(scripts, into: webView)
}

private func injectSequentially(_ scripts: [String], into webView: WKWebView) {
    guard let first = scripts.first else { return }
    webView.evaluateJavaScript(first) { _, _ in
        self.injectSequentially(Array(scripts.dropFirst()), into: webView)
    }
}
```


### DocumentContentView / CLI

`embedMermaid = true` becomes `extensions.insert("mermaid")` in the export
paths. The in-app path doesn't set extensions (WKWebView handles runtime
injection independently).


## Files changed

| File                                             | Change                                     |
| ------------------------------------------------ | ------------------------------------------ |
| `Core/Sources/Core/RenderExtension.swift`        | New: type, mermaid instance, registry      |
| `Core/Sources/Core/RenderOptions.swift`          | Replace `embedMermaid` with `extensions`   |
| `Core/Sources/Core/Rendering/HTMLTemplate.swift` | Generic extension loop; adjust visibility  |
| `App/WebView.swift`                              | Generic extension injection                |
| `App/DocumentContentView.swift`                  | `extensions.insert("mermaid")`             |
| `App/CLI/main.swift`                             | `extensions.insert("mermaid")`             |
| `Core/Tests/Core/HTMLTemplateTests.swift`        | Update mermaid tests to use extensions set |
| `Doc/AGENTS.md`                                  | Add file reference                         |


## Verification

- Mermaid rendering works identically in-app and in browser export.
- CLI `--browser` output includes mermaid scripts when mermaid blocks are
  present.
- Adding a hypothetical second extension (e.g. a test-only stub) requires only
  a new `RenderExtension` instance and a registry entry — no changes to
  HTMLTemplate, WebView, or RenderOptions.
