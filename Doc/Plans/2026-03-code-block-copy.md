Plan: Code Block Copy Button
===============================================================================

> Status: Planning


## Goal

Add a "Copy" button to fenced code blocks in Up Mode. The button sits in a
subtle header bar above the code block, with the language name on the left and
the copy button on the right. The header bar is always visible when a code
block has a language tag; the copy button appears only on hover.

Implement this as a `RenderExtension` so it can be toggled independently.


## Design

### Header bar anatomy

```
┌──────────────────────────────────────────┐
│  swift                          © Copy   │  ← header bar
├──────────────────────────────────────────┤
│  let x = 42                              │
│  print(x)                                │
└──────────────────────────────────────────┘
```

- The **header bar** is visible whenever the code block has a known language.
  For code blocks with no language, no header bar is shown (or an empty one —
  TBD during implementation).
- The **copy icon** is the Octicon "copy" SVG (16×16). Label reads `Copy`.
- On hover over the `<pre>` element, the copy button fades in.
- On click, the button copies the text content of the `<code>` element to the
  clipboard, briefly changes label to `Copied!`, then reverts.


### Why a RenderExtension?

The copy feature fits the existing `RenderExtension` pattern cleanly:

| Aspect             | How it maps                                       |
| ------------------ | ------------------------------------------------- |
| `name`             | `"copyCode"`                                      |
| `marker`           | `"mud-code"` (class on `<pre>` for code blocks)   |
| `cspSources`       | None needed — pure inline JS, no external scripts |
| `embeddedScripts`  | One `.inline(...)` script                         |
| `runtimeResources` | One JS file: `copy-code.js`                       |

The marker `mud-code` triggers inclusion only when the document actually
contains code blocks. `UpHTMLVisitor` adds a `class="mud-code"` to every
`<pre>` it emits for fenced/indented code, giving us a precise marker that
won't false-positive on `<pre>` tags in raw HTML blocks.


### Implementation layers

#### 1. CSS (`mud-up.css`)

Add styles for the header bar and copy button. Keep them in `mud-up.css` since
this is an Up Mode feature. Key style considerations:

- `pre.mud-code` needs `position: relative` and zero top-padding (the header
  bar occupies that space).
- Header bar: flex row, subtle background slightly different from code-bg,
  top-left and top-right border radii matching the `pre` element.
- Language label: small, muted text, lowercase.
- Copy button: transparent until `pre:hover`, then fades in. Cursor: pointer.
- "Copied!" state: brief green flash or check icon.

The header bar styles are **not** gated by the extension — they're part of the
base Up Mode styles. This means the language label is always visible regardless
of whether the copy extension is enabled. The copy button itself is injected
only by the JS extension.


#### 2. HTML changes (`UpHTMLVisitor.swift`)

Modify `visitCodeBlock` to emit a header bar `<div>` inside the `<pre>`, before
the `<code>` element:

```html
<pre class="mud-code">
  <div class="code-header">
    <span class="code-language">swift</span>
  </div>
  <code class="language-swift">…</code>
</pre>
```

For code blocks with no language:

```html
<pre class="mud-code">
  <code>…</code>
</pre>
```

No header `<div>` is emitted when there is no language. When the copy extension
is active, the JS inserts a header bar into language-less blocks too (so the
copy button has a place to land).


#### 3. JavaScript (`copy-code.js`)

A small runtime script that:

1. Queries all `pre.mud-code` elements.
2. For blocks without a `.code-header`, creates and prepends one.
3. Creates a button with the Octicon copy SVG and "Copy" label, appends it to
   each `.code-header`.
4. On click, reads `pre > code` text content, calls
   `navigator.clipboard.writeText()`, swaps label to "Copied!" with a check
   icon, and reverts after 2 seconds.

The SVG is embedded as a string literal in the JS file.


#### 4. Extension registration (`RenderExtension.swift`)

```swift
static let copyCode = RenderExtension(
    name: "copyCode",
    marker: "mud-code",
    cspSources: [],
    embeddedScripts: [.inline(copyCodeInitJS)],
    runtimeResources: ["copy-code"]
)
```

Add to the registry.


#### 5. App integration

- Add a `copyCode` toggle to `AppState` (persisted via UserDefaults),
  defaulting to **on**.
- Wire the toggle into `RenderOptions.extensions` alongside the existing
  Mermaid toggle.
- Add a checkbox to the Up Mode settings pane.


## Open questions

1. **Clipboard API availability** — `navigator.clipboard.writeText()` requires
   a secure context. WKWebView loads content via `about:blank` or file URLs.
   Need to verify this works. Fallback: `document.execCommand('copy')` with a
   temporary textarea (deprecated but universally supported).

2. **Header bar revert plan** — If the header bar feels clunky, the fallback is
   to remove it and position the copy button absolutely in the top-right corner
   of the `<pre>` element (simpler, more common pattern). The JS and extension
   plumbing would remain the same; only CSS and the emitted HTML change.

3. **Down Mode** — Deferred. Down Mode code blocks are the entire document (one
   big syntax-highlighted block), so a copy button doesn't make sense there in
   the same way. May revisit for per-line or per-block selection later.


## Sequence

1. CSS styles for header bar and copy button
2. `UpHTMLVisitor` changes to emit header bar HTML
3. `copy-code.js` runtime script
4. `RenderExtension.copyCode` registration
5. `AppState` toggle + settings UI + menu item
6. Test in app, iterate on styling
7. Decide on header bar vs. overlay based on feel
