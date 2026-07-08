/// A depth-first walker over a ``CMarkDocument`` tree with default-descend
/// behavior — the counterpart of swift-markdown's `MarkupWalker`, with the
/// same method vocabulary (`visitParagraph`, `visitOrderedList`,
/// `visitInlineCode`, …) so existing walkers port method-for-method.
///
/// Every `visit*` method defaults to ``defaultVisit(_:)``, which descends
/// into the node's children; an override that wants its subtree must call
/// ``descendInto(_:)`` itself. Two default chains mirror how swift-markdown
/// models the same nodes: a task list item falls back to
/// ``visitListItem(_:)`` (it *is* an item), and the table header row falls
/// back to ``visitTableRow(_:)``.
///
/// Dispatch goes through ``visit(_:)``, which splits `.list` by flavor into
/// `visitOrderedList` / `visitUnorderedList` — cmark has one list node where
/// swift-markdown has two types.
protocol CMarkWalker {
    mutating func defaultVisit(_ node: CMarkNode)

    // Blocks.
    mutating func visitDocument(_ node: CMarkNode)
    mutating func visitBlockQuote(_ node: CMarkNode)
    mutating func visitOrderedList(_ node: CMarkNode)
    mutating func visitUnorderedList(_ node: CMarkNode)
    mutating func visitListItem(_ node: CMarkNode)
    mutating func visitTaskListItem(_ node: CMarkNode)
    mutating func visitCodeBlock(_ node: CMarkNode)
    mutating func visitHTMLBlock(_ node: CMarkNode)
    mutating func visitCustomBlock(_ node: CMarkNode)
    mutating func visitParagraph(_ node: CMarkNode)
    mutating func visitHeading(_ node: CMarkNode)
    mutating func visitThematicBreak(_ node: CMarkNode)
    mutating func visitFootnoteDefinition(_ node: CMarkNode)

    // Inlines.
    mutating func visitText(_ node: CMarkNode)
    mutating func visitSoftBreak(_ node: CMarkNode)
    mutating func visitLineBreak(_ node: CMarkNode)
    mutating func visitInlineCode(_ node: CMarkNode)
    mutating func visitInlineHTML(_ node: CMarkNode)
    mutating func visitCustomInline(_ node: CMarkNode)
    mutating func visitEmphasis(_ node: CMarkNode)
    mutating func visitStrong(_ node: CMarkNode)
    mutating func visitLink(_ node: CMarkNode)
    mutating func visitImage(_ node: CMarkNode)
    mutating func visitFootnoteReference(_ node: CMarkNode)

    // Extensions.
    mutating func visitTable(_ node: CMarkNode)
    mutating func visitTableHead(_ node: CMarkNode)
    mutating func visitTableRow(_ node: CMarkNode)
    mutating func visitTableCell(_ node: CMarkNode)
    mutating func visitStrikethrough(_ node: CMarkNode)

    /// An unrecognized extension node. Descends by default so unknown
    /// containers stay transparent.
    mutating func visitUnknown(_ node: CMarkNode)
}

extension CMarkWalker {
    /// Dispatches `node` to its kind's visit method.
    mutating func visit(_ node: CMarkNode) {
        switch node.kind {
        case .document: visitDocument(node)
        case .blockQuote: visitBlockQuote(node)
        case .list:
            if node.listType == .ordered {
                visitOrderedList(node)
            } else {
                visitUnorderedList(node)
            }
        case .listItem: visitListItem(node)
        case .taskListItem: visitTaskListItem(node)
        case .codeBlock: visitCodeBlock(node)
        case .htmlBlock: visitHTMLBlock(node)
        case .customBlock: visitCustomBlock(node)
        case .paragraph: visitParagraph(node)
        case .heading: visitHeading(node)
        case .thematicBreak: visitThematicBreak(node)
        case .footnoteDefinition: visitFootnoteDefinition(node)
        case .text: visitText(node)
        case .softBreak: visitSoftBreak(node)
        case .lineBreak: visitLineBreak(node)
        case .inlineCode: visitInlineCode(node)
        case .inlineHTML: visitInlineHTML(node)
        case .customInline: visitCustomInline(node)
        case .emphasis: visitEmphasis(node)
        case .strong: visitStrong(node)
        case .link: visitLink(node)
        case .image: visitImage(node)
        case .footnoteReference: visitFootnoteReference(node)
        case .table: visitTable(node)
        case .tableHead: visitTableHead(node)
        case .tableRow: visitTableRow(node)
        case .tableCell: visitTableCell(node)
        case .strikethrough: visitStrikethrough(node)
        case .unknown: visitUnknown(node)
        }
    }

    /// Visits each of `node`'s children in order.
    mutating func descendInto(_ node: CMarkNode) {
        for child in node.children {
            visit(child)
        }
    }

    mutating func defaultVisit(_ node: CMarkNode) {
        descendInto(node)
    }

    mutating func visitDocument(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitBlockQuote(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitOrderedList(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitUnorderedList(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitListItem(_ node: CMarkNode) { defaultVisit(node) }
    /// A task list item is an item first; overriding `visitListItem` alone
    /// covers both unless task items need their own handling.
    mutating func visitTaskListItem(_ node: CMarkNode) { visitListItem(node) }
    mutating func visitCodeBlock(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitHTMLBlock(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitCustomBlock(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitParagraph(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitHeading(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitThematicBreak(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitFootnoteDefinition(_ node: CMarkNode) {
        defaultVisit(node)
    }
    mutating func visitText(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitSoftBreak(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitLineBreak(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitInlineCode(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitInlineHTML(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitCustomInline(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitEmphasis(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitStrong(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitLink(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitImage(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitFootnoteReference(_ node: CMarkNode) {
        defaultVisit(node)
    }
    mutating func visitTable(_ node: CMarkNode) { defaultVisit(node) }
    /// The header row is a row first; overriding `visitTableRow` alone covers
    /// both unless the header needs its own handling.
    mutating func visitTableHead(_ node: CMarkNode) { visitTableRow(node) }
    mutating func visitTableRow(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitTableCell(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitStrikethrough(_ node: CMarkNode) { defaultVisit(node) }
    mutating func visitUnknown(_ node: CMarkNode) { defaultVisit(node) }
}
