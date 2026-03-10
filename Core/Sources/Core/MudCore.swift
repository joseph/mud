// MudCore - Shared Markdown rendering library for the Mud app

import Foundation

/// Entry point for MudCore functionality.
public enum MudCore {
    public static let version = "1.0.0"

    private static let downVisitor = DownHTMLVisitor()

    /// Renders Markdown text to HTML body content.
    public static func renderUpToHTML(
        _ markdown: String,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        let doc = MarkdownParser.parse(markdown)
        var upVisitor = UpHTMLVisitor()
        upVisitor.baseURL = options.baseURL
        upVisitor.resolveImageSource = resolveImageSource
        upVisitor.alertDetector.doccAlertMode = options.doccAlertMode
        upVisitor.visit(doc)
        return upVisitor.result
    }

    /// Renders Markdown text to a complete HTML document with styles.
    public static func renderUpModeDocument(
        _ markdown: String,
        options: RenderOptions = .init(),
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        let body = renderUpToHTML(markdown, options: options,
                                resolveImageSource: resolveImageSource)
        var docOptions = options
        if options.includeBaseTag {
            docOptions.baseURL = options.baseURL
        } else {
            docOptions.baseURL = nil
        }
        return HTMLTemplate.wrapUp(body: body, options: docOptions)
    }

    /// Extracts headings from a Markdown string for the outline sidebar.
    public static func extractHeadings(_ markdown: String) -> [OutlineHeading] {
        let doc = MarkdownParser.parse(markdown)
        var extractor = HeadingExtractor()
        extractor.visit(doc)
        return extractor.headings
    }

    /// Renders Markdown text to an HTML table for Down mode (body only).
    public static func renderDownToHTML(
        _ text: String,
        options: RenderOptions = .init()
    ) -> String {
        downVisitor.highlightAsTable(text, doccAlertMode: options.doccAlertMode)
    }

    /// Renders Markdown text to a complete HTML document for Down mode.
    public static func renderDownModeDocument(
        _ text: String,
        options: RenderOptions = .init()
    ) -> String {
        let tableHTML = downVisitor.highlightAsTable(
            text, doccAlertMode: options.doccAlertMode)
        return HTMLTemplate.wrapDown(tableHTML: tableHTML, options: options)
    }
}
