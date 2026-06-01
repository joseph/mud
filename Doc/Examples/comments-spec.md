The quick brown fox[^comment-a] jumped over the lazy dog.

[^comment-a]: The simplest comment. No quotation, no author, no timestamp.


Valid. Properties:
* Label: comment-a
* Comment 1:
  * Message: The simplest comment. No quotation, no author, no timestamp.


----

The quick brown fox[^comment-b] jumped over the lazy dog.

[^comment-b]: > fox

    A quoted comment, no properties.

Valid. Properties:
* Label: comment-b
* Quotation: fox
* Comment 1:
  * Message: A quoted comment, no properties.

----

The quick brown fox[^comment-c] jumped over the lazy dog.

[^comment-c]: > brown fox

    JP (2026-06-01 18:33): A comment with author and timestamp.

Valid. Properties:
* Label: comment-c
* Quotation: brown fox
* Comment 1:
  * Author: JP
  * Timestamp: 2026-06-01 18:33
  * Message: A comment with author and timestamp.

----

The quick brown fox[^comment-d] jumped over the lazy dog.

[^comment-d]: > quick brown fox

    💬 JP (2026-06-01 18:33):

    First comment in thread.

    💬 Claude Opus 4.8 (2026-06-01 18:33:13):

    > First comment in thread.

    Second comment in thread, recognized as second comment because 💬 appears
    at the start of a paragraph (after the 4-space indent that keeps the
    footnote continuing).

Valid. Properties:
* Label: comment-d
* Quotation: quick brown fox
* Comment 1:
  * Author: JP
  * Timestamp: 2026-06-01 18:33
  * Message: First comment in thread.
* Comment 2:
  * Author: Claude Opus 4.8
  * Timestamp: 2026-06-01 18:33:13
  * Message:
    > First comment in thread.

    Second comment in thread, recognized as second comment because 💬 appears
    at the start of a paragraph (after the 4-space indent that keeps the
    footnote continuing).

----

The quick brown fox[^comment-e] jumped over the lazy dog.

[^comment-e]: > The quick brown fox

    JP (2026-06-01 18:33):

    First comment in thread.

    Claude Opus 4.8 (2026-06-01 18:33:13):

    Second comment in thread.

Valid, but only a single comment. Properties:

* Label: comment-e
* Quotation: The quick brown fox
* Comment 1:
  * Author: JP
  * Timestamp: 2026-06-01 18:33
  * Message:
    First comment in thread.

    Claude Opus 4.8 (2026-06-01 18:33:13):

    Second comment in thread.

----

The quick brown fox[^comment-f] jumped over the lazy dog.

[^comment-f]: > fox

    💬 JP (2026-06-01 18:33):

    A single comment. The body mentions a 💬 mid-sentence, which must not be
    read as a second comment because it is not at the start of a paragraph.

Valid, a single comment. The 💬 in the body is mid-paragraph, not at a
paragraph start, so it does not begin a new comment. Properties:
* Label: comment-f
* Quotation: fox
* Comment 1:
  * Author: JP
  * Timestamp: 2026-06-01 18:33
  * Message: A single comment. The body mentions a 💬 mid-sentence, which must
    not be read as a second comment because it is not at the start of a
    paragraph.

----

The quick brown fox[^comment-g] jumped over the lazy dog.

[^comment-g]: > brown

    💬 JP (2026-06-01 18:33)

    The colon after the timestamp is optional; this header omits it.

Valid. Properties:
* Label: comment-g
* Quotation: brown
* Comment 1:
  * Author: JP
  * Timestamp: 2026-06-01 18:33
  * Message: The colon after the timestamp is optional; this header omits it.

----

The quick brown fox[^comment-h] jumped over the lazy dog.

[^comment-h]:
    💬 JP (2026-06-01 18:33):

    A general comment with no quotation, but with a thread.

    💬 Claude Opus 4.8 (2026-06-01 18:33:13):

    A reply, also with no document quotation.

Valid, general and threaded. No leading blockquote, so there is no quotation;
two 💬 headers, so there are two comments. Properties:
* Label: comment-h
* Comment 1:
  * Author: JP
  * Timestamp: 2026-06-01 18:33
  * Message: A general comment with no quotation, but with a thread.
* Comment 2:
  * Author: Claude Opus 4.8
  * Timestamp: 2026-06-01 18:33:13
  * Message: A reply, also with no document quotation.

