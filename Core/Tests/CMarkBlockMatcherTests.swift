import Testing

@testable import MudCore

/// Stage 4a of Doc/Plans/2026-07-single-parser-rendering.md: the cmark
/// leaf-block collector and matcher against their legacy swift-markdown
/// counterparts. Parity holds over footnote-free input, where the legacy
/// pipeline's transformed source equals the raw source both sides parse.
/// Footnote-bearing input diverges **by design** — the cmark collector
/// skips definition subtrees structurally where the legacy raw-source
/// collectors see them as paragraphs — so those cases assert the cmark
/// behavior directly instead of comparing.
@Suite("CMark block matcher")
struct CMarkBlockMatcherTests {

    // MARK: - Helpers

    /// A parser-neutral description of one block match, for comparing the
    /// two pipelines' classifications.
    private struct MatchRecord: Equatable {
        let kind: String
        let oldText: String?
        let newText: String?
        let oldFingerprint: String?
        let newFingerprint: String?
    }

    private func legacyRecords(old: String, new: String) -> [MatchRecord] {
        BlockMatcher.match(
            old: ParsedMarkdown(old), new: ParsedMarkdown(new)
        ).map {
            switch $0 {
            case .unchanged(let o, let n):
                return MatchRecord(
                    kind: "unchanged",
                    oldText: o.sourceText, newText: n.sourceText,
                    oldFingerprint: o.fingerprint, newFingerprint: n.fingerprint)
            case .inserted(let n):
                return MatchRecord(
                    kind: "inserted", oldText: nil, newText: n.sourceText,
                    oldFingerprint: nil, newFingerprint: n.fingerprint)
            case .deleted(let o):
                return MatchRecord(
                    kind: "deleted", oldText: o.sourceText, newText: nil,
                    oldFingerprint: o.fingerprint, newFingerprint: nil)
            }
        }
    }

    private func cmarkRecords(old: String, new: String) throws -> [MatchRecord] {
        let oldDoc = try #require(
            CMarkDocument(parsing: ParsedMarkdown(old).body))
        let newDoc = try #require(
            CMarkDocument(parsing: ParsedMarkdown(new).body))
        return CMarkBlockMatcher.match(old: oldDoc, new: newDoc).map {
            switch $0 {
            case .unchanged(let o, let n):
                return MatchRecord(
                    kind: "unchanged",
                    oldText: o.sourceText, newText: n.sourceText,
                    oldFingerprint: o.fingerprint, newFingerprint: n.fingerprint)
            case .inserted(let n):
                return MatchRecord(
                    kind: "inserted", oldText: nil, newText: n.sourceText,
                    oldFingerprint: nil, newFingerprint: n.fingerprint)
            case .deleted(let o):
                return MatchRecord(
                    kind: "deleted", oldText: o.sourceText, newText: nil,
                    oldFingerprint: o.fingerprint, newFingerprint: nil)
            }
        }
    }

    private func cmarkBlocks(_ markdown: String) throws -> [CMarkLeafBlock] {
        let doc = try #require(
            CMarkDocument(parsing: ParsedMarkdown(markdown).body))
        return CMarkBlockMatcher.collectLeafBlocks(from: doc)
    }

    // MARK: - Collector parity over the corpus

    /// Corpus documents without footnote syntax: on these, the legacy
    /// collector and the cmark collector must agree exactly.
    private static let footnoteFreeCorpus = ParityCorpus.all.filter {
        !$0.markdown.contains("[^")
    }

    @Test(arguments: footnoteFreeCorpus)
    func collectorMatchesLegacyOverCorpus(
        _ document: ParityCorpus.Document
    ) throws {
        let parsed = ParsedMarkdown(document.markdown)
        let legacy = BlockMatcher.collectLeafBlocks(from: parsed)
        let ported = try cmarkBlocks(document.markdown)

        #expect(ported.count == legacy.count)
        for (p, l) in zip(ported, legacy) {
            #expect(p.fingerprint == l.fingerprint)
            #expect(p.sourceText == l.sourceText)
            #expect(p.sourceLine == l.sourceLine)
        }
    }

    // MARK: - Match parity over the edit corpus

    @Test(arguments: ChangeIDParityTests.corpus)
    func matchClassificationMatchesLegacy(
        _ c: ChangeIDParityTests.EditCase
    ) throws {
        let legacy = legacyRecords(old: c.old, new: c.new)
        let ported = try cmarkRecords(old: c.old, new: c.new)
        #expect(ported == legacy)
    }

    // MARK: - Definitions are invisible (plan finding #2)

    // The cmark collector walks the raw source, where footnote definitions
    // survive as `.footnoteDefinition` subtrees; it must skip them exactly
    // as `CMarkUpHTMLVisitor` skips rendering them, or a definition-body
    // edit would surface as a change the visitor cannot place.

    @Test func footnoteDefinitionProducesNoLeafBlocks() throws {
        let blocks = try cmarkBlocks("""
            Text with a footnote[^a].

            [^a]: The footnote body.

                A second paragraph inside the definition.
            """)
        #expect(blocks.count == 1)
        #expect(blocks.first?.markup.kind == .paragraph)
    }

    @Test func commentDefinitionProducesNoLeafBlocks() throws {
        let blocks = try cmarkBlocks("""
            Text with a comment[^comment-a].

            [^comment-a]: > a comment

                💬 {Tester @ 2026-07-08 12:00:00}:

                A comment thread body.
            """)
        #expect(blocks.count == 1)
        #expect(blocks.first?.markup.kind == .paragraph)
    }

    @Test func footnoteDefinitionBodyEditClassifiesAsUnchanged() throws {
        let old = "Text with a footnote[^a].\n\n[^a]: Old body.\n"
        let new = "Text with a footnote[^a].\n\n[^a]: New body.\n"
        let records = try cmarkRecords(old: old, new: new)
        #expect(records.count == 1)
        #expect(records.allSatisfy { $0.kind == "unchanged" })
    }

    @Test func commentDefinitionBodyEditClassifiesAsUnchanged() throws {
        let old = """
            Text with a comment[^comment-a].

            [^comment-a]: > a comment

                💬 {Tester @ 2026-07-08 12:00:00}:

                Old thread body.
            """
        let new = """
            Text with a comment[^comment-a].

            [^comment-a]: > a comment

                💬 {Tester @ 2026-07-08 12:00:00}:

                New thread body.
            """
        let records = try cmarkRecords(old: old, new: new)
        #expect(records.count == 1)
        #expect(records.allSatisfy { $0.kind == "unchanged" })
    }

    /// Comment *references* still strip out of fingerprints (the raw
    /// `[^comment-x]` form), so adding one to a paragraph is not a change.
    @Test func addedCommentReferenceClassifiesAsUnchanged() throws {
        let old = "The quick fox.\n"
        let new = """
            The quick fox[^comment-a].

            [^comment-a]: > quick fox

                💬 {Tester @ 2026-07-08 12:00:00}:

                A note.
            """
        let records = try cmarkRecords(old: old, new: new)
        #expect(records.count == 1)
        #expect(records.allSatisfy { $0.kind == "unchanged" })
    }
}
