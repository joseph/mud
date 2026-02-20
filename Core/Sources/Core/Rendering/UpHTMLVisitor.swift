import Foundation
import Markdown

/// AST → web HTML visitor. Walks a swift-markdown `Document` and
/// emits HTML matching cmark-gfm output for visual parity.
///
/// Heading IDs are generated during the walk using `SlugGenerator`,
/// eliminating the need for regex post-processing.
struct UpHTMLVisitor: MarkupWalker {
    var result = ""

    /// Base URL of the document being rendered (typically its file URL).
    var baseURL: URL?

    /// Optional transform applied to each image `src` during rendering.
    /// Called with the original source string and the document base URL.
    /// Return a replacement URL string, or `nil` to keep the original.
    var resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?

    // Heading slug deduplication.
    private var slugTracker = SlugGenerator.Tracker()

    // List tightness state (saved/restored for nesting).
    private var inTightList = false

    // Table rendering state.
    private var tableColumnAlignments: [Table.ColumnAlignment?] = []
    private var currentCellColumn = 0
    private var inTableHead = false

    // MARK: - Block containers

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        result += "<blockquote>\n"
        descendInto(blockQuote)
        result += "</blockquote>\n"
    }

    mutating func visitOrderedList(_ orderedList: OrderedList) {
        let prev = inTightList
        inTightList = !Self.isLooseList(orderedList)
        if orderedList.startIndex != 1 {
            result += "<ol start=\"\(orderedList.startIndex)\">\n"
        } else {
            result += "<ol>\n"
        }
        descendInto(orderedList)
        result += "</ol>\n"
        inTightList = prev
    }

    mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
        let prev = inTightList
        inTightList = !Self.isLooseList(unorderedList)
        result += "<ul>\n"
        descendInto(unorderedList)
        result += "</ul>\n"
        inTightList = prev
    }

    mutating func visitListItem(_ listItem: ListItem) {
        if inTightList {
            result += "<li>"
        } else {
            result += "<li>\n"
        }
        if let checkbox = listItem.checkbox {
            result += "<input type=\"checkbox\" disabled=\"\""
            if checkbox == .checked {
                result += " checked=\"\""
            }
            result += " /> "
        }
        descendInto(listItem)
        result += "</li>\n"
    }

    // MARK: - Block leaves

    mutating func visitHeading(_ heading: Heading) {
        let level = heading.level
        let slug = slugTracker.slug(for: heading.plainText)
        result += "<h\(level) id=\"\(slug)\">"
        descendInto(heading)
        result += "</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        if inTightList && paragraph.parent is ListItem {
            descendInto(paragraph)
            result += "\n"
        } else {
            result += "<p>"
            descendInto(paragraph)
            result += "</p>\n"
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        let lang = codeBlock.language.flatMap { $0.isEmpty ? nil : $0 }
        if let lang {
            result += "<pre><code class=\"language-"
            result += HTMLEscaping.escape(lang)
            result += "\">"
        } else {
            result += "<pre><code>"
        }
        if let highlighted = CodeHighlighter.highlight(
            codeBlock.code, language: lang
        ) {
            result += highlighted
        } else {
            result += HTMLEscaping.escape(codeBlock.code)
        }
        result += "</code></pre>\n"
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        result += html.rawHTML
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        result += "<hr />\n"
    }

    // MARK: - Table

    mutating func visitTable(_ table: Table) {
        tableColumnAlignments = table.columnAlignments
        result += "<table>\n"
        descendInto(table)
        result += "</table>\n"
        tableColumnAlignments = []
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        inTableHead = true
        currentCellColumn = 0
        result += "<thead>\n<tr>\n"
        descendInto(tableHead)
        result += "</tr>\n</thead>\n"
        inTableHead = false
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        guard tableBody.childCount > 0 else { return }
        result += "<tbody>\n"
        descendInto(tableBody)
        result += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        currentCellColumn = 0
        result += "<tr>\n"
        descendInto(tableRow)
        result += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: Table.Cell) {
        let tag = inTableHead ? "th" : "td"
        let alignment = currentCellColumn < tableColumnAlignments.count
            ? tableColumnAlignments[currentCellColumn]
            : nil
        if let alignment {
            let value: String
            switch alignment {
            case .left:   value = "left"
            case .center: value = "center"
            case .right:  value = "right"
            }
            result += "<\(tag) align=\"\(value)\">"
        } else {
            result += "<\(tag)>"
        }
        descendInto(tableCell)
        result += "</\(tag)>\n"
        currentCellColumn += 1
    }

    // MARK: - Inline containers

    mutating func visitEmphasis(_ emphasis: Emphasis) {
        result += "<em>"
        descendInto(emphasis)
        result += "</em>"
    }

    mutating func visitStrong(_ strong: Strong) {
        result += "<strong>"
        descendInto(strong)
        result += "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
        result += "<del>"
        descendInto(strikethrough)
        result += "</del>"
    }

    mutating func visitLink(_ link: Markdown.Link) {
        result += "<a href=\"\(HTMLEscaping.escape(link.destination ?? ""))\""
        if let title = link.title, !title.isEmpty {
            result += " title=\"\(HTMLEscaping.escape(title))\""
        }
        result += ">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitImage(_ image: Image) {
        var src = image.source ?? ""
        if let baseURL, let resolve = resolveImageSource,
           let resolved = resolve(src, baseURL) {
            src = resolved
        }
        result += "<img src=\"\(HTMLEscaping.escape(src))\""
        result += " alt=\"\(HTMLEscaping.escape(image.plainText))\""
        if let title = image.title, !title.isEmpty {
            result += " title=\"\(HTMLEscaping.escape(title))\""
        }
        result += " />"
    }

    // MARK: - Inline leaves

    mutating func visitText(_ text: Text) {
        result += HTMLEscaping.escape(text.string)
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        result += "<code>"
        result += HTMLEscaping.escape(inlineCode.code)
        result += "</code>"
    }

    mutating func visitInlineHTML(_ html: InlineHTML) {
        result += html.rawHTML
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        result += "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        result += "\n"
    }

    // MARK: - Helpers

    /// A list is loose if any blank lines appear between consecutive
    /// list items or between block children within a list item.
    /// Uses source positions to detect gaps.
    private static func isLooseList(_ list: some Markup) -> Bool {
        var prevItemContentEnd: Int?
        for child in list.children {
            guard let range = child.range else { continue }
            // Blank line between consecutive items.
            if let prev = prevItemContentEnd,
               range.lowerBound.line > prev + 1 {
                return true
            }
            // Use the last child block's end, not the item's own range,
            // because swift-markdown extends the item range to include
            // trailing blank lines.
            if let item = child as? ListItem,
               let lastChild = item.children.reversed().first,
               let lastRange = lastChild.range {
                prevItemContentEnd = lastRange.upperBound.line
            } else {
                prevItemContentEnd = range.upperBound.line
            }

            // Blank line between block children within an item.
            if let item = child as? ListItem {
                var prevBlockEnd: Int?
                for block in item.children {
                    guard let br = block.range else { continue }
                    if let prev = prevBlockEnd,
                       br.lowerBound.line > prev + 1 {
                        return true
                    }
                    prevBlockEnd = br.upperBound.line
                }
            }
        }
        return false
    }
}
