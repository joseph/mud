import Foundation

/// Where comments go in the rendered output (parallel to `FootnoteMode`).
///
/// - `.section`: emit a visible bottom `<section class="comments">` with
///   visible quote markers (Quick Look, and any static render).
/// - `.interactive`: column mode. The bottom section is still emitted as the
///   single source of comment HTML, but marked `is-print-only` (hidden on
///   screen, shown under `@media print`); the `comments-column` class is set so
///   the JS projects the Comments column from it and the quote markers are
///   hidden on screen. Used by the live app and by HTML exports.
public enum CommentMode: String, Sendable, Equatable {
    case interactive
    case section
}

/// A comment stored in a Markdown document as a GFM footnote whose label
/// matches `^comment-[\w-]+$`. The on-disk grammar (one worked example per case
/// with the exact properties it parses to) is pinned in
/// `Doc/Spec/comments.md`.
///
/// A comment carries an optional **quotation** (a leading blockquote echoing the
/// document text the comment refers to; `nil` ⇒ a *general*, unanchored comment)
/// and one or more **messages** (a thread). Whether an anchored comment actually
/// draws a highlight is a render-time DOM question, never stored here.
public struct Comment: Sendable, Equatable, Identifiable {
    /// Stable identity — the footnote label (e.g. `comment-a`). The reference is
    /// `[^\(label)]`.
    public var id: String { label }

    /// The footnote label, e.g. `comment-a`. Allocated in insertion order and
    /// never renumbered; used purely as a stable join key.
    public let label: String

    /// 1-based document-order position. Display only; derived from marker
    /// position at render time, not stored on disk.
    public let ordinal: Int

    /// The root blockquote text, whitespace-collapsed; `nil` for a general
    /// (unanchored) comment.
    public let quotation: String?

    /// One message per attributes block (or a single author-less message when
    /// the body carries no header).
    public let messages: [CommentMessage]

    public init(
        label: String, ordinal: Int, quotation: String?,
        messages: [CommentMessage]
    ) {
        self.label = label
        self.ordinal = ordinal
        self.quotation = quotation
        self.messages = messages
    }
}

/// One message in a comment thread, introduced on disk by a `💬 {author @
/// timestamp}:` attributes block.
public struct CommentMessage: Sendable, Equatable {
    /// The brace text before the timestamp's `@`; `nil` if the message is
    /// unattributed.
    public let author: String?

    /// Parsed from the brace's `@ <timestamp>` (`YYYY-MM-DD`, optionally with
    /// `HH:MM[:SS]`) as local wall-clock; `nil` if the header carries no
    /// parseable timestamp.
    public let created: Date?

    /// The commentary as Markdown (may itself contain blockquotes, lists, code
    /// blocks — anything the "new block below the header" rule allows).
    public let body: String

    public init(author: String?, created: Date?, body: String) {
        self.author = author
        self.created = created
        self.body = body
    }
}
