import Foundation
import Markdown

/// Produces syntax-highlighted HTML from raw Markdown source by
/// walking the swift-markdown AST and wrapping recognized nodes in
/// `<span class="md-*">` tags.  All source text is HTML-escaped in
/// the output.
public struct DownHTMLVisitor: Sendable {

    public init() {}

    /// Returns a complete `<table class="down-lines">` with one row
    /// per source line, line-number cells, and syntax-highlight spans.
    public func highlightAsTable(_ markdown: String) -> String {
        let doc = MarkdownParser.parse(markdown)
        let sourceLines = markdown.split(
            separator: "\n", omittingEmptySubsequences: false
        ).map { Array($0.utf8) }

        var collector = EventCollector(sourceLines: sourceLines)
        collector.visit(doc)
        var events = collector.events
        events.sort()
        return applyEventsAsTable(
            events, codeBlocks: collector.codeBlocks,
            to: markdown)
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
        let contentFirstLine: Int
        let contentLastLine: Int
        let highlightedLines: [String]
    }

    // MARK: - Phase 1: Collect events from the AST

    private struct EventCollector: MarkupWalker {
        let sourceLines: [[UInt8]]
        var events: [SpanEvent] = []
        var codeBlocks: [CodeBlockInfo] = []

        // -- Container nodes --

        mutating func visitHeading(_ heading: Heading) {
            emitContainer(heading, cssClass: "md-heading")
        }

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
            emitContainer(blockQuote, cssClass: "md-blockquote")
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
                        codeBlocks.append(CodeBlockInfo(
                            contentFirstLine: firstContent,
                            contentLastLine: lastContent,
                            highlightedLines:
                                HTMLLineSplitter
                                    .splitByLine(html)))
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
            events.append(SpanEvent(
                line: Int32(range.upperBound.line),
                column: Int32(range.upperBound.column) + 1,
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
                column: Int32(range.upperBound.column) + 1,
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

    // MARK: - Phase 2: Apply events as table rows

    private func applyEventsAsTable(
        _ events: [SpanEvent],
        codeBlocks: [CodeBlockInfo],
        to markdown: String
    ) -> String {
        let lines = markdown.split(
            separator: "\n", omittingEmptySubsequences: false)
        let lineCount = markdown.hasSuffix("\n") && !lines.isEmpty
            ? lines.count - 1
            : max(lines.count, 1)

        var result = "<table class=\"down-lines\"><tbody>"
        var openSpans: [String] = []
        var ei = 0

        for lineIdx in 0..<lineCount {
            let lineNum = Int32(lineIdx + 1)

            // Open row.
            result += "<tr><td class=\"ln\">"
            result += "\(lineIdx + 1)</td><td class=\"lc\">"

            // Reopen spans carried from the previous row.
            for cls in openSpans {
                result += "<span class=\"\(cls)\">"
            }

            // Emit line content — highlighted or escaped.
            if let highlighted = self.highlightedLine(
                lineNum, codeBlocks: codeBlocks)
            {
                // Process span events at line start (e.g.
                // md-code-block open) before the content.
                while ei < events.count,
                      events[ei].line == lineNum,
                      events[ei].column <= 1
                {
                    emitTag(events[ei], to: &result,
                            openSpans: &openSpans)
                    ei += 1
                }
                result += highlighted
            } else if lineIdx < lines.count {
                emitLineContent(
                    lines[lineIdx], lineNum: lineNum,
                    events: events, ei: &ei,
                    result: &result, openSpans: &openSpans)
            }

            // Flush events past end of visible content (close tags).
            while ei < events.count, events[ei].line == lineNum {
                emitTag(events[ei], to: &result,
                        openSpans: &openSpans)
                ei += 1
            }

            // Close all open spans at the row boundary.
            for _ in openSpans { result += "</span>" }

            result += "</td></tr>"
        }

        result += "</tbody></table>"
        return result
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
            if n >= cb.contentFirstLine,
               n <= cb.contentLastLine
            {
                let idx = n - cb.contentFirstLine
                return idx < cb.highlightedLines.count
                    ? cb.highlightedLines[idx] : nil
            }
        }
        return nil
    }

}
