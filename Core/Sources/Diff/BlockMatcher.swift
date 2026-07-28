import Foundation

/// How the leaf-block collector treats footnote definitions.
///
/// Up and Down mode need opposite policies because they render definitions
/// differently: the Up visitor draws nothing for a definition (its body
/// reaches the page via the footnotes section and popovers), so a collected
/// definition change could only be misplaced; Down mode shows the raw
/// source, definitions included, so their edits must diff like any other
/// Down-mode line.
enum DefinitionDiffPolicy: Hashable, Sendable {
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
/// (see ``DefinitionDiffPolicy`` and `visitFootnoteDefinition` below).
/// It feeds `ChangePlan`.
enum BlockMatcher {
    /// Compares the leaf blocks of two documents and returns an ordered
    /// list of matches describing how blocks changed.
    static func match(
        old: CMarkDocument, new: CMarkDocument,
        definitionPolicy: DefinitionDiffPolicy = .skipAll
    ) -> [BlockMatch] {
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

/// A leaf-level block extracted from a cmark AST, carrying its
/// source text fingerprint and AST node reference. The node handle retains
/// its owning document, so blocks from the *old* document keep that tree
/// alive for deletion rendering.
struct LeafBlock {
    /// The AST node for this block.
    let markup: CMarkNode
    /// The text this block is matched on: its source, with comment tokens
    /// stripped and — for prose — cosmetic whitespace collapsed (see
    /// `normalizedProse`). Two blocks with the same fingerprint are the
    /// same block as far as change tracking is concerned.
    let fingerprint: String
    /// 1-based line number of the block's start in the source.
    let sourceLine: Int
    /// The source text of this block (substring of the original markdown).
    let sourceText: String
}

// MARK: - Leaf block collection

extension BlockMatcher {
    /// Flattens an AST into an ordered list of leaf blocks.
    static func collectLeafBlocks(
        from document: CMarkDocument,
        policy: DefinitionDiffPolicy = .skipAll
    ) -> [LeafBlock] {
        var collector = LeafBlockCollector(
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
private struct LeafBlockCollector: CMarkWalker {
    let markdown: String
    let policy: DefinitionDiffPolicy
    private let lines: [Substring]
    var blocks: [LeafBlock] = []

    init(markdown: String, policy: DefinitionDiffPolicy) {
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
            // The LeafBlock keeps the list item as its markup node
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
        blocks.append(LeafBlock(
            markup: node,
            fingerprint: Self.fingerprint(of: sourceText, kind: node.kind),
            sourceLine: line, sourceText: sourceText
        ))
    }

    private mutating func appendBlock(
        _ node: CMarkNode, fingerprint raw: String
    ) {
        let line = node.range?.lowerBound.line ?? 0
        let sourceText = extractSourceText(for: node)
        blocks.append(LeafBlock(
            markup: node,
            fingerprint: Self.fingerprint(of: raw, kind: node.kind),
            sourceLine: line, sourceText: sourceText
        ))
    }

    /// Builds a block's fingerprint from the source text it is matched on:
    /// comment tokens stripped (so gaining a comment is not a change) and,
    /// for prose, cosmetic whitespace collapsed (so re-wrapping is not one
    /// either).
    private static func fingerprint(
        of raw: String, kind: CMarkNodeKind
    ) -> String {
        let stripped = FootnoteProcessor.stripCommentTokens(raw)
        return isProse(kind) ? normalizedProse(stripped) : stripped
    }

    /// Blocks whose whitespace is cosmetic. Code and HTML blocks are
    /// excluded — there a re-indent or a moved line break is a real change.
    /// Table rows are excluded too: they come in pre-normalized by
    /// ``normalizedTableRow``, which collapses their pipe padding.
    private static func isProse(_ kind: CMarkNodeKind) -> Bool {
        switch kind {
        case .paragraph, .heading, .listItem, .taskListItem: return true
        default: return false
        }
    }

    /// Collapses cosmetic whitespace out of a prose block's fingerprint, so
    /// that re-wrapping a paragraph is not a change: a soft line break
    /// renders as a space, and a wrapping tool moves them on almost every
    /// edit. Runs of whitespace become one space, and continuation lines
    /// lose the blockquote prefix cmark strips before parsing the block's
    /// text.
    ///
    /// Two things survive on purpose, because each of them changes what
    /// renders:
    ///
    /// - The first line's own indent and prefix — the block's nesting depth
    ///   and quote depth.
    /// - A hard line break: two or more trailing spaces, which render as
    ///   `<br>`. It is marked with ``hardBreakMark`` so the collapse below
    ///   cannot erase it. The other hard-break form, a trailing backslash,
    ///   needs no mark — it is not whitespace, so it survives the collapse
    ///   as itself.
    private static func normalizedProse(_ raw: String) -> String {
        var lines = raw.split(
            separator: "\n", omittingEmptySubsequences: false)
        guard let first = lines.first else { return raw }
        let indent = first.prefix { $0 == " " || $0 == "\t" }
        for i in lines.indices.dropFirst() {
            lines[i] = lines[i].drop {
                $0 == " " || $0 == "\t" || $0 == ">"
            }
        }
        let marked = replacingMatches(
            of: hardBreakRegex, in: lines.joined(separator: "\n"),
            with: "\(hardBreakMark)\n")
        // Every run is one space by now, so the edges need no more than
        // one character trimmed off each.
        let flat = replacingMatches(
            of: whitespaceRunRegex, in: marked, with: " ")
        var collapsed = flat[...]
        if collapsed.hasPrefix(" ") { collapsed = collapsed.dropFirst() }
        if collapsed.hasSuffix(" ") { collapsed = collapsed.dropLast() }
        return String(indent) + collapsed
    }

    /// Stands in for a hard line break while the whitespace around it
    /// collapses. A control character, so no readable source carries one.
    private static let hardBreakMark = "\u{1}"

    /// The whitespace Markdown itself treats as cosmetic — ASCII only.
    /// Deliberately narrower than `\s`, which also covers a non-breaking
    /// space; that renders as itself, so it is content and stays in the
    /// fingerprint.
    private static let cosmeticWhitespace = " \t\n\u{0B}\u{0C}\r"

    /// Precompiled once — `normalizedProse` runs over every prose block of
    /// both documents on every diff.
    private static let hardBreakRegex = try? NSRegularExpression(
        pattern: " {2,}\n")
    private static let whitespaceRunRegex = try? NSRegularExpression(
        pattern: "[\(cosmeticWhitespace)]+")

    private static func replacingMatches(
        of regex: NSRegularExpression?, in s: String, with template: String
    ) -> String {
        guard let regex else { return s }
        return regex.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s),
            withTemplate: template)
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
