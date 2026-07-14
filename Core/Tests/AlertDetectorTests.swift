import Testing
@testable import MudCore

/// Tests for `AlertDetector`'s `CMarkNode` alert detection: GFM `[!TAG]`
/// alerts and DocC `Kind:` asides, plus the smart-typography input the
/// detector must handle without crashing.
@Suite("AlertDetector")
struct AlertDetectorTests {

    /// Parses `markdown` (expected to contain a single block quote) and
    /// returns its block-quote node.
    private func firstBlockQuote(_ markdown: String) throws -> CMarkNode {
        let document = try #require(CMarkDocument(parsing: markdown))
        return try #require(
            document.root.children.first { $0.kind == .blockQuote })
    }

    // MARK: - GFM alerts

    struct GFMCase: Sendable {
        let markdown: String
        let category: AlertCategory?
        let title: String?
    }

    @Test(arguments: [
        GFMCase(markdown: "> [!NOTE]\n> Body.\n",
            category: .note, title: "Note"),
        GFMCase(markdown: "> [!TIP]\n> Body.\n",
            category: .tip, title: "Tip"),
        GFMCase(markdown: "> [!IMPORTANT]\n> Body.\n",
            category: .important, title: "Important"),
        GFMCase(markdown: "> [!WARNING]\n> Body.\n",
            category: .warning, title: "Warning"),
        GFMCase(markdown: "> [!CAUTION]\n> Body.\n",
            category: .caution, title: "Caution"),
        GFMCase(markdown: "> [!STATUS]\n> Body.\n",
            category: .status, title: "Status"),
        GFMCase(markdown: "> Not an alert.\n",
            category: nil, title: nil),
    ])
    func gfmAlert(_ testCase: GFMCase) throws {
        let quote = try firstBlockQuote(testCase.markdown)
        let detector = AlertDetector()
        let result = detector.detectGFMAlert(quote)
        #expect(result?.0.rawValue == testCase.category?.rawValue)
        #expect(result?.1 == testCase.title)
    }

    // MARK: - DocC asides

    struct DocCTagCase: Sendable {
        let tag: String
        let categoryRawValue: String
    }

    /// Every recognized DocC tag, from both maps, sorted for a stable sweep.
    /// Reads the maps `detectDocCAlert` itself consults, so the test proves
    /// the cmark parsing path pulls each tag out of the AST and maps it to the
    /// right category.
    static let docCTagCases: [DocCTagCase] = {
        let all = AlertDetector.coreMap.merging(
            AlertDetector.extendedMap) { core, _ in core }
        return all.keys.sorted().map { key in
            DocCTagCase(tag: key, categoryRawValue: all[key]!.rawValue)
        }
    }()

    @Test(arguments: docCTagCases)
    func docCAlertMapsEveryTag(_ testCase: DocCTagCase) throws {
        let quote = try firstBlockQuote("> \(testCase.tag): Body.\n")
        let detector = AlertDetector()
        let result = detector.detectDocCAlert(quote)
        #expect(result?.category.rawValue == testCase.categoryRawValue)
        // tagByteLength covers the tag, its colon, and the trailing space.
        #expect(result?.tagByteLength == "\(testCase.tag): ".utf8.count)
        #expect(result?.title != nil)
    }

    struct DocCTitleCase: Sendable {
        let tag: String
        let title: String
    }

    /// Pins the hand-written display names — the four tags whose title is not
    /// just the tag itself, plus two ordinary ones.
    @Test(arguments: [
        DocCTitleCase(tag: "Note", title: "Note"),
        DocCTitleCase(tag: "Bug", title: "Bug"),
        DocCTitleCase(tag: "SeeAlso", title: "See Also"),
        DocCTitleCase(tag: "ToDo", title: "To Do"),
        DocCTitleCase(tag: "MutatingVariant", title: "Mutating Variant"),
        DocCTitleCase(tag: "NonMutatingVariant",
            title: "Non-Mutating Variant"),
    ])
    func docCAlertTitle(_ testCase: DocCTitleCase) throws {
        let quote = try firstBlockQuote("> \(testCase.tag): Body.\n")
        #expect(
            AlertDetector().detectDocCAlert(quote)?.title == testCase.title)
    }

    @Test func docCAlertRejectsUnrecognizedTag() throws {
        let quote = try firstBlockQuote("> Unrecognized: Body.\n")
        #expect(AlertDetector().detectDocCAlert(quote) == nil)
    }

    @Test func docCAlertRejectsTaglessQuote() throws {
        let quote = try firstBlockQuote("> Plain quote, no tag.\n")
        #expect(AlertDetector().detectDocCAlert(quote) == nil)
    }

    @Test func docCAlertOffModeReturnsNil() throws {
        let quote = try firstBlockQuote("> Bug: Body.\n")
        var detector = AlertDetector()
        detector.docCAlertMode = .off
        #expect(detector.detectDocCAlert(quote) == nil)
    }

    @Test func docCAlertCommonModeExcludesExtendedAliases() throws {
        let quote = try firstBlockQuote("> Bug: Body.\n")
        var detector = AlertDetector()
        detector.docCAlertMode = .common
        #expect(detector.detectDocCAlert(quote) == nil)
    }

    @Test func docCAlertCommonModeStillMatchesCoreKinds() throws {
        let quote = try firstBlockQuote("> Note: Body.\n")
        var detector = AlertDetector()
        detector.docCAlertMode = .common
        #expect(
            detector.detectDocCAlert(quote)?.category.rawValue
                == AlertCategory.note.rawValue)
    }

    /// The tag-shift input swift-markdown's `Aside` was vulnerable to: smart
    /// typography expands the apostrophe in "Don't" from one byte to three, so
    /// a range built from the pre-expansion source span could invert and trap.
    /// `detectDocCAlert` measures the smart-typographed literal directly, so it
    /// has no arithmetic that can invert; "Don't" isn't a recognized tag, so
    /// the result is nil.
    @Test func tagShiftCrashInputReturnsNil() throws {
        let quote = try firstBlockQuote("> Don't: x\n")
        #expect(AlertDetector().detectDocCAlert(quote) == nil)
    }

    @Test func tagByteLengthSkipsTagColonAndSpace() throws {
        let quote = try firstBlockQuote("> Note: Body text.\n")
        let result = AlertDetector().detectDocCAlert(quote)
        #expect(result?.tagByteLength == "Note: ".utf8.count)
    }
}
