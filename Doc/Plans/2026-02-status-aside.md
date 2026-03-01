Status aside
===============================================================================

> Status: Planning


## Context

Our plan documents use a `> Status: ...` blockquote at the top to show project
state. Currently this renders as a plain blockquote. This change detects the
`> Status:` pattern and renders it as a styled callout using the same visual
treatment as the "Important" alert category (purple border, purple icon and
title color), with one unique characteristic: the status value appears inline
with the title, in bold.


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

Reuses `AlertCategory.important` for CSS class and icon. No new enum case, no
new icon, no new CSS colour variables.

Single-line (`> Status: Planning`):

```html
<blockquote class="alert alert-important">
  <p class="alert-title"><svg …/>Status: <strong>Planning</strong></p>
</blockquote>
```

Multi-line (`> Status: In Progress\n> Detail text`):

```html
<blockquote class="alert alert-important">
  <p class="alert-title"><svg …/>Status: <strong>In Progress</strong></p>
  <p>Detail text</p>
</blockquote>
```

The `<strong>` status value is bold (700) but not coloured — a small CSS
addition resets it to `--text-color`. The "Status:" label keeps the purple
colour and semibold weight (600) from `.alert-title`.


## Files changed

### `Core/Sources/Core/Rendering/UpHTMLVisitor.swift`

Four changes in the `// MARK: - Alerts` section:

1. **Update `visitBlockQuote`** — add a third branch between the DocC `else if`
   and the plain blockquote `else`:

   ```swift
   } else if let statusValue = Self.detectStatusAside(blockQuote) {
       emitAlertOpen(.important)
       emitStatusTitle(statusValue)
       emitStatusContent(blockQuote)
       result += "</blockquote>\n"
   } else {
   ```

2. **Add `detectStatusAside(_:)`** — static method returning `String?`. Checks
   the first paragraph's first `Text` node for a `"Status:"` prefix. Returns
   the trimmed status value, or `nil` if no match or empty value.

3. **Add `emitStatusTitle(_:)`** — emits the title paragraph with the important
   icon, the literal `"Status: "`, and the status value wrapped in `<strong>`.

4. **Add `emitStatusContent(_:)`** — strips the first `Text` node (which
   contains `"Status: Value"`), skips a following `SoftBreak`, then visits
   remaining inlines (as a `<p>`) and remaining block children. Follows the
   same pattern as `emitGFMAlertContent`.

   Three content scenarios:

   - **Single-line** — no remaining inlines, no remaining blocks. Nothing
     emitted.
   - **Same-paragraph continuation** — SoftBreak skipped, remaining inlines
     visited in a `<p>`.
   - **Blank-line separated** — first paragraph consumed entirely,
     `children.dropFirst()` handles subsequent paragraphs via `visit(child)`.


### `Core/Sources/Core/Resources/mud-up.css`

One rule added after line 190 (after the last `.alert-*` title colour rule):

```css
.alert-title strong {
    font-weight: 700;
    color: var(--text-color);
}
```

Resets `<strong>` inside `.alert-title` to default text colour. Without this,
the bold text would inherit the purple title colour. The explicit
`font-weight: 700` distinguishes it from the `.alert-title`'s 600 (semibold).

No other alert type currently emits `<strong>` inside `.alert-title`, so this
rule only affects Status asides today.


### `Core/Tests/Core/UpHTMLVisitorTests.swift`

Four new tests after the existing alert tests:

- `statusAsideSingleLine` — `> Status: Planning` renders with
  `alert alert-important` class and `Status: <strong>Planning</strong>` in the
  title.
- `statusAsideMultiLine` — continuation text appears in a separate `<p>`.
- `statusAsideMultiParagraph` — blank-line-separated content handled correctly.
- `statusWithoutValueIsPlainBlockquote` — bare `> Status:` falls through to
  plain blockquote.


### `Doc/Examples/alerts.md`

Add a "Status asides" section with three examples: single-line, multi-line
(same paragraph), and multi-paragraph (blank-line separated).


## Files not modified

- **`AlertCategory` enum** — no new case. Reuses `.important`.
- **SVG icons** — no new icon. Reuses `alert-important.svg`.
- **`mud-up.css` colour variables** — no new `--alert-status-*` variables.
- **Theme CSS files** — `--text-color` is already defined by every theme.
- **`DownHTMLVisitor.swift`** — down mode shows raw source; no changes.
- **`Doc/AGENTS.md`** — no new files added to the project.


## Verification

1. Run unit tests — all four new tests and existing alert tests pass.
2. Open `Doc/Examples/alerts.md` in Mud — verify the Status asides have purple
   border, purple icon, purple "Status:" label, and bold default-colour value.
3. Toggle lighting — verify colours adapt to light and dark modes.
4. Toggle themes — verify `--text-color` renders correctly across all four.
5. Check a bare `> Status:` renders as a plain blockquote.
6. Check down mode — raw source unchanged.
