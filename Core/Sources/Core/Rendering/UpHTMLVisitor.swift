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
        if let (category, title) = Self.detectGFMAlert(blockQuote) {
            emitAlertOpen(category)
            emitAlertTitle(category, title)
            emitGFMAlertContent(blockQuote, category: category)
            result += "</blockquote>\n"
        } else if let (category, title, content) = Self.detectDocCAlert(blockQuote) {
            emitAlertOpen(category)
            emitAlertTitle(category, title)
            for block in content {
                visit(block)
            }
            result += "</blockquote>\n"
        } else if let statusValue = Self.detectStatusAside(blockQuote) {
            emitAlertOpen(.status)
            emitStatusTitle(statusValue)
            emitStatusContent(blockQuote)
            result += "</blockquote>\n"
        } else {
            result += "<blockquote>\n"
            descendInto(blockQuote)
            result += "</blockquote>\n"
        }
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

    // MARK: - Alerts

    /// Visual category for GFM alerts and DocC asides.
    private enum AlertCategory: String, CaseIterable {
        case note, tip, important, warning, caution, status

        var cssClass: String { "alert-\(rawValue)" }

        var title: String { rawValue.capitalized }

        /// Inline SVG icon (GitHub Octicons, MIT licensed).
        var icon: String { Self.icons[self]! }

        private static let icons: [AlertCategory: String] = {
            var map: [AlertCategory: String] = [:]
            for category in allCases {
                let name = "alert-\(category.rawValue)"
                guard let url = Bundle.module.url(
                    forResource: name, withExtension: "svg"
                ), let svg = try? String(
                    contentsOf: url, encoding: .utf8
                ) else { continue }
                map[category] = svg
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return map
        }()
    }

    /// Maps a DocC `Aside.Kind` raw value to a visual alert category.
    /// Predefined kinds not listed explicitly default to `.note`.
    private static let doccCategoryMap: [String: AlertCategory] = {
        let explicit: [AlertCategory: [Aside.Kind]] = [
            .note: [.note, .remark],
            .tip: [.tip, .experiment],
            .important: [.important, .attention],
            .warning: [.warning, .precondition, .postcondition,
                       .requires, .invariant],
            .caution: [.bug, .throws],
        ]
        var map: [String: AlertCategory] = [:]
        for (category, kinds) in explicit {
            for kind in kinds { map[kind.rawValue] = category }
        }
        for kind in Aside.Kind.allCases where map[kind.rawValue] == nil {
            map[kind.rawValue] = .note
        }
        return map
    }()

    // GFM tag strings and their categories.
    private static let gfmAlertTags: [(String, AlertCategory)] = [
        ("[!NOTE]", .note), ("[!TIP]", .tip),
        ("[!IMPORTANT]", .important),
        ("[!WARNING]", .warning), ("[!CAUTION]", .caution),
    ]

    /// Detects a GFM alert tag in the first paragraph of a blockquote.
    private static func detectGFMAlert(
        _ blockQuote: BlockQuote
    ) -> (AlertCategory, String)? {
        // MarkupChildren.first resolves to first(where:), not the
        // Sequence property, so we materialise to Array for indexing.
        let children = Array(blockQuote.children)
        guard let paragraph = children.first as? Paragraph else {
            return nil
        }
        let text = paragraph.plainText
        guard text.hasPrefix("[!") else { return nil }
        for (tag, category) in gfmAlertTags where text.hasPrefix(tag) {
            return (category, category.title)
        }
        return nil
    }

    /// Emits the content of a GFM alert, stripping the `[!TYPE]` tag
    /// from the first paragraph. Walks the first paragraph's inline
    /// children directly: skips the tag Text node (emitting any
    /// trailing content on the same line), skips a following SoftBreak,
    /// then visits remaining inlines and subsequent block children.
    private mutating func emitGFMAlertContent(
        _ blockQuote: BlockQuote, category: AlertCategory
    ) {
        let tag = "[!\(category.rawValue.uppercased())]"
        let children = Array(blockQuote.children)
        guard let firstPara = children.first as? Paragraph else {
            return
        }

        let inlines = Array(firstPara.children)
        var index = 0
        var opened = false

        // Strip the [!TYPE] tag from the first Text node.
        if let tagNode = inlines.first as? Text {
            index = 1
            let after = String(
                tagNode.string.dropFirst(tag.count)
                    .drop(while: { $0 == " " })
            )
            if !after.isEmpty {
                opened = true
                result += "<p>"
                result += HTMLEscaping.escape(after)
            }
            // Skip SoftBreak that separates the tag line from content.
            if index < inlines.count && inlines[index] is SoftBreak {
                index += 1
            }
        }

        // Visit remaining inlines from the first paragraph.
        if index < inlines.count {
            if !opened { result += "<p>"; opened = true }
            for i in index..<inlines.count { visit(inlines[i]) }
        }
        if opened { result += "</p>\n" }

        // Visit remaining block children after the first paragraph.
        for child in children.dropFirst() { visit(child) }
    }

    /// Detects a DocC aside tag in a blockquote. Returns the alert
    /// category, display title, and tag-stripped content blocks.
    private static func detectDocCAlert(
        _ blockQuote: BlockQuote
    ) -> (AlertCategory, String, [BlockMarkup])? {
        guard let aside = Aside(
            blockQuote, tagRequirement: .requireAnyLengthTag
        ) else { return nil }
        guard let category = doccCategoryMap[aside.kind.rawValue] else {
            return nil
        }
        return (category, aside.kind.displayName, aside.content)
    }

    /// Emits the opening `<blockquote>` tag with alert CSS classes.
    private mutating func emitAlertOpen(_ category: AlertCategory) {
        result += "<blockquote class=\"alert \(category.cssClass)\">\n"
    }

    /// Emits the alert title paragraph with icon and text.
    private mutating func emitAlertTitle(
        _ category: AlertCategory, _ title: String
    ) {
        result += "<p class=\"alert-title\">"
        result += category.icon
        result += HTMLEscaping.escape(title)
        result += "</p>\n"
    }

    // MARK: - Status aside

    /// Detects a `> Status:` prefix in the first paragraph of a blockquote.
    /// Returns the status value (text after "Status: ") if found, nil
    /// otherwise. Requires a non-empty status value.
    private static func detectStatusAside(
        _ blockQuote: BlockQuote
    ) -> String? {
        let children = Array(blockQuote.children)
        guard let paragraph = children.first as? Paragraph else {
            return nil
        }
        let inlines = Array(paragraph.children)
        guard let firstText = inlines.first as? Text else {
            return nil
        }
        guard firstText.string.hasPrefix("Status:") else {
            return nil
        }
        let afterPrefix = String(
            firstText.string.dropFirst("Status:".count)
                .drop(while: { $0 == " " })
        )
        guard !afterPrefix.isEmpty else { return nil }
        return afterPrefix
    }

    /// Emits the Status aside title: icon, "Status: ", and bold value.
    private mutating func emitStatusTitle(_ statusValue: String) {
        result += "<p class=\"alert-title\">"
        result += AlertCategory.status.icon
        result += "Status: <strong>"
        result += HTMLEscaping.escape(statusValue)
        result += "</strong></p>\n"
    }

    /// Emits the body content of a Status aside. Strips the first Text
    /// node (which contains "Status: Value"), skips a following SoftBreak,
    /// then visits remaining inlines and subsequent block children.
    private mutating func emitStatusContent(
        _ blockQuote: BlockQuote
    ) {
        let children = Array(blockQuote.children)
        guard let firstPara = children.first as? Paragraph else {
            return
        }

        let inlines = Array(firstPara.children)
        var index = 0
        var opened = false

        // Skip the first Text node (contains "Status: Value").
        if inlines.first is Text {
            index = 1
            // Skip SoftBreak separating the status line from content.
            if index < inlines.count && inlines[index] is SoftBreak {
                index += 1
            }
        }

        // Visit remaining inlines from the first paragraph.
        if index < inlines.count {
            result += "<p>"
            opened = true
            for i in index..<inlines.count { visit(inlines[i]) }
        }
        if opened { result += "</p>\n" }

        // Visit remaining block children after the first paragraph.
        for child in children.dropFirst() { visit(child) }
    }

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
