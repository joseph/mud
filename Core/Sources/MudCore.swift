// MudCore - Shared Markdown rendering library for the Mud app

import Foundation

/// A rendered Up-mode HTML document plus the footnote popover documents that
/// accompany it (populated only in `.popover` mode) and the parsed comments
/// (for the live highlights, sidebar, and editor).
public struct RenderedUpDocument: Sendable {
    public let html: String
    public let footnotes: [RenderedFootnote]
    public let comments: [Comment]

    public init(
        html: String, footnotes: [RenderedFootnote], comments: [Comment] = []
    ) {
        self.html = html
        self.footnotes = footnotes
        self.comments = comments
    }
}

/// A single footnote rendered as a self-contained HTML document, keyed by its
/// label, for display in an `NSPopover`.
public struct RenderedFootnote: Sendable {
    public let label: String
    public let number: Int
    public let html: String

    public init(label: String, number: Int, html: String) {
        self.label = label
        self.number = number
        self.html = html
    }
}

/// Entry point for MudCore functionality.
public enum MudCore {
    public static let version = "1.0.0"

    private static let downVisitor = DownHTMLVisitor()

    // MARK: - ParsedMarkdown API

    /// Renders a parsed Markdown document to HTML body content.
    ///
    /// This overload is footnote-unaware: it renders whatever AST it is given.
    /// Footnote preprocessing happens at the String boundary (sourcepos needs
    /// raw bytes) — see ``renderUpModeDocumentWithFootnotes(_:options:resolveImageSource:)``.
    public static func renderUpToHTML(
        _ parsed: ParsedMarkdown,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        renderUpBody(parsed, options: options, resolveImageSource: resolveImageSource)
    }

    /// The visitor + frontmatter-prefix core shared by Up-mode body rendering
    /// and footnote-body rendering.
    private static func renderUpBody(
        _ parsed: ParsedMarkdown,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?
    ) -> String {
        var upVisitor = UpHTMLVisitor()
        upVisitor.baseURL = options.baseURL
        upVisitor.resolveImageSource = resolveImageSource
        upVisitor.alertDetector.docCAlertMode = options.docCAlertMode
        upVisitor.showInlineDeletions = options.showInlineDeletions
        if let waypoint = options.waypoint {
            upVisitor.diffContext = DiffContext(
                old: waypoint, new: parsed,
                wordDiffThreshold: options.wordDiffThreshold)
        }
        upVisitor.visit(parsed.document)
        upVisitor.emitTrailingDeletions()

        if let yaml = parsed.frontMatter {
            return renderFrontMatterHTML(yaml) + upVisitor.result
        }
        return upVisitor.result
    }

    /// Footnote/comment-processes the change-tracking waypoint the same way as
    /// the new content, so the diff compares like with like. Without this, the
    /// injected markers (and removed definitions) in the *new* render diff
    /// against the *raw* `[^label]` syntax still present in the waypoint, which
    /// flags every unchanged footnote/comment marker as a spurious change.
    private static func processingWaypoint(_ options: RenderOptions) -> RenderOptions {
        guard let waypoint = options.waypoint else { return options }
        var options = options
        let processed = FootnoteProcessor.process(
            waypoint.markdown, mode: options.footnoteMode)
        options.waypoint = ParsedMarkdown(processed.transformedMarkdown)
        return options
    }

    /// Renders a parsed Markdown document to a complete HTML document
    /// with styles. When `options.title` is empty, the title is
    /// auto-extracted from the first heading.
    public static func renderUpModeDocument(
        _ parsed: ParsedMarkdown,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        var options = options
        if options.title.isEmpty {
            options.title = parsed.title ?? ""
        }
        let body = renderUpToHTML(parsed, options: options,
                                  resolveImageSource: resolveImageSource)
        return HTMLTemplate.wrapUp(body: body, options: options)
    }

    /// Renders a parsed Markdown document to HTML for Down mode (body only).
    public static func renderDownToHTML(
        _ parsed: ParsedMarkdown,
        options: RenderOptions = .init()
    ) -> String {
        let fmRendered = downVisitor.renderFrontMatterLines(
            markdown: parsed.markdown,
            lineCount: parsed.frontMatterLineCount)
        if let waypoint = options.waypoint {
            let matches = BlockMatcher.match(old: waypoint, new: parsed)
            return downVisitor.highlightWithChanges(
                new: parsed.body, old: waypoint.body,
                matches: matches,
                docCAlertMode: options.docCAlertMode,
                wordDiffThreshold: options.wordDiffThreshold,
                frontMatterRendered: fmRendered)
        }
        return downVisitor.highlight(
            parsed.body, docCAlertMode: options.docCAlertMode,
            frontMatterRendered: fmRendered)
    }

    /// Renders a parsed Markdown document to a complete HTML document
    /// for Down mode. When `options.title` is empty, the title is
    /// auto-extracted from the first heading.
    public static func renderDownModeDocument(
        _ parsed: ParsedMarkdown,
        options: RenderOptions = .init()
    ) -> String {
        var options = options
        if options.title.isEmpty {
            options.title = parsed.title ?? ""
        }
        let bodyHTML = renderDownToHTML(parsed, options: options)
        return HTMLTemplate.wrapDown(bodyHTML: bodyHTML, options: options)
    }

    // MARK: - String convenience API

    /// Renders Markdown text to HTML body content, including footnote
    /// preprocessing and the bottom footnotes section (if any).
    public static func renderUpToHTML(
        _ markdown: String,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        let result = FootnoteProcessor.process(markdown, mode: options.footnoteMode)
        let options = processingWaypoint(options)
        let parsed = ParsedMarkdown(result.transformedMarkdown)
        var body = renderUpBody(parsed, options: options,
                                resolveImageSource: resolveImageSource)
        body += renderFootnotesSection(result.footnotes, options: options,
                                       resolveImageSource: resolveImageSource)
        body += renderCommentsSection(result.comments, options: options,
                                      resolveImageSource: resolveImageSource)
        return body
    }

    /// Renders Markdown text to a complete HTML document with styles,
    /// discarding the footnote popover map. Export call sites (browser, CLI,
    /// Quick Look, print) keep their `String` return and get the
    /// `.section` footnotes output for free.
    public static func renderUpModeDocument(
        _ markdown: String,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        renderUpModeDocumentWithFootnotes(
            markdown, options: options,
            resolveImageSource: resolveImageSource).html
    }

    /// Renders Markdown text to a complete Up-mode HTML document **and** the
    /// per-footnote popover documents (in `.popover` mode), from a single
    /// render. The bottom `<section class="footnotes">` is always emitted; in
    /// `.popover` mode it is marked `is-print-only` (hidden on screen, shown
    /// under `@media print`) and each footnote body is also rendered as a
    /// self-contained themed document for the popover WebView.
    public static func renderUpModeDocumentWithFootnotes(
        _ source: String,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> RenderedUpDocument {
        let result = FootnoteProcessor.process(source, mode: options.footnoteMode)
        let parsed = ParsedMarkdown(result.transformedMarkdown)
        var options = processingWaypoint(options)
        if options.title.isEmpty {
            options.title = parsed.title ?? ""
        }
        var body = renderUpBody(parsed, options: options,
                                resolveImageSource: resolveImageSource)
        body += renderFootnotesSection(result.footnotes, options: options,
                                       resolveImageSource: resolveImageSource)
        body += renderCommentsSection(result.comments, options: options,
                                      resolveImageSource: resolveImageSource)
        let html = HTMLTemplate.wrapUp(body: body, options: options)

        var popovers: [RenderedFootnote] = []
        if options.footnoteMode == .popover {
            popovers = result.footnotes.map { entry in
                RenderedFootnote(
                    label: entry.label, number: entry.number,
                    html: renderPopoverDocument(
                        entry, options: options,
                        resolveImageSource: resolveImageSource))
            }
        }
        return RenderedUpDocument(
            html: html, footnotes: popovers, comments: result.comments)
    }

    // MARK: - Footnote rendering

    /// The bottom `<section class="footnotes">`. Each body is rendered as an
    /// Up-mode fragment with a trailing back-reference link. Returns an empty
    /// string when there are no footnotes.
    private static func renderFootnotesSection(
        _ entries: [FootnoteEntry],
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?
    ) -> String {
        guard !entries.isEmpty else { return "" }
        var bodyOptions = options
        bodyOptions.waypoint = nil
        let printOnly = options.footnoteMode == .popover ? " is-print-only" : ""
        var html = "<section class=\"footnotes\(printOnly)\" data-footnotes>\n<ol>\n"
        for entry in entries {
            let fragment = renderUpBody(
                ParsedMarkdown(entry.bodyMarkdown),
                options: bodyOptions, resolveImageSource: resolveImageSource)
            html += "<li id=\"fn-\(entry.number)\">\n"
            html += fragment
            html += "<a class=\"footnote-backref\" href=\"#fnref-\(entry.number)\""
            html += " aria-label=\"Back to content\">\u{21A9}</a>\n"
            html += "</li>\n"
        }
        html += "</ol>\n</section>"
        return html
    }

    /// Renders a single footnote body as a self-contained themed Up-mode
    /// document for display in an `NSPopover`'s WebView.
    private static func renderPopoverDocument(
        _ entry: FootnoteEntry,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?
    ) -> String {
        var popoverOptions = options
        popoverOptions.waypoint = nil
        popoverOptions.title = ""
        // Trims the page's generous padding (esp. the 6em bottom reserved for
        // floating bars, absent in a popover).
        popoverOptions.htmlClasses.insert("footnote-popover")
        let parsed = ParsedMarkdown(entry.bodyMarkdown)
        let body = renderUpBody(parsed, options: popoverOptions,
                                resolveImageSource: resolveImageSource)
        return HTMLTemplate.wrapUp(body: body, options: popoverOptions)
    }

    // MARK: - Comment rendering

    /// The bottom `<section class="comments">`, emitted after any footnotes
    /// section. Each comment renders its quotation (if any) and its thread of
    /// messages — attribution plus body Markdown — with a back-reference to the
    /// marker. Given `is-print-only` in `.interactive` mode (hidden on screen,
    /// shown under `@media print`). Returns an empty string when there are no
    /// comments. Mud renders the thread from the parsed `Comment` model with its
    /// own markup, so styling never depends on the on-disk form.
    private static func renderCommentsSection(
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
            html += renderCommentListItem(
                comment, options: bodyOptions,
                resolveImageSource: resolveImageSource)
        }
        html += "</ol>\n</section>"
        return html
    }

    /// One comment's `<li>` for the bottom section: its thread plus a marker
    /// back-reference, carrying the machine-readable `data-mud-*` fields the
    /// Comments column projects a capsule from (label on the item, author and
    /// time on each message). Shared by the section loop and the public
    /// single-item renderer below.
    private static func renderCommentListItem(
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
        html += renderCommentThreadInner(
            comment, options: options, resolveImageSource: resolveImageSource)
        html += "<a class=\"footnote-backref\" href=\"#cmtref-\(label)\""
        html += " aria-label=\"Back to content\">\u{21A9}</a>\n"
        html += "</li>\n"
        return html
    }

    /// Renders a single comment's `<li>` exactly as it appears in the bottom
    /// section — the unit the live no-reload sync slots into the hidden section
    /// when a comment is added or changed, before the column reprojects it.
    /// `options.waypoint` is cleared internally.
    public static func renderCommentItem(
        _ comment: Comment,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        var itemOptions = options
        itemOptions.waypoint = nil
        return renderCommentListItem(
            comment, options: itemOptions, resolveImageSource: resolveImageSource)
    }

    /// The inner thread HTML for one comment — its quotation (if any) and the
    /// sequence of messages (attribution line plus rendered body Markdown).
    /// Shared by the bottom section and the editor popover so both show the
    /// identical markup. `options` should already carry `waypoint = nil`.
    private static func renderCommentThreadInner(
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
            html += messageOpenTag(message)
            let attribution = formatAttribution(message)
            if !attribution.isEmpty {
                html += "<div class=\"mud-comment-attribution\">"
                html += attribution
                html += "</div>\n"
            }
            let fragment = renderUpBody(
                ParsedMarkdown(message.body),
                options: options, resolveImageSource: resolveImageSource)
            html += "<div class=\"mud-comment-body\">\(fragment)</div>\n"
            html += "</div>\n"
        }
        return html
    }

    /// Renders one comment's thread as a self-contained themed Up-mode document
    /// for the editor popover's WebView — the comment analogue of the footnote
    /// popover document. An empty `messages` array (a comment being created)
    /// yields just the quotation.
    public static func renderCommentThreadDocument(
        _ comment: Comment,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        var docOptions = options
        docOptions.waypoint = nil
        docOptions.title = ""
        // Reuse the footnote popover's trimmed padding.
        docOptions.htmlClasses.insert("footnote-popover")
        let inner = renderCommentThreadInner(
            comment, options: docOptions, resolveImageSource: resolveImageSource)
        let body = "<div class=\"comments comment-thread-popover\">\(inner)</div>"
        return HTMLTemplate.wrapUp(body: body, options: docOptions)
    }

    /// Parses the comments stored in a Markdown source without a full render —
    /// for the write path (reply/edit needs the current thread) and any caller
    /// that wants the model alone.
    public static func parseComments(_ source: String) -> [Comment] {
        FootnoteProcessor.process(source, mode: .popover).comments
    }

    /// Removes every comment (all `[^comment-x]` references and definition
    /// blocks) from a Markdown source, leaving the rest byte-for-byte. Powers
    /// the comment-invariant content identity that lets a comment add/remove
    /// update the live view in place without a WebView reload. Comment-free
    /// input is returned unchanged.
    public static func removeComments(_ source: String) -> String {
        FootnoteProcessor.removeComments(source)
    }

    /// The opening `<div class="mud-comment-message">` tag, carrying the
    /// message's author and time as machine-readable `data-mud-*` attributes —
    /// epoch milliseconds plus the preformatted absolute string — so the column
    /// can show "💬 author" and a relative time without re-parsing the visible
    /// attribution line.
    private static func messageOpenTag(_ message: CommentMessage) -> String {
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

    // MARK: - Change tracking

    /// Computes a list of changes between two parsed Markdown documents
    /// for the sidebar change list.
    public static func computeChanges(
        old: ParsedMarkdown, new: ParsedMarkdown
    ) -> [DocumentChange] {
        ChangeList.computeChanges(old: old, new: new)
    }

    /// Extracts headings from a Markdown string for the outline sidebar.
    public static func extractHeadings(_ markdown: String) -> [OutlineHeading] {
        ParsedMarkdown(markdown).headings
    }

    /// Renders Markdown text to HTML for Down mode (body only).
    public static func renderDownToHTML(
        _ text: String,
        options: RenderOptions = .init()
    ) -> String {
        renderDownToHTML(ParsedMarkdown(text), options: options)
    }

    /// Renders Markdown text to a complete HTML document for Down mode.
    public static func renderDownModeDocument(
        _ text: String,
        options: RenderOptions = .init()
    ) -> String {
        renderDownModeDocument(ParsedMarkdown(text), options: options)
    }

    // MARK: - Frontmatter rendering

    /// Renders YAML frontmatter as a collapsible HTML block for
    /// Up mode. Parses top-level keys into a table; falls back to
    /// a raw code block if no keys are found.
    private static func renderFrontMatterHTML(_ yaml: String) -> String {
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)

        var html = "<details class=\"mud-frontmatter\">"
        html += "<summary>Frontmatter</summary>"

        if keys.isEmpty {
            html += "<pre><code class=\"language-yaml\">"
            html += HTMLEscaping.escape(yaml)
            html += "</code></pre>"
        } else {
            html += "<table class=\"mud-frontmatter-table\">"
            for kv in keys {
                html += "<tr>"
                html += "<th class=\"fm-key\">"
                html += HTMLEscaping.escape(kv.key)
                html += "</th><td>"
                switch kv.value {
                case .scalar(let v):
                    html += HTMLEscaping.escape(v)
                case .inlineArray(let items):
                    html += HTMLEscaping.escape(items.joined(separator: ", "))
                case .block(let raw):
                    html += "<pre>"
                    html += HTMLEscaping.escape(raw)
                    html += "</pre>"
                }
                html += "</td></tr>"
            }
            html += "</table>"
        }

        html += "</details>"
        return html
    }
}
