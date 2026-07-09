import Foundation
import Testing

@testable import MudCore

/// Stage 5 of Doc/Plans/2026-07-single-parser-rendering.md: the differential
/// harness over the two Down-mode renderers. The legacy pipeline blanks
/// footnote-definition lines before its swift-markdown parse and re-parses
/// each definition body separately; `CMarkDownHTMLVisitor` renders the raw
/// source from one footnote-aware cmark parse. The two outputs must match
/// byte-for-byte over the whole corpus — this comparison gates the eventual
/// cutover, so it must keep passing until Stage 6 deletes the legacy side.
@Suite("Down-mode rendering parity")
struct DownRenderingParityTests {

    /// The legacy pipeline's plain render — the exact steps of
    /// `MudCore.renderDownToHTML`'s no-waypoint branch.
    private func legacyDown(
        _ source: String, mode: DocCAlertMode
    ) -> String {
        let parsed = ParsedMarkdown(source)
        let fmRendered = FrontMatterHTMLRenderer.downModeLines(
            markdown: parsed.markdown,
            lineCount: parsed.frontMatterLineCount)
        return DownHTMLVisitor().highlight(
            parsed.body, docCAlertMode: mode,
            frontMatterRendered: fmRendered)
    }

    /// The cmark pipeline's plain render, on identical inputs.
    private func cmarkDown(
        _ source: String, mode: DocCAlertMode
    ) -> String {
        let parsed = ParsedMarkdown(source)
        let fmRendered = FrontMatterHTMLRenderer.downModeLines(
            markdown: parsed.markdown,
            lineCount: parsed.frontMatterLineCount)
        return CMarkDownHTMLVisitor().highlight(
            parsed.body, docCAlertMode: mode,
            frontMatterRendered: fmRendered)
    }

    @Test(arguments: ParityCorpus.all, DocCAlertMode.allCases)
    func downHTMLMatchesLegacyPipeline(
        _ document: ParityCorpus.Document, _ mode: DocCAlertMode
    ) {
        let legacy = legacyDown(document.markdown, mode: mode)
        let ported = cmarkDown(document.markdown, mode: mode)
        #expect(ported == legacy)
    }

    // MARK: - Footnote spans from the AST

    // The layout logic Stage 5 moves out of `FootnoteProcessor.scan`'s
    // layering pass, asserted directly so a failure names the moved logic
    // instead of pointing at a whole-document byte diff.

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

    // MARK: - AST drift near definitions

    /// A definition between two lists genuinely parses differently per
    /// pipeline — legacy's blanked main parse sees one loose list across
    /// the whitespace, cmark sees two lists split by the definition node —
    /// but Down mode draws no spans for plain lists, so the rendered
    /// bytes must agree anyway. (The Up-mode rendering of this shape
    /// *does* change at cutover — one loose list becomes two tight ones —
    /// which is why it lives here and not in the shared corpus.)
    @Test(arguments: DocCAlertMode.allCases)
    func definitionBetweenListsRendersIdentically(_ mode: DocCAlertMode) {
        let source = """
            Opening ref[^listed] paragraph.

            - item one

            [^listed]: A definition between two lists.

            - item two
            """
        let legacy = legacyDown(source, mode: mode)
        let ported = cmarkDown(source, mode: mode)
        #expect(ported == legacy)
    }

    // MARK: - Diffed rendering

    /// The legacy pipeline's diffed render — the exact steps of
    /// `MudCore.renderDownToHTML`'s waypoint branch: the plan is built
    /// from the raw sources (Down mode never preprocesses).
    private func legacyDiffedDown(
        new: String, old: String, mode: DocCAlertMode = .extended
    ) -> String {
        let parsedNew = ParsedMarkdown(new)
        let parsedOld = ParsedMarkdown(old)
        let fmRendered = FrontMatterHTMLRenderer.downModeLines(
            markdown: parsedNew.markdown,
            lineCount: parsedNew.frontMatterLineCount)
        let plan = ChangePlan.plan(old: parsedOld, new: parsedNew)
        return DownHTMLVisitor().highlightWithChanges(
            new: parsedNew.body, old: parsedOld.body, plan: plan,
            docCAlertMode: mode, frontMatterRendered: fmRendered)
    }

    /// The cmark pipeline's diffed render: same inputs, with the plan
    /// built under the Down definition policy.
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

    /// The shared and Down-specific diffed edit cases, minus one shape
    /// that orphans a footnote definition in the *new* document.
    /// `UpRenderingParityTests`' "paragraph referencing second footnote
    /// deleted" deletes the only paragraph that referenced `[^b]`, leaving
    /// `[^b]: B.` defined but unreferenced. Under Up mode's `.skipAll`
    /// policy the definition is skipped in both pipelines, so the Up sweep
    /// is unaffected; under Down's `.descendPlainFootnotes` cmark unlinks
    /// the orphaned definition while legacy keeps diffing it, so the bytes
    /// diverge. The divergence is pinned in
    /// `definitionOrphanedByDeletionDiffsAsDeleted` below.
    static let diffedDownSweepCases: [ChangeIDParityTests.EditCase] =
        (ChangeIDParityTests.corpus
            + UpRenderingParityTests.diffEditCases
            + CMarkChangePlanParityTests.downPolicyEditCases
            + downDiffEditCases)
        .filter { $0.label != "paragraph referencing second footnote deleted" }

    @Test(arguments: Self.diffedDownSweepCases)
    func diffedDownHTMLMatchesLegacyPipeline(
        _ c: ChangeIDParityTests.EditCase
    ) throws {
        let legacy = legacyDiffedDown(new: c.new, old: c.old)
        let ported = try cmarkDiffedDown(new: c.new, old: c.old)
        #expect(ported == legacy)
    }

    // MARK: - Pinned divergences (diffed)

    /// Deliberately diverges from legacy: cmark has no node for an
    /// unreferenced definition, so an edit to its body yields no changes
    /// — where legacy's raw-source plan diffs it as an ordinary
    /// paragraph. Joins the orphan rendering pin below; recorded for the
    /// cutover.
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

    /// Deliberately diverges from legacy: a multi-paragraph definition
    /// body is one leaf per *paragraph* to cmark, but legacy's raw parse
    /// reads the indented continuation paragraphs as indented code
    /// blocks — different leaf granularity, different change mechanics.
    /// Pin that the cmark plan still lands the edit on the right line.
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

    /// Deliberately diverges from legacy: deleting the only paragraph that
    /// referenced `[^b]` leaves `[^b]: B.` defined but unreferenced in the
    /// new document. cmark unlinks the orphaned definition from the new
    /// tree, so the block match sees the old document's live (referenced)
    /// `[^b]` definition with no counterpart in the new tree and diffs it
    /// as a deletion — an extra change legacy never produces, because
    /// legacy never unlinks an orphan. This is the orphan divergence (see
    /// `orphanDefinitionEditYieldsNoChanges`) manifesting inside a diff:
    /// under Down's `.descendPlainFootnotes` the phantom deletion draws a
    /// second `dl-del` line for a definition whose raw source is still
    /// present. Recorded for the cutover; excluded from the byte-parity
    /// sweep above.
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
        // Legacy's raw-source plan produces only the paragraph deletion.
        let ported = CMarkChangeList.computeChanges(plan: plan)
        #expect(ported.count == 2)
        let legacy = ChangeList.computeChanges(
            plan: ChangePlan.plan(
                old: ParsedMarkdown(old), new: ParsedMarkdown(new)))
        #expect(legacy.count == 1)
    }

    /// Deliberately diverges from legacy, and flagged for review at
    /// cutover: a fenced block inside a definition body is an indented
    /// code block to legacy's raw parse (fence lines inside the literal)
    /// but a real fenced block to cmark (fence lines outside it), and
    /// `CMarkLineDiffMap`'s fence detection reads the source-text prefix,
    /// which an indented fence defeats — so the cluster→document line
    /// mapping differs between the pipelines. Pin only that the edit
    /// produces changes annotated within the definition's lines.
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

    // MARK: - Pinned divergence (orphan definitions)

    /// Deliberately diverges from legacy, so it is excluded from the
    /// shared corpus and pinned cmark-side only: cmark unlinks an
    /// unreferenced definition from the tree (see
    /// `FootnoteProcessor.process`'s orphan-stripping comment), so the
    /// port has no nodes to walk — no marker span, no body highlighting.
    /// Legacy never blanks an orphan (its scan reports only referenced
    /// definitions), so its main parse highlights the body as ordinary
    /// Markdown. The raw text still renders — Phase 2 draws raw source
    /// lines regardless — so the cutover cost is highlighting only, on a
    /// degenerate input.
    @Test func orphanDefinitionBodyLosesHighlighting() {
        let html = CMarkDownHTMLVisitor().highlight(
            "A paragraph.\n\n[^orphan]: A body with **bold** text.\n")
        #expect(html.contains("[^orphan]: A body with **bold** text."))
        #expect(!html.contains("md-footnote-def"))
        #expect(!html.contains("md-strong"))
    }
}
