import Markdown

/// A parsed Markdown document. Parse once, reuse for rendering,
/// heading extraction, and title extraction.
public struct ParsedMarkdown {
    let document: Document
    public let markdown: String
    public let headings: [OutlineHeading]

    /// The raw YAML content from frontmatter (without delimiters),
    /// or `nil` if no frontmatter was detected.
    public let frontMatter: String?

    /// The Markdown content after frontmatter has been stripped.
    /// If no frontmatter, this equals `markdown`.
    public let body: String

    /// The number of source lines consumed by frontmatter
    /// (opening delimiter + content + closing delimiter).
    /// Zero if no frontmatter.
    let frontMatterLineCount: Int

    /// The plain text of the first heading, or `nil` if the document
    /// has no headings.
    public var title: String? { headings.first?.text }

    public init(_ markdown: String) {
        // Normalize \r\n → \n. Swift treats \r\n as a single
        // grapheme cluster, so line splitting fails without this.
        let normalized = markdown.replacingOccurrences(
            of: "\r\n", with: "\n")
        self.markdown = normalized

        if let fm = FrontMatterExtractor.extract(from: normalized) {
            self.frontMatter = fm.yaml
            self.body = fm.body
            self.frontMatterLineCount = fm.lineCount
        } else {
            self.frontMatter = nil
            self.body = normalized
            self.frontMatterLineCount = 0
        }

        self.document = MarkdownParser.parse(body)
        var extractor = HeadingExtractor()
        extractor.visit(document)
        self.headings = extractor.headings
    }
}

// MARK: - Sendable + Equatable

// @unchecked because Document wraps a reference-counted RawMarkup tree
// that lacks Sendable conformance. Safe because ParsedMarkdown is
// immutable (all let fields) and RawMarkup has no mutation API.
extension ParsedMarkdown: @unchecked Sendable {}

extension ParsedMarkdown: Equatable {
    public static func == (lhs: ParsedMarkdown, rhs: ParsedMarkdown) -> Bool {
        lhs.markdown == rhs.markdown
    }
}

extension ParsedMarkdown: Hashable {
    /// Hashes by the source text, consistent with `==` above. Lets a
    /// waypoint participate in `RenderOptions.ContentIdentity`'s synthesized
    /// conformance.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(markdown)
    }
}
