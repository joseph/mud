Mermaid diagrams
===============================================================================

> Status: Complete


## Context

```` ```mermaid ```` fenced code blocks are a widely-used convention (supported
by GitHub, GitLab, etc.) for embedding diagrams in markdown. Currently these
render as plain code blocks. This change renders them as SVG diagrams in up
mode using the mermaid.js library.


## Approach

Pure client-side JS — no changes to `UpHTMLVisitor`. The visitor already emits
`<pre><code class="language-mermaid">...escaped code...</code></pre>` for
mermaid blocks (highlight.js returns nil for the unknown "mermaid" language,
falling back to HTML-escaped text). This HTML is good fallback for CLI output
and print/PDF.

A bundled mermaid.js library and a small init script are injected via
`evaluateJavaScript` after page load, only when the rendered HTML contains
`language-mermaid` code blocks. This bypasses the CSP `script-src 'none'`
restriction and avoids loading the ~2.8 MB library for documents without
mermaid diagrams.


## Files to create

**`Core/Sources/Core/Resources/mermaid.min.js`** — Download mermaid v11 (latest
stable) UMD build. Approximately 1.5–2 MB minified. Bundled automatically by
SPM's `.process("Resources")`.

**`Core/Sources/Core/Resources/mermaid-init.js`** — Renderer script:

- Context detection: exit early if `.up-mode-output` not found (no-op in down
  mode).
- Pick mermaid theme based on `prefers-color-scheme` (`default` for light,
  `dark` for dark).
- Find all `code.language-mermaid` elements, extract `textContent`, replace
  each `<pre>` parent with a `<div class="mermaid">` container.
- Call `mermaid.run({ nodes: containers })`.
- Uses `securityLevel: "strict"` and `startOnLoad: false`.


## Files to modify

**`Core/Sources/Core/Rendering/HTMLTemplate.swift`** — Add two public static
properties following the `mudJS`/ `mudUpJS`/ `mudDownJS` pattern:

- `mermaidJS` — loads `mermaid.min.js` from the bundle.
- `mermaidInitJS` — loads `mermaid-init.js` from the bundle.

**`App/WebView.swift`** — In the Coordinator, detect `language-mermaid` in the
HTML during `updateNSView` and inject mermaid.min.js + mermaid-init.js via
`evaluateJavaScript` in `didFinish` when needed.

**`Core/Sources/Core/Resources/mud-up.css`** — Add `.mermaid` container styles
(centering, `max-width: 100%` on SVGs, bottom margin).

**`Doc/AGENTS.md`** — Update the Resources section to list `mermaid.min.js` and
`mermaid-init.js`.


## Files not modified

- `UpHTMLVisitor.swift` — current fallback output is correct.
- `Package.swift` — `.process("Resources")` already picks up new files.
- `CodeHighlighter.swift` — returns nil for unknown "mermaid" language, which
  is the desired behavior.


## Known limitations (v1)

- Lighting changes mid-session don't update already-rendered SVGs until next
  file reload (Cmd+R or auto-reload).
- CLI output (`mud -u`) shows raw mermaid source in a code block (no JS
  runtime). Acceptable for v1.


## Verification

- `HTMLTemplateTests.swift` — `mermaidJSNotEmpty`, `mermaidInitJSNotEmpty`.
- `UpHTMLVisitorTests.swift` — `mermaidCodeBlockFallback` verifying the
  `<pre><code class="language-mermaid">` output.
- Manual: open a file with mermaid blocks, verify SVG rendering, toggle down
  mode (raw source), test with invalid syntax (graceful error).
