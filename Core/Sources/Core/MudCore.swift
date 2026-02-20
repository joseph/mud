// MudCore - Shared Markdown rendering library for the Mud app

import Foundation

/// Entry point for MudCore functionality.
public enum MudCore {
    public static let version = "0.1.0"

    private static let downVisitor = DownHTMLVisitor()

    /// Renders Markdown text to HTML body content.
    public static func renderToHTML(
        _ markdown: String,
        baseURL: URL? = nil,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        let doc = MarkdownParser.parse(markdown)
        var upVisitor = UpHTMLVisitor()
        upVisitor.baseURL = baseURL
        upVisitor.resolveImageSource = resolveImageSource
        upVisitor.visit(doc)
        return upVisitor.result
    }

    /// Renders Markdown text to a complete HTML document with styles.
    ///
    /// - Parameter includeBaseTag: When `true` (the default), a `<base>`
    ///   tag pointing to `baseURL` is included in the document head.
    ///   Pass `false` when images have already been resolved to data URIs
    ///   and the document will be opened in an external browser, where a
    ///   file-path base URL would break anchor links.
    public static func renderUpModeDocument(
        _ markdown: String,
        title: String = "",
        baseURL: URL? = nil,
        theme: String = "earthy",
        includeBaseTag: Bool = true,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        let body = renderToHTML(markdown, baseURL: baseURL,
                                resolveImageSource: resolveImageSource)
        let templateBase = includeBaseTag ? baseURL : nil
        return HTMLTemplate.wrapUp(body: body, title: title, baseURL: templateBase,
                                theme: theme)
    }

    /// Extracts headings from a Markdown string for the outline sidebar.
    public static func extractHeadings(_ markdown: String) -> [OutlineHeading] {
        let doc = MarkdownParser.parse(markdown)
        var extractor = HeadingExtractor()
        extractor.visit(doc)
        return extractor.headings
    }

    /// Renders Markdown text to an HTML table for Down mode (body only).
    public static func renderDownToHTML(_ text: String) -> String {
        downVisitor.highlightAsTable(text)
    }

    /// Renders Markdown text to a complete HTML document for Down mode.
    public static func renderDownModeDocument(
        _ text: String,
        title: String = "",
        theme: String = "earthy"
    ) -> String {
        let tableHTML = downVisitor.highlightAsTable(text)
        return HTMLTemplate.wrapDown(tableHTML: tableHTML, title: title,
                                    theme: theme)
    }
}
