import Markdown
import Testing
@testable import MudCore

@Suite("HeadingExtractor")
struct HeadingExtractorTests {
    @Test func singleHeading() {
        let headings = MudCore.extractHeadings("# Hello\n")
        #expect(headings.count == 1)
        #expect(headings[0].level == 1)
        #expect(headings[0].text == "Hello")
        #expect(headings[0].id == "hello")
        #expect(headings[0].sourceLine == 1)
    }

    @Test func multipleHeadingsAtDifferentLevels() {
        let md = """
        # One
        ## Two
        ### Three
        """
        let headings = MudCore.extractHeadings(md)
        #expect(headings.count == 3)
        #expect(headings[0].level == 1)
        #expect(headings[1].level == 2)
        #expect(headings[2].level == 3)
    }

    @Test func headingWithInlineCode() {
        let headings = MudCore.extractHeadings("## The `foo` method\n")
        #expect(headings.count == 1)
        #expect(headings[0].segments == [
            .plain("The "),
            .code("foo"),
            .plain(" method"),
        ])
    }

    @Test func headingWithEmphasis() {
        let headings = MudCore.extractHeadings("## An *important* note\n")
        #expect(headings.count == 1)
        // Emphasis is flattened to plain text segments.
        #expect(headings[0].segments == [
            .plain("An "),
            .plain("important"),
            .plain(" note"),
        ])
    }

    @Test func headingWithLink() {
        let headings = MudCore.extractHeadings("## See [this](url)\n")
        #expect(headings.count == 1)
        #expect(headings[0].segments == [
            .plain("See "),
            .plain("this"),
        ])
    }

    @Test func emptyDocument() {
        #expect(MudCore.extractHeadings("").isEmpty)
        #expect(MudCore.extractHeadings("No headings here.\n").isEmpty)
    }

    @Test func slugMatchesUpVisitor() {
        let md = "## Hello World\n"
        let headings = MudCore.extractHeadings(md)
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("id=\"\(headings[0].id)\""))
    }

    // MARK: - Parity with the pre-port swift-markdown extractor

    /// The swift-markdown-based extractor `HeadingExtractor` replaced when
    /// it ported onto `CMarkNode` (Stage 2 of
    /// Doc/Plans/2026-07-single-parser-rendering.md). Copied verbatim from
    /// that implementation so this file can prove the port didn't change
    /// output.
    private struct LegacyHeadingExtractor: MarkupWalker {
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
                    segments.append(contentsOf: extractSegments(from: child))
                }
            }
            return segments
        }
    }

    @Test(arguments: ParityCorpus.all)
    func slugsAndSegmentsMatchLegacyExtractor(
        _ corpusDocument: ParityCorpus.Document
    ) throws {
        // `ParsedMarkdown` extracts headings from the frontmatter-stripped
        // body, not the raw markdown — match that here for a fair
        // comparison.
        let body = FrontMatterExtractor.extract(from: corpusDocument.markdown)?
            .body ?? corpusDocument.markdown

        var legacy = LegacyHeadingExtractor()
        legacy.visit(MarkdownParser.parse(body))

        let ported = MudCore.extractHeadings(corpusDocument.markdown)

        #expect(ported.map(\.id) == legacy.headings.map(\.id))
        #expect(ported.map(\.level) == legacy.headings.map(\.level))
        #expect(ported.map(\.text) == legacy.headings.map(\.text))
        #expect(ported.map(\.sourceLine) == legacy.headings.map(\.sourceLine))
        #expect(ported.map(\.segments) == legacy.headings.map(\.segments))
    }
}
