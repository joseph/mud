import Foundation
import Testing

@testable import MudCore

/// Down-mode rendering. One footnote-aware cmark parse renders the raw source.
/// These tests make focused assertions on the footnote-span, definition, and
/// orphan behavior the visitor owns, plus a crash-free sweep of the diffed
/// edit shapes. Whole-document output is pinned separately by
/// `GoldenRenderingTests`.
@Suite("Down-mode rendering")
struct DownRenderingTests {

    // MARK: - Footnote spans from the AST

    // The layout logic the port owns, asserted directly so a failure names
    // the logic instead of pointing at a whole-document byte diff.

    @Test func referenceAndDefinitionMarkersSpanTheSourceTokens() {
        let html = CMarkDownHTMLVisitor().highlight(
            ParityCorpus.footnoteNumbering.markdown)
        #expect(html.contains(
            "<span class=\"md-footnote-ref\">[^beta]</span>"))
        #expect(html.contains(
            "<span class=\"md-footnote-def\">[^alpha]:</span>"))
        // Comment references and definitions highlight like any other
        // footnote — Down mode draws no comment-specific structure.
        #expect(html.contains(
            "<span class=\"md-footnote-ref\">[^comment-note]</span>"))
        #expect(html.contains(
            "<span class=\"md-footnote-def\">[^comment-note]:</span>"))
    }

    @Test func undefinedReferenceGetsNoSpan() {
        let html = CMarkDownHTMLVisitor().highlight(
            ParityCorpus.footnoteNumbering.markdown)
        // `[^missing]` never becomes a reference node, so its literal
        // text renders unhighlighted — as legacy, whose scan only sees
        // resolved references.
        #expect(!html.contains(
            "<span class=\"md-footnote-ref\">[^missing]</span>"))
        #expect(html.contains("[^missing]"))
    }

    @Test func referenceInsideADefinitionBodyGetsNoSpan() {
        let html = CMarkDownHTMLVisitor().highlight(
            ParityCorpus.footnoteDefBodyVariants.markdown)
        // `[^nested]`'s body references `[^inline]`. Legacy emits nothing
        // there (scan drops in-body refs; the body sub-parse sees plain
        // text), so the port suppresses the reference node it *does* see.
        #expect(html.contains("references[^inline] the first note"))
        #expect(!html.contains(
            "references<span class=\"md-footnote-ref\">"))
    }

    @Test func definitionBodyCodeIsSpannedButNotRendered() {
        let html = CMarkDownHTMLVisitor().highlight(
            ParityCorpus.footnoteDefCodeBlocks.markdown)
        // Code inside a definition body gets fence/content spans, but no
        // highlight.js substitution and no scrollable code-line roles —
        // legacy discarded the body sub-parse's code blocks, keeping the
        // body's verbatim indentation on screen.
        #expect(html.contains("md-code-fence"))
        #expect(html.contains("md-code-block"))
        #expect(!html.contains("hljs"))
        #expect(!html.contains("dc-code"))
        #expect(!html.contains("dc-fence"))
    }

    // MARK: - Diffed rendering

    /// The cmark pipeline's diffed render: the plan is built under the Down
    /// definition policy.
    private func cmarkDiffedDown(
        new: String, old: String, mode: DocCAlertMode = .extended
    ) throws -> String {
        let parsedNew = ParsedMarkdown(new)
        let parsedOld = ParsedMarkdown(old)
        let fmRendered = FrontMatterHTMLRenderer.downModeLines(
            markdown: parsedNew.markdown,
            lineCount: parsedNew.frontMatterLineCount)
        let oldDoc = try #require(CMarkDocument(parsing: parsedOld.body))
        let newDoc = try #require(CMarkDocument(parsing: parsedNew.body))
        let plan = CMarkChangePlan.plan(
            old: oldDoc, new: newDoc,
            definitionPolicy: .descendPlainFootnotes)
        return CMarkDownHTMLVisitor().highlightWithChanges(
            new: parsedNew.body, old: parsedOld.body, plan: plan,
            docCAlertMode: mode, frontMatterRendered: fmRendered)
    }

    /// Down-specific edit cases beyond the shared corpora: shapes where
    /// the frontmatter offset or the definition policy interacts with
    /// the diffed layout. Multi-paragraph definition bodies and orphan
    /// definitions deliberately diverge — pinned below, not swept.
    static let downDiffEditCases: [ChangeIDParityTests.EditCase] = [
        .init(
            label: "definition edited below front matter",
            old: "---\ntitle: Fixed\n---\n\nRef[^a] here.\n\n"
                + "[^a]: Old body text.\n",
            new: "---\ntitle: Fixed\n---\n\nRef[^a] here.\n\n"
                + "[^a]: New body text.\n"),
        .init(
            label: "paragraph edited below front matter with a definition",
            old: "---\ntitle: Fixed\n---\n\nRef[^a] old.\n\n"
                + "[^a]: Stable body.\n",
            new: "---\ntitle: Fixed\n---\n\nRef[^a] new.\n\n"
                + "[^a]: Stable body.\n"),
    ]

    /// The shared and Down-specific diffed edit cases. One shape,
    /// `UpRenderingTests`' "paragraph referencing second footnote
    /// deleted", orphans `[^b]: B.` in the new document; under Down's
    /// `.descendPlainFootnotes` policy cmark diffs the orphaned definition
    /// as a deletion, pinned in `definitionOrphanedByDeletionDiffsAsDeleted`
    /// below, and swept here only for a crash-free render.
    static let diffedDownSweepCases: [ChangeIDParityTests.EditCase] =
        ChangeIDParityTests.corpus
        + UpRenderingTests.diffEditCases
        + CMarkChangePlanParityTests.downPolicyEditCases
        + downDiffEditCases

    @Test(arguments: Self.diffedDownSweepCases)
    func diffedDownHTMLRendersOverSweep(
        _ c: ChangeIDParityTests.EditCase
    ) throws {
        let ported = try cmarkDiffedDown(new: c.new, old: c.old)
        // The diffed render exercises the cmark diff + Down layout path over
        // every edit shape; assert it produces output without trapping.
        #expect(!ported.isEmpty)
    }

    // MARK: - Pinned definition behaviors (diffed)

    /// cmark has no node for an unreferenced definition, so an edit to its
    /// body yields no changes. Joins the orphan rendering pin below.
    @Test func orphanDefinitionEditYieldsNoChanges() throws {
        let oldDoc = try #require(CMarkDocument(
            parsing: "A paragraph.\n\n[^orphan]: Old body text.\n"))
        let newDoc = try #require(CMarkDocument(
            parsing: "A paragraph.\n\n[^orphan]: New body text.\n"))
        let plan = CMarkChangePlan.plan(
            old: oldDoc, new: newDoc,
            definitionPolicy: .descendPlainFootnotes)
        #expect(CMarkChangeList.computeChanges(plan: plan).isEmpty)
    }

    /// A multi-paragraph definition body is one leaf per *paragraph* to
    /// cmark. Pin that the cmark plan lands the edit on the right line.
    @Test func multiParagraphDefinitionEditLandsOnItsLine() throws {
        let old = "Ref[^a] here.\n\n[^a]: First paragraph.\n\n"
            + "    Second paragraph old.\n"
        let new = "Ref[^a] here.\n\n[^a]: First paragraph.\n\n"
            + "    Second paragraph new.\n"
        let oldDoc = try #require(CMarkDocument(parsing: old))
        let newDoc = try #require(CMarkDocument(parsing: new))
        let plan = CMarkChangePlan.plan(
            old: oldDoc, new: newDoc,
            definitionPolicy: .descendPlainFootnotes)
        let map = CMarkLineDiffMap(plan: plan)
        #expect(map.annotation(forLine: 5) != nil)
        #expect(map.deletionGroups.count == 1)
        #expect(map.deletionGroups.first?.oldLineRange == 5...5)
    }

    /// Deleting the only paragraph that referenced `[^b]` leaves `[^b]: B.`
    /// defined but unreferenced in the new document. cmark unlinks the
    /// orphaned definition from the new tree, so the block match sees the
    /// old document's live (referenced) `[^b]` definition with no
    /// counterpart in the new tree and diffs it as a deletion. This is the
    /// orphan behavior (see `orphanDefinitionEditYieldsNoChanges`)
    /// manifesting inside a diff: under Down's `.descendPlainFootnotes` the
    /// deletion draws a second `dl-del` line for a definition whose raw
    /// source is still present.
    @Test func definitionOrphanedByDeletionDiffsAsDeleted() throws {
        let old = "First[^a].\n\nGone with second[^b].\n\nTail.\n\n"
            + "[^a]: A.\n\n[^b]: B.\n"
        let new = "First[^a].\n\nTail.\n\n[^a]: A.\n\n[^b]: B.\n"
        let oldDoc = try #require(CMarkDocument(parsing: old))
        let newDoc = try #require(CMarkDocument(parsing: new))
        let plan = CMarkChangePlan.plan(
            old: oldDoc, new: newDoc,
            definitionPolicy: .descendPlainFootnotes)
        // Two deletions: the paragraph, and the now-orphaned definition.
        let ported = CMarkChangeList.computeChanges(plan: plan)
        #expect(ported.count == 2)
    }

    /// A fenced block inside a definition body is a real fenced block to
    /// cmark (fence lines outside the literal), and `CMarkLineDiffMap`'s
    /// fence detection reads the source-text prefix, which an indented fence
    /// defeats. Pin only that the edit produces changes annotated within the
    /// definition's lines.
    @Test func fencedCodeInDefinitionBodyEditStaysInDefinition() throws {
        let old = "Ref[^a] here.\n\n[^a]: Opener paragraph.\n\n"
            + "    ```\n    let x = 1\n    ```\n"
        let new = "Ref[^a] here.\n\n[^a]: Opener paragraph.\n\n"
            + "    ```\n    let x = 2\n    ```\n"
        let oldDoc = try #require(CMarkDocument(parsing: old))
        let newDoc = try #require(CMarkDocument(parsing: new))
        let plan = CMarkChangePlan.plan(
            old: oldDoc, new: newDoc,
            definitionPolicy: .descendPlainFootnotes)
        let map = CMarkLineDiffMap(plan: plan)
        let annotated = (1...7).filter { map.annotation(forLine: $0) != nil }
        #expect(!annotated.isEmpty)
        #expect(annotated.allSatisfy { $0 >= 5 && $0 <= 7 })
    }

    // MARK: - Pinned behavior (orphan definitions)

    /// cmark unlinks an unreferenced definition from the tree (see
    /// `FootnoteProcessor.process`'s orphan-stripping comment), so the port
    /// has no nodes to walk — no marker span, no body highlighting. The raw
    /// text still renders, since Phase 2 draws raw source lines regardless;
    /// only the highlighting is lost, on this degenerate input.
    @Test func orphanDefinitionBodyLosesHighlighting() {
        let html = CMarkDownHTMLVisitor().highlight(
            "A paragraph.\n\n[^orphan]: A body with **bold** text.\n")
        #expect(html.contains("[^orphan]: A body with **bold** text."))
        #expect(!html.contains("md-footnote-def"))
        #expect(!html.contains("md-strong"))
    }
}
