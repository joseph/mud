import Markdown
import Testing

@testable import MudCore

/// Stage 1 of Doc/Plans/2026-07-single-parser-rendering.md: the `CMarkDocument`
/// wrapper. Beyond unit-testing the wrapper itself, the two parity suites at
/// the bottom compare it directly against swift-markdown — ranges and text
/// literals must match byte-for-byte, because that is the contract every later
/// stage's port relies on.
@Suite("CMarkDocument")
struct CMarkDocumentTests {

    // MARK: - Helpers

    /// Collects every node in walk (pre-)order. Overriding only `defaultVisit`
    /// sees all nodes because every specific visit falls back to it.
    private struct NodeCollector: CMarkWalker {
        var nodes: [CMarkNode] = []

        mutating func defaultVisit(_ node: CMarkNode) {
            nodes.append(node)
            descendInto(node)
        }
    }

    private func allNodes(_ document: CMarkDocument) -> [CMarkNode] {
        var collector = NodeCollector()
        collector.visit(document.root)
        return collector.nodes
    }

    private func nodes(
        ofKind kind: CMarkNodeKind, in document: CMarkDocument
    ) -> [CMarkNode] {
        allNodes(document).filter { $0.kind == kind }
    }

    private func slice(_ source: String, _ range: Range<Int>) -> String {
        String(decoding: Array(source.utf8)[range], as: UTF8.self)
    }

    // MARK: - Parsing and kinds

    @Test func parsesEmptySource() throws {
        let document = try #require(CMarkDocument(parsing: ""))
        #expect(document.root.kind == .document)
        #expect(Array(document.root.children).isEmpty)
    }

    @Test func recognizesCoreAndExtensionKinds() throws {
        let markdown = """
            # Title

            A *b* **c** `d` [e](f "g") ~~h~~ ![i](j) text.

            > quote

            - [ ] open task
            - [x] done task

            ```swift
            let value = 1
            ```
            """
        let document = try #require(CMarkDocument(parsing: markdown))

        let heading = try #require(nodes(ofKind: .heading, in: document).first)
        #expect(heading.headingLevel == 1)

        #expect(nodes(ofKind: .emphasis, in: document).count == 1)
        #expect(nodes(ofKind: .strong, in: document).count == 1)
        #expect(nodes(ofKind: .inlineCode, in: document).count == 1)
        #expect(nodes(ofKind: .strikethrough, in: document).count == 1)
        #expect(nodes(ofKind: .blockQuote, in: document).count == 1)

        let link = try #require(nodes(ofKind: .link, in: document).first)
        #expect(link.url == "f")
        #expect(link.title == "g")

        let image = try #require(nodes(ofKind: .image, in: document).first)
        #expect(image.url == "j")

        let tasks = nodes(ofKind: .taskListItem, in: document)
        #expect(tasks.map(\.taskListItemIsChecked) == [false, true])
        #expect(nodes(ofKind: .listItem, in: document).isEmpty)

        let codeBlock = try #require(
            nodes(ofKind: .codeBlock, in: document).first)
        #expect(codeBlock.fenceInfo == "swift")
        #expect(codeBlock.literal == "let value = 1\n")
    }

    @Test func readsTableStructureAndAlignments() throws {
        let markdown = """
            | a | b | c |
            | :- | :-: | -: |
            | 1 | 2 | 3 |
            """
        let document = try #require(CMarkDocument(parsing: markdown))

        let table = try #require(nodes(ofKind: .table, in: document).first)
        #expect(table.tableColumnCount == 3)
        #expect(table.tableAlignments == [.left, .center, .right])

        let head = try #require(nodes(ofKind: .tableHead, in: document).first)
        #expect(head.tableRowIsHeader)
        let bodyRow = try #require(
            nodes(ofKind: .tableRow, in: document).first)
        #expect(!bodyRow.tableRowIsHeader)

        #expect(nodes(ofKind: .tableCell, in: document).count == 6)
    }

    @Test func readsListTightnessFromTheParser() throws {
        let document = try #require(
            CMarkDocument(parsing: ParityCorpus.listItems.markdown))
        // Walk order: outer bullet list, its nested sublist, the ordered
        // list, then the loose bullet list.
        let lists = nodes(ofKind: .list, in: document)
        #expect(lists.map(\.listIsTight) == [true, true, true, false])
        let ordered = try #require(lists.first { $0.listType == .ordered })
        #expect(ordered.listStart == 1)
    }

    @Test func parsesFootnotesAsNodes() throws {
        let document = try #require(
            CMarkDocument(
                parsing: ParityCorpus.paragraphsWithInlineSyntax.markdown))

        let definitions = nodes(ofKind: .footnoteDefinition, in: document)
        #expect(definitions.map(\.literal) == ["1", "comment-a"])

        let references = nodes(ofKind: .footnoteReference, in: document)
        #expect(references.count == 2)
        #expect(
            references.map { $0.parentFootnoteDefinition?.literal }
                == ["1", "comment-a"])
    }

    @Test func smartTypographyLandsInTextLiterals() throws {
        let document = try #require(
            CMarkDocument(parsing: ParityCorpus.smartTypography.markdown))
        let text = nodes(ofKind: .text, in: document)
            .compactMap(\.literal).joined()
        #expect(text.contains("\u{201C}Curly double quotes\u{201D}"))
        #expect(text.contains("\u{2018}curly single quotes\u{2019}"))
        #expect(text.contains("It\u{2019}s"))
        #expect(text.contains("\u{2013}"))  // en dash from `--`
        #expect(text.contains("\u{2014}"))  // em dash from `---`
        #expect(text.contains("\u{2026}"))  // ellipsis from `...`
    }

    // MARK: - Walker dispatch

    @Test func walkerDispatchesAndOverridesStopDescent() throws {
        let document = try #require(CMarkDocument(parsing: "a **b** c"))

        struct StrongSkipper: CMarkWalker {
            var strongCount = 0
            var texts: [String] = []

            mutating func visitStrong(_ node: CMarkNode) {
                strongCount += 1  // deliberately no descendInto
            }

            mutating func visitText(_ node: CMarkNode) {
                texts.append(node.literal ?? "")
            }
        }

        var walker = StrongSkipper()
        walker.visit(document.root)
        #expect(walker.strongCount == 1)
        #expect(walker.texts == ["a ", " c"])
    }

    // MARK: - Ranges

    @Test func rangesAreExclusiveUpperBoundInUTF8ByteColumns() throws {
        // é is two UTF-8 bytes: the closing `*` sits at byte column 8, so the
        // exclusive upper bound is column 9.
        let source = "ab *cé* d"
        let document = try #require(CMarkDocument(parsing: source))
        let emphasis = try #require(
            nodes(ofKind: .emphasis, in: document).first)

        let range = try #require(emphasis.range)
        #expect(range.lowerBound == CMarkSourceLocation(line: 1, column: 4))
        #expect(range.upperBound == CMarkSourceLocation(line: 1, column: 9))

        let byteRange = try #require(emphasis.byteRange)
        #expect(byteRange == 3..<8)
        #expect(slice(source, byteRange) == "*cé*")
    }

    @Test func inlineCodeRangeIncludesTheBackticks() throws {
        let source = "a `b` c"
        let document = try #require(CMarkDocument(parsing: source))
        let code = try #require(nodes(ofKind: .inlineCode, in: document).first)
        #expect(code.backtickCount == 1)
        let byteRange = try #require(code.byteRange)
        #expect(slice(source, byteRange) == "`b`")
    }

    @Test func verifiedRangeSlicesDelimitedTokens() throws {
        let source = "Text[^1] *em* `co`.\n\n[^1]: Body.\n"
        let document = try #require(CMarkDocument(parsing: source))

        let reference = try #require(
            nodes(ofKind: .footnoteReference, in: document).first)
        let refRange = try #require(reference.verifiedRange)
        #expect(slice(source, refRange) == "[^1]")

        let emphasis = try #require(
            nodes(ofKind: .emphasis, in: document).first)
        let emRange = try #require(emphasis.verifiedRange)
        #expect(slice(source, emRange) == "*em*")

        let code = try #require(nodes(ofKind: .inlineCode, in: document).first)
        let codeRange = try #require(code.verifiedRange)
        #expect(slice(source, codeRange) == "`co`")
    }

    // MARK: - Lifetime

    @Test func nodeHandleKeepsTheTreeAlive() throws {
        var document: CMarkDocument? = CMarkDocument(parsing: "Hello *w*.")
        weak let weakDocument = document
        var node: CMarkNode? = document?.root.firstChild

        document = nil
        #expect(weakDocument != nil)  // the handle retains the tree
        #expect(node?.kind == .paragraph)

        node = nil
        #expect(node == nil)
        #expect(weakDocument == nil)  // last handle gone, tree freed
    }

    // MARK: - Corpus

    /// Every corpus document parses, walks, and yields verified byte ranges
    /// for each delimiter-checkable inline — the well-formed corpus must
    /// never trip the corruption defense.
    @Test(arguments: ParityCorpus.all)
    func corpusParsesAndVerifies(_ corpusDocument: ParityCorpus.Document) throws {
        let document = try #require(
            CMarkDocument(parsing: corpusDocument.markdown))
        let nodes = allNodes(document)
        #expect(nodes.count > 1)

        let byteCount = corpusDocument.markdown.utf8.count
        for node in nodes {
            switch node.kind {
            case .emphasis, .strong, .strikethrough, .inlineCode,
                 .footnoteReference, .image:
                #expect(
                    node.verifiedRange != nil,
                    "\(node.typeString) in \(corpusDocument.name)")
            default:
                break
            }
            if let byteRange = node.byteRange {
                #expect(byteRange.upperBound <= byteCount)
            }
        }
    }

    // MARK: - Parity with swift-markdown

    private struct RangeRecord: Equatable, CustomStringConvertible {
        let label: String
        let startLine: Int
        let startColumn: Int
        let endLine: Int
        let endColumn: Int

        var description: String {
            "\(label) \(startLine):\(startColumn)..<\(endLine):\(endColumn)"
        }
    }

    /// The kinds compared across both parsers, keyed by a shared label.
    private static let comparedKinds: [CMarkNodeKind: String] = [
        .heading: "heading", .paragraph: "paragraph", .emphasis: "emphasis",
        .strong: "strong", .inlineCode: "inlineCode", .link: "link",
        .strikethrough: "strikethrough", .text: "text",
    ]

    private struct CMarkRangeCollector: CMarkWalker {
        var records: [RangeRecord] = []

        mutating func defaultVisit(_ node: CMarkNode) {
            if let label = CMarkDocumentTests.comparedKinds[node.kind],
               let range = node.range {
                records.append(RangeRecord(
                    label: label,
                    startLine: range.lowerBound.line,
                    startColumn: range.lowerBound.column,
                    endLine: range.upperBound.line,
                    endColumn: range.upperBound.column))
            }
            descendInto(node)
        }
    }

    private struct SwiftMarkdownRangeCollector: MarkupWalker {
        var records: [RangeRecord] = []

        mutating func defaultVisit(_ markup: Markup) {
            let label: String? = switch markup {
            case is Markdown.Heading: "heading"
            case is Markdown.Paragraph: "paragraph"
            case is Markdown.Emphasis: "emphasis"
            case is Markdown.Strong: "strong"
            case is Markdown.InlineCode: "inlineCode"
            case is Markdown.Link: "link"
            case is Markdown.Strikethrough: "strikethrough"
            case is Markdown.Text: "text"
            default: nil
            }
            if let label, let range = markup.range {
                records.append(RangeRecord(
                    label: label,
                    startLine: range.lowerBound.line,
                    startColumn: range.lowerBound.column,
                    endLine: range.upperBound.line,
                    endColumn: range.upperBound.column))
            }
            descendInto(markup)
        }
    }

    /// Parses `source` with both parsers and asserts the collected range
    /// records match exactly.
    private func expectRangesMatchSwiftMarkdown(
        _ source: String,
        sourceLocation: Testing.SourceLocation = #_sourceLocation
    ) throws {
        let document = try #require(
            CMarkDocument(parsing: source), sourceLocation: sourceLocation)
        var cmarkSide = CMarkRangeCollector()
        cmarkSide.visit(document.root)

        var swiftMarkdownSide = SwiftMarkdownRangeCollector()
        swiftMarkdownSide.visit(Markdown.Document(parsing: source))

        #expect(!cmarkSide.records.isEmpty, sourceLocation: sourceLocation)
        #expect(
            cmarkSide.records == swiftMarkdownSide.records,
            sourceLocation: sourceLocation)
    }

    /// The wrapper's range conventions must equal swift-markdown's exactly —
    /// including the multibyte characters that make byte columns diverge from
    /// character columns, and the backtick widening on inline code. The
    /// corpus documents are ASCII-only sources, so this hand-written document
    /// keeps the multibyte case covered.
    @Test func rangeConventionsMatchSwiftMarkdown() throws {
        try expectRangesMatchSwiftMarkdown("""
            # Héading

            Para *em* **st** `cö` [li](u) and ~~sk~~ døne.
            """)
    }

    /// The same range comparison over the whole corpus. Footnote-bearing
    /// documents are excluded for the same reason as
    /// `textLiteralsMatchSwiftMarkdown` below: swift-markdown is
    /// footnote-unaware, so its tree differs there by design.
    @Test(arguments: ParityCorpus.all.filter { !$0.markdown.contains("[^") })
    func rangeConventionsMatchSwiftMarkdownOverCorpus(
        _ corpusDocument: ParityCorpus.Document
    ) throws {
        try expectRangesMatchSwiftMarkdown(corpusDocument.markdown)
    }

    /// Both parsers must yield byte-identical text-node literals — the
    /// smart-typography contract four subsystems are calibrated to.
    /// Footnote-bearing documents are excluded: swift-markdown is
    /// footnote-unaware, so its text stream differs there by design.
    @Test(arguments: ParityCorpus.all.filter { !$0.markdown.contains("[^") })
    func textLiteralsMatchSwiftMarkdown(
        _ corpusDocument: ParityCorpus.Document
    ) throws {
        let document = try #require(
            CMarkDocument(parsing: corpusDocument.markdown))
        let cmarkLiterals = nodes(ofKind: .text, in: document)
            .compactMap(\.literal)

        struct TextCollector: MarkupWalker {
            var literals: [String] = []
            mutating func visitText(_ text: Markdown.Text) {
                literals.append(text.string)
            }
        }
        var swiftMarkdownSide = TextCollector()
        swiftMarkdownSide.visit(
            Markdown.Document(parsing: corpusDocument.markdown))

        #expect(!cmarkLiterals.isEmpty)
        #expect(cmarkLiterals == swiftMarkdownSide.literals)
    }
}
