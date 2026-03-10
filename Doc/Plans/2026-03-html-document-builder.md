Plan: HTML Document Builder
===============================================================================

> Status: Underway


## Context

`HTMLTemplate.wrapUp` currently builds the final HTML document via a single
string interpolation. Every feature that conditionally adds scripts, modifies
CSP directives, or injects attributes must be interleaved into this one
expression. The `embedMermaid` code is a concrete example: it scatters logic
across CSP construction, script-tag generation, and body closing — all inside
the same interpolated string.

Meanwhile, `WebView.injectState` does its own post-processing on the finished
HTML string, replacing `<html>` with `<html class="..." style="...">` via
`String.replacingOccurrences(of:)`. This works but is fragile and conceptually
belongs in the same assembly step.

These are symptoms of the same problem: there is no structured intermediate
between "I have a rendered body" and "I have a complete HTML string." Each new
document-level concern (scripts, CSP sources, classes, attributes) has to be
woven directly into the template or hacked on after the fact.


## Design

### `HTMLDocument` — a structured intermediate

A lightweight value type that accumulates document-level concerns as data, then
serializes them in one `render()` method:

```swift
struct HTMLDocument {
    var title: String = ""
    var baseURL: URL? = nil
    var styles: [String] = []
    var cspImgSrc: [String] = ["mud-asset:", "data:"]
    var cspScriptSrc: [String] = []
    var htmlAttributes: [String: String] = [:]
    var bodyContent: String = ""
    var bodyScripts: [Script] = []

    enum Script {
        case inline(String)
        case src(String)
    }

    func render() -> String { ... }
}
```

`render()` is the only place that produces HTML. It assembles CSP from the
accumulated source arrays, concatenates styles, appends scripts before
`</body>`, and applies HTML-element attributes. All the string interpolation
lives in one small, stable method.


### How `wrapUp` and `wrapDown` change

They become thin builders that populate an `HTMLDocument` and call `render()`:

```swift
static func wrapUp(body: String, options: RenderOptions) -> String {
    var doc = HTMLDocument()
    doc.title = options.title
    doc.baseURL = options.baseURL
    doc.styles = [themeCSS(for: options.theme), sharedCSS, upCSS]
    doc.bodyContent = "<article class=\"up-mode-output\">\n\(body)\n</article>"

    if !options.blockRemoteContent {
        doc.cspImgSrc.append("https:")
    }

    if options.embedMermaid && body.contains("language-mermaid") {
        doc.cspScriptSrc.append(contentsOf: ["https://cdn.jsdelivr.net", "'unsafe-inline'"])
        doc.bodyScripts.append(.src(mermaidCDN))
        doc.bodyScripts.append(.inline(mermaidInitJS))
    }

    return doc.render()
}
```

Each concern is a clear, self-contained block. Adding a future feature (e.g.
KaTeX) means adding another block — no changes to the template string.


### `WebView.injectState` moves into the builder

View state injection (body classes, zoom) currently post-processes the HTML
string. With `HTMLDocument`, this can happen before rendering:

```swift
// In DocumentContentView or WebView, before render:
doc.htmlAttributes["class"] = bodyClasses.sorted().joined(separator: " ")
if zoomLevel != 1.0 {
    doc.htmlAttributes["style"] = "zoom: \(zoomLevel)"
}
```

Alternatively, if view-state injection must stay in the App layer (because
`HTMLDocument` lives in Core), the `htmlAttributes` field on `RenderOptions`
could carry these through. Or `injectState` could remain as a thin App-layer
method that modifies `HTMLDocument` before calling `render()`. The exact
boundary deserves consideration during implementation.


### Scope boundaries

`HTMLDocument` lives in Core alongside `HTMLTemplate`. It is an internal type —
not part of MudCore's public API. The public API remains the
`renderUpModeDocument` / `renderDownModeDocument` functions that return
`String`.


## Changes

### 1. Add `HTMLDocument` to Core

New file `Core/Sources/Core/Rendering/HTMLDocument.swift`. The struct and its
`render()` method.


### 2. Refactor `HTMLTemplate.wrapUp`

Replace the string interpolation with `HTMLDocument` builder pattern. The
mermaid embedding becomes a conditional block that appends to `bodyScripts` and
`cspScriptSrc`.


### 3. Refactor `HTMLTemplate.wrapDown`

Same pattern. Down mode has no scripts or CSP complexity today, but uses the
same `render()` path for consistency.


### 4. Evaluate `WebView.injectState`

Determine whether view-state injection (classes, zoom) should move into the
builder or remain as a post-processing step in the App layer. If it moves,
`RenderOptions` may gain `htmlClasses` and `zoomLevel` fields; if not,
`injectState` stays but operates on `HTMLDocument` attributes before `render()`
rather than doing string replacement after.


### 5. Update tests

`HTMLTemplateTests` assertions remain the same — they test the rendered output
string, not the intermediate. Some tests may benefit from testing
`HTMLDocument.render()` directly.


### 6. Update `Doc/AGENTS.md`

Add `HTMLDocument.swift` to the Core file reference.


## Files changed

| File                                             | Change                                  |
| ------------------------------------------------ | --------------------------------------- |
| `Core/Sources/Core/Rendering/HTMLDocument.swift` | New: structured HTML document builder   |
| `Core/Sources/Core/Rendering/HTMLTemplate.swift` | Refactor wrapUp/wrapDown to use builder |
| `Core/Tests/Core/HTMLTemplateTests.swift`        | Update or extend tests                  |
| `App/WebView.swift`                              | Possibly refactor `injectState`         |
| `Doc/AGENTS.md`                                  | Add file reference                      |


## What this does NOT change

- **MudCore's public API.** The `renderUpModeDocument` /
  `renderDownModeDocument` functions still accept `RenderOptions` and return
  `String`. `HTMLDocument` is an internal implementation detail.

- **WKWebView JS injection.** The in-app mermaid path (loading mermaid.min.js
  via `evaluateJavaScript` after page load) is unrelated to document assembly.
  It stays in `WebView.Coordinator`.

- **RenderOptions.** No fields added or removed.
