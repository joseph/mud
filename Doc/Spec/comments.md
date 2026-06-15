Comments in Mud - Specification by Examples
===============================================================================

This document specifies Mud's comment footnotes by example: each block shows a
source fragment and the properties Mud reads from it.


## Nomenclature

A **comment** is any footnote whose label matches `^comment-[\w-]+$`. A comment
contains, in order:

- an optional **quotation** — a leading blockquote naming the document text the
  comment is anchored to; and
- one or more **messages**.

A message may open with a **message attribution**: a `{…}` brace group,
optionally preceded by a `💬` and followed by a `:` —

```
💬 {author @ time}:
```

A message attribution at the start of a paragraph **begins a new
message**. The first message needs no such attribution; its content may start
immediately after the quotation. A `💬` on its own — no braces — is also valid.
It begins an unattributed message in the thread.


## Author and time

Both are optional inside the braces:

| Attributes                | Author | Time             |
| ------------------------- | ------ | ---------------- |
| `{JP @ 2026-06-01 18:33}` | JP     | 2026-06-01 18:33 |
| `{JP}`                    | JP     | —                |
| `{@ 2026-06-01 18:33}`    | —      | 2026-06-01 18:33 |
| `{}` (discouraged)        | —      | —                |

To divide author from time, Mud takes the **last** `@` whose following text
(trimmed) parses as a time; everything before it (trimmed) is the author. When
no `@` is followed by a valid time, the whole brace interior is the author — so
an author may itself contain `@` (eg, an `@`-handle or email address) without
being misread. Accepted time forms: `YYYY-MM-DD`, `YYYY-MM-DD HH:MM`, and
`YYYY-MM-DD HH:MM:SS`, all local wall-clock.


## Whitespace

This all assumes the footnote definition is correctly indented — continuation
lines kept under the `[^label]:` by the usual four spaces, which is significant
Markdown structure. The whitespace _around_ a comment's parts, however, is
structural only: Mud, and any reader that recognizes comments, does not render
it.

- A space normally separates a `💬` from the opening `{`, and should be present.
- There must be **no** whitespace between the closing `}` and the optional `:`.
  Written as `{…} :`, the attributes are just `{…}` and the `:` becomes the
  first character of the message content.
- There must be a blank line between the quotation (if present) and the first
  message (otherwise Markdown will see the message as part of the quotation).
- Any whitespace, including newlines and blank lines, may appear before the
  quotation, between messages, and between a message's attributes and its
  content. None of it is meaningful.

Whitespace _within_ message content is meaningful, in the usual Markdown ways.


## Disambiguation and caveats

- A message attribution is recognized only at the start of a paragraph (the
  start of a message, or the text right after a `💬`). Braces or a `💬` in
  running prose never start a new message.
- Empty braces (`{}`) are tolerated as "blank attribution" but discouraged —
  omit them entirely instead.
- Because a paragraph-leading `{…}` is always taken as attribution, a message
  whose content genuinely begins with braced text will have that text consumed
  as attribution. This is the one case the convention cannot disambiguate. One
  workaround is to put the literal brace inside code-backticks. Another option
  is to put empty braces at the start of the message, which will be consumed
  as the attribution instead.

The attribution degrades gracefully in renderers that support footnotes but not
Mud's comments (eg, GitHub): the footnote still appears, with `{author @ time}`
reading as a plain byline tag above the message.


-------------------------------------------------------------------------------


The quick brown fox[^comment-a] jumped over the lazy dog.

[^comment-a]: The simplest comment. No quotation, no author, no time.

Valid. Properties:

- Label: comment-a
- Message 1:
  - Content: The simplest comment. No quotation, no author, no time.


-------------------------------------------------------------------------------


The quick brown fox[^comment-b] jumped over the lazy dog.[^1]

[^comment-b]: > fox

    A quoted comment, no attributes.

Valid. Properties:

- Label: comment-b
- Quotation: fox
- Message 1:
  - Content: A quoted comment, no attributes.


-------------------------------------------------------------------------------


The quick brown fox[^comment-c] jumped over the lazy dog.

[^comment-c]: > brown fox

    {JP @ 2026-06-01 18:33}: A message with author and time.

Valid. Properties:

- Label: comment-c
- Quotation: brown fox
- Message 1:
  - Author: JP
  - Time: 2026-06-01 18:33
  - Content: A message with author and time.


-------------------------------------------------------------------------------


The quick brown fox[^comment-d] jumped over the lazy dog.

[^comment-d]: > quick brown fox

    💬 {Joseph @ 2026-06-01 18:33}:

    First message in the thread.

    💬 {Claude Opus 4.8 @ 2026-06-01 18:33:13}:

    > First message in the thread.

    Second message in the thread, recognized as a new message because
    💬 begins a paragraph (after the 4-space indent that keeps the
    footnote continuing).

Valid. Properties:

- Label: comment-d
- Quotation: quick brown fox
- Message 1:
  - Author: Joseph
  - Time: 2026-06-01 18:33
  - Content: First message in the thread.
- Message 2:
  - Author: Claude Opus 4.8

  - Time: 2026-06-01 18:33:13

  - Content:

    > First message in the thread.

    Second message in the thread, recognized as a new message because 💬 begins
    a paragraph (after the 4-space indent that keeps the footnote continuing).


-------------------------------------------------------------------------------


The quick brown fox[^comment-e] jumped over the lazy dog.

[^comment-e]: > The quick brown fox

    {JP @ 2026-06-01 18:33}:

    First message in the thread.

    {Claude Opus 4.8 @ 2026-06-01 18:33:13}:

    Second message in the thread.

Valid, with two messages: the leading `💬` on a message attributes block is
optional, so each `{…}:` at a paragraph start begins a new message. Properties:

- Label: comment-e
- Quotation: The quick brown fox
- Message 1:
  - Author: JP
  - Time: 2026-06-01 18:33
  - Content: First message in the thread.
- Message 2:
  - Author: Claude Opus 4.8
  - Time: 2026-06-01 18:33:13
  - Content: Second message in the thread.


-------------------------------------------------------------------------------


The quick brown fox[^comment-f] jumped over the lazy dog.

[^comment-f]: > fox

    💬 {JP @ 2026-06-01 18:33}:

    A single message. The body mentions a 💬 mid-sentence, which must
    not be read as a second message because it is not at the start of
    a paragraph.

Valid, a single message. The 💬 in the body is mid-paragraph, not at a paragraph
start, so it does not begin a new message. Properties:

- Label: comment-f
- Quotation: fox
- Message 1:
  - Author: JP
  - Time: 2026-06-01 18:33
  - Content: A single message. The body mentions a 💬 mid-sentence, which must
    not be read as a second message because it is not at the start of a
    paragraph.


-------------------------------------------------------------------------------


The quick brown fox[^comment-g] jumped over the lazy dog.

[^comment-g]: > brown fox

    💬 {JP @ 2026-06-01 18:33}

    The colon after the closing brace is optional; this block omits
    it.

Valid. Properties:

- Label: comment-g
- Quotation: brown fox
- Message 1:
  - Author: JP
  - Time: 2026-06-01 18:33
  - Content: The colon after the closing brace is optional; this block omits
    it.


-------------------------------------------------------------------------------


The quick brown fox[^comment-h] jumped over the lazy dog.

[^comment-h]: 💬 {JP @ 2026-06-01 18:33}:

    A general message with no quotation, but part of a thread.

    💬 {Claude Opus 4.8 @ 2026-06-01 18:33:13}:

    A reply, also with no document quotation.

Valid, general and threaded. No leading blockquote, so there is no quotation;
two message attributes blocks, so there are two messages. Properties:

- Label: comment-h
- Message 1:
  - Author: JP
  - Time: 2026-06-01 18:33
  - Content: A general message with no quotation, but part of a thread.
- Message 2:
  - Author: Claude Opus 4.8
  - Time: 2026-06-01 18:33:13
  - Content: A reply, also with no document quotation.


-------------------------------------------------------------------------------


The quick brown fox[^comment-i] jumped over the lazy dog.

[^comment-i]: > fox

    {JP}: A message with an author but no time.

Valid. The message attribution has an author and no `@`-delimited time.
Properties:

- Label: comment-i
- Quotation: fox
- Message 1:
  - Author: JP
  - Content: A message with an author but no time.


-------------------------------------------------------------------------------


The quick brown fox[^comment-j] jumped over the lazy dog.

[^comment-j]: > fox

    {@ 2026-06-01}: A message with a time but no author.

Valid. The interior opens with `@`, so the author is empty; the remainder is a
date-only time. Properties:

- Label: comment-j
- Quotation: fox
- Message 1:
  - Time: 2026-06-01
  - Content: A message with a time but no author.


-------------------------------------------------------------------------------


The quick brown fox[^comment-k] jumped over the lazy dog.

[^comment-k]: > fox

    {@jp}: An author that is an `@`-handle.

Valid. The only `@` is followed by `jp`, which does not parse as a time, so
nothing splits and the whole interior — leading `@` and all — is the author.
Contrast comment-j, where the text after `@` _is_ a time. Properties:

- Label: comment-k
- Quotation: fox
- Message 1:
  - Author: @jp
  - Content: An author that is an `@`-handle.


-------------------------------------------------------------------------------


The quick brown fox[^comment-l] jumped over the lazy dog.

[^comment-l]: > fox

    {}: Empty braces have no attributes.

Valid but discouraged — prefer omitting the block entirely, as in comment-a.
The empty block is still consumed. Properties:

- Label: comment-l
- Quotation: fox
- Message 1:
  - Content: Empty braces have no attributes.


-------------------------------------------------------------------------------


The quick brown fox[^comment-m] jumped over the lazy dog.

[^comment-m]: > fox

    💬 A threaded message with no author or time.

    💬 A reply, also unattributed.

Valid: two messages, each demarcated by a bare `💬` with no attributes. The `💬`
is consumed even when no braces follow it. Properties:

- Label: comment-m
- Quotation: fox
- Message 1:
  - Content: A threaded message with no author or time.
- Message 2:
  - Content: A reply, also unattributed.


-------------------------------------------------------------------------------


[^1]: This is a regular footnote. Included to prove that footnote markers are
    independently numbered from comments.
