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
        _ c: ChangeIDParityTests.EditCase,
        policy: CMarkDefinitionDiffPolicy = .skipAll
    ) throws -> CMarkChangePlan {
        let oldDoc = try #require(
            CMarkDocument(parsing: ParsedMarkdown(c.old).body))
        let newDoc = try #require(
            CMarkDocument(parsing: ParsedMarkdown(c.new).body))
        return CMarkChangePlan.plan(
            old: oldDoc, new: newDoc, definitionPolicy: policy)
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
        let changeIDs = Set(
            ChangeList.computeChanges(plan: legacyPlan(c)).map(\.id))
        expectLineDiffMapsMatch(ported, legacy, changeIDs: changeIDs)
    }

    /// Sweeps a ported map against its legacy counterpart: deletion
    /// groups, per-line annotations, and word data over every change ID
    /// the legacy projection knows (IDs are positional `change-N`, so the
    /// annotation and group comparisons already prove ID parity).
    private func expectLineDiffMapsMatch(
        _ ported: CMarkLineDiffMap, _ legacy: LineDiffMap,
        changeIDs: Set<String>
    ) {
        #expect(ported.deletionGroups == legacy.deletionGroups)

        for line in Self.lineSweep {
            #expect(
                ported.annotation(forLine: line)
                    == legacy.annotation(forLine: line),
                "Annotation mismatch on line \(line)")
        }

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

    /// Shared by the default-policy pin and the Down-policy test below:
    /// comments must stay invisible under *both* policies.
    private static let commentBodyEditCase = ChangeIDParityTests.EditCase(
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

    @Test func commentDefinitionBodyEditYieldsNoChanges() throws {
        let ported = CMarkChangeList.computeChanges(
            plan: try cmarkPlan(Self.commentBodyEditCase))
        #expect(ported.isEmpty)
    }

    // MARK: - Down policy (Stage 5)

    /// Footnote-definition edit cases for `.descendPlainFootnotes`, shared
    /// with the Stage 5 diffed rendering sweep. Every definition body is a
    /// single-paragraph shape: legacy's raw parse and cmark's definition
    /// children agree on leaf granularity there (multi-paragraph bodies
    /// deliberately diverge — pinned in `DownRenderingParityTests`). Two
    /// authoring rules keep the legacy side honest: bodies are always
    /// multi-word (a one-word body like `[^a]: Alpha.` is a valid
    /// link-reference definition to the footnote-unaware legacy parse and
    /// vanishes from its leaf blocks), and every definition keeps a live
    /// reference (cmark unlinks orphan definitions, which legacy diffs as
    /// ordinary paragraphs — that divergence is pinned separately).
    static let downPolicyEditCases: [ChangeIDParityTests.EditCase] = [
        .init(
            label: "footnote definition body edit (down policy)",
            old: "Text with a footnote[^a].\n\n[^a]: Old body.\n",
            new: "Text with a footnote[^a].\n\n[^a]: New body.\n"),
        .init(
            label: "footnote definition high-similarity edit",
            old: "Ref[^a] here.\n\n[^a]: The quick brown fox jumps low.\n",
            new: "Ref[^a] here.\n\n[^a]: The quick brown fox jumps high.\n"),
        .init(
            label: "footnote definition lazy continuation edit",
            old: "Ref[^a] here.\n\n[^a]: First line\n    second line old.\n",
            new: "Ref[^a] here.\n\n[^a]: First line\n    second line new.\n"),
        .init(
            label: "footnote definition inserted with its reference",
            old: "A paragraph.\n\nRef[^a] one.\n\n[^a]: First note.\n",
            new: "A paragraph.\n\nRef[^a] one[^b].\n\n[^a]: First note.\n"
                + "\n[^b]: Second note.\n"),
        .init(
            label: "footnote definition deleted with its reference",
            old: "A paragraph.\n\nRef[^a] one[^b].\n\n[^a]: First note.\n"
                + "\n[^b]: Second note.\n",
            new: "A paragraph.\n\nRef[^a] one.\n\n[^a]: First note.\n"),
        .init(
            label: "paragraph edited adjacent to a definition",
            old: "Ref[^a] here.\n\n[^a]: Stable body.\n\nTail text old.\n",
            new: "Ref[^a] here.\n\n[^a]: Stable body.\n\nTail text new.\n"),
        .init(
            label: "definitions out of reference order with a later edit",
            old: "First ref is [^b], second is [^a].\n\n[^a]: Alpha note.\n"
                + "\n[^b]: Beta note.\n\nClosing paragraph old.\n",
            new: "First ref is [^b], second is [^a].\n\n[^a]: Alpha note.\n"
                + "\n[^b]: Beta note.\n\nClosing paragraph new.\n"),
    ]

    @Test(arguments: Self.downPolicyEditCases)
    func downPolicyLineDiffMapMatchesLegacy(
        _ c: ChangeIDParityTests.EditCase
    ) throws {
        let legacy = LineDiffMap(plan: legacyPlan(c))
        let ported = CMarkLineDiffMap(
            plan: try cmarkPlan(c, policy: .descendPlainFootnotes))
        let changeIDs = Set(
            ChangeList.computeChanges(plan: legacyPlan(c)).map(\.id))
        #expect(!changeIDs.isEmpty, "Edit case should produce changes")
        expectLineDiffMapsMatch(ported, legacy, changeIDs: changeIDs)
    }

    @Test func downPolicyKeepsCommentDefinitionsInvisible() throws {
        let ported = CMarkChangeList.computeChanges(
            plan: try cmarkPlan(
                Self.commentBodyEditCase, policy: .descendPlainFootnotes))
        #expect(ported.isEmpty)
    }

    @Test func policyJoinsThePlanCacheKey() throws {
        // Same source pair under both policies, default policy first:
        // without the policy in the cache key, the second call would get
        // the first call's plan back and see no changes.
        let c = ChangeIDParityTests.EditCase(
            label: "cache key",
            old: "Ref[^a] here.\n\n[^a]: Cached old body.\n",
            new: "Ref[^a] here.\n\n[^a]: Cached new body.\n")
        let skipped = CMarkChangeList.computeChanges(plan: try cmarkPlan(c))
        let descended = CMarkChangeList.computeChanges(
            plan: try cmarkPlan(c, policy: .descendPlainFootnotes))
        #expect(skipped.isEmpty)
        #expect(!descended.isEmpty)
    }
}
