import Testing

@testable import MudCore

/// Stage 1 of Doc/Plans/2026-07-single-parser-rendering.md: the `CMarkDocument`
/// wrapper. These unit-test the wrapper's kinds, ranges, walker, lifetime, and
/// smart-typography literals directly. (Through Stage 6 a parity suite here
/// also compared every range and text literal against swift-markdown; that
/// cross-check was scaffolding for the port and left with the dependency in
/// Stage 7. The range conventions it guarded — exclusive upper bound, UTF-8
/// byte columns, backtick widening — are now pinned as self-contained golden
/// slices below.)
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

    // MARK: - Multibyte range conventions (golden)

    /// The range conventions the whole port relies on, pinned as byte slices
    /// through a multibyte source (through Stage 6 these were checked against
    /// swift-markdown; the cross-check left with the dependency). `ö` and `é`
    /// are two UTF-8 bytes each, so every token after them sits at a byte
    /// column past its character column — the case that separates UTF-8 byte
    /// columns from character columns. Inline code slices include the widening
    /// backticks; the other delimited inlines slice their own fences.
    @Test func multibyteRangesSliceEveryInlineToken() throws {
        let source = "Para *em* **st** `cö` [li](u) and ~~sk~~ døne."
        let document = try #require(CMarkDocument(parsing: source))

        func onlySlice(_ kind: CMarkNodeKind) throws -> String {
            let node = try #require(nodes(ofKind: kind, in: document).first)
            return slice(source, try #require(node.verifiedRange))
        }

        #expect(try onlySlice(.emphasis) == "*em*")
        #expect(try onlySlice(.strong) == "**st**")
        #expect(try onlySlice(.inlineCode) == "`cö`")
        #expect(try onlySlice(.strikethrough) == "~~sk~~")
        #expect(try onlySlice(.link) == "[li](u)")
    }
}
