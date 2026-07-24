/// Renders deleted blocks to HTML for the cmark Up-mode overlay (ported from
/// the swift-markdown pipeline; see
/// Doc/Plans/Archive/2026-07-single-parser-rendering.md).
///
/// Lives in the rendering layer so that `Diff/` never calls rendering code:
/// `DiffContext` receives `render` as a function at construction.
///
/// `footnoteNumbers` seeds the old document's footnote numbering. Deleted
/// blocks belong to the *old* document, and the old parse is raw, so the
/// deletion visitors — which start mid-document and cannot count first
/// references for themselves — take the numbering a full walk of the old
/// document assigns (`UpHTMLVisitor.footnoteNumbering(for:)`).
enum DeletionRenderer {
    /// The native HTML tag for a leaf block.
    static func tagForBlock(_ markup: CMarkNode) -> String {
        switch markup.kind {
        case .heading:                  return "h\(markup.headingLevel)"
        case .paragraph:                return "p"
        case .codeBlock:                return "pre"
        case .listItem, .taskListItem:  return "li"
        case .tableHead, .tableRow:     return "tr"
        case .thematicBreak:            return "hr"
        default:                        return "div"
        }
    }

    /// Builds a `RenderedDeletion` for a leaf block: renders inner HTML
    /// and extracts a plain-text summary. The `tag` field records the
    /// native element type; `html` contains only inner content.
    /// When `wordSpans` is provided, the deletion's inner HTML is
    /// rendered with word-level `<del>` markers for the red block.
    static func render(
        _ block: LeafBlock, changeID: String, wordSpans: [WordSpan]?,
        footnoteNumbers: UpHTMLVisitor.FootnoteNumbering? = nil
    ) -> RenderedDeletion {
        let markup = block.markup

        // If the paragraph is inside an alert-style blockquote,
        // render the deletion as a full alert with proper styling.
        if let blockQuote = markup.parent, blockQuote.kind == .blockQuote,
           let (alertHTML, category) =
               UpHTMLVisitor.renderAlertInnerHTML(
                   blockQuote, wordSpans: wordSpans,
                   footnoteNumbers: footnoteNumbers) {
            return RenderedDeletion(
                html: alertHTML, changeID: changeID,
                summary: ChangePlan.blockSummary(block),
                tag: "blockquote",
                wordSpans: wordSpans,
                extraClasses: "alert \(category.cssClass)")
        }

        let tag = tagForBlock(markup)
        let html: String

        // Mermaid diagrams: show placeholder instead of raw source.
        if markup.kind == .codeBlock,
           ChangePlan.codeLanguage(markup)?.lowercased() == "mermaid" {
            html = "<code><em>[revised diagram]</em></code>"
            return RenderedDeletion(
                html: html, changeID: changeID,
                summary: "[revised diagram]", tag: tag)
        }

        // Deleted math renders as MathML too, never through the word-span
        // paths below — their character stream can't take a MathML
        // substitution (the insertion side skips word spans the same way).
        if markup.kind == .codeBlock, markup.fenceInfo == "math" {
            return RenderedDeletion(
                html: mathInnerHTML(markup.literal ?? ""), changeID: changeID,
                summary: ChangePlan.blockSummary(block),
                tag: "div", extraClasses: "mud-math-block")
        }
        if let tex = UpHTMLVisitor.displayMathInterior(of: markup) {
            return RenderedDeletion(
                html: mathInnerHTML(tex), changeID: changeID,
                summary: ChangePlan.blockSummary(block),
                tag: "div", extraClasses: "mud-math-block")
        }

        if let wordSpans, !wordSpans.isEmpty,
           !UpHTMLVisitor.containsInlineMath(markup) {
            html = UpHTMLVisitor.renderWithWordSpans(
                markup, spans: wordSpans, role: .deletion,
                footnoteNumbers: footnoteNumbers)
        } else {
            switch markup.kind {
            case .codeBlock:
                html = UpHTMLVisitor.codeBlockInnerHTML(markup)
            case .thematicBreak:
                html = ""
            case .htmlBlock:
                html = markup.literal ?? ""
            default:
                var visitor = UpHTMLVisitor()
                visitor.footnoteNumbers = footnoteNumbers
                for child in markup.children { visitor.visit(child) }
                html = visitor.result
            }
        }

        return RenderedDeletion(
            html: html, changeID: changeID,
            summary: ChangePlan.blockSummary(block), tag: tag,
            wordSpans: wordSpans
        )
    }

    /// The inner HTML of a deleted display-math block: the rendered MathML,
    /// or the escaped TeX when the JS layer is unavailable — the same
    /// fallback `UpHTMLVisitor.emitMathBlock` uses.
    private static func mathInnerHTML(_ tex: String) -> String {
        MathRenderer.render(tex, displayMode: true) ?? HTMLEscaping.escape(tex)
    }
}

// MARK: - DiffContext convenience

extension DiffContext {
    /// Creates a diff context by matching blocks between old and new
    /// documents, rendering deletions with the standard Up-mode renderer.
    /// The underlying `ChangePlan` is computed at most once per
    /// (old, new) pair — see `ChangePlan.plan`. The old document's
    /// footnote numbering is computed here and captured by the renderer,
    /// so every deletion of one render shares one numbering pass.
    init(old: CMarkDocument, new: CMarkDocument,
         wordDiffThreshold: Double = 0.25) {
        let numbering = UpHTMLVisitor.footnoteNumbering(for: old)
        self.init(
            plan: ChangePlan.plan(
                old: old, new: new,
                wordDiffThreshold: wordDiffThreshold),
            renderDeletion: { block, changeID, wordSpans in
                DeletionRenderer.render(
                    block, changeID: changeID, wordSpans: wordSpans,
                    footnoteNumbers: numbering)
            })
    }
}

// MARK: - Rendered deletion

/// A pre-rendered deleted block, ready for injection into the HTML output — a
/// shared, parser-agnostic value type.
struct RenderedDeletion {
    /// The inner HTML content of the deleted block (no outer tag).
    let html: String
    /// The change ID matching the sidebar entry.
    let changeID: String
    /// Plain-text summary of the deleted content.
    let summary: String
    /// The native HTML tag for this block (e.g. "p", "li", "tr", "pre").
    let tag: String
    /// Word-level diff spans when this deletion is paired with an insertion.
    /// `nil` when unpaired or when inline structure diverges.
    let wordSpans: [WordSpan]?
    /// Extra CSS classes to add to the outer tag (e.g. alert classes).
    let extraClasses: String?

    init(
        html: String, changeID: String, summary: String, tag: String,
        wordSpans: [WordSpan]? = nil, extraClasses: String? = nil
    ) {
        self.html = html
        self.changeID = changeID
        self.summary = summary
        self.tag = tag
        self.wordSpans = wordSpans
        self.extraClasses = extraClasses
    }
}
