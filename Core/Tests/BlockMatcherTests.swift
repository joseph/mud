import Testing

@testable import MudCore

/// Self-contained coverage of the cmark leaf-block collector and matcher.
/// cmark is now the only diff data layer, so these tests pin its behavior
/// directly. The focus is footnote and comment definitions: the collector
/// walks the raw source, where definitions survive as real subtrees, and
/// must skip them exactly as `UpHTMLVisitor` skips rendering them —
/// otherwise a definition-body edit would surface as a change the visitor
/// cannot place.
@Suite("CMark block matcher")
struct BlockMatcherTests {

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
        return BlockMatcher.match(old: oldDoc, new: newDoc).map {
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

    private func cmarkBlocks(_ markdown: String) throws -> [LeafBlock] {
        let doc = try #require(
            CMarkDocument(parsing: ParsedMarkdown(markdown).body))
        return BlockMatcher.collectLeafBlocks(from: doc)
    }

    // MARK: - Definitions are invisible (plan finding #2)

    // The cmark collector walks the raw source, where footnote definitions
    // survive as `.footnoteDefinition` subtrees; it must skip them exactly
    // as `UpHTMLVisitor` skips rendering them, or a definition-body
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

    // MARK: - Re-wrapping is not a change

    // A soft line break renders as a space, so moving one changes nothing
    // on the page — and a wrapping tool moves them on almost every edit.
    // Prose fingerprints collapse cosmetic whitespace so a re-wrap reads
    // as unchanged; what a reader would actually see change still doesn't.

    @Test func rewrappedParagraphClassifiesAsUnchanged() throws {
        let old = """
            A message attribution at the start of a paragraph **begins a new
            message**. The first message needs no such attribution.
            """
        let new = """
            A message attribution at the start of a paragraph **begins a
            new message**. The first message needs no such attribution.
            """
        let records = try cmarkRecords(old: old, new: new)
        #expect(records.count == 1)
        #expect(records.allSatisfy { $0.kind == "unchanged" })
    }

    @Test func rewrappedListItemClassifiesAsUnchanged() throws {
        let old = "- one workaround is to put empty braces at the\n  start."
        let new = "- one workaround is to put empty braces\n  at the start."
        let records = try cmarkRecords(old: old, new: new)
        #expect(records.count == 1)
        #expect(records.allSatisfy { $0.kind == "unchanged" })
    }

    /// A blockquote's `>` prefix repeats on every line, so a re-wrap moves
    /// the prefixes too. Continuation lines drop theirs before the collapse.
    @Test func rewrappedBlockQuoteClassifiesAsUnchanged() throws {
        let old = "> The quick brown fox\n> jumped over the lazy dog."
        let new = "> The quick brown fox jumped over the\n> lazy dog."
        let records = try cmarkRecords(old: old, new: new)
        #expect(records.count == 1)
        #expect(records.allSatisfy { $0.kind == "unchanged" })
    }

    @Test func rewrappedParagraphKeepsWordEditVisible() throws {
        let old = "The quick brown fox\njumped over the lazy dog."
        let new = "The quick red fox jumped over\nthe lazy dog."
        let records = try cmarkRecords(old: old, new: new)
        #expect(records.contains { $0.kind == "deleted" })
        #expect(records.contains { $0.kind == "inserted" })
    }

    /// Two or more trailing spaces render as `<br>`, so dropping them is a
    /// real change even though only whitespace moved.
    @Test func removedHardLineBreakClassifiesAsChanged() throws {
        let old = "The quick brown fox  \njumped over the lazy dog."
        let new = "The quick brown fox\njumped over the lazy dog."
        let records = try cmarkRecords(old: old, new: new)
        #expect(records.contains { $0.kind == "deleted" })
        #expect(records.contains { $0.kind == "inserted" })
    }

    @Test func deepenedQuoteClassifiesAsChanged() throws {
        let records = try cmarkRecords(
            old: "> The quick brown fox.\n",
            new: ">> The quick brown fox.\n")
        #expect(records.contains { $0.kind == "deleted" })
        #expect(records.contains { $0.kind == "inserted" })
    }

    @Test func codeBlockKeepsItsWhitespace() throws {
        let records = try cmarkRecords(
            old: "```\nlet x = 1\n```\n",
            new: "```\n    let x = 1\n```\n")
        #expect(records.contains { $0.kind == "deleted" })
        #expect(records.contains { $0.kind == "inserted" })
    }
}
