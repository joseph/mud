import Markdown

/// Single parse entry point. Parses once; both visitors receive
/// the same `Document`.
enum MarkdownParser {
    /// Parses a Markdown string into a typed AST.
    ///
    /// Default options enable smart typography and source-position
    /// tracking. GFM extensions (tables, strikethrough, task lists)
    /// are always active in swift-markdown.
    static func parse(_ markdown: String) -> Document {
        Document(parsing: markdown)
    }
}
