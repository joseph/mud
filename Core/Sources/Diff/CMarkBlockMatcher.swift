import Foundation

/// How the leaf-block collector treats footnote definitions.
///
/// Up and Down mode need opposite policies because they render definitions
/// differently: the Up visitor draws nothing for a definition (its body
/// reaches the page via the footnotes section and popovers), so a collected
/// definition change could only be misplaced; Down mode shows the raw
/// source, definitions included, so their edits must diff like any other
/// Down-mode line.
enum CMarkDefinitionDiffPolicy: Hashable, Sendable {
    /// Every definition — footnote or comment — is invisible to change
    /// tracking; the whole subtree is skipped. The Up-mode policy.
    case skipAll
    /// Comment definitions stay skipped, but plain footnote definitions
    /// are descended so their body blocks become leaf blocks. The
    /// Down-mode policy.
    case descendPlainFootnotes
}

/// Matches leaf blocks between two cmark-parsed Markdown documents (ported
/// from the swift-markdown pipeline; see
/// Doc/Plans/Archive/2026-07-single-parser-rendering.md). The algorithm —
/// fingerprint `CollectionDifference`, anchor walk, gap ordering — runs over
/// `CMarkDocument` nodes; footnote-definition handling depends on the mode
/// (see ``CMarkDefinitionDiffPolicy`` and `visitFootnoteDefinition` below).
/// It feeds `CMarkChangePlan`.
enum CMarkBlockMatcher {
    /// Compares the leaf blocks of two documents and returns an ordered
    /// list of matches describing how blocks changed.
    static func match(
        old: CMarkDocument, new: CMarkDocument,
        definitionPolicy: CMarkDefinitionDiffPolicy = .skipAll
    ) -> [CMarkBlockMatch] {
        let oldBlocks = collectLeafBlocks(from: old, policy: definitionPolicy)
        let newBlocks = collectLeafBlocks(from: new, policy: definitionPolicy)

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

// MARK: - CMarkBlockMatch enum

/// Describes the relationship between a block in the old and new documents.
enum CMarkBlockMatch {
    /// Block is unchanged between old and new.
    case unchanged(old: CMarkLeafBlock, new: CMarkLeafBlock)
    /// Block was inserted in the new document.
    case inserted(new: CMarkLeafBlock)
    /// Block was deleted from the old document.
    case deleted(old: CMarkLeafBlock)
}

// MARK: - CMarkLeafBlock

/// A leaf-level block extracted from a cmark AST, carrying its
/// source text fingerprint and AST node reference. The node handle retains
/// its owning document, so blocks from the *old* document keep that tree
/// alive for deletion rendering.
struct CMarkLeafBlock {
    /// The AST node for this block.
    let markup: CMarkNode
    /// Hash of the source text within this block's range.
    let fingerprint: String
    /// 1-based line number of the block's start in the source.
    let sourceLine: Int
    /// The source text of this block (substring of the original markdown).
    let sourceText: String
}

// MARK: - Leaf block collection

extension CMarkBlockMatcher {
    /// Flattens an AST into an ordered list of leaf blocks.
    static func collectLeafBlocks(
        from document: CMarkDocument,
        policy: CMarkDefinitionDiffPolicy = .skipAll
    ) -> [CMarkLeafBlock] {
        var collector = CMarkLeafBlockCollector(
            markdown: document.source, policy: policy)
        collector.visit(document.root)
        guard policy == .descendPlainFootnotes else { return collector.blocks }
        // cmark's footnote pass relocates every referenced definition to
        // the end of the tree in first-reference order, so definition-body
        // blocks are walked out of place. Restore source order (stably —
        // ties keep walk order) so anchor pairing and change-ID minting
        // see the document as written.
        return collector.blocks
            .enumerated()
            .sorted { ($0.element.sourceLine, $0.offset)
                    < ($1.element.sourceLine, $1.offset) }
            .map(\.element)
    }
}

/// Walks a cmark AST and collects leaf blocks: paragraphs, headings,
/// code blocks, list items, table rows, blockquote paragraphs, thematic
/// breaks, and HTML blocks.
private struct CMarkLeafBlockCollector: CMarkWalker {
    let markdown: String
    let policy: CMarkDefinitionDiffPolicy
    private let lines: [Substring]
    var blocks: [CMarkLeafBlock] = []

    init(markdown: String, policy: CMarkDefinitionDiffPolicy) {
        self.markdown = markdown
        self.policy = policy
        self.lines = markdown.split(
            separator: "\n", omittingEmptySubsequences: false)
    }

    mutating func visitParagraph(_ paragraph: CMarkNode) {
        appendBlock(paragraph)
    }

    mutating func visitHeading(_ heading: CMarkNode) {
        appendBlock(heading)
    }

    mutating func visitCodeBlock(_ codeBlock: CMarkNode) {
        appendBlock(codeBlock)
    }

    /// Definition handling follows `policy`. Comment definitions are always
    /// skipped whole — comments are invisible to change tracking everywhere,
    /// so a comment-only edit produces no change. Plain footnote definitions
    /// split by mode:
    ///
    /// - `.skipAll` (Up): skipped too. The Up visitor renders nothing for a
    ///   definition (its body reaches the page via the footnotes section),
    ///   so a collected definition change could only be misplaced. The
    ///   collector walks the raw source, where definitions survive as real
    ///   nodes, so it has to skip them here rather than rely on the parse.
    /// - `.descendPlainFootnotes` (Down): descended, so body blocks become
    ///   leaf blocks — Down mode renders the raw source, definitions
    ///   included, and their edits diff like any other line.
    mutating func visitFootnoteDefinition(_ node: CMarkNode) {
        guard policy == .descendPlainFootnotes,
              let label = node.literal,
              !FootnoteProcessor.isCommentLabel(label) else { return }
        descendInto(node)
    }

    /// Also handles `.taskListItem` via the walker's default fallback.
    mutating func visitListItem(_ listItem: CMarkNode) {
        let kids = Array(listItem.children)
        let isSimple = kids.count == 1 && kids[0].kind == .paragraph
        if !isSimple {
            // Complex list item (multiple paragraphs, tables, nested
            // lists, code blocks, etc.): descend so each child becomes
            // its own leaf block(s) via the normal visitor dispatch.
            descendInto(listItem)
        } else if listItem.parent?.listType == .ordered {
            // Ordered list items: fingerprint using the child
            // paragraph's column-aware source text so that renumbering
            // (e.g. "5. Foo" → "4. Foo") does not cause a false diff.
            // The CMarkLeafBlock keeps the list item as its markup node
            // for correct annotation keying downstream.
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

    mutating func visitBlockQuote(_ blockQuote: CMarkNode) {
        // Descend to find paragraphs inside the blockquote.
        descendInto(blockQuote)
    }

    mutating func visitTable(_ table: CMarkNode) {
        // Descend to find rows.
        descendInto(table)
    }

    mutating func visitTableHead(_ head: CMarkNode) {
        appendBlock(head, fingerprint: normalizedTableRow(head))
    }

    mutating func visitTableRow(_ row: CMarkNode) {
        appendBlock(row, fingerprint: normalizedTableRow(row))
    }

    mutating func visitThematicBreak(_ thematicBreak: CMarkNode) {
        appendBlock(thematicBreak)
    }

    mutating func visitHTMLBlock(_ html: CMarkNode) {
        appendBlock(html)
    }

    // MARK: - Helpers

    private mutating func appendBlock(_ node: CMarkNode) {
        let line = node.range?.lowerBound.line ?? 0
        let sourceText = extractSourceText(for: node)
        blocks.append(CMarkLeafBlock(
            markup: node,
            fingerprint: FootnoteProcessor.stripCommentTokens(sourceText),
            sourceLine: line, sourceText: sourceText
        ))
    }

    private mutating func appendBlock(_ node: CMarkNode, fingerprint: String) {
        let line = node.range?.lowerBound.line ?? 0
        let sourceText = extractSourceText(for: node)
        blocks.append(CMarkLeafBlock(
            markup: node,
            fingerprint: FootnoteProcessor.stripCommentTokens(fingerprint),
            sourceLine: line, sourceText: sourceText
        ))
    }

    /// Extracts the source text for a node using its source range.
    private func extractSourceText(for node: CMarkNode) -> String {
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
    private func normalizedTableRow(_ node: CMarkNode) -> String {
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
    private func extractColumnAwareSourceText(for node: CMarkNode) -> String {
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

private extension CMarkBlockMatcher {
    /// Builds the result array by processing gaps between anchors.
    /// Within each gap, deletions are emitted before insertions so
    /// that the old content precedes the new content at each position.
    static func buildResult(
        oldBlocks: [CMarkLeafBlock],
        newBlocks: [CMarkLeafBlock],
        removedOld: Set<Int>,
        insertedNew: Set<Int>,
        anchors: [(old: Int, new: Int)]
    ) -> [CMarkBlockMatch] {
        var result: [CMarkBlockMatch] = []

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
