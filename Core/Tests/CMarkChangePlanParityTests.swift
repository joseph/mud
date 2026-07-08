import Testing

@testable import MudCore

/// Stage 4a of Doc/Plans/2026-07-single-parser-rendering.md: the cmark
/// change plan and its two data-level projections (`CMarkChangeList`,
/// `CMarkLineDiffMap`) against the legacy pipeline, compared on output
/// values directly — cheap and strong, since both sides emit the same
/// output types (`DocumentChange`, `DeletionGroup`, `LineAnnotation`,
/// `BlockWordData`). The rendering projection (`CMarkDiffContext` feeding
/// `CMarkUpHTMLVisitor`) is proven separately by the byte-identical diffed
/// render comparison in `UpRenderingParityTests`.
@Suite("CMark change plan parity")
struct CMarkChangePlanParityTests {

    /// Line numbers to sweep when comparing per-line lookups. The edit
    /// corpus documents are all far shorter than this.
    private static let lineSweep = 1...120

    private func legacyPlan(_ c: ChangeIDParityTests.EditCase) -> ChangePlan {
        ChangePlan.plan(
            old: ParsedMarkdown(c.old), new: ParsedMarkdown(c.new))
    }

    private func cmarkPlan(
        _ c: ChangeIDParityTests.EditCase
    ) throws -> CMarkChangePlan {
        let oldDoc = try #require(
            CMarkDocument(parsing: ParsedMarkdown(c.old).body))
        let newDoc = try #require(
            CMarkDocument(parsing: ParsedMarkdown(c.new).body))
        return CMarkChangePlan.plan(old: oldDoc, new: newDoc)
    }

    // MARK: - Sidebar projection

    @Test(arguments: ChangeIDParityTests.corpus)
    func changeListMatchesLegacy(_ c: ChangeIDParityTests.EditCase) throws {
        let legacy = ChangeList.computeChanges(plan: legacyPlan(c))
        let ported = CMarkChangeList.computeChanges(plan: try cmarkPlan(c))
        #expect(!legacy.isEmpty, "Corpus case should produce changes")
        #expect(ported == legacy)
    }

    // MARK: - Down-mode projection

    @Test(arguments: ChangeIDParityTests.corpus)
    func lineDiffMapMatchesLegacy(_ c: ChangeIDParityTests.EditCase) throws {
        let legacy = LineDiffMap(plan: legacyPlan(c))
        let ported = CMarkLineDiffMap(plan: try cmarkPlan(c))

        #expect(ported.deletionGroups == legacy.deletionGroups)

        for line in Self.lineSweep {
            #expect(
                ported.annotation(forLine: line)
                    == legacy.annotation(forLine: line),
                "Annotation mismatch on line \(line)")
        }

        // Word data, swept over every change ID either projection knows.
        let changeIDs = Set(
            ChangeList.computeChanges(plan: legacyPlan(c)).map(\.id))
        for id in changeIDs {
            for line in Self.lineSweep {
                #expect(
                    ported.deletionWordData(for: id, line: line)
                        == legacy.deletionWordData(for: id, line: line),
                    "Deletion word data mismatch for \(id) line \(line)")
                #expect(
                    ported.insertionWordData(for: id, line: line)
                        == legacy.insertionWordData(for: id, line: line),
                    "Insertion word data mismatch for \(id) line \(line)")
            }
        }
    }

    // MARK: - Word spans and pairing

    @Test(arguments: ChangeIDParityTests.corpus)
    func pairingTablesMatchLegacy(_ c: ChangeIDParityTests.EditCase) throws {
        let legacy = legacyPlan(c)
        let ported = try cmarkPlan(c)
        #expect(ported.pairedChangeID == legacy.pairedChangeID)
        #expect(ported.wordSpans == legacy.wordSpans)
        #expect(ported.groupInfo.keys.sorted()
            == legacy.groupInfo.keys.sorted())
        for (id, info) in legacy.groupInfo {
            let p = ported.groupInfo[id]
            #expect(p?.groupID == info.groupID)
            #expect(p?.groupPos == info.groupPos)
            #expect(p?.groupIndex == info.groupIndex)
            #expect(p?.type == info.type)
        }
    }

    // MARK: - Definitions are invisible (plan finding #2)

    @Test func footnoteDefinitionBodyEditYieldsNoChanges() throws {
        let c = ChangeIDParityTests.EditCase(
            label: "footnote definition body edit",
            old: "Text with a footnote[^a].\n\n[^a]: Old body.\n",
            new: "Text with a footnote[^a].\n\n[^a]: New body.\n")
        let ported = CMarkChangeList.computeChanges(plan: try cmarkPlan(c))
        #expect(ported.isEmpty)
    }

    @Test func commentDefinitionBodyEditYieldsNoChanges() throws {
        let c = ChangeIDParityTests.EditCase(
            label: "comment definition body edit",
            old: """
                Text with a comment[^comment-a].

                [^comment-a]: > a comment

                    💬 {Tester @ 2026-07-08 12:00:00}:

                    Old thread body.
                """,
            new: """
                Text with a comment[^comment-a].

                [^comment-a]: > a comment

                    💬 {Tester @ 2026-07-08 12:00:00}:

                    New thread body.
                """)
        let ported = CMarkChangeList.computeChanges(plan: try cmarkPlan(c))
        #expect(ported.isEmpty)
    }
}
