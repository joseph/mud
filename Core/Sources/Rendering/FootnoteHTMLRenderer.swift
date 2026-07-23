import Foundation

/// Emits footnote HTML: the bottom `<section class="footnotes">` and the
/// self-contained popover document for a single footnote body. Moved out of
/// the `MudCore` facade, which keeps only dispatch.
enum FootnoteHTMLRenderer {
    /// The bottom `<section class="footnotes">`. Each body is rendered as an
    /// Up-mode fragment with a trailing back-reference link. Returns an empty
    /// string when there are no footnotes.
    static func section(
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
            let fragment = UpHTMLVisitor.renderBody(
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
    static func popoverDocument(
        _ entry: FootnoteEntry,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?
    ) -> String {
        var popoverOptions = options.withoutCommentsColumn()
        popoverOptions.waypoint = nil
        popoverOptions.title = ""
        // Trims the page's generous padding (esp. the 6em bottom reserved for
        // floating bars, absent in a popover).
        popoverOptions.htmlClasses.insert("footnote-popover")
        let parsed = ParsedMarkdown(entry.bodyMarkdown)
        let body = UpHTMLVisitor.renderBody(
            parsed, options: popoverOptions,
            resolveImageSource: resolveImageSource)
        return HTMLTemplate.wrapUp(body: body, options: popoverOptions)
    }
}
