/// Projects a `CMarkChangePlan` into a flat list of document changes — the
/// Stage 4 port of ``ChangeList``
/// (Doc/Plans/2026-07-single-parser-rendering.md). The output types
/// (`DocumentChange`, `ChangeType`) and the downstream grouping
/// (`ChangeGroup.build(from:)`) are the legacy ones, unchanged: they carry
/// no node references. The code-block projection and HTML-summary helpers
/// are shared with the legacy list for the same reason.
///
/// **Parallel and unwired.** The sidebar still projects the legacy plan;
/// this port has no live consumer until the Stage 6 cutover.
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
                    ChangeList.emitCodeBlockChanges(
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
}
