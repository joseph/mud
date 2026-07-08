import Markdown
import Testing
@testable import MudCore

/// Parity tests for the `CMarkNode`-based alert detection added in Stage 2
/// of Doc/Plans/2026-07-single-parser-rendering.md. `AlertDetector`'s
/// original swift-markdown methods stay in production use (`UpHTMLVisitor`,
/// `DownHTMLVisitor`) until Stage 3/5 port those visitors; these tests only
/// prove the new `CMarkNode` methods agree with them.
@Suite("AlertDetector CMark port")
struct AlertDetectorTests {

    /// Parses `markdown` (expected to be a single block quote) with both
    /// parsers and returns the block quote node from each.
    private func parseFirstBlockQuote(
        _ markdown: String
    ) throws -> (legacy: BlockQuote, ported: CMarkNode) {
        let legacy = try #require(
            MarkdownParser.parse(markdown).child(at: 0) as? BlockQuote)

        struct FirstBlockQuoteCollector: CMarkWalker {
            var blockQuote: CMarkNode?
            mutating func visitBlockQuote(_ node: CMarkNode) {
                if blockQuote == nil { blockQuote = node }
            }
        }
        let document = try #require(CMarkDocument(parsing: markdown))
        var collector = FirstBlockQuoteCollector()
        collector.visit(document.root)
        let ported = try #require(collector.blockQuote)

        return (legacy, ported)
    }

    // MARK: - GFM alerts

    @Test(arguments: [
        "> [!NOTE]\n> Body.\n",
        "> [!TIP]\n> Body.\n",
        "> [!IMPORTANT]\n> Body.\n",
        "> [!WARNING]\n> Body.\n",
        "> [!CAUTION]\n> Body.\n",
        "> [!STATUS]\n> Body.\n",
        "> Not an alert.\n",
    ])
    func gfmAlertMatchesLegacy(_ markdown: String) throws {
        let (legacyQuote, portedQuote) = try parseFirstBlockQuote(markdown)
        let detector = AlertDetector()
        let legacy = detector.detectGFMAlert(legacyQuote)
        let ported = detector.detectGFMAlert(portedQuote)
        #expect(ported?.0.rawValue == legacy?.0.rawValue)
        #expect(ported?.1 == legacy?.1)
    }

    // MARK: - DocC asides

    /// Every recognized DocC tag from both maps — so the sweep pins each of
    /// `docCDisplayName`'s hard-coded titles ("See Also", "To Do", …) against
    /// `Aside.Kind.displayName` — plus an unrecognized tag and a tagless
    /// quote.
    private static let docCCases: [String] =
        (AlertDetector.coreMap.keys.sorted()
            + AlertDetector.extendedMap.keys.sorted())
        .map { "> \($0): Body.\n" }
        + ["> Unrecognized: Body.\n", "> Plain quote, no tag.\n"]

    @Test(arguments: docCCases)
    func docCAlertMatchesLegacy(_ markdown: String) throws {
        let (legacyQuote, portedQuote) = try parseFirstBlockQuote(markdown)
        let detector = AlertDetector()
        let legacy = detector.detectDocCAlert(legacyQuote)
        let ported = detector.detectDocCAlert(portedQuote)
        #expect(ported?.category.rawValue == legacy?.0.rawValue)
        #expect(ported?.title == legacy?.1)
    }

    @Test func docCAlertOffModeMatchesLegacy() throws {
        let (legacyQuote, portedQuote) =
            try parseFirstBlockQuote("> Bug: Body.\n")
        var detector = AlertDetector()
        detector.docCAlertMode = .off
        #expect(detector.detectDocCAlert(legacyQuote) == nil)
        #expect(detector.detectDocCAlert(portedQuote) == nil)
    }

    @Test func docCAlertCommonModeExcludesExtendedAliases() throws {
        let (legacyQuote, portedQuote) =
            try parseFirstBlockQuote("> Bug: Body.\n")
        var detector = AlertDetector()
        detector.docCAlertMode = .common
        #expect(detector.detectDocCAlert(legacyQuote) == nil)
        #expect(detector.detectDocCAlert(portedQuote) == nil)
    }

    @Test func docCAlertCommonModeStillMatchesCoreKinds() throws {
        let (legacyQuote, portedQuote) =
            try parseFirstBlockQuote("> Note: Body.\n")
        var detector = AlertDetector()
        detector.docCAlertMode = .common
        #expect(
            detector.detectDocCAlert(legacyQuote)?.0.rawValue
                == AlertCategory.note.rawValue)
        #expect(
            detector.detectDocCAlert(portedQuote)?.category.rawValue
                == AlertCategory.note.rawValue)
    }

    /// The tag-shift crash swift-markdown's `Aside` is vulnerable to: smart
    /// typography expands the apostrophe in "Don't" from one byte to three,
    /// so a range built from the pre-expansion source span can invert and
    /// trap (`asideTagShiftIsInBounds` guards the legacy path against it).
    /// The ported parser never builds that range, so it can't crash this
    /// way — this only proves it returns the same (nil) result the guard
    /// produces, since "Don't" isn't a recognized tag either way.
    @Test func tagShiftCrashInputMatchesLegacyGuard() throws {
        let (legacyQuote, portedQuote) =
            try parseFirstBlockQuote("> Don't: x\n")
        let detector = AlertDetector()
        #expect(detector.detectDocCAlert(legacyQuote) == nil)
        #expect(detector.detectDocCAlert(portedQuote) == nil)
    }

    @Test func tagByteLengthSkipsTagColonAndSpace() throws {
        let (_, portedQuote) = try parseFirstBlockQuote("> Note: Body text.\n")
        let detector = AlertDetector()
        let result = detector.detectDocCAlert(portedQuote)
        #expect(result?.tagByteLength == "Note: ".utf8.count)
    }
}
