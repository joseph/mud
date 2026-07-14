/// Projects a `CMarkChangePlan` into a flat list of document changes for the
/// sidebar — the port of the old swift-markdown `ChangeList`
/// (Doc/Plans/2026-07-single-parser-rendering.md). Its output model
/// (`DocumentChange` / `ChangeType`, defined below) and the downstream grouping
/// (`ChangeGroup.build(from:)`) carry no node references, so they are shared,
/// parser-agnostic value types — they moved here from the legacy list when it
/// was deleted at the Stage 6 cutover. The code-block projection and
/// HTML-summary helpers live here for the same reason.
enum CMarkChangeList {
    /// Computes a list of changes between old and new documents.
    static func computeChanges(
        old: CMarkDocument, new: CMarkDocument
    ) -> [DocumentChange] {
        computeChanges(plan: CMarkChangePlan.plan(old: old, new: new))
    }

    /// Projects the plan's gaps, in document order. Within a gap,
    /// deletions come first (they attach to the block they precede),
    /// then insertions and code-block pairs in document order.
    static func computeChanges(plan: CMarkChangePlan) -> [DocumentChange] {
        var changes: [DocumentChange] = []
        var sawUnchangedSinceLastChange = true
        var lastSurvivingLine = 1

        for gap in plan.gaps {
            // Deletions attach to the first block after them: an
            // insertion in the same gap, else the following anchor.
            // Trailing deletions fall back to the last surviving line.
            let hostLine = gap.insertionSlots.first?.insertionBlock.sourceLine
                ?? gap.followingAnchor?.sourceLine
                ?? gap.precedingAnchor?.sourceLine
                ?? lastSurvivingLine

            for del in gap.deletions {
                let consecutive = !changes.isEmpty
                    && !sawUnchangedSinceLastChange
                let info = plan.groupInfo[del.changeID]
                changes.append(DocumentChange(
                    id: del.changeID,
                    type: .deletion,
                    summary: CMarkChangePlan.deletionSummary(del.block),
                    sourceLine: hostLine,
                    isConsecutive: consecutive,
                    groupID: info?.groupID ?? "",
                    groupIndex: info?.groupIndex ?? 0,
                    isMixed: info?.isMixed ?? false
                ))
                sawUnchangedSinceLastChange = false
            }

            for slot in gap.insertionSlots {
                switch slot {
                case .block(let change):
                    let consecutive = !changes.isEmpty
                        && !sawUnchangedSinceLastChange
                    let info = plan.groupInfo[change.changeID]
                    changes.append(DocumentChange(
                        id: change.changeID,
                        type: .insertion,
                        summary: CMarkChangePlan.blockSummary(change.block),
                        sourceLine: change.block.sourceLine,
                        isConsecutive: consecutive,
                        groupID: info?.groupID ?? "",
                        groupIndex: info?.groupIndex ?? 0,
                        isMixed: info?.isMixed ?? false
                    ))
                    sawUnchangedSinceLastChange = false
                    lastSurvivingLine = change.block.sourceLine

                case .codeBlockPair(let pair):
                    Self.emitCodeBlockChanges(
                        pair.lines,
                        sourceLine: pair.insertion.block.sourceLine,
                        changes: &changes,
                        sawUnchangedSinceLastChange:
                            &sawUnchangedSinceLastChange)
                    lastSurvivingLine = pair.insertion.block.sourceLine
                }
            }

            if let anchor = gap.followingAnchor {
                sawUnchangedSinceLastChange = true
                lastSurvivingLine = anchor.sourceLine
            }
        }

        return changes
    }

    /// Emits `DocumentChange` entries for each changed line in a code block
    /// pair. Lines sharing a change ID are grouped by the sidebar into a single
    /// `ChangeGroup` with per-line summaries. Node-type-free, so it is shared
    /// diff-list machinery rather than anything cmark-specific.
    private static func emitCodeBlockChanges(
        _ lines: [CodeBlockDiff.CodeLine], sourceLine: Int,
        changes: inout [DocumentChange],
        sawUnchangedSinceLastChange: inout Bool
    ) {
        var currentChangeID: String?

        for line in lines {
            guard let changeID = line.changeID,
                  let groupID = line.groupID
            else {
                // Unchanged line — breaks consecutive run.
                currentChangeID = nil
                sawUnchangedSinceLastChange = true
                continue
            }

            let isNewGroup = changeID != currentChangeID
            currentChangeID = changeID

            let type: ChangeType = line.annotation == .deleted
                ? .deletion : .insertion
            let consecutive = !changes.isEmpty
                && !sawUnchangedSinceLastChange
            changes.append(DocumentChange(
                id: changeID,
                type: type,
                summary: summaryFromHTML(line.highlightedHTML),
                sourceLine: sourceLine,
                isConsecutive: isNewGroup ? consecutive : true,
                groupID: groupID,
                groupIndex: line.groupIndex ?? 0,
                isMixed: false
            ))
            sawUnchangedSinceLastChange = false
        }
    }

    /// Strips HTML tags and entities, truncates to ~60 characters.
    private static func summaryFromHTML(_ html: String) -> String {
        let text = html
            .replacingOccurrences(
                of: "<[^>]+>", with: "",
                options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespaces)
        guard text.count > 60 else { return text }
        let prefix = text.prefix(60)
        if let lastSpace = prefix.lastIndex(of: " ") {
            return String(prefix[prefix.startIndex..<lastSpace]) + "…"
        }
        return String(prefix) + "…"
    }
}

// MARK: - DocumentChange

/// A single change entry for the sidebar list. `Equatable` so the diff-layer
/// parity tests can compare projections directly. A shared, parser-agnostic
/// value type (formerly inline in the legacy `ChangeList`).
public struct DocumentChange: Identifiable, Sendable, Equatable {
    public let id: String
    public let type: ChangeType
    public let summary: String
    public let sourceLine: Int
    /// True when this change immediately follows the previous change
    /// with no unchanged block between them. Always false for the first
    /// change. Used by the sidebar to group consecutive changes.
    public let isConsecutive: Bool
    /// The group this change belongs to (e.g. "group-1").
    public let groupID: String
    /// 1-based group index, used for badge numbering.
    public let groupIndex: Int
    /// True when the group contains both deletions and insertions
    /// (from the change plan), even if only one type is emitted as a
    /// DocumentChange (e.g. mermaid replacements suppress the deletion).
    public let isMixed: Bool
}

/// The type of a document change.
public enum ChangeType: Sendable, Equatable {
    case insertion
    case deletion
}
