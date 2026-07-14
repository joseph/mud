import Testing

@testable import MudCore

/// Self-contained coverage of the cmark leaf-block collector and matcher.
/// cmark is now the only diff data layer, so these tests pin its behavior
/// directly. The focus is footnote and comment definitions: the collector
/// walks the raw source, where definitions survive as real subtrees, and
/// must skip them exactly as `CMarkUpHTMLVisitor` skips rendering them —
/// otherwise a definition-body edit would surface as a change the visitor
/// cannot place.
@Suite("CMark block matcher")
struct CMarkBlockMatcherTests {

    // MARK: - Helpers

    /// A parser-neutral description of one block match.
    private struct MatchRecord: Equatable {
        let kind: String
        let oldText: String?
        let newText: String?
        let oldFingerprint: String?
        let newFingerprint: String?
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
