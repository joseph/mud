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
    /// Internal because nothing in the types distinguishes a raw parse from a
    /// processed one; the String overloads are the public entry points.
    static func renderUpToHTML(
        _ parsed: ParsedMarkdown,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        UpHTMLVisitor.renderBody(
            parsed, options: options, resolveImageSource: resolveImageSource)
    }

    /// Renders a parsed Markdown document to a complete HTML document
    /// with styles. When `options.title` is empty, the title is
    /// auto-extracted from the first heading. Internal for the same reason as
    /// the `ParsedMarkdown` overload of `renderUpToHTML` above: it skips
    /// footnote preprocessing, so it must not be a public entry point.
    static func renderUpModeDocument(
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
        let fmRendered = FrontMatterHTMLRenderer.downModeLines(
            markdown: parsed.markdown,
            lineCount: parsed.frontMatterLineCount)
        if let waypoint = options.waypoint,
           let oldDoc = waypoint.cmarkDocument,
           let newDoc = parsed.cmarkDocument {
            // Down mode diffs the raw source, footnote definitions
            // included, so the plan descends plain footnote definitions
            // (comment definitions stay invisible). The Down-mode sidebar
            // list shares this policy (`computeChanges(mode: .down)`), so its
            // change IDs match this body's by construction; waypoint dedup
            // uses it too (`computeChanges(mode: nil)`).
            let plan = ChangePlan.plan(
                old: oldDoc, new: newDoc,
                wordDiffThreshold: options.wordDiffThreshold,
                definitionPolicy: .descendPlainFootnotes)
            return downVisitor.highlightWithChanges(
                new: parsed.body, old: waypoint.body,
                plan: plan,
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

    /// Everything one Up-mode render of a Markdown source produces: the HTML
    /// body (with the bottom footnotes section appended), the bottom Comments
    /// section, the processed footnotes and comments, the parsed document, and
    /// the options after waypoint reprocessing. Both public Up-mode entry points
    /// project from one of these.
    ///
    /// The Comments section is kept apart from `body` because it is emitted
    /// **outside** the article, as its `<footer>` sibling; `body` is only what
    /// goes inside. A fragment render, which has no article to sit outside of,
    /// just concatenates the two.
    struct UpRenderPipeline {
        let body: String
        let commentsSection: String
        let footnotes: [FootnoteEntry]
        let comments: [Comment]
        let parsed: ParsedMarkdown
        let options: RenderOptions
    }

    /// The single Up-mode orchestration: footnote/comment scanning at the
    /// String boundary (for the bottom sections and the comment model), one
    /// cmark parse of the raw source, the body render, and the bottom
    /// footnotes and comments sections. Every public Up-mode String entry
    /// point runs this once and projects what it needs, so a pipeline change
    /// is made in one place.
    static func renderUpPipeline(
        _ source: String,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> UpRenderPipeline {
        // `process` supplies the footnote/comment models for the bottom
        // sections; it rewrites nothing. The cmark visitor emits the markers
        // itself and skips definitions structurally, rendering the raw source
        // directly, and `UpHTMLVisitor.renderBody` diffs the raw waypoint
        // against the raw body — so the waypoint needs no reprocessing either.
        let result = FootnoteProcessor.process(source, mode: options.footnoteMode)
        let parsed = ParsedMarkdown(source)
        var body = UpHTMLVisitor.renderBody(
            parsed, options: options, resolveImageSource: resolveImageSource)
        body += FootnoteHTMLRenderer.section(
            result.footnotes, options: options,
            resolveImageSource: resolveImageSource)
        let commentsSection = CommentHTMLRenderer.section(
            result.comments, options: options,
            resolveImageSource: resolveImageSource)
        return UpRenderPipeline(
            body: body, commentsSection: commentsSection,
            footnotes: result.footnotes,
            comments: result.comments, parsed: parsed, options: options)
    }

    /// Renders Markdown text to HTML body content, including footnote
    /// preprocessing and the bottom footnotes and comments sections (if any).
    /// A fragment has no article element, so the Comments footer — which a whole
    /// document places outside it — is simply appended here.
    public static func renderUpToHTML(
        _ markdown: String,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        let pipeline = renderUpPipeline(
            markdown, options: options,
            resolveImageSource: resolveImageSource)
        return pipeline.body + pipeline.commentsSection
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
        let pipeline = renderUpPipeline(source, options: options,
                                        resolveImageSource: resolveImageSource)
        var options = pipeline.options
        if options.title.isEmpty {
            options.title = pipeline.parsed.title ?? ""
        }
        let html = HTMLTemplate.wrapUp(
            body: pipeline.body, footer: pipeline.commentsSection,
            options: options)

        var popovers: [RenderedFootnote] = []
        if options.footnoteMode == .popover {
            popovers = pipeline.footnotes.map { entry in
                RenderedFootnote(
                    label: entry.label, number: entry.number,
                    html: FootnoteHTMLRenderer.popoverDocument(
                        entry, options: options,
                        resolveImageSource: resolveImageSource))
            }
        }
        return RenderedUpDocument(
            html: html, footnotes: popovers, comments: pipeline.comments)
    }

    // MARK: - Export

    /// Renders a Markdown source as a self-contained export document — the one
    /// recipe behind every export path: Open In Browser, the Open In editor
    /// HTML handoff, the `mud` CLI's standalone output, and Quick Look. It
    /// forces `standalone` on, drops any change-tracking waypoint, strips every
    /// comment when `includeComments` is false, and — for an Up-mode document —
    /// inlines local images as data URIs (`ImageDataURI`) and projects the
    /// read-only Comments column over a source that has comments.
    ///
    /// `commentsColumn: false` pins the export to the bottom Comments section
    /// instead, at every width. Quick Look passes it: a preview is a pane the
    /// reader can't widen and can't toggle, so a column that only fits above the
    /// Compact tier is the wrong presentation there whatever the pane's size.
    /// This is a stronger guarantee than hiding the column in CSS — without
    /// `.interactive` the document carries neither the `comments-column` class
    /// nor the column script (`HTMLTemplate.wrapUp`), so there is nothing to
    /// project and nothing to hide.
    public static func exportDocument(
        _ markdown: String,
        mode: Mode,
        options: RenderOptions,
        includeComments: Bool,
        commentsColumn: Bool = true
    ) -> String {
        var options = options
        options.standalone = true
        options.waypoint = nil
        // Unless comments are included, drop every comment at the source so
        // the exported file holds none at all — no marker, section, or column.
        let source = includeComments ? markdown : removeComments(markdown)
        switch mode {
        case .down:
            return renderDownModeDocument(source, options: options)
        case .up:
            if commentsColumn {
                options = showingReadOnlyComments(options, ifPresentIn: source)
            }
            return renderUpModeDocument(
                source, options: options,
                resolveImageSource: { source, baseURL in
                    ImageDataURI.encode(source: source, baseURL: baseURL)
                })
        }
    }

    // MARK: - Popover documents

    /// Wraps ready-made body HTML as a self-contained themed document for a
    /// popover's WebView — the general form of the recipe
    /// ``renderCommentThreadDocument(_:options:resolveImageSource:)`` and the
    /// footnote popover documents each apply to their own body. It exists for
    /// content Swift can't produce ahead of time: a Mermaid diagram's parse
    /// error, which the page only has once Mermaid has failed.
    ///
    /// `options` should be the host window's, so the popover matches it in
    /// theme, lighting, and zoom; the whole-window state a small separate page
    /// has no use for is stripped (see `forPopover`), and the waypoint and
    /// title with it.
    ///
    /// The body arrives as HTML, not Markdown — a caller holding Markdown
    /// renders it with ``renderUpToHTML(_:options:resolveImageSource:)`` first
    /// — and nothing here escapes it. So a caller must not build the fragment
    /// out of text the document supplied.
    public static func renderPopoverDocument(
        body: String, options: RenderOptions = .init()
    ) -> String {
        var popoverOptions = options.forPopover()
        popoverOptions.waypoint = nil
        popoverOptions.title = ""
        // The same trimmed padding the footnote and comment popovers use.
        popoverOptions.htmlClasses.insert("footnote-popover")
        return HTMLTemplate.wrapUp(body: body, options: popoverOptions)
    }

    // MARK: - Comment rendering

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
        return CommentHTMLRenderer.listItem(
            comment, options: itemOptions, resolveImageSource: resolveImageSource)
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
        CommentHTMLRenderer.threadDocument(
            comment, options: options, resolveImageSource: resolveImageSource)
    }

    /// Parses the comments stored in a Markdown source without a full render —
    /// for the write path (reply/edit needs the current thread) and any caller
    /// that wants the model alone.
    public static func parseComments(_ source: String) -> [Comment] {
        FootnoteProcessor.process(source, mode: .popover).comments
    }

    /// Removes every comment (all `[^💬-x]` references and definition
    /// blocks) from a Markdown source, leaving the rest byte-for-byte. Powers
    /// the comment-invariant content identity that lets a comment add/remove
    /// update the live view in place without a WebView reload. Comment-free
    /// input is returned unchanged.
    public static func removeComments(_ source: String) -> String {
        FootnoteProcessor.removeComments(source)
    }

    /// Returns `options` adjusted to project the read-only Comments column, but
    /// only when `source` actually contains comments. `exportDocument` (and the
    /// `mud -u` CLI's non-standalone output) call this so a self-contained
    /// document shows the same projected column the app does, read-only: it
    /// switches the
    /// comment mode to `.interactive` (hiding the bottom section and the inline
    /// markers in favor of the column) and turns the column on with
    /// `is-comments-column` (an export has no live toggle to set it). The
    /// read-side JS that `HTMLTemplate.wrapUp` inlines for a read-only render
    /// then builds the column from the hidden section on load.
    ///
    /// A comment-free source is returned unchanged, so it reserves no column
    /// gutter. The live app view does not use this — it drives the column from
    /// per-window visibility state and injects the JS via WKUserScript.
    public static func showingReadOnlyComments(
        _ options: RenderOptions, ifPresentIn source: String
    ) -> RenderOptions {
        guard !parseComments(source).isEmpty else { return options }
        var adjusted = options
        adjusted.commentMode = .interactive
        adjusted.htmlClasses.insert("is-comments-column")
        return adjusted
    }

    // MARK: - Change tracking

    /// Computes a list of changes between two parsed Markdown documents
    /// for the sidebar change list and the waypoint dedup / menu counts.
    ///
    /// The definition policy follows `mode`, because change IDs are a running
    /// counter (`change-N`, minted in match order): a footnote-definition edit
    /// the visible body doesn't draw would still consume a number and shift
    /// every later ID, so a sidebar list on a policy the body doesn't share
    /// misnavigates. The Up body overlay skips footnote definitions
    /// structurally, so the Up sidebar must too (`.skipAll`); the Down body
    /// highlights plain definitions, so the Down sidebar descends them
    /// (`.descendPlainFootnotes`).
    ///
    /// `mode == nil` (waypoint dedup and the menu change counts) uses
    /// `.descendPlainFootnotes`: a footnote-definition edit is real content
    /// and should count and create a waypoint, regardless of which mode is on
    /// screen. See "Settle the sidebar and Down-mode diff policy" in
    /// Doc/Plans/Archive/2026-07-single-parser-rendering.md.
    public static func computeChanges(
        old: ParsedMarkdown, new: ParsedMarkdown, mode: Mode? = nil
    ) -> [DocumentChange] {
        guard let oldDoc = old.cmarkDocument,
              let newDoc = new.cmarkDocument else { return [] }
        let policy: DefinitionDiffPolicy =
            mode == .up ? .skipAll : .descendPlainFootnotes
        return ChangeList.computeChanges(
            plan: ChangePlan.plan(
                old: oldDoc, new: newDoc,
                definitionPolicy: policy))
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
}
