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

    var alertDetector = AlertDetector()

    /// When non-nil, change attributes are emitted on native elements
    /// for blocks that differ from the waypoint document.
    var diffContext: DiffContext?

    /// When false, non-consuming `<del>` spans in paired insertion
    /// blocks are silently skipped instead of emitted inline.
    var showInlineDeletions = false

    /// Change IDs already emitted by peek-ahead in `visitListItem`,
    /// preventing double emission in `emitPrecedingDeletions`.
    private var consumedDeletionIDs: Set<String> = []

    /// Non-`<tr>` deletions encountered inside a table body, deferred
    /// until after `</table>` to avoid invalid HTML.
    private var deferredDeletions: [RenderedDeletion] = []

    // MARK: - Block containers

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        let innerParagraph = blockQuote.children.first(where: { $0 is Paragraph })
        if let (category, title) = alertDetector.detectGFMAlert(blockQuote) {
            let attrs = innerParagraph.flatMap { changeAttributes(for: $0) }
                ?? .empty
            emitAlertOpen(category, attrs: attrs)
            emitAlertTitle(category, title)
            emitGFMAlertContent(blockQuote, category: category)
            result += "</blockquote>\n"
        } else if let (category, title, content) = alertDetector.detectDocCAlert(blockQuote) {
            let attrs = innerParagraph.flatMap { changeAttributes(for: $0) }
                ?? .empty
            emitAlertOpen(category, attrs: attrs)
            activateAlertWordSpans(
                for: innerParagraph, content: content)
            emitDocCAlertTitleAndContent(category, title, content)
            deactivateWordSpans()
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
        // Peek ahead: when a deleted list item's deletion lands on the
        // first child (e.g. a Paragraph inside a complex item with a
        // nested list), emit it here — before the <li> — so it
        // becomes a valid sibling rather than nesting inside this item.
        if let diffContext,
           let firstChild = listItem.children.first(where: { _ in true }) {
            for del in diffContext.precedingDeletions(before: firstChild) {
                if del.tag == "li" {
                    emitDeletion(del)
                    consumedDeletionIDs.insert(del.changeID)
                }
            }
        }
        let attrs = changeAttributes(for: listItem)
        if inTightList {
            result += "<li\(attrs?.asString ?? "")>"
        } else {
            result += "<li\(attrs?.asString ?? "")>\n"
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
        let attrs = changeAttributes(for: heading)
        let level = heading.level
        let slug = slugTracker.slug(for: heading.plainText)
        activateWordSpans(for: heading)
        result += "<h\(level) id=\"\(slug)\"\(attrs?.asString ?? "")>"
        descendInto(heading)
        result += "</h\(level)>\n"
        deactivateWordSpans()
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        let attrs = changeAttributes(for: paragraph)
        activateWordSpans(for: paragraph)
        // List items store their annotation on the ListItem node,
        // not the inner Paragraph. Fall back to the parent.
        if wordSpans == nil, let listItem = paragraph.parent as? ListItem {
            activateWordSpans(for: listItem)
        }
        if inTightList && paragraph.parent is ListItem {
            if attrs != nil {
                result += "<span\(attrs!.asString)>"
                descendInto(paragraph)
                result += "</span>\n"
            } else {
                descendInto(paragraph)
                result += "\n"
            }
        } else {
            result += "<p\(attrs?.asString ?? "")>"
            descendInto(paragraph)
            result += "</p>\n"
        }
        deactivateWordSpans()
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        // Check for line-level diff first. changeAttributes is still
        // called so preceding deletions are emitted as a side effect.
        let attrs = changeAttributes(for: codeBlock)

        if let codeDiff = diffContext?.codeBlockDiff(for: codeBlock) {
            emitDiffedCodeBlock(codeBlock, diff: codeDiff)
            return
        }

        let classAttr: String
        if let attrs {
            classAttr = "mud-code \(attrs.classes)"
        } else {
            classAttr = "mud-code"
        }
        result += "<pre class=\"\(classAttr)\"\(attrs?.dataAttrs ?? "")>"
        result += Self.codeBlockInnerHTML(codeBlock)
        result += "</pre>\n"
    }

    /// Emits a code block with line-level diff structure.
    private mutating func emitDiffedCodeBlock(
        _ codeBlock: CodeBlock, diff: CodeBlockDiff
    ) {
        let lang = codeBlock.language.flatMap { $0.isEmpty ? nil : $0 }

        // <pre> has mud-code-diff but no block-level data-change-id.
        result += "<pre class=\"mud-code mud-code-diff\">"

        // Code header (language label).
        if let lang {
            let escaped = HTMLEscaping.escape(lang)
            result += "<div class=\"code-header\">"
            result += "<span class=\"code-language\">\(escaped)</span>"
            result += "</div>"
            result += "<code class=\"language-\(escaped)\">"
        } else {
            result += "<code>"
        }

        // Emit each line as a <span class="cl"> with annotation
        // classes and data attributes.
        for line in diff.lines {
            var classes = "cl"
            var dataAttrs = ""

            switch line.annotation {
            case .unchanged:
                break
            case .inserted:
                classes += " cl-ins"
            case .deleted:
                classes += " cl-del"
            }

            if let changeID = line.changeID {
                dataAttrs += " data-change-id=\"\(changeID)\""
            }
            if let groupID = line.groupID {
                dataAttrs += " data-group-id=\"\(groupID)\""
                if let changeID = line.changeID,
                   let info = diffContext?.groupInfo(for: changeID) {
                    dataAttrs += " data-group-type=\"\(info.type.rawValue)\""
                }
            }
            if let groupIndex = line.groupIndex {
                dataAttrs += " data-group-index=\"\(groupIndex)\""
            }

            result += "<span class=\"\(classes)\"\(dataAttrs)>"
            result += line.highlightedHTML
            result += "\n</span>"
        }

        result += "</code></pre>\n"
    }

    /// Renders the inner HTML of a code block (`<code>` with optional
    /// language header and syntax highlighting). Shared by
    /// `visitCodeBlock` and `DeletionRenderer.render`.
    static func codeBlockInnerHTML(_ codeBlock: CodeBlock) -> String {
        let lang = codeBlock.language.flatMap { $0.isEmpty ? nil : $0 }
        var html = ""
        if let lang {
            let escaped = HTMLEscaping.escape(lang)
            html += "<div class=\"code-header\">"
            html += "<span class=\"code-language\">\(escaped)</span>"
            html += "</div>"
            html += "<code class=\"language-\(escaped)\">"
        } else {
            html += "<code>"
        }
        if let highlighted = CodeHighlighter.highlight(
            codeBlock.code, language: lang
        ) {
            html += highlighted
        } else {
            html += HTMLEscaping.escape(codeBlock.code)
        }
        html += "</code>"
        return html
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        let attrs = changeAttributes(for: html)
        if attrs != nil {
            result += "<div\(attrs!.asString)>"
            result += html.rawHTML
            result += "</div>\n"
        } else {
            result += html.rawHTML
        }
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        let attrs = changeAttributes(for: thematicBreak)
        if attrs != nil {
            result += "<div\(attrs!.asString)><hr /></div>\n"
        } else {
            result += "<hr />\n"
        }
    }

    // MARK: - Table

    mutating func visitTable(_ table: Table) {
        tableColumnAlignments = table.columnAlignments

        // Emit preceding deletions BEFORE opening <table> so they don't
        // become invalid children of the table element.  <tr> deletions
        // (from a fully-replaced table) are wrapped in their own table;
        // other block-level deletions are emitted directly.
        if let diffContext,
           let head = table.children.first(where: { $0 is Table.Head }) {
            let deletions = diffContext.precedingDeletions(before: head)
            if !deletions.isEmpty {
                var trDeletions: [RenderedDeletion] = []
                for del in deletions {
                    if del.tag == "tr" {
                        trDeletions.append(del)
                    } else {
                        emitDeletion(del)
                        consumedDeletionIDs.insert(del.changeID)
                    }
                }
                if !trDeletions.isEmpty {
                    result += "<table>\n<tbody>\n"
                    for del in trDeletions {
                        emitDeletion(del)
                        consumedDeletionIDs.insert(del.changeID)
                    }
                    result += "</tbody>\n</table>\n"
                }
            }
        }

        result += "<table>\n"
        descendInto(table)
        result += "</table>\n"
        tableColumnAlignments = []

        // Emit non-<tr> deletions that were deferred from inside
        // the table body (e.g. a paragraph deleted after a table
        // whose deletion is attached to the last body row).
        for del in deferredDeletions {
            emitDeletion(del)
        }
        deferredDeletions.removeAll()
    }

    mutating func visitTableHead(_ tableHead: Table.Head) {
        inTableHead = true
        currentCellColumn = 0
        let attrs = changeAttributes(for: tableHead)
        result += "<thead>\n<tr\(attrs?.asString ?? "")>\n"
        descendInto(tableHead)
        result += "</tr>\n</thead>\n"
        inTableHead = false
    }

    mutating func visitTableBody(_ tableBody: Table.Body) {
        guard tableBody.childCount > 0 else { return }
        result += "<tbody>\n"
        emitTableBodyDeletions(in: tableBody)
        result += "</tbody>\n"
    }

    mutating func visitTableRow(_ tableRow: Table.Row) {
        currentCellColumn = 0
        let attrs = changeAttributes(for: tableRow)
        result += "<tr\(attrs?.asString ?? "")>\n"
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
        result += "<s>"
        descendInto(strikethrough)
        result += "</s>"
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
        if wordSpans != nil {
            advanceWordSpans(charCount: text.string.count, emit: true)
            closeInlineTag()
        } else {
            result += HTMLEscaping.escape(
                EmojiShortcodes.replaceShortcodes(in: text.string)
            )
        }
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        if wordSpans != nil { closeInlineTag() }
        result += "<code>"
        if wordSpans != nil {
            advanceWordSpans(charCount: inlineCode.code.count, emit: true)
            closeInlineTag()
        } else {
            result += HTMLEscaping.escape(inlineCode.code)
        }
        result += "</code>"
    }

    mutating func visitInlineHTML(_ html: InlineHTML) {
        result += html.rawHTML
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        if wordSpans != nil {
            advanceWordSpans(charCount: 1, emit: false)
            closeInlineTag()
        }
        result += "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        if wordSpans != nil {
            advanceWordSpans(charCount: 1, emit: false)
            closeInlineTag()
        }
        result += "\n"
    }

    // MARK: - Change tracking helpers

    /// Attribute bundle for a changed element.
    struct ChangeAttrs {
        let classes: String   // "mud-change-ins" or "mud-change-del"
        let dataAttrs: String // ' data-change-id="..." data-group-id="..."'

        /// Full attribute string for interpolation into an opening tag.
        var asString: String {
            " class=\"\(classes)\"\(dataAttrs)"
        }

        static let empty = ChangeAttrs(classes: "", dataAttrs: "")
    }

    /// Returns change attributes for a block node, emitting preceding
    /// deletions as a side effect. Returns `nil` for unchanged nodes.
    private mutating func changeAttributes(for node: Markup) -> ChangeAttrs? {
        guard let diffContext else { return nil }

        // Emit preceding deletions as native elements.
        emitPrecedingDeletions(before: node)

        guard let annotation = diffContext.annotation(for: node),
              let changeID = diffContext.changeID(for: node) else {
            return nil
        }

        _ = annotation // always .inserted
        let info = diffContext.groupInfo(for: changeID)
        var dataAttrs = " data-change-id=\"\(changeID)\""
        if let info {
            dataAttrs += " data-group-id=\"\(info.groupID)\""
            dataAttrs += " data-group-type=\"\(info.type.rawValue)\""
            if info.groupPos == .first || info.groupPos == .sole {
                dataAttrs += " data-group-index=\"\(info.groupIndex)\""
            }
        }
        return ChangeAttrs(classes: "mud-change-ins", dataAttrs: dataAttrs)
    }

    /// Emits preceding deletions as native HTML elements.
    private mutating func emitPrecedingDeletions(before node: Markup) {
        guard let diffContext else { return }
        let deletions = diffContext.precedingDeletions(before: node)
            .filter { !consumedDeletionIDs.contains($0.changeID) }
        emitDeletionsWrappingTableRows(deletions)
    }

    /// Emits trailing deletions (after the last surviving block).
    mutating func emitTrailingDeletions() {
        guard let diffContext else { return }
        let deletions = diffContext.trailingDeletions()
            .filter { !consumedDeletionIDs.contains($0.changeID) }
        emitDeletionsWrappingTableRows(deletions)
    }

    /// Emits a list of deletions, wrapping any `<tr>` deletions in
    /// `<table><tbody>…</tbody></table>` so they produce valid HTML
    /// even when emitted outside a table context.
    private mutating func emitDeletionsWrappingTableRows(
        _ deletions: [RenderedDeletion]
    ) {
        var pendingTRs: [RenderedDeletion] = []
        for del in deletions {
            if del.tag == "tr" {
                pendingTRs.append(del)
            } else {
                flushPendingTRs(&pendingTRs)
                emitDeletion(del)
            }
        }
        flushPendingTRs(&pendingTRs)
    }

    /// Flushes accumulated `<tr>` deletions wrapped in a table.
    private mutating func flushPendingTRs(
        _ pending: inout [RenderedDeletion]
    ) {
        guard !pending.isEmpty else { return }
        result += "<table>\n<tbody>\n"
        for del in pending {
            emitDeletion(del)
        }
        result += "</tbody>\n</table>\n"
        pending.removeAll()
    }

    /// Emits a single deletion as a native HTML element with change
    /// attributes.
    private mutating func emitDeletion(_ del: RenderedDeletion) {
        let info = diffContext?.groupInfo(for: del.changeID)
        var classes = "mud-change-del"
        if let extra = del.extraClasses {
            classes = "\(extra) \(classes)"
        }
        var attrs = " class=\"\(classes)\" data-change-id=\"\(del.changeID)\""
        if let info {
            attrs += " data-group-id=\"\(info.groupID)\""
            attrs += " data-group-type=\"\(info.type.rawValue)\""
            if info.groupPos == .first || info.groupPos == .sole {
                attrs += " data-group-index=\"\(info.groupIndex)\""
            }
        }
        if del.tag == "hr" {
            result += "<hr\(attrs) />\n"
        } else {
            result += "<\(del.tag)\(attrs)>\(del.html)</\(del.tag)>\n"
        }
    }

    /// Walks the table body's rows, emitting preceding deleted rows
    /// as `<tr>` siblings inside `<tbody>`.  Non-`<tr>` deletions
    /// (e.g. a paragraph that followed the old table) are deferred
    /// to `deferredDeletions` so they emit after `</table>`.
    ///
    /// After all surviving rows, reclaims any `<tr>` deletions that
    /// follow the last row (these would otherwise be emitted outside
    /// the table as preceding deletions of the next block, or as
    /// trailing deletions).
    private mutating func emitTableBodyDeletions(in tableBody: Table.Body) {
        guard let diffContext else {
            descendInto(tableBody)
            return
        }
        var lastRow: Table.Row?
        for child in tableBody.children {
            guard let row = child as? Table.Row else {
                visit(child)
                continue
            }
            for del in diffContext.precedingDeletions(before: row) {
                if del.tag == "tr" {
                    emitDeletion(del)
                } else {
                    deferredDeletions.append(del)
                }
                consumedDeletionIDs.insert(del.changeID)
            }
            visitTableRow(row)
            lastRow = row
        }

        // Reclaim <tr> deletions that follow the last surviving row.
        if let lastRow {
            for del in diffContext.followingDeletions(after: lastRow) {
                if del.tag == "tr" {
                    emitDeletion(del)
                    consumedDeletionIDs.insert(del.changeID)
                }
            }
        }
    }

    // MARK: - Alerts

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

    /// Emits the opening `<blockquote>` tag with alert CSS classes
    /// and optional change attributes.
    private mutating func emitAlertOpen(
        _ category: AlertCategory, attrs: ChangeAttrs = .empty
    ) {
        if attrs.classes.isEmpty {
            result += "<blockquote class=\"alert \(category.cssClass)\">\n"
        } else {
            result += "<blockquote class=\"alert \(category.cssClass)"
            result += " \(attrs.classes)\"\(attrs.dataAttrs)>\n"
        }
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

    /// Concatenated plain text of an array of inline markup nodes,
    /// used for the length check before inlining same-line content.
    private static func plainTextOf(_ nodes: [any Markup]) -> String {
        nodes.map { node -> String in
            if let t = node as? Text { return t.string }
            if let c = node as? InlineCode { return c.code }
            return plainTextOf(Array(node.children))
        }.joined()
    }

    /// Returns true if same-line content qualifies to be bolded in an aside
    /// title: non-empty and under 60 characters.
    private static func shouldInlineSameLine(_ plainText: String) -> Bool {
        return !plainText.isEmpty && plainText.count < 60
    }

    /// Emits the title and body content for a DocC aside. When the
    /// same-line content (before the first SoftBreak) is under 60
    /// characters, it is bolded on the title line; otherwise all
    /// content blocks are rendered roman in separate paragraphs.
    private mutating func emitDocCAlertTitleAndContent(
        _ category: AlertCategory,
        _ title: String,
        _ content: [BlockMarkup]
    ) {
        var sameLine: [any Markup] = []
        var restInlines: [any Markup] = []

        if let firstPara = content.first as? Paragraph {
            let inlines = Array(firstPara.children)
            if let sbIdx = inlines.firstIndex(where: { $0 is SoftBreak }) {
                sameLine = Array(inlines[..<sbIdx])
                restInlines = Array(inlines[(sbIdx + 1)...])
            } else {
                sameLine = inlines
            }
        }

        let shouldInline = Self.shouldInlineSameLine(Self.plainTextOf(sameLine))

        result += "<p class=\"alert-title\">"
        result += category.icon
        result += HTMLEscaping.escape(title)
        if shouldInline {
            result += ": <strong>"
            for node in sameLine { visit(node) }
            result += "</strong>"
        }
        result += "</p>\n"

        if shouldInline {
            emitAlertBody(restInlines: restInlines, remainingBlocks: Array(content.dropFirst()))
        } else {
            for block in content { visit(block) }
        }
    }

    /// Emits the roman body of an aside: restInlines (if any) in a `<p>`,
    /// then each remaining block visited normally.
    private mutating func emitAlertBody(
        restInlines: [any Markup],
        remainingBlocks: [any Markup]
    ) {
        if !restInlines.isEmpty {
            result += "<p>"
            for node in restInlines { visit(node) }
            result += "</p>\n"
        }
        for block in remainingBlocks { visit(block) }
    }

    // MARK: - Word-level diff rendering

    /// Role determines how word spans are emitted.
    enum WordSpanRole {
        /// Blue block (paired insertion): unchanged as-is, inserted in
        /// `<ins>`, deleted in `<del>`.
        case insertion
        /// Red block (paired deletion): unchanged as-is, deleted in
        /// `<del>`, inserted spans are skipped.
        case deletion
    }

    /// Active word spans for the current block, or `nil`.
    private var wordSpans: [WordSpan]?
    private var wordSpanCursor = 0
    private var wordSpanRole: WordSpanRole = .insertion

    /// Currently open inline tag (`<del>` or `<ins>`). Consecutive
    /// spans of the same type share a single tag, producing cleaner
    /// HTML (e.g., `<del>quick brown</del>` instead of
    /// `<del>quick</del><del> </del><del>brown</del>`).
    private var openInlineTag: InlineTag?

    private enum InlineTag {
        case del, ins

        var open: String {
            switch self {
            case .del: return "<del>"
            case .ins: return "<ins>"
            }
        }

        var close: String {
            switch self {
            case .del: return "</del>"
            case .ins: return "</ins>"
            }
        }
    }

    /// Activates word spans for a DocC aside's inner paragraph,
    /// advancing the cursor past the tag prefix that the Aside parser
    /// strips (e.g. "Status: ") so spans align with the rendered
    /// content.
    private mutating func activateAlertWordSpans(
        for paragraph: Markup?, content: [BlockMarkup]
    ) {
        guard let para = paragraph else { return }
        activateWordSpans(for: para)
        guard wordSpans != nil else { return }
        skipAlertPrefix(originalParagraph: para, content: content)
    }

    /// Computes and silently skips the tag prefix that the Aside
    /// parser strips, leaving the cursor aligned with the content.
    private mutating func skipAlertPrefix(
        originalParagraph: Markup, content: [BlockMarkup]
    ) {
        let fullLen = WordDiff.inlineText(of: originalParagraph).count
        let contentLen: Int
        if let first = content.first {
            contentLen = WordDiff.inlineText(of: first).count
        } else {
            contentLen = 0
        }
        let prefixLen = fullLen - contentLen
        if prefixLen > 0 {
            advancePrefixSpans(charCount: prefixLen)
        }
    }

    /// Advances the cursor past `charCount` consuming characters
    /// without emitting anything. Non-consuming spans within the
    /// prefix are silently skipped. Used to skip the tag prefix in
    /// aside rendering so non-consuming spans (deleted/inserted
    /// words) don't appear before the alert title.
    private mutating func advancePrefixSpans(charCount: Int) {
        guard wordSpans != nil else { return }
        var remaining = charCount
        while wordSpanCursor < wordSpans!.count && remaining > 0 {
            let span = wordSpans![wordSpanCursor]

            // Non-consuming spans in the prefix: skip silently.
            switch (span, wordSpanRole) {
            case (.deleted, .insertion), (.inserted, .deletion):
                wordSpanCursor += 1
                continue
            default:
                break
            }

            let text = span.text
            if text.count <= remaining {
                wordSpanCursor += 1
                remaining -= text.count
            } else {
                wordSpans![wordSpanCursor] = span.withText(
                    String(text.dropFirst(remaining)))
                remaining = 0
            }
        }
    }

    /// Activates word-span rendering if the block has word spans.
    private mutating func activateWordSpans(for node: Markup) {
        if let spans = diffContext?.wordSpans(for: node), !spans.isEmpty {
            wordSpans = spans
            wordSpanCursor = 0
            wordSpanRole = .insertion
        }
    }

    /// Flushes trailing non-consuming spans and clears word-span state.
    private mutating func deactivateWordSpans() {
        guard wordSpans != nil else { return }
        flushNonConsumingWordSpans()
        closeInlineTag()
        wordSpans = nil
    }

    /// Advances the word span cursor by `charCount` characters.
    ///
    /// When `emit` is true (used by `visitText` and `visitInlineCode`),
    /// consuming spans are rendered to the output. When false (used by
    /// `visitSoftBreak` and `visitLineBreak`), characters are consumed
    /// silently — the break's own HTML handles the visual whitespace.
    ///
    /// Non-consuming spans (deleted in blue mode, inserted in red mode)
    /// are always handled eagerly: emitted or skipped.
    /// If a consuming span is larger than the remaining character count,
    /// it is split and the remainder stays at the cursor.
    private mutating func advanceWordSpans(
        charCount: Int, emit: Bool
    ) {
        guard wordSpans != nil else { return }
        var remaining = charCount

        while wordSpanCursor < wordSpans!.count {
            let span = wordSpans![wordSpanCursor]

            // Non-consuming: deleted in blue, inserted in red.
            switch (span, wordSpanRole) {
            case (.deleted(let text), .insertion):
                if showInlineDeletions {
                    setInlineTag(.del)
                    result += escapeSpanText(text)
                }
                wordSpanCursor += 1
                continue
            case (.inserted, .deletion):
                wordSpanCursor += 1
                continue
            default:
                break
            }

            guard remaining > 0 else { return }

            let text = span.text
            if text.count <= remaining {
                if emit { emitSpan(span) }
                wordSpanCursor += 1
                remaining -= text.count
            } else {
                let consumed = String(text.prefix(remaining))
                let rest = String(text.dropFirst(remaining))
                if emit { emitSpan(span.withText(consumed)) }
                wordSpans![wordSpanCursor] = span.withText(rest)
                return
            }
        }
    }

    /// Emits any remaining non-consuming spans after the last text node.
    private mutating func flushNonConsumingWordSpans() {
        guard let spans = wordSpans else { return }
        while wordSpanCursor < spans.count {
            switch (spans[wordSpanCursor], wordSpanRole) {
            case (.deleted(let text), .insertion):
                if showInlineDeletions {
                    setInlineTag(.del)
                    result += escapeSpanText(text)
                }
                wordSpanCursor += 1
            case (.inserted, .deletion):
                wordSpanCursor += 1
            default:
                return
            }
        }
    }

    /// Sets the currently open inline tag, closing the previous one
    /// if needed. Consecutive same-type spans share a single tag.
    private mutating func setInlineTag(_ tag: InlineTag?) {
        guard tag != openInlineTag else { return }
        closeInlineTag()
        if let tag {
            result += tag.open
            openInlineTag = tag
        }
    }

    private mutating func closeInlineTag() {
        if let tag = openInlineTag {
            result += tag.close
            openInlineTag = nil
        }
    }

    private mutating func emitSpan(_ span: WordSpan) {
        switch span {
        case .unchanged: setInlineTag(nil)
        case .inserted:  setInlineTag(.ins)
        case .deleted:   setInlineTag(.del)
        }
        result += escapeSpanText(span.text)
    }

    private func escapeSpanText(_ text: String) -> String {
        HTMLEscaping.escape(EmojiShortcodes.replaceShortcodes(in: text))
    }

    /// Renders the inner HTML of a blockquote alert for deletion
    /// rendering. Returns the inner HTML and alert category, or nil
    /// if the blockquote is not a recognized alert. When `wordSpans`
    /// is provided, renders with word-level `<del>` markers.
    static func renderAlertInnerHTML(
        _ blockQuote: BlockQuote,
        wordSpans: [WordSpan]? = nil
    ) -> (html: String, category: AlertCategory)? {
        let detector = AlertDetector()

        if let (category, title) = detector.detectGFMAlert(blockQuote) {
            var visitor = UpHTMLVisitor()
            visitor.emitAlertTitle(category, title)
            visitor.emitGFMAlertContent(blockQuote, category: category)
            return (visitor.result, category)
        }

        if let (category, title, content) =
            detector.detectDocCAlert(blockQuote) {
            var visitor = UpHTMLVisitor()
            if let spans = wordSpans, !spans.isEmpty,
               let para = blockQuote.children
                   .first(where: { $0 is Paragraph }) {
                visitor.wordSpans = spans
                visitor.wordSpanCursor = 0
                visitor.wordSpanRole = .deletion
                visitor.skipAlertPrefix(
                    originalParagraph: para, content: content)
            }
            visitor.emitDocCAlertTitleAndContent(category, title, content)
            visitor.deactivateWordSpans()
            return (visitor.result, category)
        }

        return nil
    }

    /// Renders a markup node's inner HTML using word spans.
    ///
    /// Used by `DiffContext` to render deletion HTML with word-level
    /// `<del>` markers for the red block.
    static func renderWithWordSpans(
        _ markup: Markup, spans: [WordSpan], role: WordSpanRole
    ) -> String {
        var visitor = UpHTMLVisitor()
        visitor.wordSpans = spans
        visitor.wordSpanCursor = 0
        visitor.wordSpanRole = role
        for child in markup.children { visitor.visit(child) }
        visitor.deactivateWordSpans()
        return visitor.result
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

// MARK: - Body rendering entry point

extension UpHTMLVisitor {
    /// The visitor + frontmatter-prefix core shared by Up-mode body rendering,
    /// footnote-body rendering, and comment-body rendering. Configures a
    /// visitor from `options` (including the diff context when a waypoint is
    /// set), walks the document, and prefixes the rendered frontmatter block
    /// when the source has frontmatter.
    static func renderBody(
        _ parsed: ParsedMarkdown,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        var upVisitor = UpHTMLVisitor()
        upVisitor.baseURL = options.baseURL
        upVisitor.resolveImageSource = resolveImageSource
        upVisitor.alertDetector.docCAlertMode = options.docCAlertMode
        upVisitor.showInlineDeletions = options.showInlineDeletions
        if let waypoint = options.waypoint {
            upVisitor.diffContext = DiffContext(
                old: waypoint, new: parsed,
                wordDiffThreshold: options.wordDiffThreshold)
        }
        upVisitor.visit(parsed.document)
        upVisitor.emitTrailingDeletions()

        if let yaml = parsed.frontMatter {
            return FrontMatterHTMLRenderer.upModeHTML(yaml) + upVisitor.result
        }
        return upVisitor.result
    }
}
