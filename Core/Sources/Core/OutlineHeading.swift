/// A styled span within a heading's text.
public enum OutlineTextSegment: Equatable, Sendable {
    case plain(String)
    case code(String)
}

/// A single heading extracted from a Markdown document.
public struct OutlineHeading: Identifiable, Equatable, Sendable {
    public let id: String      // slug (matches <h# id="..."> in web mode)
    public let level: Int      // 1–6
    public let text: String    // plain text (for slugs and fallback)
    public let segments: [OutlineTextSegment] // styled spans for display
    public let sourceLine: Int // 1-based line number (for Down mode scroll)
}
