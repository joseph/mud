Plan: Code Block Copy Button
===============================================================================

> Status: Underway


## Goal

Add a "Copy" button to fenced code blocks in Up Mode, implemented as a
`RenderExtension` so it can be toggled independently. Also add an optional
header bar on code blocks showing the language name.

Both features are controlled by settings in the Up Mode settings pane.


## Design

### Header bar anatomy

When both "Code Block Headers" and "Copy Code" are on:

```
┌──────────────────────────────────────────┐
│  swift                          © Copy   │  ← header bar
├──────────────────────────────────────────┤
│  let x = 42                              │
│  print(x)                                │
└──────────────────────────────────────────┘
```

When "Code Block Headers" is off and "Copy Code" is on, the copy button floats
in the top-right corner of the code block:

```
┌──────────────────────────────────────────┐
│  let x = 42                     © Copy   │
│  print(x)                                │
└──────────────────────────────────────────┘
```

- The **copy icon** is the Octicon "copy" SVG (16×16). Label reads `Copy`.
- On hover over the `<pre>` element, the copy button fades in.
- On click, copies the text content of the `<code>` element to the clipboard,
  briefly changes label to `Copied!` with a check icon, then reverts.


### Two independent settings

| Setting            | Mechanism         | Default |
| ------------------ | ----------------- | ------- |
| Code Block Headers | `ViewToggle`      | On      |
| Copy Code          | `RenderExtension` | On      |

The header bar is purely CSS-driven (body class `is-code-header`). The copy
button is injected by JS. They are independent: any combination of on/off
works.


### Implementation layers

#### 1. HTML (`UpHTMLVisitor.swift`)

All code blocks emit `<pre class="mud-code">`. When a language is specified, a
header `<div>` is included:

```html
<pre class="mud-code">
  <div class="code-header">
    <span class="code-language">swift</span>
  </div>
  <code class="language-swift">…</code>
</pre>
```

Language-less code blocks have no header div:

```html
<pre class="mud-code">
  <code>…</code>
</pre>
```


#### 2. CSS (`mud-up.css`)

- `pre.mud-code` gets `position: relative` (needed for floating copy button).
- `.code-header` is `display: none` by default.
- `.is-code-header .code-header` overrides to `display: flex`.
- `.is-code-header pre.mud-code:has(> .code-header)` sets `padding-top: 0` (the
  header bar provides the visual spacing; language-less blocks keep normal
  padding).
- `.code-copy-btn` fades in on `pre.mud-code:hover`.
- `.code-copy-floating` absolutely positions the button in the top-right corner
  of the `<pre>`.


#### 3. JavaScript (`copy-code.js`)

A small runtime script that:

1. Queries all `pre.mud-code` elements.
2. Checks whether each block has a visible `.code-header`.
3. **Header visible:** appends the copy button to the header.
4. **Header hidden or absent:** appends the button directly to the `<pre>` with
   the `code-copy-floating` class.
5. On click, uses `navigator.clipboard.writeText()` with a
   `document.execCommand('copy')` fallback.


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


#### 5. ViewToggle (`ViewToggle.swift`)

New `codeHeader` case with class name `is-code-header`, defaulting to on. Uses
`UserDefaults.object(forKey:)` nil check to distinguish "never set" from
"explicitly off".


#### 6. Settings UI (`UpModeSettingsView.swift`)

A "Code Blocks" section in the Up Mode settings pane with two toggles:

- **Code Block Headers** — toggles `codeHeader` ViewToggle.
- **Copy Code** — toggles the `copyCode` extension.


## Open questions

1. ~~**Clipboard API availability**~~ — Resolved:
   `navigator.clipboard.writeText()` works in WKWebView.

2. ~~**Header bar revert plan**~~ — Resolved: both layouts are supported.

3. **Down Mode** — Deferred. Down Mode code blocks are the entire document (one
   big syntax-highlighted block), so a copy button doesn't make sense there in
   the same way. May revisit later.


## Sequence

All steps complete. Remaining work: final testing and commit.

1. ~~HTML: `UpHTMLVisitor` emits `<pre class="mud-code">` with header div~~
2. ~~CSS: header bar styles, floating copy button, visibility toggle~~
3. ~~JS: `copy-code.js` with header detection and fallback~~
4. ~~Extension: `RenderExtension.copyCode` registered~~
5. ~~ViewToggle: `codeHeader` case with default-on logic~~
6. ~~Settings: "Code Blocks" section with both toggles~~
7. ~~Bug fixes: `document.documentElement` class check, padding consistency,
   hidden-header button placement~~
8. ~~Rename: `Mud.setBodyClass` → `Mud.setClass`~~
