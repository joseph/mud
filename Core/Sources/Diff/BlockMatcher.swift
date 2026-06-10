import Markdown

/// Matches leaf blocks between two parsed Markdown documents.
///
/// Flattens each AST into leaf blocks, hashes source text, and runs
/// `CollectionDifference` to classify blocks as unchanged, inserted,
/// or deleted.
enum BlockMatcher {
    /// Compares the leaf blocks of two documents and returns an ordered
    /// list of matches describing how blocks changed.
    static func match(old: ParsedMarkdown, new: ParsedMarkdown) -> [BlockMatch] {
        let oldBlocks = collectLeafBlocks(from: old)
        let newBlocks = collectLeafBlocks(from: new)

        guard !oldBlocks.isEmpty || !newBlocks.isEmpty else { return [] }

        let oldFingerprints = oldBlocks.map(\.fingerprint)
        let newFingerprints = newBlocks.map(\.fingerprint)

        let diff = newFingerprints.difference(from: oldFingerprints)

        // Classify every index.
        var removedOld = Set<Int>()  // old indices removed
        var insertedNew = Set<Int>() // new indices inserted

        for change in diff {
            switch change {
            case .remove(let offset, _, _):  removedOld.insert(offset)
            case .insert(let offset, _, _):  insertedNew.insert(offset)
            }
        }

        // Find unchanged pairs (anchors) by walking both index
        // sequences and skipping removed/inserted indices.
        var anchors: [(old: Int, new: Int)] = []
        do {
            var oi = 0, ni = 0
            while oi < oldBlocks.count && ni < newBlocks.count {
                if removedOld.contains(oi) { oi += 1; continue }
                if insertedNew.contains(ni) { ni += 1; continue }
                anchors.append((old: oi, new: ni))
                oi += 1; ni += 1
            }
        }

        // Build the result in document order, processing each gap
        // between anchors: deletions first, then insertions.
        return buildResult(
            oldBlocks: oldBlocks,
            newBlocks: newBlocks,
            removedOld: removedOld,
            insertedNew: insertedNew,
            anchors: anchors
        )
    }
}

// MARK: - BlockMatch enum

/// Describes the relationship between a block in the old and new documents.
enum BlockMatch {
    /// Block is unchanged between old and new.
    case unchanged(old: LeafBlock, new: LeafBlock)
    /// Block was inserted in the new document.
    case inserted(new: LeafBlock)
    /// Block was deleted from the old document.
    case deleted(old: LeafBlock)
}

// MARK: - LeafBlock

/// A leaf-level block extracted from a Markdown AST, carrying its
/// source text fingerprint and AST node reference.
struct LeafBlock {
    /// The AST node for this block.
    let markup: Markup
    /// Hash of the source text within this block's range.
    let fingerprint: String
    /// 1-based line number of the block's start in the source.
    let sourceLine: Int
    /// The source text of this block (substring of the original markdown).
    let sourceText: String
}

// MARK: - Leaf block collection

extension BlockMatcher {
    /// Flattens an AST into an ordered list of leaf blocks.
    static func collectLeafBlocks(from parsed: ParsedMarkdown) -> [LeafBlock] {
        var collector = LeafBlockCollector(markdown: parsed.body)
        collector.visit(parsed.document)
        return collector.blocks
    }
}

/// Walks a Markdown AST and collects leaf blocks: paragraphs, headings,
/// code blocks, list items, table rows, blockquote paragraphs, thematic
/// breaks, and HTML blocks.
private struct LeafBlockCollector: MarkupWalker {
    let markdown: String
    private let lines: [Substring]
    /// Source lines occupied by comment-definition blocks. Their leaf blocks are
    /// excluded so comments stay invisible to change tracking; empty (and free)
    /// on comment-free input.
    private let commentDefLines: Set<Int>
    var blocks: [LeafBlock] = []

    init(markdown: String) {
        self.markdown = markdown
        self.lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        self.commentDefLines = Set(
            FootnoteProcessor.commentDefinitionLineRanges(markdown).flatMap { $0 })
    }

    mutating func visitParagraph(_ paragraph: Paragraph) {
        appendBlock(paragraph)
    }

    mutating func visitHeading(_ heading: Heading) {
        appendBlock(heading)
    }

    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        appendBlock(codeBlock)
    }

    mutating func visitListItem(_ listItem: ListItem) {
        let kids = Array(listItem.children)
        let isSimple = kids.count == 1 && kids[0] is Paragraph
        if !isSimple {
            // Complex list item (multiple paragraphs, tables, nested
            // lists, code blocks, etc.): descend so each child becomes
            // its own leaf block(s) via the normal visitor dispatch.
            descendInto(listItem)
        } else if listItem.parent is OrderedList {
            // Ordered list items: fingerprint using the child
            // paragraph's column-aware source text so that renumbering
            // (e.g. "5. Foo" → "4. Foo") does not cause a false diff.
            // The LeafBlock keeps the ListItem as its markup node for
            // correct annotation keying downstream.
            var fingerprint = ""
            for child in listItem.children {
                fingerprint = extractColumnAwareSourceText(for: child)
                break
            }
            appendBlock(listItem, fingerprint: fingerprint)
        } else {
            appendBlock(listItem)
            // No descending — the list item is the leaf unit for diffing.
        }
    }

    mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
        // Descend to find paragraphs inside the blockquote.
        descendInto(blockQuote)
    }

    mutating func visitTable(_ table: Table) {
        // Descend to find rows.
        descendInto(table)
    }

    mutating func visitTableHead(_ head: Table.Head) {
        appendBlock(head, fingerprint: normalizedTableRow(head))
    }

    mutating func visitTableRow(_ row: Table.Row) {
        appendBlock(row, fingerprint: normalizedTableRow(row))
    }

    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
        appendBlock(thematicBreak)
    }

    mutating func visitHTMLBlock(_ html: HTMLBlock) {
        appendBlock(html)
    }

    // MARK: - Helpers

    private mutating func appendBlock(_ node: Markup) {
        let line = node.range?.lowerBound.line ?? 0
        guard !commentDefLines.contains(line) else { return }
        let sourceText = extractSourceText(for: node)
        blocks.append(LeafBlock(
            markup: node,
            fingerprint: FootnoteProcessor.stripCommentTokens(sourceText),
            sourceLine: line, sourceText: sourceText
        ))
    }

    private mutating func appendBlock(_ node: Markup, fingerprint: String) {
        let line = node.range?.lowerBound.line ?? 0
        guard !commentDefLines.contains(line) else { return }
        let sourceText = extractSourceText(for: node)
        blocks.append(LeafBlock(
            markup: node,
            fingerprint: FootnoteProcessor.stripCommentTokens(fingerprint),
            sourceLine: line, sourceText: sourceText
        ))
    }

    /// Extracts the source text for a node using its source range.
    private func extractSourceText(for node: Markup) -> String {
        guard let range = node.range else { return "" }
        let startLine = range.lowerBound.line  // 1-based
        let endLine = range.upperBound.line    // 1-based
        guard startLine >= 1, endLine >= startLine,
              startLine <= lines.count else { return "" }

        let clampedEnd = min(endLine, lines.count)
        var slice = lines[(startLine - 1)..<clampedEnd]
        // cmark-gfm extends the last list item's range to include
        // trailing blank lines.  Strip them so fingerprints stay
        // stable regardless of what follows the block.
        while let last = slice.last, last.allSatisfy(\.isWhitespace) {
            slice = slice.dropLast()
        }
        return slice.joined(separator: "\n")
    }

    /// Normalizes a table row's source text for fingerprinting by
    /// collapsing runs of whitespace to a single space.  GFM table
    /// cells are often padded to align pipes visually; this padding
    /// is cosmetic and should not trigger a diff.
    private func normalizedTableRow(_ node: Markup) -> String {
        let raw = extractSourceText(for: node)
        return raw.replacingOccurrences(
            of: "\\s+", with: " ",
            options: .regularExpression)
    }

    /// Extracts the source text for a node respecting column offsets.
    ///
    /// Unlike `extractSourceText`, this clips the first line at
    /// `startColumn` and the last line at `endColumn`, producing text
    /// that excludes structural prefixes like ordered-list markers.
    private func extractColumnAwareSourceText(for node: Markup) -> String {
        guard let range = node.range else { return "" }
        let startLine = range.lowerBound.line   // 1-based
        let endLine = range.upperBound.line     // 1-based
        let startCol = range.lowerBound.column  // 1-based
        let endCol = range.upperBound.column    // 1-based
        guard startLine >= 1, endLine >= startLine,
              startLine <= lines.count else { return "" }

        let clampedEnd = min(endLine, lines.count)

        if startLine == endLine {
            let line = lines[startLine - 1]
            let from = line.index(
                line.startIndex,
                offsetBy: min(startCol - 1, line.count))
            let to = line.index(
                line.startIndex,
                offsetBy: min(endCol - 1, line.count))
            return String(line[from..<to])
        }

        var parts: [Substring] = []
        // First line: clip from startColumn.
        let first = lines[startLine - 1]
        let fromIdx = first.index(
            first.startIndex,
            offsetBy: min(startCol - 1, first.count))
        parts.append(first[fromIdx...])
        // Middle lines: take in full.
        for li in startLine..<(clampedEnd - 1) {
            parts.append(lines[li])
        }
        // Last line: clip up to endColumn.
        if clampedEnd > startLine {
            let last = lines[clampedEnd - 1]
            let toIdx = last.index(
                last.startIndex,
                offsetBy: min(endCol - 1, last.count))
            parts.append(last[..<toIdx])
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Result builder

private extension BlockMatcher {
    /// Builds the result array by processing gaps between anchors.
    /// Within each gap, deletions are emitted before insertions so
    /// that the old content precedes the new content at each position.
    static func buildResult(
        oldBlocks: [LeafBlock],
        newBlocks: [LeafBlock],
        removedOld: Set<Int>,
        insertedNew: Set<Int>,
        anchors: [(old: Int, new: Int)]
    ) -> [BlockMatch] {
        var result: [BlockMatch] = []

        let boundaries =
            [(-1, -1)]
            + anchors.map { ($0.old, $0.new) }
            + [(oldBlocks.count, newBlocks.count)]

        for i in 0..<(boundaries.count - 1) {
            let (prevOld, prevNew) = boundaries[i]
            let (nextOld, nextNew) = boundaries[i + 1]

            // Emit deletions in this gap first.
            for oi in (prevOld + 1)..<nextOld
                where removedOld.contains(oi) {
                result.append(.deleted(old: oldBlocks[oi]))
            }

            // Then emit insertions.
            for ni in (prevNew + 1)..<nextNew
                where insertedNew.contains(ni) {
                result.append(.inserted(new: newBlocks[ni]))
            }

            // Emit the anchor (skip the terminal sentinel).
            if i + 1 < boundaries.count - 1 {
                result.append(.unchanged(
                    old: oldBlocks[nextOld], new: newBlocks[nextNew]))
            }
        }

        return result
    }
}
