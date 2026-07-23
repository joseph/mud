import Testing

@testable import MudCore

/// Self-contained coverage of the cmark change plan and its sidebar
/// projection (`CMarkChangeList`). cmark is now the only diff data layer,
/// so these tests pin concrete properties of its output directly rather
/// than comparing against a second implementation: every corpus edit
/// produces changes, footnote and comment definitions stay invisible under
/// the Up policy, and the definition policy joins the plan cache key so the
/// Down policy descends plain footnote definitions where the Up policy
/// skips them.
@Suite("CMark change plan")
struct CMarkChangePlanParityTests {

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

    /// Every corpus edit is a real change, so the sidebar projection must
    /// report at least one change for each.
    @Test(arguments: ChangeIDParityTests.corpus)
    func changeListReportsChanges(_ c: ChangeIDParityTests.EditCase) throws {
        let ported = CMarkChangeList.computeChanges(plan: try cmarkPlan(c))
        #expect(!ported.isEmpty, "Corpus case should produce changes")
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

    /// Shared by the Up-policy pin and the Down-policy test below:
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

    // MARK: - Down policy

    /// Footnote-definition edit cases for `.descendPlainFootnotes`, shared
    /// with the Down-mode diffed rendering sweep. Every definition body is a
    /// single-paragraph shape. Two authoring rules keep the cases
    /// well-formed: bodies are always multi-word (a one-word body like
    /// `[^a]: Alpha.` parses as a link-reference definition, not a footnote
    /// body), and every definition keeps a live reference (cmark unlinks
    /// orphan definitions).
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

    /// Under `.descendPlainFootnotes`, plain footnote-definition bodies
    /// become leaf blocks, so each of these edits produces changes — where
    /// the Up policy (`.skipAll`) would skip the definition entirely.
    @Test(arguments: Self.downPolicyEditCases)
    func downPolicyDescendsFootnoteDefinitions(
        _ c: ChangeIDParityTests.EditCase
    ) throws {
        let descended = CMarkChangeList.computeChanges(
            plan: try cmarkPlan(c, policy: .descendPlainFootnotes))
        #expect(!descended.isEmpty, "Edit case should produce changes")
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
