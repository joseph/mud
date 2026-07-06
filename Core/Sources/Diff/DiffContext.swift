import Markdown

/// Bridge between the diff engine and the rendering visitors.
///
/// Built from two `ParsedMarkdown` values. Provides annotation lookups
/// for AST nodes (used during rendering) and pre-rendered HTML for
/// deleted blocks.
struct DiffContext {
    private let annotations: [SourceKey: AnnotationEntry]
    private let precedingDeletionMap: [SourceKey: [RenderedDeletion]]
    private let followingDeletionMap: [SourceKey: [RenderedDeletion]]
    private let _trailingDeletions: [RenderedDeletion]
    private let _groupMap: [String: GroupInfo]
    private let _pairMap: [String: String]
    private let _codeBlockDiffMap: [SourceKey: CodeBlockDiff]

    /// Creates a diff context by matching blocks between old and new documents.
    init(old: ParsedMarkdown, new: ParsedMarkdown,
         wordDiffThreshold: Double = 0.25) {
        let matches = BlockMatcher.match(old: old, new: new)

        var annotations: [SourceKey: AnnotationEntry] = [:]
        var precedingMap: [SourceKey: [RenderedDeletion]] = [:]
        var followingMap: [SourceKey: [RenderedDeletion]] = [:]
        var trailing: [RenderedDeletion] = []

        // Assign change IDs and build lookup tables.
        var changeCounter = 0

        func nextChangeID() -> String {
            changeCounter += 1
            return "change-\(changeCounter)"
        }

        // Track change IDs in document order for the grouping pass.
        struct ChangeEntry {
            let changeID: String
            let isDeletion: Bool
            let isConsecutive: Bool
        }
        // Replaces a paired code block's del+ins entries so the
        // grouping pass can assign group IDs in document order.
        struct CodeBlockMarker { let sourceKey: SourceKey }
        enum ChangeItem {
            case entry(ChangeEntry)
            case codeBlock(CodeBlockMarker)
        }
        var changeItems: [ChangeItem] = []
        var lastWasChange = false

        // Track deletions and insertions per gap for positional
        // pairing. Within each gap, buildResult emits all deletions
        // before all insertions. The i-th deletion pairs with the
        // i-th insertion.
        struct PendingBlock {
            let changeID: String
            let block: LeafBlock
        }
        var pendingDeletions: [PendingBlock] = []
        var pendingInsertions: [PendingBlock] = []
        var deletionFlushTarget: SourceKey?
        var lastUnchangedKey: SourceKey?
        var pairMap: [String: String] = [:]
        var wordSpanMap: [String: [WordSpan]] = [:]
        var codeBlockDiffMap: [SourceKey: CodeBlockDiff] = [:]
        var rawCodeBlockDiffs: [SourceKey: CodeBlockDiff.RawDiff] = [:]
        var groupCounter = 0

        /// Finalizes the current gap: pairs deletions with insertions,
        /// computes word spans, renders deletions (with word spans
        /// now available), and flushes them into the preceding map.
        func finalizeGap() {
            // Scan paired blocks for code block pairs that need
            // line-level diff or mermaid suppression. Process these
            // before normal pairing so they can be removed from the
            // pending lists.
            processCodeBlockPairs()

            // Pair and compute word spans.
            for (del, ins) in zip(pendingDeletions, pendingInsertions) {
                pairMap[del.changeID] = ins.changeID
                pairMap[ins.changeID] = del.changeID

                let spans = WordDiff.diff(
                    old: WordDiff.inlineText(of: del.block.markup),
                    new: WordDiff.inlineText(of: ins.block.markup))
                let hasWordChanges = WordDiff.hasSignificantChanges(
                    spans, threshold: wordDiffThreshold)
                if hasWordChanges {
                    wordSpanMap[del.changeID] = spans
                    wordSpanMap[ins.changeID] = spans
                }
            }

            // Render deletions and flush to preceding map or trailing.
            // Also store in following map keyed by the last unchanged
            // block before this gap, so the rendering visitor can
            // reclaim deletions that logically follow a table body.
            if !pendingDeletions.isEmpty {
                let rendered = pendingDeletions.map {
                    Self.renderedDeletion(
                        for: $0.block, changeID: $0.changeID,
                        wordSpans: wordSpanMap[$0.changeID])
                }
                if let key = deletionFlushTarget {
                    precedingMap[key] = rendered
                } else {
                    trailing += rendered
                }
                if let key = lastUnchangedKey {
                    followingMap[key] = rendered
                }
            }

            pendingDeletions.removeAll()
            pendingInsertions.removeAll()
            deletionFlushTarget = nil
        }

        /// Scans the gap for code block pairs by matching CodeBlock
        /// deletions to CodeBlock insertions (regardless of position).
        /// For each matched pair:
        /// - Mermaid: suppress deletion, keep insertion block-level.
        /// - Other: compute line-level diff. If successful, store in
        ///   codeBlockDiffMap and remove block-level entries. If no
        ///   line changes, leave as normal block-level pair.
        func processCodeBlockPairs() {
            // Find CodeBlock insertions and deletions.
            var cbIns: [(at: Int, pending: PendingBlock)] = []
            for (i, ins) in pendingInsertions.enumerated() {
                if ins.block.markup is CodeBlock {
                    cbIns.append((at: i, pending: ins))
                }
            }
            guard !cbIns.isEmpty else { return }

            var cbDel: [(at: Int, pending: PendingBlock)] = []
            for (i, del) in pendingDeletions.enumerated() {
                if del.block.markup is CodeBlock {
                    cbDel.append((at: i, pending: del))
                }
            }
            guard !cbDel.isEmpty else { return }

            // Pair the i-th CodeBlock deletion with the i-th
            // CodeBlock insertion.
            var delIndicesToRemove: [Int] = []
            var insIndicesToRemove: [Int] = []

            for (del, ins) in zip(cbDel, cbIns) {
                let oldCB = del.pending.block.markup as! CodeBlock
                let newCB = ins.pending.block.markup as! CodeBlock

                let isMermaid = oldCB.language?.lowercased() == "mermaid"
                    || newCB.language?.lowercased() == "mermaid"

                // Mermaid: skip line-level diff, let normal
                // block-level del+ins pairing handle it.
                if isMermaid { continue }

                guard let insKey = sourceKey(for: newCB)
                else { continue }

                let raw = CodeBlockDiff.computeRaw(
                    oldCode: oldCB.code,
                    newCode: newCB.code,
                    oldLanguage: oldCB.language,
                    newLanguage: newCB.language,
                    wordDiffThreshold: wordDiffThreshold)

                guard let raw else { continue }

                // Mint cluster change IDs now, at gap-finalization
                // time, so the numbering matches LineDiffMap's (Down
                // mode). Group IDs are assigned in document order
                // during the grouping pass.
                var rawLines = raw.lines
                CodeBlockDiff.assignChangeIDs(
                    &rawLines, nextChangeID: { nextChangeID() })
                rawCodeBlockDiffs[insKey] =
                    CodeBlockDiff.RawDiff(lines: rawLines)

                // Remove block-level annotation for the insertion.
                annotations.removeValue(forKey: insKey)

                // Replace the del+ins change items with a single
                // code block marker so the grouping pass assigns
                // IDs in document order. The marker takes the
                // insertion's position (document order).
                let delID = del.pending.changeID
                let insID = ins.pending.changeID

                if let insIdx = changeItems.firstIndex(where: {
                    if case .entry(let e) = $0 {
                        return e.changeID == insID
                    }
                    return false
                }) {
                    changeItems[insIdx] = .codeBlock(
                        CodeBlockMarker(sourceKey: insKey))
                }
                changeItems.removeAll {
                    if case .entry(let e) = $0 {
                        return e.changeID == delID
                    }
                    return false
                }

                delIndicesToRemove.append(del.at)
                insIndicesToRemove.append(ins.at)
            }

            // Remove processed pairs from pending lists (reverse
            // order to preserve indices).
            for i in delIndicesToRemove.sorted().reversed() {
                pendingDeletions.remove(at: i)
            }
            for i in insIndicesToRemove.sorted().reversed() {
                pendingInsertions.remove(at: i)
            }
        }

        for match in matches {
            switch match {
            case .unchanged(_, let new):
                // Set flush target for any pending deletions that
                // haven't been claimed by an insertion.
                if !pendingDeletions.isEmpty && deletionFlushTarget == nil {
                    deletionFlushTarget = sourceKey(for: new.markup)
                }
                finalizeGap()
                lastUnchangedKey = sourceKey(for: new.markup)
                lastWasChange = false

            case .inserted(let new):
                // First block after pending deletions becomes
                // the flush target.
                if !pendingDeletions.isEmpty && deletionFlushTarget == nil {
                    deletionFlushTarget = sourceKey(for: new.markup)
                }
                let id = nextChangeID()
                if let key = sourceKey(for: new.markup) {
                    annotations[key] = AnnotationEntry(
                        annotation: .inserted, changeID: id)
                }
                pendingInsertions.append(PendingBlock(
                    changeID: id, block: new))
                changeItems.append(.entry(ChangeEntry(
                    changeID: id, isDeletion: false,
                    isConsecutive: lastWasChange)))
                lastWasChange = true

            case .deleted(let old):
                let id = nextChangeID()
                pendingDeletions.append(PendingBlock(
                    changeID: id, block: old))
                changeItems.append(.entry(ChangeEntry(
                    changeID: id, isDeletion: true,
                    isConsecutive: lastWasChange)))
                lastWasChange = true
            }
        }

        // Finalize any trailing gap (renders trailing deletions).
        finalizeGap()

        // Attach word spans to annotations created before gap
        // processing computed them.
        for (key, entry) in annotations {
            guard entry.wordSpans == nil,
                  let spans = wordSpanMap[entry.changeID]
            else { continue }
            annotations[key] = AnnotationEntry(
                annotation: entry.annotation,
                changeID: entry.changeID,
                wordSpans: spans)
        }

        // Grouping pass: break change items into groups at
        // non-consecutive boundaries. Code block markers get their
        // own group IDs assigned to their line groups.
        var groupMap: [String: GroupInfo] = [:]
        var currentGroup: [ChangeEntry] = []

        func finalizeGroup() {
            guard !currentGroup.isEmpty else { return }
            groupCounter += 1
            let groupID = "group-\(groupCounter)"
            let hasDel = currentGroup.contains { $0.isDeletion }
            let hasIns = currentGroup.contains { !$0.isDeletion }
            let isMixed = hasDel && hasIns
            let count = currentGroup.count
            for (i, entry) in currentGroup.enumerated() {
                let pos: GroupPos
                if count == 1 {
                    pos = .sole
                } else if i == 0 {
                    pos = .first
                } else if i == count - 1 {
                    pos = .last
                } else {
                    pos = .middle
                }
                groupMap[entry.changeID] = GroupInfo(
                    groupID: groupID, groupPos: pos,
                    groupIndex: groupCounter, isMixed: isMixed)
            }
            currentGroup.removeAll()
        }

        for item in changeItems {
            switch item {
            case .entry(let entry):
                if !entry.isConsecutive && !currentGroup.isEmpty {
                    finalizeGroup()
                }
                currentGroup.append(entry)

            case .codeBlock(let marker):
                // Code block boundary always breaks block-level groups.
                finalizeGroup()

                // Assign group IDs to the raw code block diff's line
                // clusters (change IDs were minted at gap time).
                if let raw = rawCodeBlockDiffs[marker.sourceKey] {
                    var lines = raw.lines
                    CodeBlockDiff.assignGroupIDs(
                        &lines,
                        nextGroupID: {
                            groupCounter += 1
                            return (id: "group-\(groupCounter)",
                                    index: groupCounter)
                        })
                    codeBlockDiffMap[marker.sourceKey] =
                        CodeBlockDiff(lines: lines)
                }
            }
        }
        finalizeGroup()

        self.annotations = annotations
        self.precedingDeletionMap = precedingMap
        self.followingDeletionMap = followingMap
        self._trailingDeletions = trailing
        self._groupMap = groupMap
        self._pairMap = pairMap
        self._codeBlockDiffMap = codeBlockDiffMap
    }

    // MARK: - Public API

    /// Returns the annotation for a block in the new AST, or `nil` if unchanged.
    func annotation(for node: Markup) -> BlockAnnotation? {
        guard let key = sourceKey(for: node) else { return nil }
        return annotations[key]?.annotation
    }

    /// Returns the change ID for a block in the new AST, or `nil` if unchanged.
    func changeID(for node: Markup) -> String? {
        guard let key = sourceKey(for: node) else { return nil }
        return annotations[key]?.changeID
    }

    /// Returns pre-rendered deleted blocks that should appear before
    /// the given node.
    func precedingDeletions(before node: Markup) -> [RenderedDeletion] {
        guard let key = sourceKey(for: node) else { return [] }
        return precedingDeletionMap[key] ?? []
    }

    /// Returns pre-rendered deleted blocks that follow the given node
    /// (i.e. deletions in the gap after this unchanged block).
    func followingDeletions(after node: Markup) -> [RenderedDeletion] {
        guard let key = sourceKey(for: node) else { return [] }
        return followingDeletionMap[key] ?? []
    }

    /// Returns pre-rendered deleted blocks that appear after the last
    /// surviving block (or all deletions when the new document is empty).
    func trailingDeletions() -> [RenderedDeletion] {
        _trailingDeletions
    }

    /// Returns group info for a change ID, or `nil` if unknown.
    func groupInfo(for changeID: String) -> GroupInfo? {
        _groupMap[changeID]
    }

    /// Returns the change ID of the block paired with the given change ID
    /// (deletion ↔ insertion), or `nil` if the block is unpaired.
    func pairedChangeID(for changeID: String) -> String? {
        _pairMap[changeID]
    }

    /// Returns word-level diff spans for a block in the new AST,
    /// or `nil` if the block is unpaired or has divergent structure.
    func wordSpans(for node: Markup) -> [WordSpan]? {
        guard let key = sourceKey(for: node) else { return nil }
        return annotations[key]?.wordSpans
    }

    /// Returns a line-level diff for a code block in the new AST,
    /// or `nil` if the block is not a diffed code block pair.
    func codeBlockDiff(for node: Markup) -> CodeBlockDiff? {
        guard let key = sourceKey(for: node) else { return nil }
        return _codeBlockDiffMap[key]
    }
}

// MARK: - Block annotation

/// The type of change for a block in the new document.
enum BlockAnnotation: Equatable {
    case inserted
}

// MARK: - Group info

/// Position of a change within its group.
enum GroupPos: String {
    case first, middle, last, sole
}

/// Describes a change's membership in a consecutive group.
struct GroupInfo {
    /// The group identifier (e.g. "group-1").
    let groupID: String
    /// Position within the group.
    let groupPos: GroupPos
    /// 1-based group index, used for badge numbers.
    let groupIndex: Int
    /// True when the group contains both deletions and insertions.
    let isMixed: Bool
}

// MARK: - Rendered deletion

/// A pre-rendered deleted block, ready for injection into the HTML output.
struct RenderedDeletion {
    /// The inner HTML content of the deleted block (no outer tag).
    let html: String
    /// The change ID matching the sidebar entry.
    let changeID: String
    /// Plain-text summary of the deleted content (for the sidebar).
    let summary: String
    /// The native HTML tag for this block (e.g. "p", "li", "tr", "pre").
    let tag: String
    /// Word-level diff spans when this deletion is paired with an insertion.
    /// `nil` when unpaired or when inline structure diverges.
    let wordSpans: [WordSpan]?
    /// Extra CSS classes to add to the outer tag (e.g. alert classes).
    let extraClasses: String?

    init(
        html: String, changeID: String, summary: String, tag: String,
        wordSpans: [WordSpan]? = nil, extraClasses: String? = nil
    ) {
        self.html = html
        self.changeID = changeID
        self.summary = summary
        self.tag = tag
        self.wordSpans = wordSpans
        self.extraClasses = extraClasses
    }
}

// MARK: - Source key

/// A hashable key derived from a Markup node's source range,
/// used to look up annotations by AST node.
private struct SourceKey: Hashable {
    let startLine: Int
    let startColumn: Int
    let endLine: Int
    let endColumn: Int
}

private func sourceKey(for node: Markup) -> SourceKey? {
    guard let range = node.range else { return nil }
    return SourceKey(
        startLine: range.lowerBound.line,
        startColumn: range.lowerBound.column,
        endLine: range.upperBound.line,
        endColumn: range.upperBound.column
    )
}

// MARK: - Annotation entry

private struct AnnotationEntry {
    let annotation: BlockAnnotation
    let changeID: String
    let wordSpans: [WordSpan]?

    init(
        annotation: BlockAnnotation, changeID: String,
        wordSpans: [WordSpan]? = nil
    ) {
        self.annotation = annotation
        self.changeID = changeID
        self.wordSpans = wordSpans
    }
}

// MARK: - Block rendering

extension DiffContext {
    /// The native HTML tag for a leaf block.
    static func tagForBlock(_ markup: Markup) -> String {
        switch markup {
        case let h as Heading:             return "h\(h.level)"
        case is Paragraph:                 return "p"
        case is CodeBlock:                 return "pre"
        case is ListItem:                  return "li"
        case is Table.Head, is Table.Row:  return "tr"
        case is ThematicBreak:             return "hr"
        default:                           return "div"
        }
    }

    /// Builds a `RenderedDeletion` for a leaf block: renders inner HTML
    /// and extracts a plain-text summary. The `tag` field records the
    /// native element type; `html` contains only inner content.
    /// When `wordSpans` is provided, the deletion's inner HTML is
    /// rendered with word-level `<del>` markers for the red block.
    static func renderedDeletion(
        for block: LeafBlock, changeID: String,
        wordSpans: [WordSpan]? = nil
    ) -> RenderedDeletion {
        let markup = block.markup

        // If the paragraph is inside an alert-style blockquote,
        // render the deletion as a full alert with proper styling.
        if let blockQuote = markup.parent as? BlockQuote,
           let (alertHTML, category) =
               UpHTMLVisitor.renderAlertInnerHTML(
                   blockQuote, wordSpans: wordSpans) {
            return RenderedDeletion(
                html: alertHTML, changeID: changeID,
                summary: blockSummary(block), tag: "blockquote",
                wordSpans: wordSpans,
                extraClasses: "alert \(category.cssClass)")
        }

        let tag = tagForBlock(markup)
        let html: String

        // Mermaid diagrams: show placeholder instead of raw source.
        if let cb = markup as? CodeBlock,
           cb.language?.lowercased() == "mermaid" {
            html = "<code><em>[revised diagram]</em></code>"
            return RenderedDeletion(
                html: html, changeID: changeID,
                summary: "[revised diagram]", tag: tag)
        }

        if let wordSpans, !wordSpans.isEmpty {
            html = UpHTMLVisitor.renderWithWordSpans(
                markup, spans: wordSpans, role: .deletion)
        } else {
            switch markup {
            case let cb as CodeBlock:
                html = UpHTMLVisitor.codeBlockInnerHTML(cb)
            case is ThematicBreak:
                html = ""
            case let hb as HTMLBlock:
                html = hb.rawHTML
            default:
                var visitor = UpHTMLVisitor()
                for child in markup.children { visitor.visit(child) }
                html = visitor.result
            }
        }

        return RenderedDeletion(
            html: html, changeID: changeID,
            summary: blockSummary(block), tag: tag,
            wordSpans: wordSpans
        )
    }

    /// Extracts a plain-text summary (~60 chars) from a leaf block.
    ///
    /// Strips markdown syntax (list markers, code fences, emphasis) so the
    /// sidebar shows clean, readable text.
    static func blockSummary(_ block: LeafBlock) -> String {
        let raw: String
        if block.markup is Paragraph || block.markup is Heading {
            raw = WordDiff.inlineText(of: block.markup)
        } else if let codeBlock = block.markup as? CodeBlock {
            raw = codeBlock.code
                .split(separator: "\n", maxSplits: 1,
                       omittingEmptySubsequences: false)
                .first.map(String.init) ?? ""
        } else if let listItem = block.markup as? ListItem,
                  let para = listItem.children
                      .first(where: { $0 is Paragraph }) as? Paragraph {
            raw = WordDiff.inlineText(of: para)
        } else {
            raw = block.sourceText
        }
        let text = raw
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard text.count > 60 else { return text }
        let prefix = text.prefix(60)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }
}
