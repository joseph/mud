import Foundation
import Markdown

/// Produces syntax-highlighted HTML from raw Markdown source by
/// walking the swift-markdown AST and wrapping recognized nodes in
/// `<span class="md-*">` tags.  All source text is HTML-escaped in
/// the output.
public struct DownHTMLVisitor: Sendable {

    public init() {}

    /// Returns a `<div class="down-lines">` container with one
    /// flex-row per source line, line numbers, syntax-highlight
    /// spans, and scrollable code-block regions.
    public func highlight(
        _ markdown: String,
        docCAlertMode: DocCAlertMode = .extended,
        frontMatterRendered: [String] = []
    ) -> String {
        let result = highlightLines(markdown, docCAlertMode: docCAlertMode)
        return buildLayout(
            result.rendered, codeBlocks: result.codeBlocks,
            frontMatterRendered: frontMatterRendered)
    }

    /// Renders with change-tracking markers for Down mode.
    ///
    /// Highlights both old and new markdown, builds a `LineDiffMap`
    /// from block matches, and produces a layout that interleaves
    /// deleted old-doc lines and annotates inserted/modified new-doc
    /// lines.
    func highlightWithChanges(
        new newMarkdown: String,
        old oldMarkdown: String,
        matches: [BlockMatch],
        docCAlertMode: DocCAlertMode = .extended,
        wordDiffThreshold: Double = 0.25,
        frontMatterRendered: [String] = []
    ) -> String {
        let newResult = highlightLines(
            newMarkdown, docCAlertMode: docCAlertMode)
        let oldResult = highlightLines(
            oldMarkdown, docCAlertMode: docCAlertMode)
        let diffMap = LineDiffMap(
            matches: matches,
            wordDiffThreshold: wordDiffThreshold)
        return buildLayoutWithChanges(
            newResult.rendered,
            codeBlocks: newResult.codeBlocks,
            diffMap: diffMap,
            oldRendered: oldResult.rendered,
            frontMatterRendered: frontMatterRendered)
    }

    // MARK: - Phase 1+2: Highlight lines

    private struct HighlightResult {
        let rendered: [String]
        let codeBlocks: [CodeBlockInfo]
    }

    /// Runs Phase 1 (AST event collection) and Phase 2 (per-line
    /// rendering) without building the final layout.
    private func highlightLines(
        _ markdown: String,
        docCAlertMode: DocCAlertMode
    ) -> HighlightResult {
        // Phase 1: Collect span events and code block info.
        let sourceLines = markdown.split(
            separator: "\n", omittingEmptySubsequences: false
        ).map { Array($0.utf8) }

        // swift-markdown is footnote-unaware: it misreads definition bodies as
        // indented code blocks and leaves references / markers unhighlighted.
        // A `cmark-gfm` scan supplies the structure Down mode needs.
        let layout = FootnoteProcessor.scan(markdown)

        // Feed the main parse a copy with every footnote-definition line
        // blanked (each byte → a space, newlines and all positions preserved)
        // so swift-markdown emits nothing for the bodies it would misread. The
        // marker / reference spans and the re-parsed definition bodies are
        // layered on below; Phase 2 still renders the original verbatim lines,
        // so the source text is untouched on screen.
        let doc = MarkdownParser.parse(
            Self.blankingDefinitions(layout.defs, in: sourceLines,
                                     original: markdown))

        var alertDetector = AlertDetector()
        alertDetector.docCAlertMode = docCAlertMode
        var collector = EventCollector(sourceLines: sourceLines)
        collector.alertDetector = alertDetector
        collector.visit(doc)
        var events = collector.events

        // Footnote markers, references, and re-parsed definition bodies.
        for ref in layout.refs {
            events += Self.footnoteSpan(
                "md-footnote-ref", line: ref.line,
                openColumn: ref.startColumn, closeColumn: ref.endColumn + 1)
        }
        for def in layout.defs {
            events += Self.footnoteSpan(
                "md-footnote-def", line: def.startLine,
                openColumn: def.startColumn, closeColumn: def.markerEndColumn)
            events += subParseDefBody(
                def, sourceLines: sourceLines, docCAlertMode: docCAlertMode)
        }

        events.sort()

        // Phase 2: Render per-line HTML content strings.
        let lines = markdown.split(
            separator: "\n", omittingEmptySubsequences: false)
        let lineCount = markdown.hasSuffix("\n") && !lines.isEmpty
            ? lines.count - 1
            : max(lines.count, 1)
        let rendered = renderLineContent(
            lines: lines, lineCount: lineCount,
            events: events, codeBlocks: collector.codeBlocks)

        return HighlightResult(
            rendered: rendered, codeBlocks: collector.codeBlocks)
    }

    // MARK: - Footnotes

    /// An open/close `SpanEvent` pair for a footnote marker or reference at an
    /// explicit position. The high depth keeps it outermost; footnote spans
    /// never share a column with a document span, so ordering is unaffected.
    private static func footnoteSpan(
        _ cssClass: String, line: Int,
        openColumn: Int, closeColumn: Int
    ) -> [SpanEvent] {
        let depth: Int32 = 1_000
        return [
            SpanEvent(line: Int32(line), column: Int32(openColumn),
                      isClose: false, depth: depth, cssClass: cssClass),
            SpanEvent(line: Int32(line), column: Int32(closeColumn),
                      isClose: true, depth: depth, cssClass: cssClass),
        ]
    }

    /// Re-parses a footnote definition body as ordinary Markdown so its inline
    /// and block constructs highlight like the rest of the document, returning
    /// the span events translated back into original-source coordinates.
    ///
    /// The body is recovered by stripping the `[^label]:` marker from the
    /// opener line and the shared continuation indent from the rest; each
    /// stripped width is remembered per line so columns map back exactly.
    /// Only the *events* are used — rendering still happens against the raw
    /// source lines, so the verbatim indentation is preserved (and a fenced
    /// code block inside a body is span-colored but not highlight.js-rendered).
    private func subParseDefBody(
        _ def: FootnoteLayout.Def,
        sourceLines: [[UInt8]],
        docCAlertMode: DocCAlertMode
    ) -> [SpanEvent] {
        var bodyLines: [[UInt8]] = []
        var origLine: [Int] = []
        var colOffset: [Int] = []

        for line in def.startLine...def.endLine {
            let idx = line - 1
            guard idx >= 0, idx < sourceLines.count else { continue }
            let bytes = sourceLines[idx]
            let drop = line == def.startLine
                ? min(def.contentStartColumn - 1, bytes.count)
                : Self.leadingWhitespace(bytes, max: def.contentIndent)
            bodyLines.append(Array(bytes[drop...]))
            origLine.append(line)
            colOffset.append(drop)
        }
        guard !bodyLines.isEmpty else { return [] }

        let body = bodyLines
            .map { String(decoding: $0, as: UTF8.self) }
            .joined(separator: "\n")
        let doc = MarkdownParser.parse(body)
        var alertDetector = AlertDetector()
        alertDetector.docCAlertMode = docCAlertMode
        var collector = EventCollector(sourceLines: bodyLines)
        collector.alertDetector = alertDetector
        collector.visit(doc)

        return collector.events.compactMap { ev in
            let i = Int(ev.line) - 1
            guard i >= 0, i < origLine.count else { return nil }
            return SpanEvent(
                line: Int32(origLine[i]),
                column: ev.column + Int32(colOffset[i]),
                isClose: ev.isClose, depth: ev.depth,
                cssClass: ev.cssClass)
        }
    }

    /// Count of leading whitespace bytes — space or tab, each one byte —
    /// capped at `max`. Byte-counted (never exceeds the line length) so the
    /// stripped width maps cleanly back to source columns.
    private static func leadingWhitespace(_ bytes: [UInt8], max cap: Int) -> Int {
        var n = 0
        for b in bytes {
            if n >= cap || (b != 0x20 && b != 0x09) { break }
            n += 1
        }
        return n
    }

    /// Returns `original` with every line covered by a footnote definition
    /// replaced by spaces — one per byte, newlines untouched. Byte lengths and
    /// line offsets are preserved, so the source positions swift-markdown
    /// reports for the surviving content still map onto the original lines
    /// exactly. Returns `original` unchanged when there are no definitions.
    private static func blankingDefinitions(
        _ defs: [FootnoteLayout.Def], in sourceLines: [[UInt8]],
        original: String
    ) -> String {
        guard !defs.isEmpty else { return original }
        var lines = sourceLines
        for def in defs {
            for line in def.startLine...def.endLine {
                let idx = line - 1
                guard idx >= 0, idx < lines.count else { continue }
                lines[idx] = Array(repeating: 0x20, count: lines[idx].count)
            }
        }
        return lines
            .map { String(decoding: $0, as: UTF8.self) }
            .joined(separator: "\n")
    }

    // MARK: - SpanEvent

    private struct SpanEvent: Comparable {
        let line: Int32
        let column: Int32
        let isClose: Bool
        let depth: Int32
        let cssClass: String

        static func < (lhs: SpanEvent, rhs: SpanEvent) -> Bool {
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            if lhs.column != rhs.column {
                return lhs.column < rhs.column
            }
            // Close before open at the same position.
            if lhs.isClose != rhs.isClose { return lhs.isClose }
            // Inner closes first; outer opens first.
            return lhs.isClose
                ? lhs.depth > rhs.depth
                : lhs.depth < rhs.depth
        }
    }

    private struct CodeBlockInfo {
        let isFenced: Bool
        let contentFirstLine: Int
        let contentLastLine: Int
        let highlightedLines: [String]

        var hasContent: Bool { contentFirstLine <= contentLastLine }
    }

    // MARK: - Phase 1: Collect events from the AST

    private struct EventCollector: MarkupWalker {
        let sourceLines: [[UInt8]]
        var events: [SpanEvent] = []
        var codeBlocks: [CodeBlockInfo] = []
        var alertDetector = AlertDetector()

        // Footnote-definition lines are blanked out of the parser input (see
        // `blankingDefinitions`), so the main parse never produces events for
        // them and no per-visitor suppression is needed here.

        // -- Container nodes --

        mutating func visitHeading(_ heading: Heading) {
            emitContainer(heading, cssClass: "md-heading")
        }

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
            let depth = Self.nodeDepth(blockQuote)
            if let (category, _) = alertDetector.detectGFMAlert(blockQuote) {
                emitContainer(blockQuote,
                    cssClass: "md-blockquote md-alert-\(category.rawValue)")
                emitAlertMarkers(in: blockQuote, depth: depth)
                let tag = "[!\(category.rawValue.uppercased())]"
                emitAlertTagSpan(in: blockQuote, tagLen: tag.utf8.count,
                                 depth: depth)
            } else if let (category, _, _) = alertDetector.detectDocCAlert(blockQuote) {
                emitContainer(blockQuote,
                    cssClass: "md-blockquote md-alert-\(category.rawValue)")
                emitAlertMarkers(in: blockQuote, depth: depth)
                if let aside = Aside(blockQuote,
                                     tagRequirement: .requireAnyLengthTag) {
                    emitAlertTagSpan(in: blockQuote,
                                     tagLen: aside.kind.rawValue.utf8.count + 1,
                                     depth: depth)
                }
            } else {
                emitContainer(blockQuote, cssClass: "md-blockquote")
            }
        }

        /// Emits a 1-character `md-alert-tag` span over the `>` marker
        /// on every line of the blockquote.
        private mutating func emitAlertMarkers(
            in blockQuote: BlockQuote, depth: Int32
        ) {
            guard let range = blockQuote.range else { return }
            let col = range.lowerBound.column
            for line in range.lowerBound.line...range.upperBound.line {
                emitSpan("md-alert-tag", depth: depth + 1,
                         from: (line: line, column: col),
                         to:   (line: line, column: col + 1))
            }
        }

        /// Emits a nested `md-alert-tag` span covering the tag text
        /// (e.g. `[!NOTE]` or `Note:`) on the first line of a blockquote.
        private mutating func emitAlertTagSpan(
            in blockQuote: BlockQuote, tagLen: Int, depth: Int32
        ) {
            guard let para = Array(blockQuote.children).first as? Paragraph,
                  let textNode = Array(para.children).first as? Text,
                  let range = textNode.range else { return }
            let line = range.lowerBound.line
            let col  = range.lowerBound.column
            emitSpan("md-alert-tag", depth: depth + 2,
                     from: (line: line, column: col),
                     to:   (line: line, column: col + tagLen))
        }

        mutating func visitEmphasis(_ emphasis: Emphasis) {
            emitContainer(emphasis, cssClass: "md-emphasis")
        }

        mutating func visitStrong(_ strong: Strong) {
            emitContainer(strong, cssClass: "md-strong")
        }

        mutating func visitLink(_ link: Markdown.Link) {
            emitContainer(link, cssClass: "md-link")
        }

        mutating func visitImage(_ image: Image) {
            emitContainer(image, cssClass: "md-image")
        }

        mutating func visitStrikethrough(
            _ strikethrough: Strikethrough
        ) {
            emitContainer(strikethrough, cssClass: "md-strikethrough")
        }

        mutating func visitTable(_ table: Table) {
            emitContainer(table, cssClass: "md-table")
        }

        mutating func visitListItem(_ listItem: ListItem) {
            if listItem.checkbox != nil {
                emitContainer(listItem, cssClass: "md-task")
            } else {
                descendInto(listItem)
            }
        }

        // -- Leaf nodes --

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
            guard let range = codeBlock.range else { return }
            let depth = Self.nodeDepth(codeBlock)
            let fenceLen = measureFence(at: range.lowerBound)

            if fenceLen > 0 {
                // -- Fenced code block: fence / content / fence --

                // Opening fence line.
                let openLineLen = lineLen(range.lowerBound.line)
                emitSpan("md-code-fence", depth: depth,
                         from: (range.lowerBound.line,
                                range.lowerBound.column),
                         to: (range.lowerBound.line,
                              openLineLen + 1))

                // Content lines (between the fences), if any.
                let firstContent = range.lowerBound.line + 1
                let lastContent = range.upperBound.line - 1
                var highlighted: [String] = []
                if firstContent <= lastContent {
                    let lastLen = lineLen(lastContent)
                    emitSpan("md-code-block", depth: depth,
                             from: (firstContent, 1),
                             to: (lastContent,
                                  max(lastLen, 1) + 1))

                    if let html = CodeHighlighter.highlight(
                        codeBlock.code,
                        language: codeBlock.language)
                    {
                        highlighted = HTMLLineSplitter
                            .splitByLine(html)
                    }
                }

                // Closing fence line.
                let closeLineLen = lineLen(range.upperBound.line)
                emitSpan("md-code-fence", depth: depth,
                         from: (range.upperBound.line, 1),
                         to: (range.upperBound.line,
                              closeLineLen + 1))

                // Info string (language name) on the opening
                // fence, nested inside md-code-fence.
                if let lang = codeBlock.language, !lang.isEmpty {
                    let infoCol = range.lowerBound.column + fenceLen
                    emitSpan("md-code-info", depth: depth + 1,
                             from: (range.lowerBound.line, infoCol),
                             to: (range.lowerBound.line,
                                  infoCol + lang.utf8.count))
                }

                // Always record for layout, even when empty.
                codeBlocks.append(CodeBlockInfo(
                    isFenced: true,
                    contentFirstLine: firstContent,
                    contentLastLine: lastContent,
                    highlightedLines: highlighted))

            } else {
                // -- Indented code block: content only --
                let lineCount = codeBlock.code.lazy
                    .filter { $0 == "\n" }.count
                let lastLine = range.lowerBound.line
                    + max(lineCount, 1) - 1
                let lastLen = lineLen(lastLine)
                emitSpan("md-code-block", depth: depth,
                         from: (range.lowerBound.line,
                                range.lowerBound.column),
                         to: (lastLine, lastLen + 1))

                codeBlocks.append(CodeBlockInfo(
                    isFenced: false,
                    contentFirstLine: range.lowerBound.line,
                    contentLastLine: lastLine,
                    highlightedLines: []))
            }
        }

        mutating func visitInlineCode(_ inlineCode: InlineCode) {
            emitLeaf(inlineCode, cssClass: "md-code")
        }

        mutating func visitThematicBreak(
            _ thematicBreak: ThematicBreak
        ) {
            emitLeaf(thematicBreak, cssClass: "md-hr")
        }

        mutating func visitHTMLBlock(_ html: HTMLBlock) {
            emitLeaf(html, cssClass: "md-html")
        }

        mutating func visitInlineHTML(_ html: InlineHTML) {
            emitLeaf(html, cssClass: "md-html")
        }

        // -- Helpers --

        /// Emit open event, descend into children, emit close event.
        private mutating func emitContainer(
            _ node: some Markup, cssClass: String
        ) {
            guard let range = node.range else {
                descendInto(node)
                return
            }
            let depth = Self.nodeDepth(node)
            events.append(SpanEvent(
                line: Int32(range.lowerBound.line),
                column: Int32(range.lowerBound.column),
                isClose: false,
                depth: depth,
                cssClass: cssClass
            ))
            descendInto(node)
            // cmark-gfm's upperBound is exclusive (one past the last
            // byte), matching the column convention used by
            // emitLineContent.
            var closeLine = range.upperBound.line
            var closeCol = range.upperBound.column
            // cmark-gfm may report incorrect end positions for
            // multi-line strikethrough (child ranges extend beyond
            // the parent). Use the maximum descendant end position
            // to ensure the span covers all content.
            for child in node.children {
                guard let cr = child.range else { continue }
                if cr.upperBound.line > closeLine ||
                   (cr.upperBound.line == closeLine &&
                    cr.upperBound.column > closeCol) {
                    closeLine = cr.upperBound.line
                    closeCol = cr.upperBound.column
                }
            }
            events.append(SpanEvent(
                line: Int32(closeLine),
                column: Int32(closeCol),
                isClose: true,
                depth: depth,
                cssClass: cssClass
            ))
        }

        /// Emit open and close events for a leaf node (no children).
        private mutating func emitLeaf(
            _ node: some Markup, cssClass: String
        ) {
            guard let range = node.range else { return }
            let depth = Self.nodeDepth(node)
            events.append(SpanEvent(
                line: Int32(range.lowerBound.line),
                column: Int32(range.lowerBound.column),
                isClose: false,
                depth: depth,
                cssClass: cssClass
            ))
            events.append(SpanEvent(
                line: Int32(range.upperBound.line),
                column: Int32(range.upperBound.column),
                isClose: true,
                depth: depth,
                cssClass: cssClass
            ))
        }

        /// Emit an open/close event pair for a span at explicit
        /// (line, column) positions.
        private mutating func emitSpan(
            _ cssClass: String, depth: Int32,
            from open: (line: Int, column: Int),
            to close: (line: Int, column: Int)
        ) {
            events.append(SpanEvent(
                line: Int32(open.line),
                column: Int32(open.column),
                isClose: false,
                depth: depth,
                cssClass: cssClass
            ))
            events.append(SpanEvent(
                line: Int32(close.line),
                column: Int32(close.column),
                isClose: true,
                depth: depth,
                cssClass: cssClass
            ))
        }

        /// UTF-8 byte length of a source line (1-based line number).
        private func lineLen(_ line: Int) -> Int {
            let idx = line - 1
            guard idx >= 0, idx < sourceLines.count else { return 0 }
            return sourceLines[idx].count
        }

        private static func nodeDepth(_ node: some Markup) -> Int32 {
            var depth: Int32 = 0
            var current = node.parent
            while current != nil {
                depth += 1
                current = current?.parent
            }
            return depth
        }

        /// Count consecutive fence characters (backtick or tilde) at
        /// the given source position to determine fence length.
        private func measureFence(
            at location: SourceLocation
        ) -> Int {
            let lineIdx = location.line - 1
            guard lineIdx >= 0, lineIdx < sourceLines.count else {
                return 0
            }
            let line = sourceLines[lineIdx]
            let colIdx = location.column - 1
            guard colIdx >= 0, colIdx < line.count else { return 0 }

            let fenceChar = line[colIdx]
            guard fenceChar == 0x60 || fenceChar == 0x7E else {
                return 0  // Not a backtick or tilde
            }
            var len = 0
            while colIdx + len < line.count,
                  line[colIdx + len] == fenceChar {
                len += 1
            }
            return len
        }
    }

    // MARK: - Phase 2: Render per-line HTML content

    /// Produces one HTML content string per source line by applying
    /// span events (or substituting highlight.js output for code
    /// blocks).  Knows nothing about layout or line numbers.
    private func renderLineContent(
        lines: [Substring],
        lineCount: Int,
        events: [SpanEvent],
        codeBlocks: [CodeBlockInfo]
    ) -> [String] {
        var rendered: [String] = []
        rendered.reserveCapacity(lineCount)
        var openSpans: [String] = []
        var ei = 0

        for lineIdx in 0..<lineCount {
            let lineNum = Int32(lineIdx + 1)
            var content = ""

            // Reopen spans carried from the previous line.
            for cls in openSpans {
                content += "<span class=\"\(cls)\">"
            }

            // Emit line content — highlighted or escaped.
            if let highlighted = highlightedLine(
                lineNum, codeBlocks: codeBlocks)
            {
                // Process span events at line start (e.g.
                // md-code-block open) before the content.
                while ei < events.count,
                      events[ei].line == lineNum,
                      events[ei].column <= 1
                {
                    emitTag(events[ei], to: &content,
                            openSpans: &openSpans)
                    ei += 1
                }
                content += highlighted
            } else if lineIdx < lines.count {
                emitLineContent(
                    lines[lineIdx], lineNum: lineNum,
                    events: events, ei: &ei,
                    result: &content, openSpans: &openSpans)
            }

            // Flush events past end of visible content (close tags).
            while ei < events.count, events[ei].line == lineNum {
                emitTag(events[ei], to: &content,
                        openSpans: &openSpans)
                ei += 1
            }

            // Close all open spans at the line boundary.
            for _ in openSpans { content += "</span>" }

            rendered.append(content)
        }

        return rendered
    }

    /// Emit one line's content, escaping text in segments between
    /// event positions rather than byte-by-byte.
    private func emitLineContent(
        _ line: Substring,
        lineNum: Int32,
        events: [SpanEvent],
        ei: inout Int,
        result: inout String,
        openSpans: inout [String]
    ) {
        let utf8 = line.utf8
        let lineLen = Int32(utf8.count)
        var segStart = utf8.startIndex
        var col: Int32 = 1

        // Process events whose column falls within the line.
        while ei < events.count,
              events[ei].line == lineNum,
              events[ei].column <= lineLen
        {
            let targetCol = events[ei].column
            if targetCol > col {
                let segEnd = utf8.index(
                    segStart, offsetBy: Int(targetCol - col))
                result += HTMLEscaping.escape(
                    String(line[segStart..<segEnd]))
                segStart = segEnd
                col = targetCol
            }
            emitTag(events[ei], to: &result,
                    openSpans: &openSpans)
            ei += 1
        }

        // Emit remaining content after the last event.
        if segStart < utf8.endIndex {
            result += HTMLEscaping.escape(String(line[segStart...]))
        }
    }

    private func emitTag(
        _ event: SpanEvent,
        to result: inout String,
        openSpans: inout [String]
    ) {
        if event.isClose {
            result += "</span>"
            if let idx = openSpans.lastIndex(of: event.cssClass) {
                openSpans.remove(at: idx)
            }
        } else {
            result += "<span class=\"\(event.cssClass)\">"
            openSpans.append(event.cssClass)
        }
    }

    private func highlightedLine(
        _ lineNum: Int32,
        codeBlocks: [CodeBlockInfo]
    ) -> String? {
        let n = Int(lineNum)
        for cb in codeBlocks {
            guard !cb.highlightedLines.isEmpty,
                  n >= cb.contentFirstLine,
                  n <= cb.contentLastLine
            else { continue }
            let idx = n - cb.contentFirstLine
            return idx < cb.highlightedLines.count
                ? cb.highlightedLines[idx] : nil
        }
        return nil
    }

    // MARK: - Phase 3: Build structural layout

    /// Wraps rendered line content in the div-based layout with
    /// line numbers, `.dc-fence` / `.dc-code` classes, and
    /// `.dc-scroll` wrappers around code block regions.
    private func buildLayout(
        _ rendered: [String],
        codeBlocks: [CodeBlockInfo],
        frontMatterRendered: [String] = []
    ) -> String {
        let allRendered = frontMatterRendered + rendered
        let allRoles = Self.frontMatterRoles(
            count: frontMatterRendered.count)
            + lineRoles(lineCount: rendered.count, codeBlocks: codeBlocks)

        var html = "<div class=\"down-lines\">"
        var inScroll = false

        for (i, content) in allRendered.enumerated() {
            let role = allRoles[i]

            if role.isScrollable && !inScroll {
                html += "<div class=\"dc-scroll\">"
                inScroll = true
            }

            html += "<div class=\"\(role.cssClass)\">"
            html += "<span class=\"ln\">\(i + 1)</span>"
            html += "<span class=\"lc\">\(content)</span>"
            html += "</div>"

            if inScroll {
                let next = i + 1 < allRoles.count
                    ? allRoles[i + 1] : .regular
                if !next.isScrollable {
                    html += "</div>"
                    inScroll = false
                }
            }
        }

        html += "</div>"
        return html
    }

    private enum LineRole {
        case regular, fence, code, fmFence, fmCode

        /// CSS class(es) for this role's line div.
        var cssClass: String {
            switch self {
            case .regular: "dl"
            case .fence:   "dl dc-fence"
            case .code:    "dl dc-code"
            case .fmFence: "dl fm-fence"
            case .fmCode:  "dl fm-code"
            }
        }

        /// Whether this role participates in `dc-scroll` wrapping.
        var isScrollable: Bool {
            self == .fence || self == .code
        }
    }

    /// Builds line roles for frontmatter lines: first and last
    /// are fences, everything between is code.
    private static func frontMatterRoles(
        count: Int
    ) -> [LineRole] {
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            (i == 0 || i == count - 1) ? .fmFence : .fmCode
        }
    }

    /// Classifies each source line based on code block metadata.
    private func lineRoles(
        lineCount: Int,
        codeBlocks: [CodeBlockInfo]
    ) -> [LineRole] {
        var roles = [LineRole](repeating: .regular, count: lineCount)
        for cb in codeBlocks {
            if cb.hasContent {
                for line in cb.contentFirstLine...cb.contentLastLine {
                    let idx = line - 1
                    if idx >= 0, idx < lineCount {
                        roles[idx] = .code
                    }
                }
            }
            if cb.isFenced {
                let openFence = cb.contentFirstLine - 2
                let closeFence = cb.contentLastLine
                if openFence >= 0, openFence < lineCount {
                    roles[openFence] = .fence
                }
                if closeFence >= 0, closeFence < lineCount {
                    roles[closeFence] = .fence
                }
            }
        }
        return roles
    }

    // MARK: - Phase 3 (diff-aware): Build layout with changes

    /// Variant of `buildLayout` that interleaves deleted old-doc lines
    /// and annotates inserted/modified new-doc lines.
    private func buildLayoutWithChanges(
        _ rendered: [String],
        codeBlocks: [CodeBlockInfo],
        diffMap: LineDiffMap,
        oldRendered: [String],
        frontMatterRendered: [String] = []
    ) -> String {
        let roles = lineRoles(
            lineCount: rendered.count, codeBlocks: codeBlocks)
        let fmCount = frontMatterRendered.count
        let fmRoles = Self.frontMatterRoles(
            count: fmCount)

        var html = "<div class=\"down-lines\">"

        // Emit frontmatter lines (no change tracking).
        for (i, content) in frontMatterRendered.enumerated() {
            html += "<div class=\"\(fmRoles[i].cssClass)\">"
            html += "<span class=\"ln\">\(i + 1)</span>"
            html += "<span class=\"lc\">\(content)</span>"
            html += "</div>"
        }

        var inScroll = false
        var groupIdx = 0

        for (i, var content) in rendered.enumerated() {
            let lineNum = i + 1 + fmCount
            let bodyLineNum = i + 1  // 1-based body line for diff lookup
            let role = roles[i]

            // Emit deletion groups that precede this body line.
            while groupIdx < diffMap.deletionGroups.count,
                  diffMap.deletionGroups[groupIdx].beforeNewLine
                      <= bodyLineNum
            {
                emitDeletionGroup(
                    diffMap.deletionGroups[groupIdx],
                    oldRendered: oldRendered,
                    diffMap: diffMap, to: &html)
                groupIdx += 1
            }

            if role.isScrollable && !inScroll {
                html += "<div class=\"dc-scroll\">"
                inScroll = true
            }

            if let annotation = diffMap.annotation(
                forLine: bodyLineNum)
            {
                html += "<div class=\"\(role.cssClass) dl-ins\""
                html += " data-change-id=\"\(annotation.changeID)\">"
                // Word-level markers for paired insertion lines.
                if let wd = diffMap.insertionWordData(
                    for: annotation.changeID, line: bodyLineNum)
                {
                    let markers = Self.wordMarkers(
                        from: wd, forLine: bodyLineNum)
                    if !markers.isEmpty {
                        content = Self.injectMarkers(
                            into: content, markers: markers)
                    }
                }
            } else {
                html += "<div class=\"\(role.cssClass)\">"
            }

            html += "<span class=\"ln\">\(lineNum)</span>"
            html += "<span class=\"lc\">\(content)</span>"
            html += "</div>"

            if inScroll {
                let next = i + 1 < roles.count
                    ? roles[i + 1] : .regular
                if !next.isScrollable {
                    html += "</div>"
                    inScroll = false
                }
            }
        }

        // Trailing deletion groups.
        while groupIdx < diffMap.deletionGroups.count {
            emitDeletionGroup(
                diffMap.deletionGroups[groupIdx],
                oldRendered: oldRendered,
                diffMap: diffMap, to: &html)
            groupIdx += 1
        }

        html += "</div>"
        return html
    }

    /// Emits a deletion group's lines into the HTML output.
    private func emitDeletionGroup(
        _ group: DeletionGroup,
        oldRendered: [String],
        diffMap: LineDiffMap,
        to html: inout String
    ) {
        for oldLine in group.oldLineRange {
            let oldIdx = oldLine - 1
            var content = oldIdx >= 0 && oldIdx < oldRendered.count
                ? oldRendered[oldIdx] : ""
            if let wd = diffMap.deletionWordData(
                for: group.changeID, line: oldLine) {
                let markers = Self.wordMarkers(
                    from: wd, forLine: oldLine)
                if !markers.isEmpty {
                    content = Self.injectMarkers(
                        into: content, markers: markers)
                }
            }
            html += "<div class=\"dl dl-del\""
            html += " data-change-id=\"\(group.changeID)\">"
            html += "<span class=\"ln\">\u{2013}</span>"
            html += "<span class=\"lc\">\(content)</span>"
            html += "</div>"
        }
    }

    // MARK: - Word-level marker injection

    struct WordMarker {
        let start: Int   // 0-based char offset within the line
        let end: Int     // exclusive
        let tag: String  // "ins" or "del"
    }

    /// Computes character ranges to mark for a single source line
    /// within a paired block.
    private static func wordMarkers(
        from data: BlockWordData, forLine line: Int
    ) -> [WordMarker] {
        let blockLineIdx = line - data.startLine
        let sourceLines = data.sourceText.split(
            separator: "\n", omittingEmptySubsequences: false)
        guard blockLineIdx >= 0,
              blockLineIdx < sourceLines.count else { return [] }

        // Character offset of this line within the block text.
        var lineOffset = 0
        for i in 0..<blockLineIdx {
            lineOffset += sourceLines[i].count + 1  // +1 for \n
        }
        let lineLength = sourceLines[blockLineIdx].count

        var markers: [WordMarker] = []
        var pos = 0  // position within block source text

        for span in data.spans {
            switch span {
            case .unchanged(let text):
                pos += text.count
            case .inserted(let text):
                if data.isInsertion {
                    appendClipped(
                        start: pos, length: text.count, tag: "ins",
                        lineOffset: lineOffset, lineLength: lineLength,
                        to: &markers)
                    pos += text.count
                }
            case .deleted(let text):
                if !data.isInsertion {
                    appendClipped(
                        start: pos, length: text.count, tag: "del",
                        lineOffset: lineOffset, lineLength: lineLength,
                        to: &markers)
                    pos += text.count
                }
            }
        }

        // Coalesce adjacent same-type markers into single ranges.
        var coalesced: [WordMarker] = []
        for marker in markers {
            if let last = coalesced.last,
               last.end == marker.start, last.tag == marker.tag {
                coalesced[coalesced.count - 1] = WordMarker(
                    start: last.start, end: marker.end, tag: last.tag)
            } else {
                coalesced.append(marker)
            }
        }
        return coalesced
    }

    /// Clips a marker to a line's range and appends if non-empty.
    private static func appendClipped(
        start: Int, length: Int, tag: String,
        lineOffset: Int, lineLength: Int,
        to markers: inout [WordMarker]
    ) {
        let spanEnd = start + length
        let lineEnd = lineOffset + lineLength
        let clippedStart = max(start, lineOffset)
        let clippedEnd = min(spanEnd, lineEnd)
        guard clippedStart < clippedEnd else { return }
        markers.append(WordMarker(
            start: clippedStart - lineOffset,
            end: clippedEnd - lineOffset,
            tag: tag))
    }

    /// Injects `<ins>` / `<del>` tags into syntax-highlighted HTML
    /// at source character boundaries.
    ///
    /// To prevent markers from crossing HTML tag boundaries (which
    /// causes invalid nesting and layout breakage), the marker is
    /// closed before each HTML tag and reopened after it.
    // MARK: - Frontmatter line rendering

    /// Renders frontmatter lines from the original source with YAML
    /// syntax highlighting via `CodeHighlighter`.
    ///
    /// Returns an array of HTML content strings (one per
    /// frontmatter source line) ready for use in `buildLayout`.
    /// The input `markdown` should already be `\r\n`-normalized
    /// (see `ParsedMarkdown.init`).
    func renderFrontMatterLines(
        markdown: String, lineCount: Int
    ) -> [String] {
        guard lineCount > 0 else { return [] }

        let allLines = markdown.split(
            separator: "\n", omittingEmptySubsequences: false)
        guard allLines.count >= lineCount else { return [] }

        var rendered = [String]()
        rendered.reserveCapacity(lineCount)

        // First and last lines are the `---` delimiters.
        let openingDelimiter = HTMLEscaping.escape(String(allLines[0]))
        rendered.append(
            "<span class=\"md-code-fence\">\(openingDelimiter)</span>")

        // YAML content lines (between delimiters).
        if lineCount > 2 {
            let yamlLines = allLines[1..<(lineCount - 1)]
            let yamlText = yamlLines.joined(separator: "\n")

            if let highlighted = CodeHighlighter.highlight(
                yamlText, language: "yaml")
            {
                rendered += HTMLLineSplitter.splitByLine(highlighted)
            } else {
                for line in yamlLines {
                    rendered.append(HTMLEscaping.escape(String(line)))
                }
            }
        }

        // Closing delimiter.
        let closingDelimiter = HTMLEscaping.escape(
            String(allLines[lineCount - 1]))
        rendered.append(
            "<span class=\"md-code-fence\">\(closingDelimiter)</span>")

        return rendered
    }

    static func injectMarkers(
        into html: String, markers: [WordMarker]
    ) -> String {
        var result = ""
        result.reserveCapacity(html.count + markers.count * 11)
        var srcPos = 0
        var mIdx = 0
        var open = false

        var i = html.startIndex
        while i < html.endIndex {
            // HTML tag — close marker, copy tag, reopen marker.
            if html[i] == "<" {
                if open {
                    result += "</\(markers[mIdx].tag)>"
                }
                let tagStart = i
                while i < html.endIndex, html[i] != ">" {
                    i = html.index(after: i)
                }
                if i < html.endIndex { i = html.index(after: i) }
                result += html[tagStart..<i]
                if open {
                    result += "<\(markers[mIdx].tag)>"
                }
                continue
            }

            // Check marker transitions at this source position.
            if open, mIdx < markers.count,
               srcPos >= markers[mIdx].end {
                result += "</\(markers[mIdx].tag)>"
                open = false
                mIdx += 1
            }
            if !open, mIdx < markers.count,
               srcPos >= markers[mIdx].start {
                result += "<\(markers[mIdx].tag)>"
                open = true
            }

            // Emit the character (entity = one source char).
            if html[i] == "&" {
                let entityStart = i
                while i < html.endIndex, html[i] != ";" {
                    i = html.index(after: i)
                }
                if i < html.endIndex { i = html.index(after: i) }
                result += html[entityStart..<i]
            } else {
                result.append(html[i])
                i = html.index(after: i)
            }
            srcPos += 1
        }

        if open, mIdx < markers.count {
            result += "</\(markers[mIdx].tag)>"
        }

        return result
    }

}
