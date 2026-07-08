import Foundation

/// AST → web HTML visitor over the single cmark parse — the Stage 3 port of
/// ``UpHTMLVisitor`` (Doc/Plans/2026-07-single-parser-rendering.md). Walks a
/// ``CMarkDocument`` whose parse is footnote-aware, so `[^label]` references
/// arrive as AST nodes: ``visitFootnoteReference(_:)`` emits the same marker
/// HTML the legacy pipeline bakes into the source, and the numbering logic
/// (first-reference order over authorial references only, occurrence-suffixed
/// back-link ids) moves from `FootnoteProcessor.process`'s rewrite pass into
/// the render.
///
/// **Parallel and unwired.** The legacy `UpHTMLVisitor` remains the production
/// renderer; `UpRenderingParityTests` holds this visitor byte-identical to it
/// over the parity corpus, and that harness gates the eventual cutover.
/// Change tracking (change attributes, deletion placement, word spans,
/// code-block diffs) is deliberately absent: `DiffContext` keys on
/// swift-markdown nodes over the footnote-transformed source, so the diff
/// features port together with the diff layer in Stage 4.
struct CMarkUpHTMLVisitor: CMarkWalker {
    var result = ""

    /// Base URL of the document being rendered (typically its file URL).
    var baseURL: URL?

    /// Optional transform applied to each image `src` during rendering.
    /// Called with the original source string and the document base URL.
    /// Return a replacement URL string, or `nil` to keep the original.
    var resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?

    // Heading slug deduplication.
    private var slugTracker = SlugGenerator.Tracker()

    // List tightness state (saved/restored for nesting). Read straight off
    // the parser (`listIsTight`) — this replaces the legacy visitor's
    // `isLooseList` range arithmetic.
    private var inTightList = false

    // Table rendering state.
    private var tableAlignments: [CMarkTableAlignment] = []
    private var currentCellColumn = 0
    private var inTableHead = false

    var alertDetector = AlertDetector()

    // Footnote numbering state, moved here from `FootnoteProcessor.process`'s
    // rewrite pass: numbers are assigned in first-reference order over
    // authorial references only, so comments occupy no number and leave no
    // gap; the per-label occurrence index drives back-link ids (fnref-N-K).
    private var authorialNumber: [String: Int] = [:]
    private var nextFootnoteNumber = 1
    private var occurrence: [String: Int] = [:]

    // MARK: - Block containers

    mutating func visitBlockQuote(_ blockQuote: CMarkNode) {
        if let (category, title) = alertDetector.detectGFMAlert(blockQuote) {
            emitAlertOpen(category)
            emitAlertTitle(category, title)
            emitGFMAlertContent(blockQuote, category: category)
            result += "</blockquote>\n"
        } else if let alert = alertDetector.detectDocCAlert(blockQuote) {
            emitAlertOpen(alert.category)
            emitDocCAlertTitleAndContent(
                alert.category, alert.title,
                blockQuote: blockQuote, tagByteLength: alert.tagByteLength)
            result += "</blockquote>\n"
        } else {
            result += "<blockquote>\n"
            descendInto(blockQuote)
            result += "</blockquote>\n"
        }
    }

    mutating func visitOrderedList(_ orderedList: CMarkNode) {
        let prev = inTightList
        inTightList = orderedList.listIsTight
        if orderedList.listStart != 1 {
            result += "<ol start=\"\(orderedList.listStart)\">\n"
        } else {
            result += "<ol>\n"
        }
        descendInto(orderedList)
        result += "</ol>\n"
        inTightList = prev
    }

    mutating func visitUnorderedList(_ unorderedList: CMarkNode) {
        let prev = inTightList
        inTightList = unorderedList.listIsTight
        result += "<ul>\n"
        descendInto(unorderedList)
        result += "</ul>\n"
        inTightList = prev
    }

    /// Also handles `.taskListItem` via the walker's default fallback.
    mutating func visitListItem(_ listItem: CMarkNode) {
        if inTightList {
            result += "<li>"
        } else {
            result += "<li>\n"
        }
        if listItem.kind == .taskListItem {
            result += "<input type=\"checkbox\" disabled=\"\""
            if listItem.taskListItemIsChecked {
                result += " checked=\"\""
            }
            result += " /> "
        }
        descendInto(listItem)
        result += "</li>\n"
    }

    // MARK: - Block leaves

    mutating func visitHeading(_ heading: CMarkNode) {
        let level = heading.headingLevel
        let slug = slugTracker.slug(for: heading.plainText)
        result += "<h\(level) id=\"\(slug)\">"
        descendInto(heading)
        result += "</h\(level)>\n"
    }

    mutating func visitParagraph(_ paragraph: CMarkNode) {
        let parentKind = paragraph.parent?.kind
        let inListItem = parentKind == .listItem || parentKind == .taskListItem
        if inTightList && inListItem {
            descendInto(paragraph)
            result += "\n"
        } else {
            result += "<p>"
            descendInto(paragraph)
            result += "</p>\n"
        }
    }

    mutating func visitCodeBlock(_ codeBlock: CMarkNode) {
        result += "<pre class=\"mud-code\">"
        result += Self.codeBlockInnerHTML(codeBlock)
        result += "</pre>\n"
    }

    /// Renders the inner HTML of a code block (`<code>` with optional
    /// language header and syntax highlighting) — the counterpart of
    /// `UpHTMLVisitor.codeBlockInnerHTML`.
    static func codeBlockInnerHTML(_ codeBlock: CMarkNode) -> String {
        let lang = codeBlock.fenceInfo.flatMap { $0.isEmpty ? nil : $0 }
        let code = codeBlock.literal ?? ""
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
        if let highlighted = CodeHighlighter.highlight(code, language: lang) {
            html += highlighted
        } else {
            html += HTMLEscaping.escape(code)
        }
        html += "</code>"
        return html
    }

    mutating func visitHTMLBlock(_ html: CMarkNode) {
        result += html.literal ?? ""
    }

    mutating func visitThematicBreak(_ thematicBreak: CMarkNode) {
        result += "<hr />\n"
    }

    // MARK: - Footnotes and comments

    /// Definitions render nothing in the body: the legacy pipeline deletes
    /// them from the source before its render parse; here they are skipped
    /// structurally (their references never enter the numbering either).
    /// Their bodies feed the bottom sections via `FootnoteProcessor`, not
    /// this walk.
    mutating func visitFootnoteDefinition(_ node: CMarkNode) {}

    mutating func visitFootnoteReference(_ node: CMarkNode) {
        // cmark keeps the label on the resolved definition and stores its own
        // per-reference number as the literal. A reference always resolves —
        // cmark drops unmatched `[^label]` back to literal text — so the
        // guards below mirror the legacy rewrite pass's defenses exactly:
        // an integer number literal and a sourcepos that verifiably delimits
        // `[^…]`. The legacy pass leaves a failing reference's raw text in
        // the source; emit the equivalent text here. (The definition's label
        // spelling stands in for the reference's raw bytes, which a broken
        // sourcepos can no longer locate.)
        guard let label = node.parentFootnoteDefinition?.literal else { return }
        guard let literal = node.literal, Int(literal) != nil,
              node.verifiedRange != nil else {
            emitTextRun("[^\(label)]")
            return
        }
        if FootnoteProcessor.isCommentLabel(label) {
            result += FootnoteProcessor.commentMarkerHTML(label: label)
        } else {
            let number = authorialNumber[label] ?? nextFootnoteNumber
            if authorialNumber[label] == nil {
                authorialNumber[label] = number
                nextFootnoteNumber += 1
            }
            let k = (occurrence[label] ?? 0) + 1
            occurrence[label] = k
            result += FootnoteProcessor.markerHTML(
                number: number, label: label, occurrence: k)
        }
    }

    // MARK: - Table

    mutating func visitTable(_ table: CMarkNode) {
        tableAlignments = table.tableAlignments
        result += "<table>\n"
        // cmark has no table-body node: the first child row is the header,
        // the rest are body rows (the legacy pipeline's Table.Head /
        // Table.Body structure, flattened).
        let rows = Array(table.children)
        if let head = rows.first {
            visit(head)
        }
        let bodyRows = rows.dropFirst()
        if !bodyRows.isEmpty {
            result += "<tbody>\n"
            for row in bodyRows { visit(row) }
            result += "</tbody>\n"
        }
        result += "</table>\n"
        tableAlignments = []
    }

    mutating func visitTableHead(_ tableHead: CMarkNode) {
        inTableHead = true
        currentCellColumn = 0
        result += "<thead>\n<tr>\n"
        descendInto(tableHead)
        result += "</tr>\n</thead>\n"
        inTableHead = false
    }

    mutating func visitTableRow(_ tableRow: CMarkNode) {
        currentCellColumn = 0
        result += "<tr>\n"
        descendInto(tableRow)
        result += "</tr>\n"
    }

    mutating func visitTableCell(_ tableCell: CMarkNode) {
        let tag = inTableHead ? "th" : "td"
        let alignment = currentCellColumn < tableAlignments.count
            ? tableAlignments[currentCellColumn]
            : .none
        switch alignment {
        case .none:   result += "<\(tag)>"
        case .left:   result += "<\(tag) align=\"left\">"
        case .center: result += "<\(tag) align=\"center\">"
        case .right:  result += "<\(tag) align=\"right\">"
        }
        descendInto(tableCell)
        result += "</\(tag)>\n"
        currentCellColumn += 1
    }

    // MARK: - Inline containers

    mutating func visitEmphasis(_ emphasis: CMarkNode) {
        result += "<em>"
        descendInto(emphasis)
        result += "</em>"
    }

    mutating func visitStrong(_ strong: CMarkNode) {
        result += "<strong>"
        descendInto(strong)
        result += "</strong>"
    }

    mutating func visitStrikethrough(_ strikethrough: CMarkNode) {
        result += "<s>"
        descendInto(strikethrough)
        result += "</s>"
    }

    mutating func visitLink(_ link: CMarkNode) {
        result += "<a href=\"\(HTMLEscaping.escape(link.url ?? ""))\""
        if let title = link.title, !title.isEmpty {
            result += " title=\"\(HTMLEscaping.escape(title))\""
        }
        result += ">"
        descendInto(link)
        result += "</a>"
    }

    mutating func visitImage(_ image: CMarkNode) {
        var src = image.url ?? ""
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

    mutating func visitText(_ text: CMarkNode) {
        emitTextRun(text.literal ?? "")
    }

    /// Emits a text run exactly as `visitText` does — shared with the DocC
    /// aside path and the footnote fallback, which emit text that no longer
    /// matches any node's literal.
    private mutating func emitTextRun(_ string: String) {
        result += HTMLEscaping.escape(
            EmojiShortcodes.replaceShortcodes(in: string)
        )
    }

    mutating func visitInlineCode(_ inlineCode: CMarkNode) {
        result += "<code>"
        result += HTMLEscaping.escape(inlineCode.literal ?? "")
        result += "</code>"
    }

    mutating func visitInlineHTML(_ html: CMarkNode) {
        result += html.literal ?? ""
    }

    mutating func visitLineBreak(_ lineBreak: CMarkNode) {
        result += "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: CMarkNode) {
        result += "\n"
    }

    // MARK: - Alerts

    /// Emits the content of a GFM alert, stripping the `[!TYPE]` tag
    /// from the first paragraph. Walks the first paragraph's inline
    /// children directly: skips the tag text node (emitting any
    /// trailing content on the same line), skips a following soft break,
    /// then visits remaining inlines and subsequent block children.
    private mutating func emitGFMAlertContent(
        _ blockQuote: CMarkNode, category: AlertCategory
    ) {
        let tag = "[!\(category.rawValue.uppercased())]"
        let children = Array(blockQuote.children)
        guard let firstPara = children.first, firstPara.kind == .paragraph
        else { return }

        let inlines = Array(firstPara.children)
        var index = 0
        var opened = false

        // Strip the [!TYPE] tag from the first text node. The legacy visitor
        // escapes the remainder without emoji replacement; match it.
        if let tagNode = inlines.first, tagNode.kind == .text {
            index = 1
            let literal = tagNode.literal ?? ""
            let after = String(
                literal.dropFirst(tag.count)
                    .drop(while: { $0 == " " })
            )
            if !after.isEmpty {
                opened = true
                result += "<p>"
                result += HTMLEscaping.escape(after)
            }
            // Skip the soft break that separates the tag line from content.
            if index < inlines.count && inlines[index].kind == .softBreak {
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

    /// Concatenated plain text of an array of inline nodes, used for the
    /// length check before inlining same-line content. Matches the legacy
    /// visitor's `plainTextOf`: inline code contributes its bare literal
    /// (no backticks), unlike `CMarkNode.plainText`.
    private static func plainTextOf(_ nodes: [CMarkNode]) -> String {
        nodes.map { node -> String in
            switch node.kind {
            case .text, .inlineCode: return node.literal ?? ""
            default: return plainTextOf(Array(node.children))
            }
        }.joined()
    }

    /// Returns true if same-line content qualifies to be bolded in an aside
    /// title: non-empty and under 60 characters.
    private static func shouldInlineSameLine(_ plainText: String) -> Bool {
        return !plainText.isEmpty && plainText.count < 60
    }

    /// Emits the title and body content for a DocC aside. Where the legacy
    /// path works on `Aside`'s rebuilt content blocks, this port works on the
    /// original blockquote plus the detector's `tagByteLength`: the first
    /// text node's literal minus that prefix is the tag-stripped text the
    /// rebuilt tree would have carried. When the same-line content (before
    /// the first soft break) is under 60 characters, it is bolded on the
    /// title line; otherwise all content renders roman in separate
    /// paragraphs.
    private mutating func emitDocCAlertTitleAndContent(
        _ category: AlertCategory,
        _ title: String,
        blockQuote: CMarkNode,
        tagByteLength: Int
    ) {
        let children = Array(blockQuote.children)
        // Detection guarantees a first paragraph whose first child is the
        // tag text node; render plain content defensively otherwise.
        guard let firstPara = children.first, firstPara.kind == .paragraph,
              let tagNode = firstPara.firstChild, tagNode.kind == .text,
              let tagLiteral = tagNode.literal else {
            result += "<p class=\"alert-title\">"
            result += category.icon
            result += HTMLEscaping.escape(title)
            result += "</p>\n"
            for child in children { visit(child) }
            return
        }

        // The tag prefix is ASCII (`Kind:` plus spaces/tabs), so the UTF-8
        // offset lands on a character boundary.
        let utf8 = tagLiteral.utf8
        let strippedStart = utf8.index(
            utf8.startIndex, offsetBy: min(tagByteLength, utf8.count))
        let strippedFirst = String(tagLiteral[strippedStart...])

        // Split the first paragraph's remaining inlines at the first soft
        // break, as the legacy visitor does.
        var sameLineNodes: [CMarkNode] = []
        var restInlines: [CMarkNode] = []
        let tail = Array(firstPara.children.dropFirst())
        if let sbIdx = tail.firstIndex(where: { $0.kind == .softBreak }) {
            sameLineNodes = Array(tail[..<sbIdx])
            restInlines = Array(tail[(sbIdx + 1)...])
        } else {
            sameLineNodes = tail
        }

        let sameLinePlain = strippedFirst + Self.plainTextOf(sameLineNodes)
        let shouldInline = Self.shouldInlineSameLine(sameLinePlain)

        result += "<p class=\"alert-title\">"
        result += category.icon
        result += HTMLEscaping.escape(title)
        if shouldInline {
            result += ": <strong>"
            emitTextRun(strippedFirst)
            for node in sameLineNodes { visit(node) }
            result += "</strong>"
        }
        result += "</p>\n"

        if shouldInline {
            // The rest of the first paragraph (after the soft break) in its
            // own <p>, then the remaining blocks.
            if !restInlines.isEmpty {
                result += "<p>"
                for node in restInlines { visit(node) }
                result += "</p>\n"
            }
        } else {
            // The whole first paragraph, tag-stripped, rendered roman.
            result += "<p>"
            emitTextRun(strippedFirst)
            for node in firstPara.children.dropFirst() { visit(node) }
            result += "</p>\n"
        }
        for child in children.dropFirst() { visit(child) }
    }
}

// MARK: - Body rendering entry point

extension CMarkUpHTMLVisitor {
    /// The cmark-pipeline counterpart of `UpHTMLVisitor.renderBody`: CRLF
    /// normalization and frontmatter extraction (matching `ParsedMarkdown`),
    /// one footnote-aware parse of the body, the visitor walk, and the
    /// rendered-frontmatter prefix. No footnote preprocessing happens — that
    /// is the point of the port. `options.waypoint` is ignored: change
    /// tracking ports with the diff layer in Stage 4.
    static func renderBody(
        _ source: String,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let yaml: String?
        let body: String
        if let fm = FrontMatterExtractor.extract(from: normalized) {
            yaml = fm.yaml
            body = fm.body
        } else {
            yaml = nil
            body = normalized
        }

        let prefix = yaml.map(FrontMatterHTMLRenderer.upModeHTML) ?? ""
        guard let document = CMarkDocument(parsing: body) else {
            return prefix
        }
        var visitor = CMarkUpHTMLVisitor()
        visitor.baseURL = options.baseURL
        visitor.resolveImageSource = resolveImageSource
        visitor.alertDetector.docCAlertMode = options.docCAlertMode
        visitor.visit(document.root)
        return prefix + visitor.result
    }
}
