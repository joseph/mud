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
        let html = DownHTMLVisitor().highlight(
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
        let html = DownHTMLVisitor().highlight(
            ParityCorpus.footnoteNumbering.markdown)
        // `[^missing]` never becomes a reference node, so its literal
        // text renders unhighlighted: only a resolved reference gets a span.
        #expect(!html.contains(
            "<span class=\"md-footnote-ref\">[^missing]</span>"))
        #expect(html.contains("[^missing]"))
    }

    @Test func referenceInsideADefinitionBodyGetsNoSpan() {
        let html = DownHTMLVisitor().highlight(
            ParityCorpus.footnoteDefBodyVariants.markdown)
        // `[^nested]`'s body references `[^inline]`. Legacy emits nothing
        // there (scan drops in-body refs; the body sub-parse sees plain
        // text), so the port suppresses the reference node it *does* see.
        #expect(html.contains("references[^inline] the first note"))
        #expect(!html.contains(
            "references<span class=\"md-footnote-ref\">"))
    }

    @Test func definitionBodyCodeIsSpannedButNotRendered() {
        let html = DownHTMLVisitor().highlight(
            ParityCorpus.footnoteDefCodeBlocks.markdown)
        // Code inside a definition body gets fence/content spans, but no
        // highlight.js substitution and no scrollable code-line roles, so
        // the body's verbatim indentation stays on screen.
        #expect(html.contains("md-code-fence"))
        #expect(html.contains("md-code-block"))
        #expect(!html.contains("hljs"))
        #expect(!html.contains("dc-code"))
        #expect(!html.contains("dc-fence"))
    }

    // MARK: - Definition-body continuation lines

    /// cmark derives an inline's position from its offset within the
    /// enclosing block's content, and inside a definition it adds back the
    /// content offset it fixed at the opener line. So on a continuation line
    /// every inline span lands `len("[^label]: ") - indent` bytes too far
    /// right unless converted — +2, +20, and +14 for the three labels here.
    ///
    /// Asserted as whole rendered lines with exact occurrence counts: a
    /// slipped span still contains the same markup text, just wrapped around
    /// the wrong characters, so a `contains` on the markup alone would pass.
    @Test func definitionContinuationLinesSpanTheirOwnMarkup() {
        let html = DownHTMLVisitor().highlight(
            ParityCorpus.footnoteDefContinuationSpans.markdown)

        func span(_ cssClass: String, _ text: String) -> String {
            "<span class=\"\(cssClass)\">\(text)</span>"
        }
        func count(_ needle: String) -> Int {
            html.components(separatedBy: needle).count - 1
        }
        let code = span("md-code", "`code`")
        let italic = span("md-emphasis", "_italic_")
        let struck = span("md-strikethrough", "~~struck~~")
        let link = span("md-link", "[link](https://example.org)")

        // Second lines: two definitions end in strikethrough, one in a link.
        #expect(count("<span class=\"lc\">    Second line with \(code), "
            + "\(italic), and \(struck) text.</span>") == 2)
        #expect(count("<span class=\"lc\">    Second line with \(code), "
            + "\(italic), and a \(link).</span>") == 1)
        // Third lines: one per definition, all three identical.
        #expect(count("<span class=\"lc\">    Third line with \(code) and "
            + "\(italic).</span>") == 3)
    }

    /// A definition's *later* blocks begin on a continuation line, where the
    /// prefix cmark stripped is already the plain indent — so those lines need
    /// no correction at all, while the opening block's continuation lines
    /// need the full `indent - len("[^label]: ")`. Both regimes appear in this
    /// one document; anchoring the correction on the definition's opener
    /// instead of the block's first line gets the first right and shifts every
    /// later block left.
    @Test func definitionLaterBlocksSpanTheirOwnMarkup() {
        let html = DownHTMLVisitor().highlight(
            ParityCorpus.footnoteDefLaterBlockSpans.markdown)

        func span(_ cssClass: String, _ text: String) -> String {
            "<span class=\"\(cssClass)\">\(text)</span>"
        }
        func count(_ needle: String) -> Int {
            html.components(separatedBy: needle).count - 1
        }
        let code = span("md-code", "`code`")
        let italic = span("md-emphasis", "_italic_")

        // A later block's own continuation lines — correction is zero.
        #expect(count("<span class=\"lc\">    Its continuation line with "
            + "\(code) and \(italic).</span>") == 1)
        #expect(count("<span class=\"lc\">    Its continuation with "
            + "\(code) and \(italic).</span>") == 1)
        // The opening block's continuation line — correction is -16.
        #expect(count("<span class=\"lc\">    Opening block continuation with "
            + "\(code) and \(italic).</span>") == 1)
        // Both later blocks' first lines, which take no correction either.
        #expect(count("<span class=\"lc\">    A later block with \(code) and "
            + "\(italic) on its first line.</span>") == 1)
        #expect(count("<span class=\"lc\">    A later block with \(code) and "
            + "\(italic).</span>") == 1)
    }

    /// cmark-gfm orders footnote definitions by first reference, not by where
    /// they are written, so a definition referenced early but written late is
    /// walked first. A scan that assumes source order and stops early misses
    /// every definition written before it — leaving this continuation line
    /// uncorrected.
    @Test func definitionSpansSurviveOutOfOrderDefinitions() {
        let html = DownHTMLVisitor().highlight(
            ParityCorpus.footnoteDefOutOfOrder.markdown)
        #expect(html.contains(
            "<span class=\"lc\">    Continuation with "
            + "<span class=\"md-code\">`code`</span> and "
            + "<span class=\"md-emphasis\">_italic_</span>.</span>"))
    }

    /// The opener line is the case the conversion must leave alone: there the
    /// offset cmark fixed *is* the real prefix, so its columns are already
    /// raw.
    @Test func definitionOpenerLineSpansAreUnshifted() {
        let html = DownHTMLVisitor().highlight(
            ParityCorpus.footnoteDefContinuationSpans.markdown)
        #expect(html.contains(
            "<span class=\"md-footnote-def\">[^s]:</span> Opener with "
            + "<span class=\"md-code\">`code`</span>, "
            + "<span class=\"md-emphasis\">_italic_</span>, and a "
            + "<span class=\"md-link\">[link](https://example.org)</span>."))
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
        let plan = ChangePlan.plan(
            old: oldDoc, new: newDoc,
            definitionPolicy: .descendPlainFootnotes)
        return DownHTMLVisitor().highlightWithChanges(
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
        + ChangePlanParityTests.downPolicyEditCases
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
        let plan = ChangePlan.plan(
            old: oldDoc, new: newDoc,
            definitionPolicy: .descendPlainFootnotes)
        #expect(ChangeList.computeChanges(plan: plan).isEmpty)
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
        let plan = ChangePlan.plan(
            old: oldDoc, new: newDoc,
            definitionPolicy: .descendPlainFootnotes)
        let map = LineDiffMap(plan: plan)
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
        let plan = ChangePlan.plan(
            old: oldDoc, new: newDoc,
            definitionPolicy: .descendPlainFootnotes)
        // Two deletions: the paragraph, and the now-orphaned definition.
        let ported = ChangeList.computeChanges(plan: plan)
        #expect(ported.count == 2)
    }

    /// A fenced block inside a definition body is a real fenced block to
    /// cmark (fence lines outside the literal), and `LineDiffMap`'s
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
        let plan = ChangePlan.plan(
            old: oldDoc, new: newDoc,
            definitionPolicy: .descendPlainFootnotes)
        let map = LineDiffMap(plan: plan)
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
        let html = DownHTMLVisitor().highlight(
            "A paragraph.\n\n[^orphan]: A body with **bold** text.\n")
        #expect(html.contains("[^orphan]: A body with **bold** text."))
        #expect(!html.contains("md-footnote-def"))
        #expect(!html.contains("md-strong"))
    }
}
