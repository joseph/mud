Tables
===============================================================================

This document exercises GFM table syntax. A table is a **header row**, a
**delimiter row** of dashes that separates the header from the body, and zero
or more **body rows**. Cells are divided by pipes (`|`); the leading and
trailing pipes on each line are optional. Every column in the body aligns to
the header column above it.

The last two sections cover **wide tables** — more columns, or wider content,
than the window can hold. Mud gives each such table its own horizontal
scrollbar so the overflow stays reachable without scrolling the whole document.


## Basic table

The minimal table: a header, a delimiter row, and two body rows.

| Name | Role     | Location |
| ---- | -------- | -------- |
| Ana  | Engineer | Lisbon   |
| Ben  | Designer | Berlin   |

The delimiter row needs at least one dash per column. The pipes around the edge
are optional, so this renders identically:

| Name | Role     | Location |
| ---- | -------- | -------- |
| Ana  | Engineer | Lisbon   |
| Ben  | Designer | Berlin   |


## Column alignment

A colon in the delimiter row sets a column's alignment: `:---` is left, `:--:`
is center, `---:` is right, and a plain `---` leaves it at the default (left).

| Left (default)        | Left         | Center        | Right        |
| --------------------- | ------------ | :-----------: | -----------: |
| alphabetical          | alphabetical | alphabetical  | alphabetical |
| foo                   | foo          | foo           | foo          |
| 1                     | 10           | 100           | 1000         |

Alignment applies to the whole column, header included — note how the header
labels above track their columns.


## Inline formatting in cells

Cells hold inline Markdown, so the usual inline syntax works inside them:
**bold**, _italic_, `inline code`, [links](https://example.com),
~~strikethrough~~, and :sparkles: emoji shortcodes.

| Construct     | Example                                  |
| ------------- | ---------------------------------------- |
| Bold          | **important**                            |
| Italic        | _emphasis_                               |
| Code          | `let x = 1`                              |
| Link          | [Mud](https://example.com)               |
| Strikethrough | ~~removed~~                              |
| Emoji         | :rocket: :white_check_mark: :warning:    |
| Mixed         | **bold** and _italic_ with `code` :tada: |

Block-level constructs — lists, code blocks, multiple paragraphs — are **not**
allowed inside a cell. For a manual line break within a cell, use a raw `<br>`:

| Field   | Value                       |
| ------- | --------------------------- |
| Address | 12 Example Street<br>Lisbon |


## Escaping pipes

A pipe is the column separator, so a literal pipe inside a cell must be escaped
with a backslash (`\|`) — even inside a code span, because a row is split into
columns before its cell contents are parsed as inline Markdown. In source, an
escaped-pipe row looks like this:

```
| Expression | Meaning    |
| ---------- | ---------- |
| a \| b     | bitwise OR |
| p(x \| y)  | given y    |
```

Each first cell holds a literal pipe; the `\|` keeps it from starting a new
column, so the row stays two cells wide.


## Ragged rows

A body row need not have the same number of cells as the header. Missing
trailing cells render empty; extra cells past the last header column are
dropped.

| A     | B    | C     |
| ----- | ---- | ----- |
| full  | row  | here  |
| short | row  |       |
| too   | many | cells | here |

An empty cell is written as nothing between two pipes:

| Key   | Value |
| ----- | ----- |
| set   | yes   |
| unset |       |


## Wide table: many columns

The column count alone can push a table past the window. This one has eleven
columns; in a normal-width window the rightmost columns fall off the edge.
Instead of clipping, the table scrolls sideways on its own — drag horizontally
within it, and the rest of the document stays put.

| Region  | Users  | Sessions | Errors | p50 ms | p95 ms | p99 ms | Uptime | Cost/mo | Owner  | Notes                   |
| ------- | ------ | -------- | ------ | ------ | ------ | ------ | ------ | ------- | ------ | ----------------------- |
| us-east | 12,004 | 88,210   | 12     | 41     | 120    | 310    | 99.98% | $4,210  | ana@x  | steady traffic all week |
| us-west | 9,551  | 71,900   | 4      | 38     | 110    | 280    | 99.99% | $3,880  | ben@x  | nightly batch spike     |
| eu-cen  | 7,220  | 54,100   | 31     | 55     | 160    | 420    | 99.90% | $3,015  | cara@x | GDPR region, extra logs |
| ap-se   | 5,880  | 40,320   | 9      | 62     | 180    | 500    | 99.95% | $2,540  | dan@x  | high latency to origin  |


## Wide table: unbreakable content

A cell can also be too wide on its own. A long token with no spaces — a hash, a
URL, a fingerprint — cannot wrap, so the column can't shrink to fit. The same
horizontal scroll keeps it reachable.

| Key         | Value                                                                                        |
| ----------- | -------------------------------------------------------------------------------------------- |
| commit      | `9f3c1e7a4b2d8e6f0a1c9b3d5e7f2a4c6b8d0e1f3a5c7e9b1d3f5a7c9e1b3d5f7a9c1e3b5d7f9a1c3e5b7d9f1a` |
| download    | `https://downloads.example.org/builds/2026/07/mud-macos-universal-14.0-signed-notarized.dmg` |
| fingerprint | `SHA256:AAAABBBBCCCCDDDDEEEEFFFF0000111122223333444455556666777788889999aaaabbbbccccdddd`    |

A narrow table, by contrast, shrinks to fit its content and never shows a
scrollbar — the scroll only appears when a table is genuinely wider than the
text column.
