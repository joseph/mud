/// Renders deleted blocks to HTML for the cmark Up-mode overlay (ported from
/// the swift-markdown pipeline; see
/// Doc/Plans/Archive/2026-07-single-parser-rendering.md).
///
/// Lives in the rendering layer so that `Diff/` never calls rendering code:
/// `CMarkDiffContext` receives `render` as a function at construction.
///
/// `footnoteNumbers` seeds the old document's footnote numbering. Deleted
/// blocks belong to the *old* document, and the old parse is raw, so the
/// deletion visitors — which start mid-document and cannot count first
/// references for themselves — take the numbering a full walk of the old
/// document assigns (`CMarkUpHTMLVisitor.footnoteNumbering(for:)`).
enum CMarkDeletionRenderer {
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
        _ block: CMarkLeafBlock, changeID: String, wordSpans: [WordSpan]?,
        footnoteNumbers: CMarkUpHTMLVisitor.FootnoteNumbering? = nil
    ) -> RenderedDeletion {
        let markup = block.markup

        // If the paragraph is inside an alert-style blockquote,
        // render the deletion as a full alert with proper styling.
        if let blockQuote = markup.parent, blockQuote.kind == .blockQuote,
           let (alertHTML, category) =
               CMarkUpHTMLVisitor.renderAlertInnerHTML(
                   blockQuote, wordSpans: wordSpans,
                   footnoteNumbers: footnoteNumbers) {
            return RenderedDeletion(
                html: alertHTML, changeID: changeID,
                summary: CMarkChangePlan.blockSummary(block),
                tag: "blockquote",
                wordSpans: wordSpans,
                extraClasses: "alert \(category.cssClass)")
        }

        let tag = tagForBlock(markup)
        let html: String

        // Mermaid diagrams: show placeholder instead of raw source.
        if markup.kind == .codeBlock,
           CMarkChangePlan.codeLanguage(markup)?.lowercased() == "mermaid" {
            html = "<code><em>[revised diagram]</em></code>"
            return RenderedDeletion(
                html: html, changeID: changeID,
                summary: "[revised diagram]", tag: tag)
        }

        if let wordSpans, !wordSpans.isEmpty {
            html = CMarkUpHTMLVisitor.renderWithWordSpans(
                markup, spans: wordSpans, role: .deletion,
                footnoteNumbers: footnoteNumbers)
        } else {
            switch markup.kind {
            case .codeBlock:
                html = CMarkUpHTMLVisitor.codeBlockInnerHTML(markup)
            case .thematicBreak:
                html = ""
            case .htmlBlock:
                html = markup.literal ?? ""
            default:
                var visitor = CMarkUpHTMLVisitor()
                visitor.footnoteNumbers = footnoteNumbers
                for child in markup.children { visitor.visit(child) }
                html = visitor.result
            }
        }

        return RenderedDeletion(
            html: html, changeID: changeID,
            summary: CMarkChangePlan.blockSummary(block), tag: tag,
            wordSpans: wordSpans
        )
    }
}

// MARK: - CMarkDiffContext convenience

extension CMarkDiffContext {
    /// Creates a diff context by matching blocks between old and new
    /// documents, rendering deletions with the standard Up-mode renderer.
    /// The underlying `CMarkChangePlan` is computed at most once per
    /// (old, new) pair — see `CMarkChangePlan.plan`. The old document's
    /// footnote numbering is computed here and captured by the renderer,
    /// so every deletion of one render shares one numbering pass.
    init(old: CMarkDocument, new: CMarkDocument,
         wordDiffThreshold: Double = 0.25) {
        let numbering = CMarkUpHTMLVisitor.footnoteNumbering(for: old)
        self.init(
            plan: CMarkChangePlan.plan(
                old: old, new: new,
                wordDiffThreshold: wordDiffThreshold),
            renderDeletion: { block, changeID, wordSpans in
                CMarkDeletionRenderer.render(
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
