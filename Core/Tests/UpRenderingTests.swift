import Foundation
import Testing

@testable import MudCore

/// Up-mode body rendering. One footnote-aware cmark parse renders the raw
/// source. These tests make focused assertions on the footnote-numbering,
/// diff, and marker behavior the visitor owns, and pin that the retained-tree
/// overload matches the string overload. Whole-document output is pinned
/// separately by `GoldenRenderingTests`.
@Suite("Up-mode rendering")
struct UpRenderingTests {

    // MARK: - Footnote numbering

    // The numbering logic the port owns, asserted directly so a failure names
    // the logic instead of pointing at a whole-document byte diff.

    @Test func footnoteNumberingFollowsFirstReferenceOrder() {
        let body = UpHTMLVisitor.renderBody(
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
        let body = UpHTMLVisitor.renderBody(
            ParityCorpus.footnoteNumbering.markdown, options: .init())
        // The comment renders as a 💬 marker between footnotes 1 and 2 and
        // leaves no gap in the numbering.
        #expect(body.contains("data-mud-label=\"comment-note\""))
        #expect(!body.contains("data-fn-num=\"3\""))
    }

    @Test func undefinedReferenceStaysLiteralAndOrphanDefinitionVanishes() {
        let body = UpHTMLVisitor.renderBody(
            ParityCorpus.footnoteNumbering.markdown, options: .init())
        // `[^missing]` resolves to no definition, so its text survives.
        #expect(body.contains("[^missing]"))
        // The unreferenced definition renders nothing.
        #expect(!body.contains("Never referenced"))
        // Referenced definition bodies belong to the bottom section, not
        // the rendered body.
        #expect(!body.contains("Alpha body"))
    }

    // MARK: - Table column alignment

    // The delimiter row's alignment reaches the HTML as the presentational
    // `align` attribute on each cell (`mud-up.css` then honors it with
    // attribute selectors that outrank the bare `th, td` rule). These pin the
    // markup so a regression is caught at the render layer, not only in CSS.

    @Test func tableCellsCarryColumnAlignmentAttributes() {
        let markdown = """
            | Left | Center | Right | Default |
            | :--- | :----: | ----: | ------- |
            | a    | b      | c     | d       |

            """
        let body = UpHTMLVisitor.renderBody(markdown, options: .init())
        // Header cells carry the column's alignment.
        #expect(body.contains("<th align=\"left\">Left</th>"))
        #expect(body.contains("<th align=\"center\">Center</th>"))
        #expect(body.contains("<th align=\"right\">Right</th>"))
        // A plain `---` column gets no attribute, so it falls to the default.
        #expect(body.contains("<th>Default</th>"))
        // Body cells carry the same per-column alignment.
        #expect(body.contains("<td align=\"left\">a</td>"))
        #expect(body.contains("<td align=\"center\">b</td>"))
        #expect(body.contains("<td align=\"right\">c</td>"))
        #expect(body.contains("<td>d</td>"))
    }

    /// The Up stylesheet honors the `align` attribute with attribute-selector
    /// rules. Without them a bare `th, td { text-align: left }` would override
    /// the presentational hint, which is the bug this pins against.
    @Test func upStylesheetHonorsAlignmentAttributes() throws {
        let css = try #require(HTMLTemplate.loadResource("mud-up", type: "css"))
        #expect(css.contains("td[align=\"center\"]"))
        #expect(css.contains("td[align=\"right\"]"))
    }

    // MARK: - GFM alerts

    // GitHub wants the `[!TYPE]` tag alone on its line; Mud also renders
    // content that follows it on the same line, as body text.

    @Test func contentAfterTheTagKeepsItsLineBreak() {
        let markdown = """
            > [!TIP] Same-line content after the tag.
            > A second line in the first paragraph.

            """
        let body = UpHTMLVisitor.renderBody(markdown, options: .init())
        // The soft break between the two lines is the paragraph's own, not
        // the one that ended the tag line, so it still renders. Dropping it
        // ran "tag.A second" together.
        #expect(
            body.contains(
                "<p>Same-line content after the tag.\n"
                    + "A second line in the first paragraph.</p>"))
    }

    @Test func aTagAloneOnItsLineLosesItsBreak() {
        let markdown = """
            > [!NOTE]
            > The body starts on the second line.

            """
        let body = UpHTMLVisitor.renderBody(markdown, options: .init())
        // Nothing rendered from the tag line, so the break that ended it
        // would open the body with a stray newline.
        #expect(
            body.contains("<p>The body starts on the second line.</p>"))
    }

    // MARK: - Diffed rendering

    /// The cmark pipeline's diffed body render: the raw waypoint goes
    /// straight into `RenderOptions`.
    private func cmarkDiffedBody(
        new: String, old: String, options: RenderOptions
    ) -> String {
        var options = options
        options.waypoint = ParsedMarkdown(old)
        return UpHTMLVisitor.renderBody(new, options: options)
    }

    /// Edit cases beyond `ChangeIDParityTests.corpus` (which covers
    /// paragraph and code-block gap shapes): the deletion-placer paths
    /// (list items, table rows, hoisting, deferral, reclaiming, trailing),
    /// word spans in every activating block shape, alerts, and the
    /// footnote/comment interplay with change tracking. Consumed by the
    /// overload-parity sweep below and by `DownRenderingTests`' diffed
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
            label: "GFM alert body reworded",
            old: "> [!NOTE]\n> The report covers March results.\n",
            new: "> [!NOTE]\n> The report covers April results.\n"),
        .init(
            label: "GFM alert reworded on the tag line",
            old: "> [!TIP] Ship the beta build.\n> Then tag it.\n",
            new: "> [!TIP] Ship the final build.\n> Then tag it.\n"),
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

    // `UpHTMLVisitor.renderBody(_ parsed:)` reuses `ParsedMarkdown`'s
    // retained `cmarkDocument` instead of re-parsing the source string. It is
    // the entry production calls, so it must render byte-identically to the
    // String overload — plain and diffed.

    @Test(arguments: ParityCorpus.all, DocCAlertMode.allCases)
    func parsedOverloadMatchesStringOverloadPlain(
        _ document: ParityCorpus.Document, _ mode: DocCAlertMode
    ) {
        var options = RenderOptions()
        options.docCAlertMode = mode
        let viaString = UpHTMLVisitor.renderBody(
            document.markdown, options: options)
        let viaParsed = UpHTMLVisitor.renderBody(
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
        let viaString = UpHTMLVisitor.renderBody(c.new, options: options)
        let viaParsed = UpHTMLVisitor.renderBody(
            ParsedMarkdown(c.new), options: options)
        #expect(viaParsed == viaString)
    }

    // MARK: - Deletion footnote numbering

    // Deleted blocks belong to the old document. The cmark deletion path
    // seeds their numbering via `UpHTMLVisitor.footnoteNumbering(for:)`;
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

    /// A deleted block emits no comment marker, paired or not. The surviving
    /// block carries the label's live marker; a duplicate inside the hidden
    /// red block would be the first `data-mud-label` match in the DOM, and
    /// the column (`anchorFor` in mud-comments.js) would anchor the capsule
    /// to the hidden copy and drop the comment from the column.
    @Test func deletedBlockEmitsNoCommentMarker() {
        let def = "\n\n[^comment-a]: > quote\n\n"
            + "    💬 {Tester @ 2026-07-08 12:00:00}:\n\n"
            + "    A note.\n"
        let old = "The quick fox[^comment-a].\(def)"
        let marker = FootnoteProcessor.commentMarkerHTML(label: "comment-a")

        // Paired edit: word spans active in both blocks, yet only the
        // insertion block renders the marker.
        let paired = cmarkDiffedBody(
            new: "The slow fox[^comment-a].\(def)", old: old, options: .init())
        #expect(paired.contains("<ins>"))
        #expect(paired.contains("mud-change-del"))
        #expect(paired.components(separatedBy: marker).count - 1 == 1)

        // Low-similarity replacement: the old block renders whole as a
        // deletion, again without its marker.
        let replaced = cmarkDiffedBody(
            new: "Entirely different words now[^comment-a].\(def)",
            old: old, options: .init())
        #expect(replaced.contains("mud-change-del"))
        #expect(replaced.components(separatedBy: marker).count - 1 == 1)
    }

    /// A paired **edit** of a roman-path DocC aside (first line over the
    /// 60-character bold-inline threshold). The visitor renders the first
    /// paragraph inline, never routing it through a separate paragraph visit,
    /// so this pins three properties: the preceding deletion emits exactly
    /// once (not a second time inside the alert), the `mud-change-ins`
    /// attributes sit on the blockquote alone (not duplicated on an inner
    /// `<p>`), and the word markers align past the stripped `Warning: `
    /// prefix (not sheared by its length).
    @Test func romanAsideEditRendersCleanly() {
        let old = "> Warning: This DocC aside body is long enough that "
            + "the renderer keeps it\n> roman in its own paragraph "
            + "instead of bolding it once.\n"
        let new = "> Warning: This DocC aside body is long enough that "
            + "the renderer keeps it\n> roman in its own paragraph "
            + "instead of bolding it twice.\n"
        let body = cmarkDiffedBody(new: new, old: old, options: .init())

        // The deleted alert renders exactly once.
        #expect(body.components(separatedBy: "mud-change-del").count - 1 == 1)
        // Change attributes sit on the alert blockquote only, not the
        // inner <p>.
        #expect(body.contains(
            "<blockquote class=\"alert alert-warning mud-change-ins\""))
        #expect(!body.contains("<p class=\"mud-change-ins\""))
        // Word markers align past the stripped "Warning: " prefix.
        #expect(body.contains("<ins>twice.</ins>"))
        #expect(body.contains("<del>once.</del>"))
    }
}
