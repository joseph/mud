import Foundation

/// AST → web HTML visitor: renders the Up-mode body from one footnote-aware
/// cmark parse (ported from the swift-markdown pipeline; see
/// Doc/Plans/Archive/2026-07-single-parser-rendering.md). It walks a
/// ``CMarkDocument`` whose parse is footnote-aware, so `[^label]` references
/// arrive as AST nodes: ``visitFootnoteReference(_:)`` emits the marker HTML,
/// and the visitor owns footnote numbering directly (first-reference order
/// over authorial references only, occurrence-suffixed back-link ids).
///
/// Change tracking rides the same walk: `diffContext` / `DeletionPlacer`
/// emit change attributes and pre-rendered deletions, `WordSpanEmitter` drives
/// word-level markers, and `renderBody` builds a `DiffContext` when
/// `options.waypoint` is set. There is no waypoint preprocessing — cmark
/// parses footnotes directly, so no transformed source needs reconciling.
struct UpHTMLVisitor: CMarkWalker {
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
    // the parser (`listIsTight`).
    private var inTightList = false

    // Table rendering state.
    private var tableAlignments: [CMarkTableAlignment] = []
    private var currentCellColumn = 0
    private var inTableHead = false

    var alertDetector = AlertDetector()

    /// When non-nil, change attributes are emitted on native elements
    /// for blocks that differ from the waypoint document.
    var diffContext: DiffContext? {
        didSet {
            deletionPlacer = diffContext.map {
                DeletionPlacer(diffContext: $0)
            }
        }
    }

    /// Renders deletions into the output stream and owns their
    /// exactly-once bookkeeping. Created alongside `diffContext`.
    private var deletionPlacer: DeletionPlacer?

    /// When false, non-consuming `<del>` spans in paired insertion
    /// blocks are silently skipped instead of emitted inline.
    var showInlineDeletions = false

    // Footnote numbering state: numbers are assigned in first-reference order
    // over authorial references only, so comments occupy no number and leave
    // no gap; the per-label occurrence index drives back-link ids (fnref-N-K).
    private var authorialNumber: [String: Int] = [:]
    private var nextFootnoteNumber = 1
    private var occurrence: [String: Int] = [:]

    /// Pre-assigned reference numbering, keyed by each reference's verified
    /// byte range in its document's source. Set for visitors whose walk
    /// starts mid-document — deletion rendering walks a single deleted block
    /// of the *old* document, so the incremental first-reference counting
    /// above cannot reproduce the numbers a full walk would have assigned
    /// (see ``footnoteNumbering(for:)``). Nil for full-document walks.
    var footnoteNumbers: FootnoteNumbering?

    // MARK: - Block containers

    mutating func visitBlockQuote(_ blockQuote: CMarkNode) {
        let innerParagraph = blockQuote.children
            .first(where: { $0.kind == .paragraph })
        if let (category, title) = alertDetector.detectGFMAlert(blockQuote) {
            let attrs = innerParagraph.flatMap { changeAttributes(for: $0) }
                ?? .empty
            emitAlertOpen(category, attrs: attrs)
            emitAlertTitle(category, title)
            emitGFMAlertContent(blockQuote, category: category)
            result += "</blockquote>\n"
        } else if let alert = alertDetector.detectDocCAlert(blockQuote) {
            let attrs = innerParagraph.flatMap { changeAttributes(for: $0) }
                ?? .empty
            emitAlertOpen(alert.category, attrs: attrs)
            activateAlertWordSpans(
                for: innerParagraph, tagByteLength: alert.tagByteLength)
            emitDocCAlertTitleAndContent(
                alert.category, alert.title,
                blockQuote: blockQuote, tagByteLength: alert.tagByteLength)
            deactivateWordSpans()
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
        // Peek ahead: when a deleted list item's deletion lands on the
        // first child (e.g. a paragraph inside a complex item with a
        // nested list), emit it here — before the <li> — so it
        // becomes a valid sibling rather than nesting inside this item.
        if deletionPlacer != nil, let firstChild = listItem.firstChild {
            result += deletionPlacer!.listItemHTML(before: firstChild)
        }
        let attrs = changeAttributes(for: listItem)
        if inTightList {
            result += "<li\(attrs?.asString ?? "")>"
        } else {
            result += "<li\(attrs?.asString ?? "")>\n"
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
        let attrs = changeAttributes(for: heading)
        let level = heading.headingLevel
        let slug = slugTracker.slug(for: heading.plainText)
        activateWordSpans(for: heading)
        result += "<h\(level) id=\"\(slug)\"\(attrs?.asString ?? "")>"
        descendInto(heading)
        result += "</h\(level)>\n"
        deactivateWordSpans()
    }

    mutating func visitParagraph(_ paragraph: CMarkNode) {
        // A paragraph that is exactly `$$…$$` is display math. Recover the raw
        // source (cmark has already inline-parsed the interior — turning `_`
        // into emphasis) and render it as a block instead of descending.
        if let tex = displayMathInterior(of: paragraph) {
            emitMathBlock(paragraph, tex: tex)
            return
        }

        let attrs = changeAttributes(for: paragraph)
        // Inline `$`…`$` math renders only when word spans are inactive (see
        // visitInlineCode), so a paragraph carrying inline math skips word
        // spans and takes a whole-block change annotation instead — the same
        // treatment code and display-math blocks get.
        let hasInlineMath = paragraphContainsInlineMath(paragraph)
        if !hasInlineMath { activateWordSpans(for: paragraph) }
        let parentKind = paragraph.parent?.kind
        let inListItem = parentKind == .listItem || parentKind == .taskListItem
        // List items store their annotation on the list-item node,
        // not the inner paragraph. Fall back to the parent.
        if !hasInlineMath, spanEmitter == nil, inListItem,
           let listItem = paragraph.parent {
            activateWordSpans(for: listItem)
        }
        if inTightList && inListItem {
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

    mutating func visitCodeBlock(_ codeBlock: CMarkNode) {
        // A ```math fenced block is display math, not code: render it to
        // MathML and skip the code path entirely (including line-level diff —
        // math gets whole-block change treatment, like a code block does).
        if codeBlock.fenceInfo == "math" {
            emitMathBlock(codeBlock, tex: codeBlock.literal ?? "")
            return
        }

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
        _ codeBlock: CMarkNode, diff: CodeBlockDiff
    ) {
        let lang = ChangePlan.codeLanguage(codeBlock)

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
    /// language header and syntax highlighting). Shared by `visitCodeBlock`
    /// and `DeletionRenderer.render`.
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
        // Always wrap the pass-through literal in a `.mud-html-block` div. cmark
        // parses a raw-HTML block as one `htmlBlock` node with no source byte a
        // comment could anchor to, so the wrapper marks the subtree the comment
        // scripts skip — the affordances disable up front instead of failing at
        // save (issue #5, raw-HTML case). Change attributes fold into the same
        // wrapper (previously the only reason a div appeared here).
        let attrs = changeAttributes(for: html)
        let classes = attrs.map { "mud-html-block \($0.classes)" } ?? "mud-html-block"
        result += "<div class=\"\(classes)\"\(attrs?.dataAttrs ?? "")>"
        result += html.literal ?? ""
        result += "</div>\n"
    }

    mutating func visitThematicBreak(_ thematicBreak: CMarkNode) {
        let attrs = changeAttributes(for: thematicBreak)
        if attrs != nil {
            result += "<div\(attrs!.asString)><hr /></div>\n"
        } else {
            result += "<hr />\n"
        }
    }

    // MARK: - Footnotes and comments

    /// Definitions render nothing in the body: they are skipped structurally
    /// (their references never enter the numbering either). Their bodies feed
    /// the bottom sections via `FootnoteProcessor`, not this walk.
    /// `BlockMatcher`'s collector skips them the same way, so change
    /// tracking never asks this visitor to place a change inside a definition.
    mutating func visitFootnoteDefinition(_ node: CMarkNode) {}

    mutating func visitFootnoteReference(_ node: CMarkNode) {
        // cmark keeps the label on the resolved definition and stores its own
        // per-reference number as the literal. A reference always resolves —
        // cmark drops unmatched `[^label]` back to literal text — so the
        // guards below require an integer number literal and a sourcepos that
        // verifiably delimits `[^…]`. A reference that fails either guard
        // renders as its raw text. (The definition's label spelling stands in
        // for the reference's raw bytes, which a broken sourcepos can no
        // longer locate.)
        guard let label = node.parentFootnoteDefinition?.literal else { return }
        guard let literal = node.literal, Int(literal) != nil,
              let range = node.verifiedRange else {
            // Emitted directly, bypassing any active span emitter:
            // `WordDiff.inlineText` gives a reference zero characters, so
            // consuming here would shear every later word marker.
            result += HTMLEscaping.escape(
                EmojiShortcodes.replaceShortcodes(in: "[^\(label)]"))
            return
        }
        if FootnoteProcessor.isCommentLabel(label) {
            result += FootnoteProcessor.commentMarkerHTML(label: label)
        } else if let footnoteNumbers {
            // Mid-document walk: use the numbering a full walk assigned.
            if let assigned = footnoteNumbers[range] {
                result += FootnoteProcessor.markerHTML(
                    number: assigned.number, label: label,
                    occurrence: assigned.occurrence)
            } else {
                result += HTMLEscaping.escape(
                    EmojiShortcodes.replaceShortcodes(in: "[^\(label)]"))
            }
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
        // cmark has no table-body node: the first child row is the header,
        // the rest are body rows. Deletion handling folds in accordingly:
        // hoisting before <table> hangs off the header row, and the per-row
        // placement loop lives in the body-rows walk below instead of a
        // visitTableBody method.
        let rows = Array(table.children)

        // Emit preceding deletions BEFORE opening <table> so they don't
        // become invalid children of the table element.
        if deletionPlacer != nil, let head = rows.first {
            result += deletionPlacer!.hoistedHTML(beforeHead: head)
        }

        result += "<table>\n"
        if let head = rows.first {
            visit(head)
        }
        let bodyRows = rows.dropFirst()
        if !bodyRows.isEmpty {
            result += "<tbody>\n"
            if deletionPlacer != nil {
                // Deleted rows emit as <tr> siblings; anything else is
                // deferred by the placer until after </table>. After all
                // surviving rows, reclaim <tr> deletions that follow the
                // last row.
                var lastRow: CMarkNode?
                for row in bodyRows {
                    result += deletionPlacer!.rowHTML(before: row)
                    visit(row)
                    lastRow = row
                }
                if let lastRow {
                    result += deletionPlacer!.reclaimedRowHTML(after: lastRow)
                }
            } else {
                for row in bodyRows { visit(row) }
            }
            result += "</tbody>\n"
        }
        result += "</table>\n"
        tableAlignments = []

        // Emit non-<tr> deletions that were deferred from inside
        // the table body.
        if deletionPlacer != nil {
            result += deletionPlacer!.deferredHTML()
        }
    }

    mutating func visitTableHead(_ tableHead: CMarkNode) {
        inTableHead = true
        currentCellColumn = 0
        let attrs = changeAttributes(for: tableHead)
        result += "<thead>\n<tr\(attrs?.asString ?? "")>\n"
        descendInto(tableHead)
        result += "</tr>\n</thead>\n"
        inTableHead = false
    }

    mutating func visitTableRow(_ tableRow: CMarkNode) {
        currentCellColumn = 0
        let attrs = changeAttributes(for: tableRow)
        result += "<tr\(attrs?.asString ?? "")>\n"
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
        var literal = text.literal ?? ""
        // Drop the `$` delimiters bounding an adjacent inline-math span so they
        // don't render as literal dollar signs; the math body itself is
        // rendered by visitInlineCode. Only when word spans are inactive, so
        // the emitter's character count never desyncs (math-bearing paragraphs
        // skip word spans — see visitParagraph).
        if spanEmitter == nil {
            if let next = text.nextSibling, isInlineMath(next),
               literal.hasSuffix("$") {
                literal = String(literal.dropLast())
            }
            if let prev = text.previousSibling, isInlineMath(prev),
               literal.hasPrefix("$") {
                literal = String(literal.dropFirst())
            }
        }
        emitTextRun(literal)
    }

    /// Emits a text run exactly as `visitText` does, span emitter included —
    /// shared with the DocC aside path, which emits the tag-stripped first
    /// text that no longer matches any node's literal.
    private mutating func emitTextRun(_ string: String) {
        if spanEmitter != nil {
            result += spanEmitter!.advance(by: string.count, emit: true)
            result += spanEmitter!.closeOpenTag()
        } else {
            result += HTMLEscaping.escape(
                EmojiShortcodes.replaceShortcodes(in: string)
            )
        }
    }

    mutating func visitInlineCode(_ inlineCode: CMarkNode) {
        // A code span bounded by `$` on both sides is GitHub inline math
        // (`` $`…`$ ``). Render it to MathML — but only with word spans
        // inactive, so the adjacent `$`-stripping in visitText stays in step.
        if spanEmitter == nil, isInlineMath(inlineCode),
           let mathml = MathRenderer.render(
               inlineCode.literal ?? "", displayMode: false) {
            result += mathml
            return
        }
        if spanEmitter != nil { result += spanEmitter!.closeOpenTag() }
        result += "<code>"
        if spanEmitter != nil {
            result += spanEmitter!.advance(
                by: (inlineCode.literal ?? "").count, emit: true)
            result += spanEmitter!.closeOpenTag()
        } else {
            result += HTMLEscaping.escape(inlineCode.literal ?? "")
        }
        result += "</code>"
    }

    mutating func visitInlineHTML(_ html: CMarkNode) {
        result += html.literal ?? ""
    }

    mutating func visitLineBreak(_ lineBreak: CMarkNode) {
        if spanEmitter != nil {
            result += spanEmitter!.advance(by: 1, emit: false)
            result += spanEmitter!.closeOpenTag()
        }
        result += "<br />\n"
    }

    mutating func visitSoftBreak(_ softBreak: CMarkNode) {
        if spanEmitter != nil {
            result += spanEmitter!.advance(by: 1, emit: false)
            result += spanEmitter!.closeOpenTag()
        }
        result += "\n"
    }

    // MARK: - Math

    /// Emits a display-math block: a `<div class="mud-math-block">` wrapping
    /// the MathML for `tex`. Shared by the ```` ```math ```` and `$$…$$` paths.
    /// Carries whole-block change attributes (and emits preceding deletions)
    /// like a code block; never takes word-level spans. If the JS layer is
    /// unavailable (`MathRenderer` returns nil), falls back to the escaped TeX
    /// so the source is still shown.
    private mutating func emitMathBlock(_ node: CMarkNode, tex: String) {
        let attrs = changeAttributes(for: node)
        let classes = attrs.map { "mud-math-block \($0.classes)" }
            ?? "mud-math-block"
        result += "<div class=\"\(classes)\"\(attrs?.dataAttrs ?? "")>"
        if let mathml = MathRenderer.render(tex, displayMode: true) {
            result += mathml
        } else {
            result += HTMLEscaping.escape(tex)
        }
        result += "</div>\n"
    }

    /// If `paragraph` is a standalone `$$…$$` display-math block, returns its
    /// TeX interior (delimiters stripped); otherwise nil. Reads the raw source
    /// so cmark's inline parse of the interior (emphasis, smart punctuation)
    /// never reaches the renderer. A paragraph mixing text with `$$…$$`, or
    /// carrying more than one display span, is rejected.
    private func displayMathInterior(of paragraph: CMarkNode) -> String? {
        guard let raw = rawSource(of: paragraph) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"),
              trimmed.count >= 4 else { return nil }
        let interior = trimmed.dropFirst(2).dropLast(2)
        guard !interior.contains("$$") else { return nil }
        return String(interior)
    }

    /// True when `node` is the body of a GitHub inline-math span `` $`…`$ ``:
    /// an inline-code node whose previous sibling text ends with `$` and whose
    /// next sibling text starts with `$`. The three visit methods that touch
    /// inline math all key off this one predicate so their edits stay in step.
    private func isInlineMath(_ node: CMarkNode) -> Bool {
        guard node.kind == .inlineCode,
              let prev = node.previousSibling, prev.kind == .text,
              (prev.literal ?? "").hasSuffix("$"),
              let next = node.nextSibling, next.kind == .text,
              (next.literal ?? "").hasPrefix("$")
        else { return false }
        return true
    }

    /// True when any inline child of `paragraph` is an inline-math span.
    private func paragraphContainsInlineMath(_ paragraph: CMarkNode) -> Bool {
        for child in paragraph.children where isInlineMath(child) {
            return true
        }
        return false
    }

    /// The exact source text a node spans, decoded from the parse's UTF-8
    /// bytes, or nil if its position can't be resolved.
    private func rawSource(of node: CMarkNode) -> String? {
        guard let range = node.byteRange else { return nil }
        let bytes = node.document.geometry.bytes
        guard range.lowerBound >= 0, range.upperBound <= bytes.count
        else { return nil }
        return String(decoding: bytes[range], as: UTF8.self)
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
    private mutating func changeAttributes(
        for node: CMarkNode
    ) -> ChangeAttrs? {
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

        // Strip the [!TYPE] tag from the first text node, then escape the
        // remainder without emoji replacement (so a `:tada:` on the tag line
        // stays literal).
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

    /// Concatenated plain text of an array of inline nodes, used for the
    /// length check before inlining same-line content. Inline code
    /// contributes its bare literal (no backticks), unlike
    /// `CMarkNode.plainText`.
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

    /// Emits the title and body content for a DocC aside, working from the
    /// original blockquote plus the detector's `tagByteLength`: the first
    /// text node's literal minus that prefix is the tag-stripped text. When
    /// the same-line content (before the first soft break) is under 60
    /// characters, it is bolded on the title line; otherwise all content
    /// renders roman in separate paragraphs.
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
        // break.
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
            // Flush and clear the span emitter at the paragraph's end, so
            // leftover non-consuming spans land at the right byte position and
            // later blocks render without the emitter.
            deactivateWordSpans()
        }
        for child in children.dropFirst() { visit(child) }
    }

    // MARK: - Word-level diff rendering

    /// Active word-span emitter for the current block, or `nil`. The
    /// visitor owns block structure (which nodes have spans, when a
    /// block starts and ends); the cursor machine lives in
    /// `WordSpanEmitter`.
    private var spanEmitter: WordSpanEmitter?

    /// Activates word spans for a DocC aside's inner paragraph, advancing
    /// the cursor past the tag prefix so spans align with the rendered
    /// content. The prefix length is the detector's `tagByteLength`: the
    /// prefix is ASCII (`Kind:` plus spaces/tabs), so its **byte** length
    /// equals the **character** count `skipPrefix` expects.
    private mutating func activateAlertWordSpans(
        for paragraph: CMarkNode?, tagByteLength: Int
    ) {
        guard let para = paragraph else { return }
        activateWordSpans(for: para)
        guard spanEmitter != nil else { return }
        if tagByteLength > 0 {
            spanEmitter?.skipPrefix(charCount: tagByteLength)
        }
    }

    /// Activates word-span rendering if the block has word spans.
    private mutating func activateWordSpans(for node: CMarkNode) {
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
        _ blockQuote: CMarkNode,
        wordSpans: [WordSpan]? = nil,
        footnoteNumbers: FootnoteNumbering? = nil
    ) -> (html: String, category: AlertCategory)? {
        let detector = AlertDetector()

        if let (category, title) = detector.detectGFMAlert(blockQuote) {
            var visitor = UpHTMLVisitor()
            visitor.footnoteNumbers = footnoteNumbers
            visitor.emitAlertTitle(category, title)
            visitor.emitGFMAlertContent(blockQuote, category: category)
            return (visitor.result, category)
        }

        if let alert = detector.detectDocCAlert(blockQuote) {
            var visitor = UpHTMLVisitor()
            visitor.footnoteNumbers = footnoteNumbers
            if let spans = wordSpans, !spans.isEmpty {
                visitor.spanEmitter = WordSpanEmitter(
                    spans: spans, role: .deletion,
                    showInlineDeletions: false)
                if alert.tagByteLength > 0 {
                    visitor.spanEmitter?.skipPrefix(
                        charCount: alert.tagByteLength)
                }
            }
            visitor.emitDocCAlertTitleAndContent(
                alert.category, alert.title,
                blockQuote: blockQuote, tagByteLength: alert.tagByteLength)
            visitor.deactivateWordSpans()
            return (visitor.result, alert.category)
        }

        return nil
    }

    /// Renders a node's inner HTML using word spans.
    ///
    /// Used by `DeletionRenderer` to render deletion HTML with
    /// word-level `<del>` markers for the red block.
    static func renderWithWordSpans(
        _ node: CMarkNode, spans: [WordSpan], role: WordSpanEmitter.Role,
        footnoteNumbers: FootnoteNumbering? = nil
    ) -> String {
        var visitor = UpHTMLVisitor()
        visitor.footnoteNumbers = footnoteNumbers
        visitor.spanEmitter = WordSpanEmitter(
            spans: spans, role: role, showInlineDeletions: false)
        for child in node.children { visitor.visit(child) }
        visitor.deactivateWordSpans()
        return visitor.result
    }
}

// MARK: - Footnote numbering for mid-document walks

extension UpHTMLVisitor {
    /// The (number, occurrence) a full-document walk assigns each authorial
    /// footnote reference, keyed by the reference's **verified byte range**
    /// — a position key, not the node handle, because the plan cache hands
    /// deletion blocks whose nodes point into a different (textually
    /// identical) tree than the one this map was built from; identical
    /// source bytes parse to identical positions, so the ranges still join.
    typealias FootnoteNumbering = [Range<Int>: (number: Int, occurrence: Int)]

    /// Assigns numbering over `document` exactly as a full rendering walk
    /// would: first-reference order over verifiable authorial references,
    /// comments and definition-interior references excluded. Seeds the
    /// deletion-rendering visitors, whose walks start mid-document and so
    /// cannot count for themselves.
    static func footnoteNumbering(
        for document: CMarkDocument
    ) -> FootnoteNumbering {
        var walker = FootnoteNumberingWalker()
        walker.visit(document.root)
        return walker.numbers
    }
}

/// The numbering pass behind `UpHTMLVisitor.footnoteNumbering(for:)`,
/// mirroring `visitFootnoteReference`'s guards and counters exactly.
private struct FootnoteNumberingWalker: CMarkWalker {
    var numbers: UpHTMLVisitor.FootnoteNumbering = [:]
    private var authorialNumber: [String: Int] = [:]
    private var nextFootnoteNumber = 1
    private var occurrence: [String: Int] = [:]

    /// References inside definitions never enter the numbering — the
    /// rendering visitor skips definition subtrees entirely.
    mutating func visitFootnoteDefinition(_ node: CMarkNode) {}

    mutating func visitFootnoteReference(_ node: CMarkNode) {
        guard let label = node.parentFootnoteDefinition?.literal else { return }
        guard let literal = node.literal, Int(literal) != nil,
              let range = node.verifiedRange else { return }
        guard !FootnoteProcessor.isCommentLabel(label) else { return }
        let number = authorialNumber[label] ?? nextFootnoteNumber
        if authorialNumber[label] == nil {
            authorialNumber[label] = number
            nextFootnoteNumber += 1
        }
        let k = (occurrence[label] ?? 0) + 1
        occurrence[label] = k
        numbers[range] = (number: number, occurrence: k)
    }
}

// MARK: - Body rendering entry point

extension UpHTMLVisitor {
    /// Renders the Up-mode body from a source string: CRLF normalization and
    /// frontmatter extraction (matching `ParsedMarkdown`), one footnote-aware
    /// parse of the body, the visitor walk, and the rendered-frontmatter
    /// prefix. No footnote preprocessing happens. When `options.waypoint` is
    /// set, the waypoint's body is parsed as-is and diffed against this parse;
    /// with no transformed source on either side, they compare like-with-like.
    ///
    /// This String overload parses on the spot; the `ParsedMarkdown` overload
    /// below reuses the retained parse. Both drive the same private core.
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

        guard let document = CMarkDocument(parsing: body) else {
            return yaml.map(FrontMatterHTMLRenderer.upModeHTML) ?? ""
        }
        return renderBody(
            document: document, frontMatterYAML: yaml,
            oldDocument: options.waypoint.flatMap { CMarkDocument(parsing: $0.body) },
            options: options, resolveImageSource: resolveImageSource)
    }

    /// The production entry: renders from `ParsedMarkdown`'s retained
    /// `cmarkDocument` and, when a waypoint is set, its retained tree too —
    /// one owned parse per render, no re-parsing. This is the overload
    /// `MudCore.renderUpToHTML` calls.
    static func renderBody(
        _ parsed: ParsedMarkdown,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
    ) -> String {
        guard let document = parsed.cmarkDocument else {
            return parsed.frontMatter.map(FrontMatterHTMLRenderer.upModeHTML) ?? ""
        }
        return renderBody(
            document: document, frontMatterYAML: parsed.frontMatter,
            oldDocument: options.waypoint?.cmarkDocument,
            options: options, resolveImageSource: resolveImageSource)
    }

    /// Shared core: configure the visitor, wire the diff context from an
    /// already-parsed old document, walk, and prepend rendered frontmatter.
    private static func renderBody(
        document: CMarkDocument,
        frontMatterYAML: String?,
        oldDocument: CMarkDocument?,
        options: RenderOptions,
        resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)?
    ) -> String {
        let prefix = frontMatterYAML.map(FrontMatterHTMLRenderer.upModeHTML) ?? ""
        var visitor = UpHTMLVisitor()
        visitor.baseURL = options.baseURL
        visitor.resolveImageSource = resolveImageSource
        visitor.alertDetector.docCAlertMode = options.docCAlertMode
        visitor.showInlineDeletions = options.showInlineDeletions
        if let oldDocument {
            visitor.diffContext = DiffContext(
                old: oldDocument, new: document,
                wordDiffThreshold: options.wordDiffThreshold)
        }
        visitor.visit(document.root)
        visitor.emitTrailingDeletions()
        return prefix + visitor.result
    }
}
