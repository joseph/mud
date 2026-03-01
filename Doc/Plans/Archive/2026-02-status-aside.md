Status aside
===============================================================================

> Status: Complete


## Context

Our plan documents use a `> Status: ...` blockquote at the top to show project
state. Currently this renders as a plain blockquote. This change detects the
`> Status:` pattern and renders it as a styled callout with a deep orange
border and title colour, a pulse icon, and a unique title format where the
status value appears inline with "Status:", in bold.


## Detection

A third detection branch in `visitBlockQuote`, after GFM and DocC, before the
plain blockquote fallback:

1. Materialise `blockQuote.children` to `Array`.
2. Get the first child as `Paragraph`, then its first inline child as `Text`.
3. Check `text.string.hasPrefix("Status:")` (case-sensitive).
4. Extract the remainder after `"Status:"`, trimming leading spaces. This is
   the status value.
5. Require a non-empty status value. Bare `> Status:` falls through to plain
   blockquote.

Manual prefix detection (not `Aside`) avoids double-parsing — `detectDocCAlert`
already called `Aside` and rejected the blockquote because "Status" is not a
known `Aside.Kind`.


## Rendering

New `AlertCategory.status` case with its own icon (`alert-status.svg`, the
Octicon pulse icon) and deep orange colour (`#cf5400` light, `#ff6600` dark).

Single-line (`> Status: Planning`):

```html
<blockquote class="alert alert-status">
  <p class="alert-title"><svg …/>Status: <strong>Planning</strong></p>
</blockquote>
```

Multi-line (`> Status: In Progress\n> Detail text`):

```html
<blockquote class="alert alert-status">
  <p class="alert-title"><svg …/>Status: <strong>In Progress</strong></p>
  <p>Detail text</p>
</blockquote>
```

The `<strong>` status value is bold (700) but not coloured — a CSS rule resets
it to `--text-color`. The "Status:" label keeps the orange colour and semibold
weight (600) from `.alert-title`.


## Files changed

### `Core/Sources/Core/Rendering/UpHTMLVisitor.swift`

- **`AlertCategory`** — added `.status` case. Icon loaded from bundled
  `alert-status.svg`.
- **`visitBlockQuote`** — third branch using `.status` category.
- **`detectStatusAside(_:)`** — static method returning `String?`. Checks the
  first paragraph's first `Text` node for a `"Status:"` prefix.
- **`emitStatusTitle(_:)`** — emits the title paragraph with the status icon,
  `"Status: "`, and the value wrapped in `<strong>`.
- **`emitStatusContent(_:)`** — strips the first `Text` node, skips a following
  `SoftBreak`, visits remaining inlines and block children. Same pattern as
  `emitGFMAlertContent`.


### `Core/Sources/Core/Resources/alert-status.svg` (new)

Octicon pulse icon (MIT licensed). 16x16, `fill="currentColor"`.


### `Core/Sources/Core/Resources/mud-up.css`

- `--alert-status-border` and `--alert-status-title` custom properties
  (`#cf5400` light, `#ff6600` dark).
- `.alert-status` border rule and `.alert-status .alert-title` colour rule.
- `.alert-title strong` rule: resets `<strong>` inside titles to `--text-color`
  at `font-weight: 700`.


### `Core/Tests/Core/UpHTMLVisitorTests.swift`

Four new tests:

- `statusAsideSingleLine` — correct CSS class and bold status value in title.
- `statusAsideMultiLine` — continuation text in a separate `<p>`.
- `statusAsideMultiParagraph` — blank-line-separated content handled correctly.
- `statusWithoutValueIsPlainBlockquote` — bare `> Status:` falls through.


### `Doc/Examples/alerts.md`

Status asides section with three examples: single-line, multi-line, and
multi-paragraph.


### `Doc/AGENTS.md`

Updated `alert-*.svg` resource listing to include `status`.


## Files not modified

- **Theme CSS files** — `--text-color` is already defined by every theme.
  Themes can optionally override `--alert-status-*` variables.
- **`DownHTMLVisitor.swift`** — down mode shows raw source; no changes.


## Verification

1. Run unit tests — all four new tests and existing alert tests pass.
2. Open `Doc/Examples/alerts.md` in Mud — verify the Status asides have orange
   border, orange icon, orange "Status:" label, and bold default-colour value.
3. Toggle lighting — verify colours adapt to light and dark modes.
4. Toggle themes — verify `--text-color` renders correctly across all four.
5. Check a bare `> Status:` renders as a plain blockquote.
6. Check down mode — raw source unchanged.
