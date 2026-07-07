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
    var diffContext: DiffContext? {
        didSet {
            deletionPlacer = diffContext.map { DeletionPlacer(diffContext: $0) }
        }
    }

    /// Renders deletions into the output stream and owns their
    /// exactly-once bookkeeping. Created alongside `diffContext`.
    private var deletionPlacer: DeletionPlacer?

    /// When false, non-consuming `<del>` spans in paired insertion
    /// blocks are silently skipped instead of emitted inline.
    var showInlineDeletions = false

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
        if deletionPlacer != nil,
           let firstChild = listItem.children.first(where: { _ in true }) {
            result += deletionPlacer!.listItemHTML(before: firstChild)
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
        if spanEmitter == nil, let listItem = paragraph.parent as? ListItem {
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
        // become invalid children of the table element.
        if deletionPlacer != nil,
           let head = table.children.first(where: { $0 is Table.Head }) {
            result += deletionPlacer!.hoistedHTML(beforeHead: head)
        }

        result += "<table>\n"
        descendInto(table)
        result += "</table>\n"
        tableColumnAlignments = []

        // Emit non-<tr> deletions that were deferred from inside
        // the table body.
        if deletionPlacer != nil {
            result += deletionPlacer!.deferredHTML()
        }
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
        if spanEmitter != nil {
            result += spanEmitter!.advance(by: text.string.count, emit: true)
            result += spanEmitter!.closeOpenTag()
        } else {
            result += HTMLEscaping.escape(
                EmojiShortcodes.replaceShortcodes(in: text.string)
            )
        }
    }

    mutating func visitInlineCode(_ inlineCode: InlineCode) {
        if spanEmitter != nil { result += spanEmitter!.closeOpenTag() }
        result += "<code>"
        if spanEmitter != nil {
            result += spanEmitter!.advance(
                by: inlineCode.code.count, emit: true)
            result += spanEmitter!.closeOpenTag()
        } else {
            result += HTMLEscaping.escape(inlineCode.code)
        }
        result += "</code>"
    }

    mutating func visitInlineHTML(_ html: InlineHTML) {
        result += html.rawHTML
    }

    mutating func visitLineBreak(_ lineBreak: LineBreak) {
        if spanEmitter != nil {
            result += spanEmitter!.advance(by: 1, emit: false)
            result += spanEmitter!.closeOpenTag()
        }
        result += "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: SoftBreak) {
        if spanEmitter != nil {
            result += spanEmitter!.advance(by: 1, emit: false)
            result += spanEmitter!.closeOpenTag()
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
        if let placer = deletionPlacer {
            result += placer.precedingHTML(before: node)
        }

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

    /// Emits trailing deletions (after the last surviving block).
    mutating func emitTrailingDeletions() {
        guard let placer = deletionPlacer else { return }
        result += placer.trailingHTML()
    }

    /// Walks the table body's rows, emitting preceding deleted rows
    /// as `<tr>` siblings inside `<tbody>`. Non-`<tr>` deletions are
    /// deferred by the placer so they emit after `</table>`.
    ///
    /// After all surviving rows, reclaims any `<tr>` deletions that
    /// follow the last row.
    private mutating func emitTableBodyDeletions(in tableBody: Table.Body) {
        guard deletionPlacer != nil else {
            descendInto(tableBody)
            return
        }
        var lastRow: Table.Row?
        for child in tableBody.children {
            guard let row = child as? Table.Row else {
                visit(child)
                continue
            }
            result += deletionPlacer!.rowHTML(before: row)
            visitTableRow(row)
            lastRow = row
        }

        // Reclaim <tr> deletions that follow the last surviving row.
        if let lastRow {
            result += deletionPlacer!.reclaimedRowHTML(after: lastRow)
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

    /// Active word-span emitter for the current block, or `nil`. The
    /// visitor owns block structure (which nodes have spans, when a
    /// block starts and ends); the cursor machine lives in
    /// `WordSpanEmitter`.
    private var spanEmitter: WordSpanEmitter?

    /// Activates word spans for a DocC aside's inner paragraph,
    /// advancing the cursor past the tag prefix that the Aside parser
    /// strips (e.g. "Status: ") so spans align with the rendered
    /// content.
    private mutating func activateAlertWordSpans(
        for paragraph: Markup?, content: [BlockMarkup]
    ) {
        guard let para = paragraph else { return }
        activateWordSpans(for: para)
        guard spanEmitter != nil else { return }
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
            spanEmitter?.skipPrefix(charCount: prefixLen)
        }
    }

    /// Activates word-span rendering if the block has word spans.
    private mutating func activateWordSpans(for node: Markup) {
        if let spans = diffContext?.wordSpans(for: node), !spans.isEmpty {
            spanEmitter = WordSpanEmitter(
                spans: spans, role: .insertion,
                showInlineDeletions: showInlineDeletions)
        }
    }

    /// Flushes trailing non-consuming spans and clears the emitter.
    private mutating func deactivateWordSpans() {
        guard spanEmitter != nil else { return }
        result += spanEmitter!.finish()
        spanEmitter = nil
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
                visitor.spanEmitter = WordSpanEmitter(
                    spans: spans, role: .deletion,
                    showInlineDeletions: false)
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
        _ markup: Markup, spans: [WordSpan], role: WordSpanEmitter.Role
    ) -> String {
        var visitor = UpHTMLVisitor()
        visitor.spanEmitter = WordSpanEmitter(
            spans: spans, role: role, showInlineDeletions: false)
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
