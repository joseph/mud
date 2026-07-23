import Foundation

/// Emits comment HTML: the bottom `<section class="comments">`, the single
/// `<li>` item the live no-reload sync slots in, and the self-contained
/// thread document for the editor popover. Moved out of the `MudCore`
/// facade, which keeps only dispatch.
enum CommentHTMLRenderer {
    /// The bottom `<section class="comments">`, emitted after any footnotes
    /// section. Each comment renders its quotation (if any) and its thread of
    /// messages — attribution plus body Markdown — with a back-reference to the
    /// marker. Given `is-print-only` in `.interactive` mode (hidden on screen,
    /// shown under `@media print`). Returns an empty string when there are no
    /// comments. Mud renders the thread from the parsed `Comment` model with its
    /// own markup, so styling never depends on the on-disk form.
    static func section(
        _ comments: [Comment],
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?
    ) -> String {
        guard !comments.isEmpty else { return "" }
        var bodyOptions = options
        bodyOptions.waypoint = nil
        let printOnly = options.commentMode == .interactive ? " is-print-only" : ""
        var html = "<section class=\"comments\(printOnly)\" data-comments>\n"
        html += "<h2>Comments</h2>\n<ol>\n"
        for comment in comments {
            html += listItem(
                comment, options: bodyOptions,
                resolveImageSource: resolveImageSource)
        }
        html += "</ol>\n</section>"
        return html
    }

    /// One comment's `<li>` for the bottom section: its thread plus a marker
    /// back-reference, carrying the machine-readable `data-mud-*` fields the
    /// Comments column projects a capsule from (label on the item, author and
    /// time on each message). Shared by the section loop and
    /// `MudCore.renderCommentItem`. `options` should already carry
    /// `waypoint = nil`.
    static func listItem(
        _ comment: Comment,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?
    ) -> String {
        let label = HTMLEscaping.escape(comment.label)
        var html = "<li id=\"cmt-\(label)\" data-mud-label=\"\(label)\""
        if let quotation = comment.quotation, !quotation.isEmpty {
            html += " data-mud-quotation=\"\(HTMLEscaping.escape(quotation))\""
        }
        html += ">\n"
        html += threadInner(
            comment, options: options, resolveImageSource: resolveImageSource)
        html += "<a class=\"footnote-backref\" href=\"#cmtref-\(label)\""
        html += " aria-label=\"Back to content\">\u{21A9}</a>\n"
        html += "</li>\n"
        return html
    }

    /// Renders one comment's thread as a self-contained themed Up-mode document
    /// for the editor popover's WebView — the comment analogue of the footnote
    /// popover document. An empty `messages` array (a comment being created)
    /// yields just the quotation.
    static func threadDocument(
        _ comment: Comment,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?
    ) -> String {
        var docOptions = options.withoutCommentsColumn()
        docOptions.waypoint = nil
        docOptions.title = ""
        // Reuse the footnote popover's trimmed padding.
        docOptions.htmlClasses.insert("footnote-popover")
        let inner = threadInner(
            comment, options: docOptions, resolveImageSource: resolveImageSource)
        let body = "<div class=\"comments comment-thread-popover\">\(inner)</div>"
        return HTMLTemplate.wrapUp(body: body, options: docOptions)
    }

    /// The inner thread HTML for one comment — its quotation (if any) and the
    /// sequence of messages (attribution line plus rendered body Markdown).
    /// Shared by the bottom section and the editor popover so both show the
    /// identical markup. `options` should already carry `waypoint = nil`.
    private static func threadInner(
        _ comment: Comment,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?
    ) -> String {
        var html = ""
        if let quotation = comment.quotation, !quotation.isEmpty {
            html += "<blockquote class=\"mud-comment-quote\">"
            html += HTMLEscaping.escape(quotation)
            html += "</blockquote>\n"
        }
        for message in comment.messages {
            html += messageOpenTag(message, mode: options.commentMode)
            let attribution = formatAttribution(message)
            if !attribution.isEmpty {
                html += "<div class=\"mud-comment-attribution\">"
                html += attribution
                html += "</div>\n"
            }
            let fragment = UpHTMLVisitor.renderBody(
                ParsedMarkdown(message.body),
                options: options, resolveImageSource: resolveImageSource)
            html += "<div class=\"mud-comment-body\">\(fragment)</div>\n"
            html += "</div>\n"
        }
        return html
    }

    /// The opening `<div class="mud-comment-message">` tag, carrying the
    /// message's author and time as machine-readable `data-mud-*` attributes —
    /// epoch milliseconds plus the preformatted absolute string — so the column
    /// can show "💬 author" and a relative time without re-parsing the visible
    /// attribution line.
    ///
    /// In interactive mode the tag also carries `data-mud-body`: the message's
    /// **raw** Markdown source, so the write-side Edit action can fill the
    /// compose textarea with the original syntax rather than the rendered, and
    /// thus lossy, text. Export mode (`.section`) is read-only and omits it.
    private static func messageOpenTag(
        _ message: CommentMessage, mode: CommentMode
    ) -> String {
        var attrs = "class=\"mud-comment-message\""
        if let author = message.author, !author.isEmpty {
            attrs += " data-mud-author=\"\(HTMLEscaping.escape(author))\""
        }
        if let created = message.created {
            let ms = Int((created.timeIntervalSince1970 * 1000).rounded())
            attrs += " data-mud-time=\"\(ms)\""
            attrs += " data-mud-time-abs=\""
            attrs += HTMLEscaping.escape(CommentSerialization.formatTimestamp(created))
            attrs += "\""
        }
        if mode == .interactive {
            attrs += " data-mud-body=\"\(HTMLEscaping.escape(message.body))\""
        }
        return "<div \(attrs)>\n"
    }

    /// The `author · timestamp` attribution line for a message, HTML-escaped;
    /// empty when the message carries neither.
    private static func formatAttribution(_ message: CommentMessage) -> String {
        var parts: [String] = []
        if let author = message.author, !author.isEmpty {
            parts.append(HTMLEscaping.escape(author))
        }
        if let created = message.created {
            parts.append(HTMLEscaping.escape(
                CommentSerialization.formatTimestamp(created)))
        }
        return parts.joined(separator: " \u{00B7} ")
    }
}

extension RenderOptions {
    /// Strips the host document's comments-column state for a self-contained
    /// popover document. A footnote or comment-thread popover is its own tiny
    /// page in a separate WebView: it must not reserve the 324px column gutter
    /// or carry the write-side editing styles, whatever the host document was
    /// showing. The read-side comment styles and the bottom section are left
    /// alone, so a comment-thread popover still renders its quotation and
    /// messages.
    func withoutCommentsColumn() -> RenderOptions {
        var o = self
        o.commentMode = .section
        o.commentsEditable = false
        o.htmlClasses.remove("is-comments-column")
        o.htmlClasses.remove("comment-return-saves")
        return o
    }
}
