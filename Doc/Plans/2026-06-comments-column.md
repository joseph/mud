Plan: Comments Column
===============================================================================

> Status: Underway


## Width and position

The Comments column sits to the right of the document. It can be toggled on or
off.

In Readable Column mode, it occupies the 300 pixels directly to the right of
the column, with a 12px margin either side — the document remains centered if
there is 324px+ of available space to the right of it, otherwise it is nudged
leftwards until there is. If the window is narrower than 1124px of total
available width (800 + 12 + 300 + 12), then the document will occupy that width
minus 324px for the Comments column.

When not in Readable Column mode, the document will occupy the window width
minus 324px for the Comments column.


## Visibility

The Comments column is not visible by default. It becomes visible when opening
a document that contains comments. It also becomes visible whenever you add a
comment (necessarily, so that you can type your comment). Its visibility can be
toggled on or off via the View menu item (Ctrl+Cmd+K).

Unlike other view toggles, the Comments column visibility is NOT persisted.
Making it visible for one document does not make it visible for other
documents. The column is an Up-mode feature: in Down mode the toggle is inert
and the column does not appear.


## Rows

The Comments column contains rows. A row is a comment or a set of controls.
When a comment is expanded, each comment in the thread is a separate row. Each
row is 300px wide. There is a gap of exactly 15px between each row.

The textarea of the comment-compose form is a row. The controls for the
comment-compose form — Cancel and Done — are a separate row.

The Reply button for a thread is a control, thus it is on its own row below the
rows of comments in the thread.

Controls are capsule-shaped, and they are exactly 30px high. A row places a set
of controls side-by-side, right-aligned, with a gap of 10px between each
control.

A comment when inactive is always exactly 45px high, and capsule-shaped
(meaning it has a border-radius of 23px).

When active, a comment must be large enough to display the comment header ("💬
name relative-time") plus the entire message, plus the Edit and Delete buttons
if it is the last comment in the thread.


### Placement rule

Each comment has a **preferred position**: the top of its quotation highlight
(the `<mark>`), measured as an `offsetTop` in the column's scroll space. A
comment with no quote uses the position of its hidden marker instead.

The **placement pass** lays the comments out in one walk down the column. Sort
the comments by preferred position; then, top to bottom, give each comment a
top of:

```
top = max(preferredPosition, previousBottom + 15)
```

where `previousBottom` is the previous comment's top plus its current rendered
height. So a comment sits at its preferred position when there is room, and is
pushed down to clear the comment above it when there is not. The 15px is a
**minimum** gap: when a comment's preferred position already falls below the
previous comment's bottom, it stays at its preferred position and the gap is
simply larger.

Heights are measured live, not counted in fixed units — an inactive comment is
45px, an active one is as tall as its content, and a compose form is a fixed
225px (textarea, a 15px gap, and the controls row). The pass reads each row's
current height, so activating, replying, or editing a comment grows that row
and pushes the rows below it down on the next pass.

A row is anchored by its top and grows downward only; expanding a comment never
moves its own top. The pass is also idempotent: every top is recomputed from
`max(preferredPosition, previousBottom + 15)` each time it runs, so when
whatever pushed a comment down goes away — a comment above it collapses or is
deleted — the next pass returns it to its preferred position with no special
restore step.

When two comments share a preferred position (anchored to the same line), break
the tie by source order — the order they appear in the bottom Comments section.

Capsules and their controls scale-in from the top-center; any row that has to
move to make room slides into its new position at the same speed.

The column is not separately scrollable. It lives in the document body's scroll
space, so its capsules are positioned against the body and simply continue past
the bottom of the document text as far as the last comment needs. The HTML body
is the only thing that scrolls.


### Reflow triggers

The placement pass runs once at load and again whenever something moves a
comment's preferred position or changes a row's height. The column lives in the
document's scroll space — capsules are positioned against the document body,
not the viewport — so plain scrolling moves the column with the text and needs
**no** re-run. Everything else that re-runs the pass falls into two groups.

**Geometry changes** recompute each comment's preferred position from fresh
highlight rectangles, then re-run the pass:

- The webview resizes (window resize, or the native left sidebar showing or
  hiding, which narrows the webview).
- Readable Column is toggled, changing the text wrap width.
- Zoom changes.
- Async content finishes laying out and shifts the text below it — images
  loading, web fonts arriving, Mermaid diagrams rendering.

A single `ResizeObserver` on the Up container catches most of these — it fires
on any height change, including late image and Mermaid layout — with the window
`resize` event covering width-only changes. Coalesce bursts with
`requestAnimationFrame` so a flurry of image loads solves once.

**State changes** keep the preferred positions but change a row's height or
membership, then re-run the pass:

- A compose form opens or closes (new comment, reply, or edit), growing or
  shrinking a row to the compose height.
- A comment is activated or deactivated, expanding to its full content height
  or collapsing to 45px.
- A comment add, reply, edit, or delete arrives through the live no-reload
  sync, inserting, resizing, or removing a capsule. Delete runs its
  puff-of-smoke animation first, then re-runs the pass so the capsules below
  slide up into place.

A document reload (the file changed on disk) rebuilds the column from scratch.
A comment-only edit does not reload — the content identity that decides reloads
ignores comments — so those arrive through the live sync above.


## Adding a comment

To comment on something, select the text and trigger Add Comment — from the
toolbar button, the Edit menu, the Cmd+Shift+K shortcut, or the right-click
menu. All four are enabled only when the selection is commentable; a selection
that can't anchor a comment, such as part of a code block, leaves them
disabled.

![Selecting text](./2026-06-comments-column-assets/02-selected-text.png)

This action reveals the column if it was hidden. The selection becomes a
highlight span in the theme's highlight color, and the compose form opens with
its top at the selection's preferred position. If a comment anchored earlier in
the document is already there, the form is pushed down to clear it, the same as
any other row. The "Cancel" and "Done" buttons sit at the bottom of the form,
with a 15px vertical gap between the textarea and the buttons:

![Adding comment](./2026-06-comments-column-assets/03-adding-comment.png)

The "Done" button is accent-colored. The textarea and cancel button are
outlined in the theme's foreground-color.

Once you click "Done", the comment is saved to the document, and the comment
collapses to its inactive 45px height, with the text preceded by "💬 **Author**:
" and truncated with an ellipsis at the end of the line:

![Inactive comment](./2026-06-comments-column-assets/04-inactive-comment.png)


## Navigating comments

When you hover over a comment in the column, the highlight for the quoted
section will appear in the document:

![Hover over comment](./2026-06-comments-column-assets/05-hover-over-comment.png)

When you click on the comment, the highlight remains (because the comment is
now "active") and the comment expands to whatever height it needs to display
its entire contents plus a "Reply" button:

![Active comment](./2026-06-comments-column-assets/06-selected-comment.png)

An active comment shows each message's author and time. The time is relative
for the first 24 hours — "5 minutes ago", "11 hours ago" — and an absolute
date-time after that.

The base of the message bubble shows two small icons: an Edit button (as a
comment-bubble-with-pencil icon) and a Delete button (as a trash-can icon).
These buttons are only present for the last comment in the thread.

![Edit icon](./2026-06-comments-column-assets/icon-comment-edit.svg)

The Edit button transforms the bubble into the compose form, same as at the
"Adding comment" step above, with the same Cancel and Done buttons below the
textarea.

![Delete icon](./2026-06-comments-column-assets/icon-comment-delete.svg)

The Delete button removes the comment in a sort of puff-of-smoke animation
(using a simple scale-blur-fade combo, I think). As that ends, the rows below
slide up into place.


## Replies & threads

If you click the Reply button below the active comment, it will transform that
row into a new compose form, the same height as the one for a new comment (with
the Cancel & Done buttons at the bottom of the form).

![Replying](./2026-06-comments-column-assets/07-replying.png)

Note that the Edit and Delete buttons are removed from the active comment
bubble, since it will no longer be the last comment in the thread. (They are
restored if you Cancel out of the new comment, of course.) This means that the
active comment will sometimes shrink a little, so the compose form can
immediately slide up in that case.

After the reply is submitted (by clicking Done), the full thread will appear,
with each comment as tall as it needs to display in full, and the last comment
showing the Edit and Delete icon-buttons:

![Selected comment with replies](./2026-06-comments-column-assets/08-selected-comment-with-replies.png)

Mouse-down anywhere outside the comment will collapse it to an inactive
comment. In this form, only the truncation of the first comment in the thread
is shown, with "1 reply" / "2 replies" / etc as a label that cuts into the
border of the bubble:

![Inactive comment with replies](./2026-06-comments-column-assets/09-inactive-comment-with-replies.png)


## Implementation details

MudCore parses a document's comments into a `Comment` model and renders each
one to HTML — its quotation and the Markdown of every message. It writes these
as the **Comments section** at the foot of the document: one block per comment,
each block carrying its label and quotation, and each message carrying its
author and time as structured markup (not just prose). This section is the
single source of comment HTML in the page.

On screen the section is hidden by CSS, and the JS builds the column from it.
For each comment it reads the structured block and projects a capsule —
collapsed (💬 author and a truncated first message) or, when active, expanded
(the cloned message HTML, author and time, and the Reply / Edit / Delete
controls). The JS only clones and re-wraps nodes that are already rendered; it
never parses Markdown. For printing the rule reverses: the column is hidden and
the section is shown (see Exporting & printing).

Because the column is a projection of the section, there is one comment format
to maintain, and the same projection builds the read-only export column and the
live editing column alike. The section's markup is therefore a contract the
column JS depends on, and any clone of a section node must strip or namespace
its `#cmt-LABEL` id so the page holds no duplicate ids.


### The quote marker

In interactive Up mode there is no visible `[⋯]` marker beside the quoted text
— the highlight and the column capsule are the only affordances. The marker is
present in the HTML but hidden by CSS on screen; print and export reveal it,
with its `#cmt-LABEL` link to the section. Keeping it in the DOM gives the
highlight its anchor: the JS finds each quotation by the marker's position,
wraps the quoted text in a `<mark>`, and the placement pass reads that mark's
`offsetTop` for the comment's preferred position. (Pulling the marker out of
the DOM in Up mode would mean anchoring the highlight some other way — more
work for no visible gain, so it is hidden rather than removed.)


### The write path

Editing is native. The compose form contains a HTML `<textarea>`; on submit,
its text crosses to Swift through a message handler carrying the action (add,
reply, edit, delete), the target label, the body, and — for a new comment — the
draft locator that pins the quotation to a source byte. A Swift controller then
performs the byte-exact, atomic, security-scoped write to the `.md` file.
Keyboard handling lives with the textarea: Esc cancels, Cmd-Enter submits, and
the field gets the standard cut / copy / paste.


### Live updates, no reload

A comment add, reply, edit, or delete updates the column in place, with no
document reload, so scroll position and any open selection survive. After the
write, Swift hands the JS the changed comment as a section fragment; the JS
slots it into the hidden section, reprojects that one capsule, and re-runs the
placement pass. A full reload is reserved for an actual change to the document
body on disk — a comment-only edit does not trigger one.


### Commentability

The Add Comment button must appear only for a selection that can actually be
saved — otherwise a click would fail at submit. A code-block selection, for
instance, has no anchor. The exact predicate — which selections are
commentable, and whether a selection may span more than one block — is **still
open**, to be settled during implementation. The plan assumes for now that the
button shows when the selection lies in ordinary body text and hides otherwise.


### Read and write JavaScript

The exported column is read-only, so the comment JS splits in two: a **read**
file — projection, highlight anchoring, hover, activate-and-expand, the
placement pass, and layout — included everywhere, exports included; and a
**write** file — selection capture and the Add Comment button, the compose box,
submit, edit, and delete — included only in the app. An export loads only the
read file, so its column reveals highlights on hover and expands on click but
offers no editing.


## Exporting & printing

The same document HTML serves several read-only contexts. Each picks what to
show with CSS and which JavaScript it loads.

- **HTML export and the `mud -u` CLI** include the column, read-only. Every
  comment starts collapsed; it reveals its highlighted quotation on hover and
  expands on click, but nothing can be added, edited, replied to, or deleted.
  This follows from loading only the read JavaScript (see Implementation
  details).
- **Quick Look** excludes the column — the preview is too narrow to spend the
  width on it, and no app JavaScript runs there anyway. Comments degrade to
  their static form, exactly as footnotes do in Quick Look: the quote markers
  are shown and the bottom Comments section is visible, and clicking a marker
  scrolls down to its entry (a same-document `#cmt-LABEL` jump, no popover or
  column).
- **Print** hides the column and shows the bottom Comments section instead,
  with the quote markers revealed and linking into it.

The bottom section is the single source the column projects from, so all of
these read from one rendered form of the comments.
