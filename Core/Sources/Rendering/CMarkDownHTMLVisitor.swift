import Foundation

/// Produces syntax-highlighted HTML from raw Markdown source by walking a
/// footnote-aware ``CMarkDocument`` tree and wrapping recognized nodes in
/// `<span class="md-*">` tags — the Stage 5 port of ``DownHTMLVisitor``
/// (Doc/Plans/2026-07-single-parser-rendering.md). All source text is
/// HTML-escaped in the output.
///
/// **Parallel and unwired.** The legacy `DownHTMLVisitor` still renders
/// every production document; `DownRenderingParityTests` holds this port
/// byte-identical to it until Stage 6 cuts the pipelines over. Phases 2–3
/// (per-line rendering and layout) are parser-agnostic string machinery
/// duplicated verbatim from the legacy file, matching how Stages 3–4 built
/// their ports; Phase 1 is the real port. One footnote-aware parse replaces
/// the legacy trio of `FootnoteProcessor.scan`, the definition-line
/// blanking, and the per-definition body sub-parse: references and
/// definitions arrive as AST nodes whose positions are already original
/// source coordinates, which is exactly what the deleted remap produced.
struct CMarkDownHTMLVisitor: Sendable {

    init() {}

    /// Returns a `<div class="down-lines">` container with one
    /// flex-row per source line, line numbers, syntax-highlight
    /// spans, and scrollable code-block regions.
    func highlight(
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
    /// Highlights both old and new markdown, builds a `CMarkLineDiffMap`
    /// from the change plan, and produces a layout that interleaves
    /// deleted old-doc lines and annotates inserted/modified new-doc
    /// lines. The plan should be built with the
    /// `.descendPlainFootnotes` definition policy — Down mode diffs the
    /// raw source, definitions included.
    func highlightWithChanges(
        new newMarkdown: String,
        old oldMarkdown: String,
        plan: CMarkChangePlan,
        docCAlertMode: DocCAlertMode = .extended,
        wordDiffThreshold: Double = 0.25,
        frontMatterRendered: [String] = []
    ) -> String {
        let newResult = highlightLines(
            newMarkdown, docCAlertMode: docCAlertMode)
        let oldResult = highlightLines(
            oldMarkdown, docCAlertMode: docCAlertMode)
        let diffMap = CMarkLineDiffMap(
            plan: plan,
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

        var events: [SpanEvent] = []
        var codeBlocks: [CodeBlockInfo] = []
        // A nil document only on cmark allocation failure — fall through
        // and render the raw lines unhighlighted.
        if let document = CMarkDocument(parsing: markdown) {
            var alertDetector = AlertDetector()
            alertDetector.docCAlertMode = docCAlertMode
            var collector = EventCollector(
                sourceLines: sourceLines, document: document)
            collector.alertDetector = alertDetector
            collector.visit(document.root)
            // Main-parse events first, then every reference span, then each
            // definition's marker span with its body events — the exact
            // pre-sort grouping the legacy pipeline builds by layering
            // `scan`'s spans onto the blanked parse's events (main, then
            // `layout.refs`, then per-def marker + `subParseDefBody`).
            // `SpanEvent`'s comparator has no total order and Swift's sort
            // is unstable, so this grouping is part of byte parity.
            events = collector.events
                + collector.refEvents + collector.defEvents
            codeBlocks = collector.codeBlocks
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
            events: events, codeBlocks: codeBlocks)

        return HighlightResult(
            rendered: rendered, codeBlocks: codeBlocks)
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

    private struct EventCollector: CMarkWalker {
        let sourceLines: [[UInt8]]
        let document: CMarkDocument
        var events: [SpanEvent] = []
        /// Reference spans, kept apart from `events` and `defEvents` so the
        /// pre-sort order matches the legacy pipeline's layering (see
        /// `highlightLines`): main events, then all references, then
        /// definitions.
        var refEvents: [SpanEvent] = []
        /// Definition marker spans and the events emitted while descending a
        /// definition body — grouped per definition in document order,
        /// mirroring legacy's per-def marker + `subParseDefBody` append.
        var defEvents: [SpanEvent] = []
        var codeBlocks: [CodeBlockInfo] = []
        var alertDetector = AlertDetector()

        /// Set while descending a footnote definition. Carries the
        /// geometry legacy's `subParseDefBody` used to de-indent the body
        /// before re-parsing it, so `lineDrop` can reproduce the per-line
        /// column offset its remap added back — and it doubles as the
        /// "inside a definition" flag that suppresses reference spans and
        /// code-block recording.
        private struct DefinitionContext {
            let startLine: Int
            let endLine: Int
            /// First body byte column on the opener line.
            let contentStartColumn: Int
            /// Shared continuation-line indent, capped at 4.
            let contentIndent: Int
        }
        private var definitionContext: DefinitionContext?

        init(sourceLines: [[UInt8]], document: CMarkDocument) {
            self.sourceLines = sourceLines
            self.document = document
        }

        // -- Container nodes --

        mutating func visitHeading(_ heading: CMarkNode) {
            emitContainer(heading, cssClass: "md-heading")
        }

        mutating func visitBlockQuote(_ blockQuote: CMarkNode) {
            let depth = Self.nodeDepth(blockQuote)
            if let (category, _) = alertDetector.detectGFMAlert(blockQuote) {
                emitContainer(blockQuote,
                    cssClass: "md-blockquote md-alert-\(category.rawValue)")
                emitAlertMarkers(in: blockQuote, depth: depth)
                let tag = "[!\(category.rawValue.uppercased())]"
                emitAlertTagSpan(in: blockQuote, tagLen: tag.utf8.count,
                                 depth: depth)
            } else if let docC = alertDetector.detectDocCAlert(blockQuote) {
                emitContainer(blockQuote,
                    cssClass: "md-blockquote md-alert-\(docC.category.rawValue)")
                emitAlertMarkers(in: blockQuote, depth: depth)
                // The tuple's `tagByteLength` is deliberately unused for
                // the span width (see `docCTagSpanWidth`).
                if let tagLen = Self.docCTagSpanWidth(blockQuote) {
                    emitAlertTagSpan(in: blockQuote, tagLen: tagLen,
                                     depth: depth)
                }
            } else {
                emitContainer(blockQuote, cssClass: "md-blockquote")
            }
        }

        /// Emits a 1-character `md-alert-tag` span over the `>` marker
        /// on every line of the blockquote.
        ///
        /// The column is constant in *body* coordinates: legacy emitted it
        /// from the blockquote's start column and, inside a definition
        /// body, the sub-parse remap then added each line's stripped
        /// prefix back. Reproduce that by converting the raw start column
        /// to a body column once and re-adding the per-line drop (a no-op
        /// outside definitions, where every drop is zero).
        private mutating func emitAlertMarkers(
            in blockQuote: CMarkNode, depth: Int32
        ) {
            guard let range = blockQuote.range else { return }
            let bodyCol = range.lowerBound.column
                - lineDrop(range.lowerBound.line)
            for line in range.lowerBound.line...range.upperBound.line {
                let col = bodyCol + lineDrop(line)
                emitSpan("md-alert-tag", depth: depth + 1,
                         from: (line: line, column: col),
                         to:   (line: line, column: col + 1))
            }
        }

        /// Emits a nested `md-alert-tag` span covering the tag text
        /// (e.g. `[!NOTE]` or `Note:`) on the first line of a blockquote.
        private mutating func emitAlertTagSpan(
            in blockQuote: CMarkNode, tagLen: Int, depth: Int32
        ) {
            guard let para = blockQuote.firstChild,
                  para.kind == .paragraph,
                  let textNode = para.firstChild,
                  textNode.kind == .text,
                  let range = textNode.range else { return }
            let line = range.lowerBound.line
            let col  = range.lowerBound.column
            emitSpan("md-alert-tag", depth: depth + 2,
                     from: (line: line, column: col),
                     to:   (line: line, column: col + tagLen))
        }

        /// The UTF-8 byte width of a DocC aside's tag span: the first text
        /// literal through its colon. Matches the legacy span width,
        /// `Aside.kind.rawValue.utf8.count + 1` — both measure the
        /// smart-typography-substituted literal, not source bytes — and is
        /// deliberately not `detectDocCAlert`'s `tagByteLength`, which
        /// also counts the whitespace after the colon that the legacy span
        /// excludes.
        private static func docCTagSpanWidth(
            _ blockQuote: CMarkNode
        ) -> Int? {
            guard let para = blockQuote.firstChild,
                  para.kind == .paragraph,
                  let text = para.firstChild, text.kind == .text,
                  let literal = text.literal,
                  let colon = literal.firstIndex(of: ":")
            else { return nil }
            return literal[...colon].utf8.count
        }

        mutating func visitEmphasis(_ emphasis: CMarkNode) {
            emitContainer(emphasis, cssClass: "md-emphasis")
        }

        mutating func visitStrong(_ strong: CMarkNode) {
            emitContainer(strong, cssClass: "md-strong")
        }

        mutating func visitLink(_ link: CMarkNode) {
            emitContainer(link, cssClass: "md-link")
        }

        mutating func visitImage(_ image: CMarkNode) {
            emitContainer(image, cssClass: "md-image")
        }

        mutating func visitStrikethrough(
            _ strikethrough: CMarkNode
        ) {
            emitContainer(strikethrough, cssClass: "md-strikethrough")
        }

        mutating func visitTable(_ table: CMarkNode) {
            emitContainer(table, cssClass: "md-table")
        }

        mutating func visitListItem(_ listItem: CMarkNode) {
            descendInto(listItem)
        }

        mutating func visitTaskListItem(_ listItem: CMarkNode) {
            emitContainer(listItem, cssClass: "md-task")
        }

        // -- Footnotes --

        /// An open/close `SpanEvent` pair for a footnote marker or
        /// reference at an explicit position. The high depth keeps it
        /// outermost; footnote spans never share a column with a document
        /// span, so ordering is unaffected.
        private func footnoteSpanEvents(
            _ cssClass: String, line: Int,
            openColumn: Int, closeColumn: Int
        ) -> [SpanEvent] {
            let depth: Int32 = 1_000
            return [
                SpanEvent(
                    line: Int32(line), column: Int32(openColumn),
                    isClose: false, depth: depth, cssClass: cssClass),
                SpanEvent(
                    line: Int32(line), column: Int32(closeColumn),
                    isClose: true, depth: depth, cssClass: cssClass),
            ]
        }

        /// A `[^label]` reference becomes an `md-footnote-ref` span at its
        /// verified position. Inside a definition body, nothing is emitted
        /// — legacy emits nothing there either (`scan` drops in-body
        /// references, and its body sub-parse saw them as plain text).
        /// The guards mirror `FootnoteProcessor.scan`'s byte-for-byte: a
        /// position is trusted only when it actually delimits `[^…]`.
        mutating func visitFootnoteReference(_ node: CMarkNode) {
            guard definitionContext == nil else { return }
            let geo = document.geometry
            let line = node.startLine
            let startColumn = node.startColumn
            let endColumn = node.endColumn
            guard line >= 1, line <= geo.lastLine,
                  startColumn >= 1, endColumn >= startColumn
            else { return }
            let s = geo.offset(line: line, column: startColumn)
            let e = geo.offset(line: line, column: endColumn)
            guard geo.delimitsFootnoteRef(start: s, end: e + 1)
            else { return }
            refEvents += footnoteSpanEvents(
                "md-footnote-ref", line: line,
                openColumn: startColumn, closeColumn: endColumn + 1)
        }

        /// A definition emits its `md-footnote-def` marker span, then
        /// descends so its body highlights through the normal visit
        /// methods — the single-parse replacement for legacy's body
        /// sub-parse. Body node positions are already original source
        /// coordinates (what the deleted remap produced); only explicit
        /// column arithmetic needs the definition context (see
        /// `lineDrop`). Comment definitions are handled identically —
        /// Down mode shows the raw source and draws no comment-specific
        /// structure.
        mutating func visitFootnoteDefinition(_ node: CMarkNode) {
            let geo = document.geometry
            let startLine = node.startLine
            let endLine = node.endLine
            guard startLine >= 1, endLine <= geo.lastLine,
                  endLine >= startLine,
                  let label = node.literal
            else { return }
            // cmark's definition start_column points at the *body*, not
            // the marker, so locate the `[` as the opener line's first
            // non-whitespace byte — the same math as scan's Def.
            let startColumn = geo.firstNonSpaceColumn(line: startLine)
            // `[^` + label + `]:` → label.utf8.count + 4 chars.
            let markerEndColumn = startColumn + label.utf8.count + 4
            defEvents += footnoteSpanEvents(
                "md-footnote-def", line: startLine,
                openColumn: startColumn, closeColumn: markerEndColumn)

            definitionContext = DefinitionContext(
                startLine: startLine,
                endLine: endLine,
                contentStartColumn: geo.firstContentColumn(
                    line: startLine, from: markerEndColumn),
                contentIndent: geo.continuationIndent(
                    startLine: startLine, endLine: endLine))
            descendInto(node)
            definitionContext = nil
        }

        /// The stripped-prefix byte width legacy's `subParseDefBody`
        /// removed from `line` before re-parsing — the amount its remap
        /// added back to every event column. Zero outside a definition
        /// body, so callers can apply it unconditionally.
        private func lineDrop(_ line: Int) -> Int {
            guard let def = definitionContext else { return 0 }
            let idx = line - 1
            guard idx >= 0, idx < sourceLines.count else { return 0 }
            let bytes = sourceLines[idx]
            return line == def.startLine
                ? min(def.contentStartColumn - 1, bytes.count)
                : Self.leadingWhitespace(bytes, max: def.contentIndent)
        }

        /// Count of leading whitespace bytes — space or tab, each one
        /// byte — capped at `max`. Byte-counted (never exceeds the line
        /// length) so the stripped width maps cleanly back to source
        /// columns.
        private static func leadingWhitespace(
            _ bytes: [UInt8], max cap: Int
        ) -> Int {
            var n = 0
            for b in bytes {
                if n >= cap || (b != 0x20 && b != 0x09) { break }
                n += 1
            }
            return n
        }

        // -- Leaf nodes --

        mutating func visitCodeBlock(_ codeBlock: CMarkNode) {
            guard let range = codeBlock.range else { return }
            let depth = Self.nodeDepth(codeBlock)
            let fenceLen = measureFence(at: range.lowerBound)

            // Inside a definition body, spans are emitted but the block
            // is not recorded: legacy discarded the body sub-parse's
            // `codeBlocks`, so definition-body code gets no highlight.js
            // substitution and no `dc-fence`/`dc-code` line roles.
            let inDefinition = definitionContext != nil

            if fenceLen > 0 {
                // -- Fenced code block: fence / content / fence --

                // Opening fence line. The close column is the full raw
                // line width regardless of definition context: legacy
                // measured the stripped line and its remap added the
                // stripped width back.
                emitSpan("md-code-fence", depth: depth,
                         from: (range.lowerBound.line,
                                range.lowerBound.column),
                         to: (range.lowerBound.line,
                              lineLen(range.lowerBound.line) + 1))

                // Content lines (between the fences), if any. Legacy's
                // column-1 anchors and `max(len, 1)` floor were in body
                // coordinates, so both take the per-line drop here (a
                // no-op at the top level).
                let firstContent = range.lowerBound.line + 1
                let lastContent = range.upperBound.line - 1
                var highlighted: [String] = []
                if firstContent <= lastContent {
                    let lastDrop = lineDrop(lastContent)
                    let lastLen = lineLen(lastContent) - lastDrop
                    emitSpan("md-code-block", depth: depth,
                             from: (firstContent,
                                    1 + lineDrop(firstContent)),
                             to: (lastContent,
                                  max(lastLen, 1) + 1 + lastDrop))

                    if !inDefinition,
                       let html = CodeHighlighter.highlight(
                        codeBlock.literal ?? "",
                        language: CMarkChangePlan.codeLanguage(codeBlock))
                    {
                        highlighted = HTMLLineSplitter
                            .splitByLine(html)
                    }
                }

                // Closing fence line.
                emitSpan("md-code-fence", depth: depth,
                         from: (range.upperBound.line,
                                1 + lineDrop(range.upperBound.line)),
                         to: (range.upperBound.line,
                              lineLen(range.upperBound.line) + 1))

                // Info string (language name) on the opening
                // fence, nested inside md-code-fence.
                if let lang = CMarkChangePlan.codeLanguage(codeBlock),
                   !lang.isEmpty {
                    let infoCol = range.lowerBound.column + fenceLen
                    emitSpan("md-code-info", depth: depth + 1,
                             from: (range.lowerBound.line, infoCol),
                             to: (range.lowerBound.line,
                                  infoCol + lang.utf8.count))
                }

                // Always record for layout, even when empty.
                if !inDefinition {
                    codeBlocks.append(CodeBlockInfo(
                        isFenced: true,
                        contentFirstLine: firstContent,
                        contentLastLine: lastContent,
                        highlightedLines: highlighted))
                }

            } else {
                // -- Indented code block: content only --
                let lineCount = (codeBlock.literal ?? "").lazy
                    .filter { $0 == "\n" }.count
                let lastLine = range.lowerBound.line
                    + max(lineCount, 1) - 1
                emitSpan("md-code-block", depth: depth,
                         from: (range.lowerBound.line,
                                range.lowerBound.column),
                         to: (lastLine, lineLen(lastLine) + 1))

                if !inDefinition {
                    codeBlocks.append(CodeBlockInfo(
                        isFenced: false,
                        contentFirstLine: range.lowerBound.line,
                        contentLastLine: lastLine,
                        highlightedLines: []))
                }
            }
        }

        mutating func visitInlineCode(_ inlineCode: CMarkNode) {
            emitLeaf(inlineCode, cssClass: "md-code")
        }

        mutating func visitThematicBreak(
            _ thematicBreak: CMarkNode
        ) {
            emitLeaf(thematicBreak, cssClass: "md-hr")
        }

        mutating func visitHTMLBlock(_ html: CMarkNode) {
            emitLeaf(html, cssClass: "md-html")
        }

        mutating func visitInlineHTML(_ html: CMarkNode) {
            emitLeaf(html, cssClass: "md-html")
        }

        // -- Helpers --

        /// Appends to the active event stream: `defEvents` while a
        /// definition body is being walked (so body spans stay grouped with
        /// their marker in the pre-sort order), `events` otherwise.
        private mutating func append(_ event: SpanEvent) {
            if definitionContext == nil {
                events.append(event)
            } else {
                defEvents.append(event)
            }
        }

        /// Emit open event, descend into children, emit close event.
        private mutating func emitContainer(
            _ node: CMarkNode, cssClass: String
        ) {
            guard let range = node.range else {
                descendInto(node)
                return
            }
            let depth = Self.nodeDepth(node)
            append(SpanEvent(
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
            append(SpanEvent(
                line: Int32(closeLine),
                column: Int32(closeCol),
                isClose: true,
                depth: depth,
                cssClass: cssClass
            ))
        }

        /// Emit open and close events for a leaf node (no children).
        private mutating func emitLeaf(
            _ node: CMarkNode, cssClass: String
        ) {
            guard let range = node.range else { return }
            let depth = Self.nodeDepth(node)
            append(SpanEvent(
                line: Int32(range.lowerBound.line),
                column: Int32(range.lowerBound.column),
                isClose: false,
                depth: depth,
                cssClass: cssClass
            ))
            append(SpanEvent(
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
            append(SpanEvent(
                line: Int32(open.line),
                column: Int32(open.column),
                isClose: false,
                depth: depth,
                cssClass: cssClass
            ))
            append(SpanEvent(
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

        /// Ancestor count. For definition-body nodes this runs one deeper
        /// than legacy's sub-parse depths (the `footnoteDefinition`
        /// ancestor stands in for the sub-parse's own document root, plus
        /// the real root above it) — a uniform shift within the body.
        /// That cannot change output bytes: the `SpanEvent` comparator
        /// consults depth only among events tied on (line, column,
        /// isClose), body events shift together, and the depth-1000
        /// footnote marker spans stay outermost either way.
        private static func nodeDepth(_ node: CMarkNode) -> Int32 {
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
            at location: CMarkSourceLocation
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
        diffMap: CMarkLineDiffMap,
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
        diffMap: CMarkLineDiffMap,
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
