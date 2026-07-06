import Markdown

/// Renders deleted blocks to HTML for the Up-mode overlay.
///
/// Lives in the rendering layer (moved out of `DiffContext`) so that
/// `Diff/` never calls rendering code: `DiffContext` receives `render`
/// as a function at construction.
enum DeletionRenderer {
    /// The native HTML tag for a leaf block.
    static func tagForBlock(_ markup: Markup) -> String {
        switch markup {
        case let h as Heading:             return "h\(h.level)"
        case is Paragraph:                 return "p"
        case is CodeBlock:                 return "pre"
        case is ListItem:                  return "li"
        case is Table.Head, is Table.Row:  return "tr"
        case is ThematicBreak:             return "hr"
        default:                           return "div"
        }
    }

    /// Builds a `RenderedDeletion` for a leaf block: renders inner HTML
    /// and extracts a plain-text summary. The `tag` field records the
    /// native element type; `html` contains only inner content.
    /// When `wordSpans` is provided, the deletion's inner HTML is
    /// rendered with word-level `<del>` markers for the red block.
    static func render(
        _ block: LeafBlock, changeID: String, wordSpans: [WordSpan]?
    ) -> RenderedDeletion {
        let markup = block.markup

        // If the paragraph is inside an alert-style blockquote,
        // render the deletion as a full alert with proper styling.
        if let blockQuote = markup.parent as? BlockQuote,
           let (alertHTML, category) =
               UpHTMLVisitor.renderAlertInnerHTML(
                   blockQuote, wordSpans: wordSpans) {
            return RenderedDeletion(
                html: alertHTML, changeID: changeID,
                summary: ChangePlan.blockSummary(block), tag: "blockquote",
                wordSpans: wordSpans,
                extraClasses: "alert \(category.cssClass)")
        }

        let tag = tagForBlock(markup)
        let html: String

        // Mermaid diagrams: show placeholder instead of raw source.
        if let cb = markup as? CodeBlock,
           cb.language?.lowercased() == "mermaid" {
            html = "<code><em>[revised diagram]</em></code>"
            return RenderedDeletion(
                html: html, changeID: changeID,
                summary: "[revised diagram]", tag: tag)
        }

        if let wordSpans, !wordSpans.isEmpty {
            html = UpHTMLVisitor.renderWithWordSpans(
                markup, spans: wordSpans, role: .deletion)
        } else {
            switch markup {
            case let cb as CodeBlock:
                html = UpHTMLVisitor.codeBlockInnerHTML(cb)
            case is ThematicBreak:
                html = ""
            case let hb as HTMLBlock:
                html = hb.rawHTML
            default:
                var visitor = UpHTMLVisitor()
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
}

// MARK: - DiffContext convenience

extension DiffContext {
    /// Creates a diff context by matching blocks between old and new
    /// documents, rendering deletions with the standard Up-mode renderer.
    /// The underlying `ChangePlan` is computed at most once per
    /// (old, new) pair — see `ChangePlan.plan`.
    init(old: ParsedMarkdown, new: ParsedMarkdown,
         wordDiffThreshold: Double = 0.25) {
        self.init(
            plan: ChangePlan.plan(
                old: old, new: new,
                wordDiffThreshold: wordDiffThreshold),
            renderDeletion: DeletionRenderer.render)
    }
}
