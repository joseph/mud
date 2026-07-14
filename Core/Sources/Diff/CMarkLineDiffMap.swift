/// Maps a `CMarkChangePlan` to line-level annotations for Down mode — the
/// Stage 4 port of ``LineDiffMap``
/// (Doc/Plans/2026-07-single-parser-rendering.md). Reuses the legacy output
/// types (`LineAnnotation`, `DeletionGroup`, `BlockWordData`) unchanged:
/// they carry no node references, only line numbers and word spans.
///
/// **Parallel and unwired.** Down mode still projects the legacy plan; this
/// port has no live consumer until Stage 5, so its parity tests are its only
/// proof of correctness for now.
struct CMarkLineDiffMap {
    private let annotations: [Int: LineAnnotation]
    let deletionGroups: [DeletionGroup]
    private let delWordData: [String: [Int: BlockWordData]]
    private let insWordData: [String: [Int: BlockWordData]]

    func annotation(forLine line: Int) -> LineAnnotation? {
        annotations[line]
    }

    func deletionWordData(
        for changeID: String, line: Int
    ) -> BlockWordData? {
        delWordData[changeID]?[line]
    }

    func insertionWordData(
        for changeID: String, line: Int
    ) -> BlockWordData? {
        insWordData[changeID]?[line]
    }
}

// MARK: - Construction

extension CMarkLineDiffMap {
    init(plan: CMarkChangePlan, wordDiffThreshold: Double = 0.25) {
        var annotations: [Int: LineAnnotation] = [:]
        var groups: [DeletionGroup] = []
        var delWD: [String: [Int: BlockWordData]] = [:]
        var insWD: [String: [Int: BlockWordData]] = [:]

        // MARK: Line-level pair

        /// Runs `LineLevelDiff` on a paired block's source text and
        /// emits fine-grained annotations, deletion groups, and
        /// per-line word data.
        func processLineLevelPair(
            _ pair: CMarkChangePlan.Pair,
            insLineRange: ClosedRange<Int>,
            anchorLine: Int
        ) {
            let del = pair.deletion
            let ins = pair.insertion
            let oldLines = del.block.sourceText.split(
                separator: "\n",
                omittingEmptySubsequences: false).map(String.init)
            let newLines = ins.block.sourceText.split(
                separator: "\n",
                omittingEmptySubsequences: false).map(String.init)

            guard let entries = LineLevelDiff.diff(
                old: oldLines, new: newLines
            ) else {
                emitBlockLevel(pair, insLineRange: insLineRange)
                return
            }

            var idx = 0
            while idx < entries.count {
                if entries[idx].annotation == .unchanged {
                    idx += 1
                    continue
                }

                // Collect the gap (consecutive changed entries).
                var gapDelOldLines: [Int] = []
                var gapInsNewLines: [Int] = []

                while idx < entries.count,
                      entries[idx].annotation != .unchanged {
                    switch entries[idx].annotation {
                    case .deleted:
                        gapDelOldLines.append(
                            del.block.sourceLine
                                + entries[idx].sourceIndex)
                    case .inserted:
                        gapInsNewLines.append(
                            ins.block.sourceLine
                                + entries[idx].sourceIndex)
                    case .unchanged:
                        break
                    }
                    idx += 1
                }

                // Position deletion group before the first insertion
                // in this gap, or before the next unchanged line, or
                // before the overall anchor.
                let beforeLine: Int
                if let firstIns = gapInsNewLines.first {
                    beforeLine = firstIns
                } else if idx < entries.count {
                    beforeLine = ins.block.sourceLine
                        + entries[idx].sourceIndex
                } else {
                    beforeLine = anchorLine
                }

                if let first = gapDelOldLines.first,
                   let last = gapDelOldLines.last {
                    groups.append(DeletionGroup(
                        beforeNewLine: beforeLine,
                        oldLineRange: first...last,
                        changeID: del.changeID))
                }

                for newLine in gapInsNewLines {
                    annotations[newLine] = LineAnnotation(
                        changeID: ins.changeID)
                }

                // Word-level diffs for best-matched line pairs.
                let delTexts = gapDelOldLines.map {
                    oldLines[$0 - del.block.sourceLine]
                }
                let insTexts = gapInsNewLines.map {
                    newLines[$0 - ins.block.sourceLine]
                }
                for linePair in WordPairing.bestPairs(
                    delLines: delTexts, insLines: insTexts) {
                    let delLine = gapDelOldLines[linePair.del]
                    let insLine = gapInsNewLines[linePair.ins]
                    let di = delLine - del.block.sourceLine
                    let ii = insLine - ins.block.sourceLine
                    guard di < oldLines.count,
                          ii < newLines.count else { continue }
                    let spans = WordDiff.diff(
                        old: oldLines[di], new: newLines[ii])
                    guard WordDiff.hasSignificantChanges(
                        spans, threshold: wordDiffThreshold)
                    else { continue }
                    delWD[del.changeID, default: [:]][delLine] =
                        BlockWordData(
                            spans: spans,
                            sourceText: oldLines[di],
                            isInsertion: false,
                            startLine: delLine)
                    insWD[ins.changeID, default: [:]][insLine] =
                        BlockWordData(
                            spans: spans,
                            sourceText: newLines[ii],
                            isInsertion: true,
                            startLine: insLine)
                }
            }
        }

        // MARK: Code block pair

        /// Projects a code block pair's cluster lines (change IDs
        /// pre-assigned by the plan) onto document line numbers.
        func processCodeBlockPair(
            _ pair: CMarkChangePlan.CodeBlockPair
        ) {
            let del = pair.deletion
            let ins = pair.insertion

            // Content start offsets (fenced blocks skip the fence).
            let delFenced = del.block.sourceText.hasPrefix("`")
                || del.block.sourceText.hasPrefix("~")
            let insFenced = ins.block.sourceText.hasPrefix("`")
                || ins.block.sourceText.hasPrefix("~")
            let delStart = del.block.sourceLine
                + (delFenced ? 1 : 0)
            let insStart = ins.block.sourceLine
                + (insFenced ? 1 : 0)

            // Source lines for word diffs.
            let delSrcLines = del.block.sourceText.split(
                separator: "\n",
                omittingEmptySubsequences: false).map(String.init)
            let insSrcLines = ins.block.sourceText.split(
                separator: "\n",
                omittingEmptySubsequences: false).map(String.init)
            let delFenceOff = delFenced ? 1 : 0
            let insFenceOff = insFenced ? 1 : 0

            var oldCI = 0, newCI = 0
            var gapDels: [(doc: Int, code: Int)] = []
            var gapIns: [(doc: Int, code: Int)] = []
            var gapChangeID: String?

            func flushCodeGap() {
                guard let changeID = gapChangeID else { return }

                if let first = gapDels.first,
                   let last = gapDels.last {
                    let before = gapIns.first?.doc
                        ?? (insStart + newCI)
                    groups.append(DeletionGroup(
                        beforeNewLine: before,
                        oldLineRange: first.doc...last.doc,
                        changeID: changeID))
                }

                for entry in gapIns {
                    annotations[entry.doc] = LineAnnotation(
                        changeID: changeID)
                }

                let gapDelTexts = gapDels.compactMap {
                    let si = $0.code + delFenceOff
                    return si < delSrcLines.count
                        ? delSrcLines[si] : nil
                }
                let gapInsTexts = gapIns.compactMap {
                    let si = $0.code + insFenceOff
                    return si < insSrcLines.count
                        ? insSrcLines[si] : nil
                }
                for linePair in WordPairing.bestPairs(
                    delLines: gapDelTexts,
                    insLines: gapInsTexts) {
                    let d = gapDels[linePair.del]
                    let i = gapIns[linePair.ins]
                    let dsi = d.code + delFenceOff
                    let isi = i.code + insFenceOff
                    guard dsi < delSrcLines.count,
                          isi < insSrcLines.count
                    else { continue }
                    let spans = WordDiff.diff(
                        old: delSrcLines[dsi],
                        new: insSrcLines[isi])
                    guard WordDiff.hasSignificantChanges(
                        spans, threshold: wordDiffThreshold)
                    else { continue }
                    delWD[changeID, default: [:]][d.doc] =
                        BlockWordData(
                            spans: spans,
                            sourceText: delSrcLines[dsi],
                            isInsertion: false,
                            startLine: d.doc)
                    insWD[changeID, default: [:]][i.doc] =
                        BlockWordData(
                            spans: spans,
                            sourceText: insSrcLines[isi],
                            isInsertion: true,
                            startLine: i.doc)
                }

                gapDels.removeAll()
                gapIns.removeAll()
                gapChangeID = nil
            }

            for line in pair.lines {
                switch line.annotation {
                case .unchanged:
                    flushCodeGap()
                    oldCI += 1
                    newCI += 1
                case .deleted:
                    gapDels.append(
                        (doc: delStart + oldCI, code: oldCI))
                    gapChangeID = line.changeID
                    oldCI += 1
                case .inserted:
                    gapIns.append(
                        (doc: insStart + newCI, code: newCI))
                    gapChangeID = line.changeID
                    newCI += 1
                }
            }
            flushCodeGap()
        }

        // MARK: Block-level fallback

        /// Falls back to block-level treatment: all lines of the old
        /// block are deleted, all lines of the new block are inserted.
        func emitBlockLevel(
            _ pair: CMarkChangePlan.Pair,
            insLineRange: ClosedRange<Int>
        ) {
            let del = pair.deletion
            let ins = pair.insertion
            let spans = WordDiff.diff(
                old: del.block.sourceText,
                new: ins.block.sourceText)
            let hasWordChanges = WordDiff.hasSignificantChanges(
                spans, threshold: wordDiffThreshold)
            if hasWordChanges {
                let delData = BlockWordData(
                    spans: spans,
                    sourceText: del.block.sourceText,
                    isInsertion: false,
                    startLine: del.block.sourceLine)
                let insData = BlockWordData(
                    spans: spans,
                    sourceText: ins.block.sourceText,
                    isInsertion: true,
                    startLine: ins.block.sourceLine)
                if let range = Self.lineRange(for: del.block) {
                    for line in range {
                        delWD[del.changeID, default: [:]][line] =
                            delData
                    }
                }
                for line in insLineRange {
                    insWD[ins.changeID, default: [:]][line] =
                        insData
                }
            }

            if let range = Self.lineRange(for: del.block) {
                groups.append(DeletionGroup(
                    beforeNewLine: insLineRange.lowerBound,
                    oldLineRange: range,
                    changeID: del.changeID))
            }
            for line in insLineRange {
                annotations[line] = LineAnnotation(
                    changeID: ins.changeID)
            }
        }

        // MARK: Gap projection

        for gap in plan.gaps {
            let anchorLine = gap.followingAnchor
                .flatMap { Self.lineRange(for: $0)?.lowerBound }
                ?? Int.max

            // Paired blocks, in document order of their insertions.
            var pairIndex = 0
            for slot in gap.insertionSlots {
                switch slot {
                case .codeBlockPair(let pair):
                    processCodeBlockPair(pair)

                case .block(let change):
                    if pairIndex < gap.pairs.count {
                        let pair = gap.pairs[pairIndex]
                        pairIndex += 1
                        if let insRange = Self.lineRange(
                            for: pair.insertion.block) {
                            processLineLevelPair(
                                pair, insLineRange: insRange,
                                anchorLine: anchorLine)
                        } else if let range = Self.lineRange(
                            for: pair.deletion.block) {
                            // No line range on the insertion side —
                            // fall back to a plain deletion group.
                            groups.append(DeletionGroup(
                                beforeNewLine: anchorLine,
                                oldLineRange: range,
                                changeID: pair.deletion.changeID))
                        }
                    } else if let range = Self.lineRange(
                        for: change.block) {
                        // Unpaired insertion — block-level.
                        for line in range {
                            annotations[line] = LineAnnotation(
                                changeID: change.changeID)
                        }
                    }
                }
            }

            // Unpaired deletions — block-level, before the anchor.
            for del in gap.deletions.dropFirst(gap.pairs.count) {
                if let range = Self.lineRange(for: del.block) {
                    groups.append(DeletionGroup(
                        beforeNewLine: anchorLine,
                        oldLineRange: range,
                        changeID: del.changeID))
                }
            }
        }

        self.annotations = annotations
        self.deletionGroups = groups
        self.delWordData = delWD
        self.insWordData = insWD
    }

    /// Derives the 1-based line range from a leaf block's source text.
    private static func lineRange(
        for block: CMarkLeafBlock
    ) -> ClosedRange<Int>? {
        guard block.markup.range != nil else { return nil }
        let lineCount = block.sourceText.split(
            separator: "\n",
            omittingEmptySubsequences: false).count
        guard lineCount > 0 else { return nil }
        return block.sourceLine...(block.sourceLine + lineCount - 1)
    }
}

// MARK: - Line diff value types

// Shared, parser-agnostic value types the line map projects into. They moved
// here from the legacy `LineDiffMap` when it was deleted at the Stage 6
// cutover. `Equatable` so diff-layer parity tests can compare projections.

/// A line in the new document that belongs to a changed block.
struct LineAnnotation: Equatable {
    let changeID: String
}

/// A contiguous group of old-document lines to re-insert as deletions.
struct DeletionGroup: Equatable {
    /// Insert before this new-document line number (1-based).
    /// `Int.max` for trailing deletions (after all new-doc lines).
    let beforeNewLine: Int
    /// Line range in the old document (1-based, closed).
    let oldLineRange: ClosedRange<Int>
    /// Change ID for `data-change-id` attributes and sidebar matching.
    let changeID: String
}

/// Word-level diff data for a line within a paired block.
struct BlockWordData: Equatable {
    /// Word spans from `WordDiff.diff(old:new:)`.
    let spans: [WordSpan]
    /// This line's source text (raw markdown).
    let sourceText: String
    /// True for insertion lines, false for deletion lines.
    let isInsertion: Bool
    /// 1-based line number of this entry in its document.
    let startLine: Int
}
