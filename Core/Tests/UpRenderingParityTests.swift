import Testing

@testable import MudCore

/// Stage 3 of Doc/Plans/2026-07-single-parser-rendering.md: the differential
/// harness over the two Up-mode body renderers. The legacy pipeline
/// preprocesses the source (`FootnoteProcessor.process` bakes marker HTML
/// into the bytes) and renders through swift-markdown; `CMarkUpHTMLVisitor`
/// renders the raw source from one footnote-aware cmark parse. The two bodies
/// must match byte-for-byte over the whole corpus — this comparison gates the
/// eventual cutover, so it must keep passing until Stage 6 deletes the legacy
/// side.
@Suite("Up-mode rendering parity")
struct UpRenderingParityTests {

    /// The legacy pipeline's body render: footnote preprocessing at the
    /// String boundary, then the swift-markdown visitor — the exact steps of
    /// `MudCore.renderUpPipeline` minus the bottom footnotes/comments
    /// sections, which both pipelines share (`FootnoteHTMLRenderer` /
    /// `CommentHTMLRenderer` render from models, not from either parse).
    private func legacyBody(
        _ source: String, options: RenderOptions
    ) -> String {
        let processed = FootnoteProcessor.process(
            source, mode: options.footnoteMode)
        return UpHTMLVisitor.renderBody(
            ParsedMarkdown(processed.transformedMarkdown), options: options)
    }

    @Test(arguments: ParityCorpus.all, DocCAlertMode.allCases)
    func bodyHTMLMatchesLegacyPipeline(
        _ document: ParityCorpus.Document, _ mode: DocCAlertMode
    ) {
        var options = RenderOptions()
        options.docCAlertMode = mode
        let legacy = legacyBody(document.markdown, options: options)
        let ported = CMarkUpHTMLVisitor.renderBody(
            document.markdown, options: options)
        #expect(ported == legacy)
    }

    // MARK: - Footnote numbering

    // The numbering logic Stage 3 moves out of `FootnoteProcessor.process`'s
    // rewrite pass, asserted directly so a failure names the moved logic
    // instead of pointing at a whole-document byte diff.

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
}
