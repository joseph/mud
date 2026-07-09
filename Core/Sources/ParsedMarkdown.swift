import Markdown

/// A parsed Markdown document. Parse once, reuse for rendering,
/// heading extraction, and title extraction.
public struct ParsedMarkdown {
    let document: Document

    /// The single footnote-aware cmark parse of `body` — the tree the
    /// render pipeline is moving onto (Stage 6 cutover of
    /// Doc/Plans/2026-07-single-parser-rendering.md). Retained on the struct
    /// so every cmark consumer (headings now; the visitors and diff layer at
    /// cutover) shares one owned tree. Optional only because
    /// `CMarkDocument(parsing:)` is failable; cmark parsing effectively never
    /// fails on a valid Swift string. The legacy `document` above is deleted
    /// once the swift-markdown pipeline goes.
    let cmarkDocument: CMarkDocument?

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

        // One footnote-aware cmark parse of `body`, retained on the struct
        // (see `cmarkDocument`). Headings read from it now; the visitors and
        // diff layer read from it at the Stage 6 cutover
        // (Doc/Plans/2026-07-single-parser-rendering.md). The legacy
        // swift-markdown `document` above is deleted once that lands.
        let cmarkDocument = CMarkDocument(parsing: body)
        self.cmarkDocument = cmarkDocument

        var extractor = HeadingExtractor()
        if let cmarkDocument {
            extractor.visit(cmarkDocument.root)
        }
        self.headings = extractor.headings
    }
}

// MARK: - Sendable + Equatable

// @unchecked because `document` wraps a reference-counted RawMarkup tree
// and `cmarkDocument` wraps a manually-freed cmark tree, neither of which
// is Sendable. Safe because ParsedMarkdown is immutable (all let fields),
// RawMarkup has no mutation API, and the cmark tree is read-only after
// parse (shared read-only across copies).
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
