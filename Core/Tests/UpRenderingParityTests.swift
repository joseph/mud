import Foundation
import Testing

@testable import MudCore

/// Up-mode body rendering, now that `CMarkUpHTMLVisitor` is the sole
/// pipeline. One footnote-aware cmark parse renders the raw source; the
/// legacy swift-markdown pipeline it replaced has been deleted. These tests
/// keep the cmark-side coverage: a smoke sweep over the shared corpus plus
/// focused assertions on the footnote-numbering, diff, and marker behavior
/// the port owns.
@Suite("Up-mode rendering")
struct UpRenderingParityTests {

    @Test(arguments: ParityCorpus.all, DocCAlertMode.allCases)
    func bodyHTMLRendersOverCorpus(
        _ document: ParityCorpus.Document, _ mode: DocCAlertMode
    ) {
        var options = RenderOptions()
        options.docCAlertMode = mode
        let ported = CMarkUpHTMLVisitor.renderBody(
            document.markdown, options: options)
        // Every corpus document has body content, so the render is non-empty.
        #expect(!ported.isEmpty)
    }

    // MARK: - Footnote numbering

    // The numbering logic the port owns, asserted directly so a failure names
    // the logic instead of pointing at a whole-document byte diff.

    @Test func footnoteNumberingFollowsFirstReferenceOrder() {
        let body = CMarkUpHTMLVisitor.renderBody(
            ParityCorpus.footnoteNumbering.markdown, options: .init())
        // beta is referenced first → number 1; alpha second → number 2,
        // regardless of definition order.
        #expect(body.contains("data-fn-label=\"beta\" data-fn-num=\"1\""))
        #expect(body.contains("data-fn-label=\"alpha\" data-fn-num=\"2\""))
        // The first beta reference gets the bare back-link id; the repeat
        // gets the occurrence suffix.
        #expect(body.contains("id=\"fnref-1\""))
        #expect(body.contains("id=\"fnref-1-2\""))
    }

    @Test func commentReferenceConsumesNoFootnoteNumber() {
        let body = CMarkUpHTMLVisitor.renderBody(
            ParityCorpus.footnoteNumbering.markdown, options: .init())
        // The comment renders as a 💬 marker between footnotes 1 and 2 and
        // leaves no gap in the numbering.
        #expect(body.contains("data-mud-label=\"comment-note\""))
        #expect(!body.contains("data-fn-num=\"3\""))
    }

    @Test func undefinedReferenceStaysLiteralAndOrphanDefinitionVanishes() {
        let body = CMarkUpHTMLVisitor.renderBody(
            ParityCorpus.footnoteNumbering.markdown, options: .init())
        // `[^missing]` resolves to no definition, so its text survives.
        #expect(body.contains("[^missing]"))
        // The unreferenced definition renders nothing.
        #expect(!body.contains("Never referenced"))
        // Referenced definition bodies belong to the bottom section, not
        // the rendered body.
        #expect(!body.contains("Alpha body"))
    }

    // MARK: - Diffed rendering

    /// The cmark pipeline's diffed body render: the raw waypoint goes
    /// straight into `RenderOptions`.
    private func cmarkDiffedBody(
        new: String, old: String, options: RenderOptions
    ) -> String {
        var options = options
        options.waypoint = ParsedMarkdown(old)
        return CMarkUpHTMLVisitor.renderBody(new, options: options)
    }

    /// Edit cases beyond `ChangeIDParityTests.corpus` (which covers
    /// paragraph and code-block gap shapes): the deletion-placer paths
    /// (list items, table rows, hoisting, deferral, reclaiming, trailing),
    /// word spans in every activating block shape, alerts, and the
    /// footnote/comment interplay with change tracking. Consumed by the
    /// overload-parity sweep below and by `DownRenderingParityTests`' diffed
    /// sweep.
    ///
    /// Footnote cases with a *paired* edit deliberately use low-similarity
    /// text so no word spans activate; the word-span-active footnote case is
    /// pinned separately in `wordSpannedFootnoteMarkerStaysIntact`. A paired
    /// edit of a *roman-path* DocC aside (long first line) is likewise pinned
    /// in `romanAsideEditAvoidsLegacyDefects` rather than swept here.
    static let diffEditCases: [ChangeIDParityTests.EditCase] = [
        .init(
            label: "word change in paragraph",
            old: "The quick fox.\n",
            new: "The slow fox.\n"),
        .init(
            label: "word change with inline code",
            old: "Call `foo()` and wait.\n",
            new: "Call `foo()` and sleep.\n"),
        .init(
            label: "word change across soft break",
            old: "The quick brown\nfox jumps over.\n",
            new: "The slow brown\nfox jumps over.\n"),
        .init(
            label: "word change with divergent formatting",
            old: "Hello **bold** world.\n",
            new: "Hello *italic* world.\n"),
        .init(
            label: "low-similarity paragraph replacement",
            old: "The quick brown fox jumps.\n",
            new: "A slow red dog leaps.\n"),
        .init(
            label: "heading edit",
            old: "# Title one\n\nBody.\n",
            new: "# Title two\n\nBody.\n"),
        .init(
            label: "deleted formatted paragraph",
            old: "Keep.\n\n**Bold gone.**\n",
            new: "Keep.\n"),
        .init(
            label: "inserted heading",
            old: "Paragraph.\n",
            new: "Paragraph.\n\n## New heading\n"),
        .init(
            label: "deleted list item",
            old: "- Alpha\n- Beta\n- Gamma\n",
            new: "- Alpha\n- Gamma\n"),
        .init(
            label: "inserted list item",
            old: "- Alpha\n",
            new: "- Alpha\n- Beta\n"),
        .init(
            label: "list item word change",
            old: "- The quick fox\n",
            new: "- The slow fox\n"),
        .init(
            label: "ordered list item deleted (renumbering absorbed)",
            old: "1. First\n2. Second\n3. Third\n",
            new: "1. First\n3. Third\n"),
        .init(
            label: "deleted item before complex item",
            old: "1. First\n2. Second\n3. Third\n   - Sub A\n   - Sub B\n",
            new: "1. First\n3. Third\n   - Sub A\n   - Sub B\n"),
        .init(
            label: "paragraph edited inside tight complex item",
            old: "- Item one\n- Item two\n  - Nested\n",
            new: "- Item one\n- Item two edited\n  - Nested\n"),
        .init(
            label: "loose list item inserted",
            old: "- Alpha\n\n- Beta\n",
            new: "- Alpha\n\n- Beta\n\n- Gamma\n"),
        .init(
            label: "table row inserted",
            old: "| A |\n|---|\n| 1 |\n",
            new: "| A |\n|---|\n| 1 |\n| 2 |\n"),
        .init(
            label: "table row deleted mid-body",
            old: "| A |\n|---|\n| 1 |\n| 2 |\n| 3 |\n",
            new: "| A |\n|---|\n| 1 |\n| 3 |\n"),
        .init(
            label: "last table row deleted with following block",
            old: "| A |\n|---|\n| 1 |\n| 2 |\n\nAfter.\n",
            new: "| A |\n|---|\n| 1 |\n\nAfter.\n"),
        .init(
            label: "last table row deleted trailing",
            old: "| A |\n|---|\n| 1 |\n| 2 |\n",
            new: "| A |\n|---|\n| 1 |\n"),
        .init(
            label: "paragraph deleted after table",
            old: "| A |\n|---|\n| 1 |\n\nGone after table.\n\nTail.\n",
            new: "| A |\n|---|\n| 1 |\n\nTail.\n"),
        .init(
            label: "whole table deleted",
            old: "Intro.\n\n| A |\n|---|\n| 1 |\n\nTail.\n",
            new: "Intro.\n\nTail.\n"),
        .init(
            label: "whole table inserted",
            old: "Intro.\n\nTail.\n",
            new: "Intro.\n\n| A |\n|---|\n| 1 |\n\nTail.\n"),
        .init(
            label: "paragraph deleted before table",
            old: "Gone.\n\n| A |\n|---|\n| 1 |\n",
            new: "| A |\n|---|\n| 1 |\n"),
        .init(
            label: "GFM alert inserted",
            old: "Keep.\n",
            new: "Keep.\n\n> [!NOTE]\n> Added alert.\n"),
        .init(
            label: "GFM alert deleted",
            old: "> [!NOTE]\n> Important info.\n\nKeep.\n",
            new: "Keep.\n"),
        .init(
            label: "DocC aside replaced",
            old: "> Status: Planning\n",
            new: "> Status: Underway\n"),
        .init(
            label: "DocC aside deleted",
            old: "> Status: Planning\n\nKeep.\n",
            new: "Keep.\n"),
        .init(
            label: "DocC aside inserted",
            old: "Keep.\n",
            new: "Keep.\n\n> Note: New aside.\n"),
        .init(
            // The first line exceeds the 60-character bold-inline
            // threshold, so the deletion renders through the roman aside
            // path. An *edit* of a roman aside is pinned separately in
            // `romanAsideEditAvoidsLegacyDefects` rather than swept here.
            label: "long DocC aside deleted",
            old: "> Warning: This DocC aside body is long enough that "
                + "the renderer keeps it\n> roman in its own paragraph "
                + "instead of bolding it.\n\nKeep.\n",
            new: "Keep.\n"),
        .init(
            label: "blockquote paragraph edited",
            old: "> Quoted one.\n\nTail.\n",
            new: "> Quoted two.\n\nTail.\n"),
        .init(
            label: "thematic break deleted",
            old: "Alpha.\n\n---\n\nBeta.\n",
            new: "Alpha.\n\nBeta.\n"),
        .init(
            label: "thematic break inserted",
            old: "Alpha.\n\nBeta.\n",
            new: "Alpha.\n\n---\n\nBeta.\n"),
        .init(
            label: "HTML block deleted",
            old: "Keep.\n\n<div>\nraw\n</div>\n",
            new: "Keep.\n"),
        .init(
            label: "HTML block inserted",
            old: "Keep.\n",
            new: "Keep.\n\n<div>\nraw\n</div>\n"),
        .init(
            label: "mermaid diagram replaced",
            old: "```mermaid\ngraph TD\nA-->B\n```\n",
            new: "```mermaid\ngraph TD\nA-->C\n```\n"),
        .init(
            label: "all content deleted",
            old: "Gone.\n",
            new: ""),
        .init(
            label: "all content inserted",
            old: "",
            new: "Brand new.\n"),
        .init(
            label: "footnote paragraph replaced (low similarity)",
            old: "Alpha beta[^a].\n\n[^a]: Body.\n",
            new: "Entirely different words now[^a].\n\n[^a]: Body.\n"),
        .init(
            label: "paragraph referencing second footnote deleted",
            old: "First[^a].\n\nGone with second[^b].\n\nTail.\n\n"
                + "[^a]: A.\n\n[^b]: B.\n",
            new: "First[^a].\n\nTail.\n\n[^a]: A.\n\n[^b]: B.\n"),
        .init(
            label: "paragraph with repeated reference deleted",
            old: "Twice[^a] and again[^a].\n\nGone third[^a].\n\nTail.\n\n"
                + "[^a]: A.\n",
            new: "Twice[^a] and again[^a].\n\nTail.\n\n[^a]: A.\n"),
        .init(
            label: "footnote definition body edited",
            old: "Text with a footnote[^a].\n\n[^a]: Old body.\n",
            new: "Text with a footnote[^a].\n\n[^a]: New body.\n"),
        .init(
            label: "comment definition body edited",
            old: "Text with a comment[^comment-a].\n\n"
                + "[^comment-a]: > a comment\n\n"
                + "    💬 {Tester @ 2026-07-08 12:00:00}:\n\n"
                + "    Old thread body.\n",
            new: "Text with a comment[^comment-a].\n\n"
                + "[^comment-a]: > a comment\n\n"
                + "    💬 {Tester @ 2026-07-08 12:00:00}:\n\n"
                + "    New thread body.\n"),
        .init(
            label: "comment paragraph replaced (low similarity)",
            old: "Alpha beta[^comment-a].\n\n"
                + "[^comment-a]: > Alpha\n\n"
                + "    💬 {Tester @ 2026-07-08 12:00:00}:\n\n"
                + "    A note.\n",
            new: "Entirely different words now[^comment-a].\n\n"
                + "[^comment-a]: > Alpha\n\n"
                + "    💬 {Tester @ 2026-07-08 12:00:00}:\n\n"
                + "    A note.\n"),
    ]

    // MARK: - Retained-tree overload parity

    // `CMarkUpHTMLVisitor.renderBody(_ parsed:)` reuses `ParsedMarkdown`'s
    // retained `cmarkDocument` instead of re-parsing the source string. It is
    // the entry production calls, so it must render byte-identically to the
    // String overload — plain and diffed.

    @Test(arguments: ParityCorpus.all, DocCAlertMode.allCases)
    func parsedOverloadMatchesStringOverloadPlain(
        _ document: ParityCorpus.Document, _ mode: DocCAlertMode
    ) {
        var options = RenderOptions()
        options.docCAlertMode = mode
        let viaString = CMarkUpHTMLVisitor.renderBody(
            document.markdown, options: options)
        let viaParsed = CMarkUpHTMLVisitor.renderBody(
            ParsedMarkdown(document.markdown), options: options)
        #expect(viaParsed == viaString)
    }

    @Test(arguments: ChangeIDParityTests.corpus + diffEditCases, [false, true])
    func parsedOverloadMatchesStringOverloadDiffed(
        _ c: ChangeIDParityTests.EditCase, _ showInlineDeletions: Bool
    ) {
        var options = RenderOptions()
        options.showInlineDeletions = showInlineDeletions
        options.waypoint = ParsedMarkdown(c.old)
        let viaString = CMarkUpHTMLVisitor.renderBody(c.new, options: options)
        let viaParsed = CMarkUpHTMLVisitor.renderBody(
            ParsedMarkdown(c.new), options: options)
        #expect(viaParsed == viaString)
    }

    // MARK: - Deletion footnote numbering

    // Deleted blocks belong to the old document. The cmark deletion path
    // seeds their numbering via `CMarkUpHTMLVisitor.footnoteNumbering(for:)`;
    // asserted directly so a failure names the seeding, not a byte diff.

    @Test func deletedBlockKeepsOldDocumentFootnoteNumber() {
        let old = "First[^a].\n\nGone with second[^b].\n\nTail.\n\n"
            + "[^a]: A.\n\n[^b]: B.\n"
        let new = "First[^a].\n\nTail.\n\n[^a]: A.\n\n[^b]: B.\n"
        let body = cmarkDiffedBody(new: new, old: old, options: .init())
        // The deleted paragraph's reference is the old document's second
        // footnote — not number 1, which a fresh mid-document count
        // would have assigned.
        #expect(body.contains(FootnoteProcessor.markerHTML(
            number: 2, label: "b", occurrence: 1)))
    }

    @Test func deletedBlockKeepsOldDocumentOccurrence() {
        let old = "Twice[^a] and again[^a].\n\nGone third[^a].\n\nTail.\n\n"
            + "[^a]: A.\n"
        let new = "Twice[^a] and again[^a].\n\nTail.\n\n[^a]: A.\n"
        let body = cmarkDiffedBody(new: new, old: old, options: .init())
        // The deleted paragraph's reference is the third occurrence of the
        // label in the old document (back-link id fnref-1-3).
        #expect(body.contains(FootnoteProcessor.markerHTML(
            number: 1, label: "a", occurrence: 3)))
    }

    /// A behavior the old swift-markdown pipeline got wrong and the port
    /// fixes: with word spans active on a paired edit, the reference is an
    /// AST node and its marker emits intact, rather than an `<ins>`/`<del>`
    /// landing *inside* the marker anchor. Pinned so a regression is named.
    @Test func wordSpannedFootnoteMarkerStaysIntact() {
        let old = "The quick fox[^a].\n\n[^a]: A.\n"
        let new = "The slow fox[^a].\n\n[^a]: A.\n"
        let body = cmarkDiffedBody(new: new, old: old, options: .init())
        // Word spans are active (high similarity), yet the marker HTML
        // appears unbroken in both the insertion and deletion blocks.
        let marker = FootnoteProcessor.markerHTML(
            number: 1, label: "a", occurrence: 1)
        let occurrences = body.components(separatedBy: marker).count - 1
        #expect(occurrences == 2)
        #expect(body.contains("<ins>"))
    }

    /// A paired **edit** of a roman-path DocC aside (first line over the
    /// 60-character bold-inline threshold). The old swift-markdown pipeline
    /// produced three defects at once here: the preceding deletion emitted a
    /// second time inside the alert, the inner `<p>` duplicated the
    /// `mud-change-ins` attributes already on the blockquote, and the
    /// word markers sheared by the stripped `Warning: ` prefix. The cmark
    /// visitor never routes the first paragraph through a separate paragraph
    /// visit, so none of that can happen; this pins the correct behavior.
    @Test func romanAsideEditAvoidsLegacyDefects() {
        let old = "> Warning: This DocC aside body is long enough that "
            + "the renderer keeps it\n> roman in its own paragraph "
            + "instead of bolding it once.\n"
        let new = "> Warning: This DocC aside body is long enough that "
            + "the renderer keeps it\n> roman in its own paragraph "
            + "instead of bolding it twice.\n"
        let body = cmarkDiffedBody(new: new, old: old, options: .init())

        // The deleted alert renders exactly once (legacy: twice).
        #expect(body.components(separatedBy: "mud-change-del").count - 1 == 1)
        // Change attributes sit on the alert blockquote only (legacy also
        // puts them on the inner <p>).
        #expect(body.contains(
            "<blockquote class=\"alert alert-warning mud-change-ins\""))
        #expect(!body.contains("<p class=\"mud-change-ins\""))
        // Word markers align past the stripped "Warning: " prefix
        // (legacy shears them by its length).
        #expect(body.contains("<ins>twice.</ins>"))
        #expect(body.contains("<del>once.</del>"))
    }
}
