Comments
==============================================================================

The simplest possible comment.[^comment-a]

[^comment-a]: No quotation, no title, just an observation.

The only thing that makes this a comment is that the footnote label matches
the pattern `comment-\w+`. Mud would never generate a comment like this —
but someone could hand-write a comment like this.

----

A quoted comment.[^comment-b]

[^comment-b]: <q>A quoted comment.</q> The commentary comes after the `<q>`.

----

A fully-attributed comment.[^comment-c]

[^comment-c]:
    <q title="Claude Opus 4.8 @ 2026-06-01T10:53:00Z">attributed comment.</q>
    This comment has a `<q>` element with a `title` attribute, and the value of
    it can be broken down into `<author> @ <datetime>`, which Mud can parse and
    use as author and creation-time properties of the comment in its UI.

    The comment has several paragraphs, and is written in _markdown format_
    itself. Note that even though we could have started this comment on the
    first line (after `-c]:`), we placed a newline there and started the
    comment 4 spaces indented. We kept line lengths to under 80 characters
    where possible in the comment.


----

A threaded[^comment-d] comment.

[^comment-d]:
    <q title="JP @ 2026-06-01T10:53:00Z">threaded</q>
    Here, JP has written an initial comment on the content in the document.  
    <q title="Claude Opus 4.8 @ 2026-06-01T10:53:15Z">content in the document</q>
    Claude replies to a specific range in the JP's comment.  
    <q title="JP @ 2026-06-01T10:53:23Z">…</q>
    JP replies to Claude's reply in general (`…` means no specific range).


Note that it's recommended to put two spaces after the final line in each
comment in the thread, for nice formatting in other markdown renderers.
