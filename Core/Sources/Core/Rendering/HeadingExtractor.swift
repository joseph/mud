import Markdown

/// Walks a swift-markdown `Document` and collects headings for the
/// outline sidebar.
struct HeadingExtractor: MarkupWalker {
    var headings: [OutlineHeading] = []
    private var slugTracker = SlugGenerator.Tracker()

    mutating func visitHeading(_ heading: Heading) {
        let slug = slugTracker.slug(for: heading.plainText)
        let line = heading.range?.lowerBound.line ?? 0
        let segments = Self.extractSegments(from: heading)
        headings.append(OutlineHeading(
            id: slug, level: heading.level,
            text: heading.plainText, segments: segments,
            sourceLine: line
        ))
    }

    /// Walks inline children of a markup node and produces styled
    /// text segments.  Code spans become `.code`; everything else
    /// (plain text, emphasis, strong, links, etc.) becomes `.plain`.
    private static func extractSegments(
        from node: Markup
    ) -> [OutlineTextSegment] {
        var segments: [OutlineTextSegment] = []
        for child in node.children {
            if let code = child as? InlineCode {
                segments.append(.code(code.code))
            } else if let text = child as? Markdown.Text {
                segments.append(.plain(text.string))
            } else if child is SoftBreak {
                segments.append(.plain(" "))
            } else {
                // Emphasis, Strong, Link, etc. — recurse.
                segments.append(contentsOf: extractSegments(from: child))
            }
        }
        return segments
    }
}
