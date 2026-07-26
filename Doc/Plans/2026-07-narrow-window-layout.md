Plan: Narrow Window Layout
===============================================================================

> Status: Underway


## Context

Mud's layout has no width-based media queries at all. Every geometric constant
— content padding, list indents, table cell padding, the Down-mode line-number
gutter, the Comments column gutter — is sized for a comfortable desktop window
and applies unchanged at any width.

That is most visible in Quick Look. `MudPreviewProvider` is a _view-based_
`QLPreviewingController`, so Finder embeds it directly into the column-view
preview pane — which is often only ~250pt wide. In that pane today:

- `.up-mode-output { padding: 2em 2em 6em }` spends 64px on horizontal padding
  alone, a quarter of the width.
- A commented file reserves `--comment-column-gutter` (300px column + 24px
  margins) for the Comments column, leaving the document essentially no room.
  `MudCore.exportDocument(…, includeComments: true)` routes through
  `showingReadOnlyComments`, so every commented `.md` hits this.
- `h1 { font-size: 2em }` is 32px in a 250px pane; most headings wrap three or
  four times.
- Down mode gives line numbers a fixed `4em` gutter plus `1em` of content
  padding on each line.

The goal is to fit substantially more into a small viewport while the result
still reads as Mud — same themes, same background gradient, same heading rules
and colors, just tighter geometry and a compressed type scale. The rules are
plain viewport media queries, so a narrow app window benefits too; Quick Look
is the motivating case, not a special case.


## Approach

Add one new stylesheet, `Core/Sources/Resources/mud-narrow.css`, holding every
width-based override for both modes — the direct parallel of `mud-print.css`,
which already gathers every `@media print` rule into one file included last so
its rules win over the on-screen defaults.

Two breakpoints:

| Tier    | Query              | Target                          |
| ------- | ------------------ | ------------------------------- |
| Compact | `max-width: 700px` | Narrow app window; wide QL pane |
| Tight   | `max-width: 420px` | Finder column-view preview pane |


### Everything is scoped to `@media screen and (…)`

Not bare `@media (max-width: …)`. In print the media query evaluates against
the **page box**, and `mud-print.css` sets `@page { margin: 1.8cm }` — US
Letter comes out around 680 CSS px and A4 around 660. A bare `max-width: 700px`
would therefore fire on every printed page and silently shrink printed output.
`@media screen and (max-width: 700px)` cannot. This also matches the existing
`@media screen` scoping already used for the Comments column block in
`mud-comments.css`.

`mud-print.css` still loads last, so print continues to win outright.


### Compact tier (≤ 700px)

**Up mode** — `.up-mode-output` padding drops from `2em 2em 6em` to roughly
`1.25rem 1.25rem 4rem`. The bottom value stays generous enough to clear the
floating Changes bar (~50px tall, per `ChangesFeature.swift`). Code block
padding, list indents (`ul, ol`), blockquote padding, table cell padding, and
the frontmatter table/summary padding all tighten by roughly a third.

**Down mode** — `.ln` flex-basis 4em → ~2.75em with a smaller right pad, `.lc`
padding 1em → ~0.6em, and the first/last-line `padding-top: 2rem` /
`padding-bottom: 6rem` come down to ~1.25rem / ~4rem.

**Comments column collapses.** Below this width the column and its 324px gutter
are dropped and the bottom `<footer class="comments">` — the same one print
reveals — is shown instead, with the inline `💬` markers restored. The section
stands in for the column, so it answers to the same `is-comments-column`
toggle: Show Comments reveals it, Hide Comments takes it away. Revealing it on
width alone would leave Hide Comments looking broken here — the comments would
stay on screen with nothing left to switch off.

Rather than writing undo-rules against the visually-hidden marker (brittle: it
would have to restate `.mud-comment-marker`'s base padding/margin and go stale
the moment those change), the three `@media screen { … }` blocks in
`mud-comments.css` (marker hiding, gutter layout) and `mud-comments-edit.css`
(the column resize handle) gain an `and (min-width: 700.02px)` guard, so they
simply do not apply below the breakpoint. The `.02px` closes the sub-pixel gap
a fractional viewport width — browser zoom on an exported document — would
otherwise fall into. That leaves `mud-narrow.css` needing only:

- `#mud-comments-column { display: none }` — the element still exists in the
  DOM (`mud-comments.js` builds it), so it must be hidden explicitly.
- `html.is-comments-column .comments.is-print-only { display: block }` — reveal
  the bottom section, under the same toggle that governs the column.

All three files get a comment naming the shared 700px breakpoint and pointing
at the others. The placement pass keeps running against a hidden column, and
the marker hover/highlight listeners in `mud-comments.js` are registered
unconditionally on `container`, so hovering a restored marker still lights its
quotation.

**Quick Look opts out of the column entirely**, rather than relying on the
breakpoint. A preview pane is not the reader's to widen and carries no toggle,
so a column that appears or vanishes with the Finder window is the wrong
presentation at any size. `MudCore.exportDocument` gains `commentsColumn:`
(default `true`, so the browser / editor / CLI exports are unchanged) and
`MudPreviewProvider` passes `false`, which keeps the render on
`CommentMode.section`. That is stronger than a CSS rule: without `.interactive`
the document has neither the `comments-column` class nor the inlined column
script, so no column is ever built. Comments show as the bottom Comments
section with the inline `💬` markers visible — which is what `.section` mode has
always meant.


### Making room for the column

The column holds the compose box, so below the breakpoint every command that
needs it — Add Comment, Show Comments, and a marker click — has nothing to
show. All three route through `App/CommentColumnFit.swift` first, which makes
room rather than explaining that there isn't any:

| Situation                                | What happens                     |
| ---------------------------------------- | -------------------------------- |
| Content pane already over 700pt          | Proceed                          |
| The screen has room to grow              | Widen the window, no prompt      |
| Window already screen-wide, sidebar open | Ask: "Hide Sidebar" / "Continue" |
| Neither, or the user continues           | Scroll to the Comments section   |

Widening is silent because it isn't a decision — the window is the app's to
size, and the user just asked for content that needs the width. Collapsing the
sidebar does ask, since which panes are open is their own layout choice and
nothing about showing comments implies giving it up. The second button is
"Continue", not "Cancel": declining the sidebar doesn't mean dropping the
comments, it means reading them in the bottom section instead, which the
informative text says. Hiding the column never resizes anything back; once
widened, the window is the user's again.

The last row is why `WebCommand.scrollToComments` exists: below the breakpoint
the page shows the bottom Comments section in the column's place, so scrolling
there is the honest answer to "show me the comments" on a display that can't
fit a column. `mud-comments.js` gains `scrollToSection` for it, which takes an
optional label — a marker click named one comment, so the fallback lands on
that comment's `<li>` rather than on the top of the section.

The fallback also turns the toggle on, since the section is hidden without it.
`scrollToSection` sets the class in the page rather than waiting for the app's
class sync, the same way `openToComment` does — otherwise the scroll would
measure an element that is still `display: none`. `withRoomForComments` sets
`commentsColumnVisible` alongside it, so the toolbar reads "Hide Comments" and
a later sync doesn't take the section back down.

The marker click is the one entry point that used to open the column from JS.
It now posts its label over `mudRevealColumn` and waits: the window controller
makes room and calls back into `comments.openToComment`, or falls back. An
export has no app to ask and no window to widen, so it decides for itself,
reading the column's own width (below the Compact tier the column is
`display: none`, so its width is zero) rather than restating the breakpoint a
fourth time.

Both toolbar buttons that reach the column are disabled in Down mode, matching
the View menu item, so no entry point can widen a window for a column that mode
wouldn't draw.

Widening targets a 720pt content pane — comfortably past the breakpoint rather
than one point over it, so the document keeps a readable width beside the
column and a small later drag doesn't tip it straight back out. On a screen
that can't reach 720 it widens as far as it can, since anything over 700 opens
the column. In practice that means the prompt is rare: on any real display,
even with the sidebar at its 400pt maximum, there is room to widen.

The content split-view item hosts the WebView, so its width _is_ the page's CSS
viewport width — no SwiftUI plumbing needed to read it. The breakpoint itself
lives in `MudCore.Layout.compactBreakpoint`, since a media query can only be
written in CSS; a test reads `mud-narrow.css` and checks the two agree.

`CommentColumnFit.remedy` is a pure function of four widths so the branches are
testable as a truth table (`App/Tests/CommentColumnFitTests.swift`), following
`OpenInFormatTests`. The controller keeps a four-line `withRoomForComments`
helper; the geometry, the prompt and the remedies live in `CommentColumnFit`,
the way `CommentSubmissionHandler` holds the submit path.

Two enablement details left alone: the Add Comment button and menu item keep
their existing conditions (Up mode, writable document, commentable selection),
and Show Comments in Down mode records the preference without resizing a window
that would show nothing for it.


### Tight tier (≤ 420px)

Everything from Compact, plus:

- `html { font-size: 14px }` — roughly 40 characters per line in a 250px pane
  instead of 24.
- Compressed heading scale: `h1` 2em → 1.5em, `h2` 1.5em → 1.3em, `h3` 1.25em →
  1.15em, with `margin-top` 1.5em → ~1.2em. Heading rules, colors and the
  `border-bottom` on `h1`/`h2` are untouched — that is the Mud silhouette.
- Content padding down again to ~`0.9rem 0.9rem` horizontally.
- List/footnote/comment `ol` indents to ~1.25em; table cells to ~4px 6px.
- Frontmatter table: `th { width: 20% }` becomes `width: auto` and
  `white-space: normal` so a long key wraps instead of forcing the table wide.
- Down mode: `.ln` to ~2.25em with a smaller font-size, `.lc` padding ~0.4em.

Nothing here touches `.is-readable-column` (its `max-width: 800px` is inert
below the breakpoints), the table horizontal-scroll rule in `mud-up.css`
(already correct for narrow viewports), or
`img { max-width: min(800px, 100%) }`.


### Wiring it in

`Core/Sources/Rendering/HTMLTemplate.swift` gains a `narrowCSS` accessor
alongside `printCSS`, and both `wrapUp` and `wrapDown` append it **immediately
before** `printCSS` — after `upCSS`/`downCSS`/`commentsCSS`/`commentsEditCSS`/
`changesCSS`/`findCSS`/`mathCSS`, so it can override the base layout, and
before the print sheet, so print still wins.

`Core/Package.swift` needs no change — resources are declared as
`.process("Resources")`, a whole-directory rule, so a new file in that folder
is picked up automatically.


### Knock-on effect: the popover documents

`FootnoteHTMLRenderer` and `CommentHTMLRenderer.threadDocument` both build
their documents through `wrapUp` with `html.footnote-popover`, and
`FootnotePopover.swift` fixes the popover at **360px** wide. Those popovers
will therefore pick up the Tight tier: 14px root type and the compressed
heading scale. Their own `padding: 1.5em` is unaffected — the
`.footnote-popover .up-mode-output` selector outranks the bare
`.up-mode-output` rule regardless of order.

I think that is an improvement (more footnote body visible in the same clamped
popover height), and it is the consistent reading of "a narrow viewport is a
narrow viewport". If it looks wrong in practice, the escape hatch is one token
on two rules: scope the root font-size and heading block to
`html:not(.footnote-popover)`.


## Files

- `Core/Sources/Resources/mud-narrow.css` — **new.** Both tiers, both modes.
- `Core/Sources/Resources/mud-comments.css` — add `and (min-width: 700.02px)`
  to the two existing `@media screen` blocks; cross-reference comment.
- `Core/Sources/Resources/mud-comments-edit.css` — the same guard on the resize
  handle block.
- `Core/Sources/Rendering/HTMLTemplate.swift` — `narrowCSS` accessor; append in
  `wrapUp` and `wrapDown` before `printCSS`.
- `Core/Sources/Layout.swift` — **new.** `Layout.compactBreakpoint`, the one
  Swift-side statement of the CSS breakpoint.
- `App/CommentColumnFit.swift` — **new.** The fit check, the remedies, the
  sidebar prompt.
- `App/DocumentState.swift`, `App/WebView.swift`,
  `Core/Sources/Resources/mud-comments.js` — the `scrollToComments` and
  `revealComment` commands, and their `comments.scrollToSection` /
  `comments.openToComment` handlers.
- `App/MudJSBridge.swift`, `App/DocumentContentView.swift` — `mudRevealColumn`
  carries the clicked comment's label and routes to the window controller.
- `App/DocumentWindowController.swift` — `addComment`, `toggleCommentsColumn`
  and `revealComment` ask `CommentColumnFit` first; the Comments-column toolbar
  button disables itself in Down mode.
- `App/Tests/CommentColumnFitTests.swift` — **new.** The `remedy` truth table.
- `Core/Tests/HTMLTemplateTests.swift` — the tests below.
- `Doc/AGENTS.md` — add `mud-narrow.css` to the Resources list (the file
  quick-reference is required to stay in sync).


## Tests

Add to `Core/Tests/HTMLTemplateTests.swift`, following the
`findStylesLiveViewOnly` pattern:

- Narrow styles are present in both `wrapUp` and `wrapDown`, and in exports
  (`standalone = true`) as well as the live view — unlike the Find styles,
  these are unconditional.
- The narrow sheet appears **before** the print sheet in the rendered document,
  since the whole design rests on that cascade order.
- Every media query in `mud-narrow.css` is screen-scoped: the resource contains
  no occurrence of `@media (max-width` — only `@media screen and (max-width`.
  This is the guard against the printed-page-width regression described above.
- The two comment stylesheets no longer have a bare `@media screen {` block —
  an unguarded one would reserve the gutter below the Compact tier, leaving a
  blank strip with no column in it.
- `Layout.compactBreakpoint` matches the number in all three stylesheets. If
  those drift, the app opens a compose box into a column CSS has hidden.

And in `App/Tests/CommentColumnFitTests.swift`, the `CommentColumnFit.remedy`
truth table: widen when the screen allows, widen only as far as it allows,
prefer widening over hiding the sidebar when both would work, hide the sidebar
when the window is already screen-wide, and offer nothing when neither would
clear the breakpoint (including the boundary case — 700 is inside the Compact
tier, since the query is `max-width`).


## Verification

I'll need you to run these; I can't drive the GUI or Xcode.

1. **Test suites** — Cmd+U on the MudCore scheme (or `swift test` in `Core/`)
   for the stylesheet checks, and Cmd+U on the Mud scheme for
   `CommentColumnFitTests`.
2. **Quick Look, column view** — Finder in column view on a `.md` file; drag
   the preview column narrow and wide. Check a plain document and one with
   comments: the bottom Comments section with `💬` markers visible inline, and
   no column at any width.
3. **Quick Look, spacebar** — the larger QL window shows the same bottom
   Comments section. No column here either, however wide the window.
4. **App window** — open a document, drag the window from wide to ~250pt in
   both Mark Up and Mark Down. Watch the two thresholds land cleanly.
5. **Print regression (the important one)** — Cmd+P at a _narrow_ window and
   confirm the print preview is identical to Cmd+P at a wide window. This is
   what the `@media screen` scoping buys.
6. **Export** — `mud -u somefile.md > /tmp/out.html`, open in Safari, resize
   the window across both breakpoints.
7. **Popovers** — click a footnote reference and a comment marker at a normal
   window width; confirm the 360px popovers still look right with the Tight
   tier applied (see the knock-on note above).
8. **Making room** — drag the window until the content pane is under 700pt,
   select some text, and hit Add Comment: the window should widen on its own
   and the compose box open on that same selection. Repeat with Show Comments
   (Ctrl+Cmd+K) and no selection. Then hide the column and confirm the window
   keeps its new width.
9. **The sidebar prompt** — zoom the window to fill the screen with the sidebar
   open, and drag the sidebar wide enough that the content pane drops under
   700pt. Add Comment should now ask before collapsing it; Continue should
   scroll to the bottom Comments section rather than doing nothing.
10. **Marker click** — with "Show comment markers" on and the column hidden,
    click a `💬` marker under 700pt: the window should widen and the column open
    with that comment expanded. On a display too narrow to widen, it should
    scroll to that comment in the bottom section, not to the section's top.
11. **Down mode** — switch to Mark Down and confirm both the Comment and the
    Comments-column toolbar buttons are dimmed.

A commented, footnoted, table- and code-bearing fixture is the best single test
document — `Doc/Plans/Archive/2026-06-comments-column.md` or similar.
