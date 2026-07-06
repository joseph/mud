import Foundation
import Markdown

/// The single diff pass shared by every change-tracking consumer.
///
/// `DiffContext` (the Up-mode overlay), `LineDiffMap` (Down mode), and
/// `ChangeList` (the sidebar) all project from one `ChangePlan`, so the
/// decisions they must agree on are made exactly once:
///
/// - Change-ID numbering: `change-N`, minted in match order. A code-block
///   pair's line clusters mint their IDs when the pair's gap closes, after
///   every block-level ID in that gap.
/// - Pairing within a gap: deleted code blocks pair with inserted code
///   blocks by type (the i-th deleted with the i-th inserted, wherever
///   each sits in the gap); the remaining deletions and insertions pair
///   positionally.
/// - Word-level diff spans for paired blocks (Up-mode flavor: rendered
///   inline text), kept only when they pass the significance threshold.
/// - Grouping: `group-N` IDs, badge indices, positions, and each group's
///   ins/del/mix type — including one group per code-block line cluster.
struct ChangePlan {
    /// A changed block with its minted change ID.
    struct Change {
        let changeID: String
        let block: LeafBlock
    }

    /// A deletion and insertion paired within a gap. `wordSpans` is `nil`
    /// when the word-level diff fails the significance threshold.
    struct Pair {
        let deletion: Change
        let insertion: Change
        let wordSpans: [WordSpan]?
    }

    /// A code-block pair with a line-level diff. The lines carry cluster
    /// change IDs and group IDs. The `deletion` and `insertion` keep the
    /// block-level IDs minted before pairing; those IDs render nowhere
    /// but keep the counter aligned across consumers.
    struct CodeBlockPair {
        let deletion: Change
        let insertion: Change
        var lines: [CodeBlockDiff.CodeLine]
    }

    /// One insertion position in a gap, in match order: either a
    /// block-level insertion or a paired code block sitting at its
    /// insertion's position.
    enum InsertionSlot {
        case block(Change)
        case codeBlockPair(CodeBlockPair)

        /// The inserted block occupying this slot.
        var insertionBlock: LeafBlock {
            switch self {
            case .block(let change): return change.block
            case .codeBlockPair(let pair): return pair.insertion.block
            }
        }
    }

    /// A run of deletions and insertions between two unchanged anchors.
    struct Gap {
        /// Block-level deletions in match order (code-pair deletions are
        /// consumed by their pair and excluded here).
        let deletions: [Change]
        /// Insertions in match order, with paired code blocks in place.
        /// `var` so the grouping pass can write group IDs into pair lines.
        var insertionSlots: [InsertionSlot]
        /// Positional pairs among `deletions` and the block-level slots:
        /// the i-th deletion with the i-th block insertion.
        let pairs: [Pair]
        /// The unchanged block before this gap; `nil` at document start.
        let precedingAnchor: LeafBlock?
        /// The unchanged block after this gap; `nil` at document end.
        let followingAnchor: LeafBlock?
    }

    /// Gaps in document order.
    let gaps: [Gap]
    /// Group membership per change ID, including code-line clusters.
    let groupInfo: [String: GroupInfo]
    /// Deletion ↔ insertion change IDs for paired blocks.
    let pairedChangeID: [String: String]
    /// Significant word spans per paired change ID (both directions).
    let wordSpans: [String: [WordSpan]]
}

// MARK: - Construction

extension ChangePlan {
    /// Runs the pass over `BlockMatcher.match` output.
    init(matches: [BlockMatch], wordDiffThreshold: Double = 0.25) {
        var changeCounter = 0
        func nextChangeID() -> String {
            changeCounter += 1
            return "change-\(changeCounter)"
        }

        // Walk matches, accumulating each gap's deletions and insertions
        // (block IDs mint here, in match order) and closing the gap at
        // every unchanged anchor.
        var gaps: [Gap] = []
        var pendingDeletions: [Change] = []
        var pendingInsertions: [Change] = []
        var precedingAnchor: LeafBlock?

        func closeGap(followingAnchor: LeafBlock?) {
            guard !pendingDeletions.isEmpty || !pendingInsertions.isEmpty
            else { return }

            // Code-block pairing by type: the i-th deleted code block
            // with the i-th inserted one. Mermaid blocks are excluded
            // (their deletion renders as a placeholder, not lines), as
            // are pairs whose line diff finds no changed lines — both
            // stay block-level. Cluster change IDs mint now, in pair
            // order, after every block-level ID in the gap.
            let deletedCode = pendingDeletions.enumerated()
                .filter { $0.element.block.markup is CodeBlock }
            let insertedCode = pendingInsertions.enumerated()
                .filter { $0.element.block.markup is CodeBlock }

            var consumedDeletions = Set<Int>()
            var codePairs: [Int: CodeBlockPair] = [:]  // insertion index → pair

            for (del, ins) in zip(deletedCode, insertedCode) {
                let oldCB = del.element.block.markup as! CodeBlock
                let newCB = ins.element.block.markup as! CodeBlock

                let isMermaid = oldCB.language?.lowercased() == "mermaid"
                    || newCB.language?.lowercased() == "mermaid"
                if isMermaid { continue }
                guard newCB.range != nil else { continue }
                guard let raw = CodeBlockDiff.computeRaw(
                    oldCode: oldCB.code, newCode: newCB.code,
                    oldLanguage: oldCB.language,
                    newLanguage: newCB.language,
                    wordDiffThreshold: wordDiffThreshold)
                else { continue }

                var lines = raw.lines
                CodeBlockDiff.assignChangeIDs(
                    &lines, nextChangeID: nextChangeID)
                codePairs[ins.offset] = CodeBlockPair(
                    deletion: del.element, insertion: ins.element,
                    lines: lines)
                consumedDeletions.insert(del.offset)
            }

            let deletions = pendingDeletions.enumerated()
                .filter { !consumedDeletions.contains($0.offset) }
                .map(\.element)

            var insertionSlots: [InsertionSlot] = []
            var blockInsertions: [Change] = []
            for (i, ins) in pendingInsertions.enumerated() {
                if let pair = codePairs[i] {
                    insertionSlots.append(.codeBlockPair(pair))
                } else {
                    insertionSlots.append(.block(ins))
                    blockInsertions.append(ins)
                }
            }

            // Positional word pairing over the remaining blocks.
            var pairs: [Pair] = []
            for (del, ins) in zip(deletions, blockInsertions) {
                let spans = WordDiff.diff(
                    old: WordDiff.inlineText(of: del.block.markup),
                    new: WordDiff.inlineText(of: ins.block.markup))
                let significant = WordDiff.hasSignificantChanges(
                    spans, threshold: wordDiffThreshold)
                pairs.append(Pair(
                    deletion: del, insertion: ins,
                    wordSpans: significant ? spans : nil))
            }

            gaps.append(Gap(
                deletions: deletions,
                insertionSlots: insertionSlots,
                pairs: pairs,
                precedingAnchor: precedingAnchor,
                followingAnchor: followingAnchor))

            pendingDeletions.removeAll()
            pendingInsertions.removeAll()
        }

        for match in matches {
            switch match {
            case .deleted(let old):
                pendingDeletions.append(Change(
                    changeID: nextChangeID(), block: old))
            case .inserted(let new):
                pendingInsertions.append(Change(
                    changeID: nextChangeID(), block: new))
            case .unchanged(_, let new):
                closeGap(followingAnchor: new)
                precedingAnchor = new
            }
        }
        closeGap(followingAnchor: nil)

        // Grouping pass, in document order. Every gap starts a new group
        // (an unchanged anchor always separates gaps); a code-block pair
        // closes the current group and its line clusters become groups
        // of their own.
        var groupCounter = 0
        var groupInfo: [String: GroupInfo] = [:]
        var currentGroup: [(changeID: String, isDeletion: Bool)] = []

        func finalizeGroup() {
            guard !currentGroup.isEmpty else { return }
            groupCounter += 1
            let groupID = "group-\(groupCounter)"
            let hasDel = currentGroup.contains { $0.isDeletion }
            let hasIns = currentGroup.contains { !$0.isDeletion }
            let type: GroupType =
                (hasDel && hasIns) ? .mix : (hasIns ? .ins : .del)
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
                groupInfo[entry.changeID] = GroupInfo(
                    groupID: groupID, groupPos: pos,
                    groupIndex: groupCounter, type: type)
            }
            currentGroup.removeAll()
        }

        for g in gaps.indices {
            finalizeGroup()
            for del in gaps[g].deletions {
                currentGroup.append((del.changeID, true))
            }
            for s in gaps[g].insertionSlots.indices {
                switch gaps[g].insertionSlots[s] {
                case .block(let change):
                    currentGroup.append((change.changeID, false))
                case .codeBlockPair(var pair):
                    finalizeGroup()
                    var lines = pair.lines
                    CodeBlockDiff.assignGroupIDs(&lines, nextGroupID: {
                        groupCounter += 1
                        return (id: "group-\(groupCounter)",
                                index: groupCounter)
                    })
                    Self.registerClusterGroups(lines, into: &groupInfo)
                    pair.lines = lines
                    gaps[g].insertionSlots[s] = .codeBlockPair(pair)
                }
            }
        }
        finalizeGroup()

        // Pair lookup tables.
        var pairedChangeID: [String: String] = [:]
        var wordSpans: [String: [WordSpan]] = [:]
        for gap in gaps {
            for pair in gap.pairs {
                pairedChangeID[pair.deletion.changeID] = pair.insertion.changeID
                pairedChangeID[pair.insertion.changeID] = pair.deletion.changeID
                if let spans = pair.wordSpans {
                    wordSpans[pair.deletion.changeID] = spans
                    wordSpans[pair.insertion.changeID] = spans
                }
            }
        }

        self.gaps = gaps
        self.groupInfo = groupInfo
        self.pairedChangeID = pairedChangeID
        self.wordSpans = wordSpans
    }

    /// Registers a `GroupInfo` for each line cluster so the rendering
    /// layer can look up a cluster's group type by its change ID.
    private static func registerClusterGroups(
        _ lines: [CodeBlockDiff.CodeLine],
        into groupInfo: inout [String: GroupInfo]
    ) {
        var i = 0
        while i < lines.count {
            guard lines[i].annotation != .unchanged else {
                i += 1
                continue
            }
            let start = i
            while i < lines.count && lines[i].annotation != .unchanged {
                i += 1
            }
            let cluster = lines[start..<i]
            guard let changeID = cluster.first?.changeID,
                  let groupID = cluster.first?.groupID
            else { continue }
            let hasDel = cluster.contains { $0.annotation == .deleted }
            let hasIns = cluster.contains { $0.annotation == .inserted }
            groupInfo[changeID] = GroupInfo(
                groupID: groupID, groupPos: .sole,
                groupIndex: cluster.compactMap(\.groupIndex).first ?? 0,
                type: (hasDel && hasIns) ? .mix : (hasIns ? .ins : .del))
        }
    }
}

// MARK: - Summaries

extension ChangePlan {
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

    /// The sidebar summary for a deleted block. Mermaid diagrams show a
    /// placeholder, matching their rendered deletion.
    static func deletionSummary(_ block: LeafBlock) -> String {
        if let cb = block.markup as? CodeBlock,
           cb.language?.lowercased() == "mermaid" {
            return "[revised diagram]"
        }
        return blockSummary(block)
    }
}

// MARK: - Group info

/// Position of a change within its group.
enum GroupPos: String {
    case first, middle, last, sole
}

/// A group's content type, emitted as `data-group-type` so the overlay
/// JS never re-derives it from CSS classes.
enum GroupType: String {
    case ins, del, mix
}

/// Describes a change's membership in a consecutive group.
struct GroupInfo {
    /// The group identifier (e.g. "group-1").
    let groupID: String
    /// Position within the group.
    let groupPos: GroupPos
    /// 1-based group index, used for badge numbers.
    let groupIndex: Int
    /// Whether the group holds insertions, deletions, or both.
    let type: GroupType

    /// True when the group contains both deletions and insertions.
    var isMixed: Bool { type == .mix }
}

// MARK: - Cache

// @unchecked because LeafBlock wraps reference-counted Markup nodes that
// lack Sendable conformance. Safe for the same reason ParsedMarkdown is:
// the plan is immutable after construction and Markup has no mutation API.
extension ChangePlan: @unchecked Sendable {}

extension ChangePlan {
    private struct CacheKey: Equatable {
        let old: String
        let new: String
        let threshold: Double
    }

    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache:
        [(key: CacheKey, plan: ChangePlan)] = []
    private static let cacheLimit = 8

    /// Returns the plan for a (waypoint, content) pair, computing it at
    /// most once per pair. One reload asks for the same plan from the Up
    /// render, the Down render, the sidebar, and the waypoint menu; this
    /// memo (keyed by the diffed texts, LRU-bounded) makes the repeats
    /// free. `ChangeTracker` holds the texts alive between reloads, so
    /// re-renders hit the cache too.
    static func plan(
        old: ParsedMarkdown, new: ParsedMarkdown,
        wordDiffThreshold: Double = 0.25
    ) -> ChangePlan {
        let key = CacheKey(
            old: old.markdown, new: new.markdown,
            threshold: wordDiffThreshold)

        cacheLock.lock()
        if let index = cache.firstIndex(where: { $0.key == key }) {
            let entry = cache.remove(at: index)
            cache.insert(entry, at: 0)
            cacheLock.unlock()
            return entry.plan
        }
        cacheLock.unlock()

        let plan = ChangePlan(
            matches: BlockMatcher.match(old: old, new: new),
            wordDiffThreshold: wordDiffThreshold)

        cacheLock.lock()
        cache.insert((key, plan), at: 0)
        if cache.count > cacheLimit {
            cache.removeLast(cache.count - cacheLimit)
        }
        cacheLock.unlock()
        return plan
    }
}
