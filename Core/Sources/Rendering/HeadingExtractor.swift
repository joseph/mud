/// Walks a `CMarkDocument` and collects headings for the outline sidebar.
struct HeadingExtractor: CMarkWalker {
    var headings: [OutlineHeading] = []
    private var slugTracker = SlugGenerator.Tracker()

    mutating func visitHeading(_ node: CMarkNode) {
        let text = node.plainText
        let slug = slugTracker.slug(for: text)
        let line = node.range?.lowerBound.line ?? 0
        let segments = Self.extractSegments(from: node)
        headings.append(OutlineHeading(
            id: slug, level: node.headingLevel,
            text: text, segments: segments,
            sourceLine: line
        ))
    }

    /// Walks inline children of a heading node and produces styled
    /// text segments.  Code spans become `.code`; everything else
    /// (plain text, emphasis, strong, links, etc.) becomes `.plain`.
    private static func extractSegments(
        from node: CMarkNode
    ) -> [OutlineTextSegment] {
        var segments: [OutlineTextSegment] = []
        for child in node.children {
            switch child.kind {
            case .inlineCode:
                segments.append(.code(child.literal ?? ""))
            case .text:
                segments.append(.plain(child.literal ?? ""))
            case .softBreak:
                segments.append(.plain(" "))
            default:
                // Emphasis, Strong, Link, etc. — recurse.
                segments.append(contentsOf: extractSegments(from: child))
            }
        }
        return segments
    }
}
