// MudCore - Shared Markdown rendering library for the Mud app

import Foundation

/// A rendered Up-mode HTML document plus the footnote popover documents that
/// accompany it (populated only in `.popover` mode).
public struct RenderedUpDocument: Sendable {
    public let html: String
    public let footnotes: [RenderedFootnote]

    public init(html: String, footnotes: [RenderedFootnote]) {
        self.html = html
        self.footnotes = footnotes
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
        let parsed = ParsedMarkdown(result.transformedMarkdown)
        var body = renderUpBody(parsed, options: options,
                                resolveImageSource: resolveImageSource)
        body += renderFootnotesSection(result.footnotes, options: options,
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
        var options = options
        if options.title.isEmpty {
            options.title = parsed.title ?? ""
        }
        var body = renderUpBody(parsed, options: options,
                                resolveImageSource: resolveImageSource)
        body += renderFootnotesSection(result.footnotes, options: options,
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
        return RenderedUpDocument(html: html, footnotes: popovers)
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
