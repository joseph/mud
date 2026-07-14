/// Line-level diff within a paired code block.
///
/// When a code block is modified (deletion + insertion in the same gap),
/// this type provides per-line change data: unchanged, inserted, and
/// deleted lines with pre-highlighted HTML, change IDs, and group info.
struct CodeBlockDiff {
  let lines: [CodeLine]

  struct CodeLine {
    /// Pre-highlighted HTML content for this line (no outer tag).
    let highlightedHTML: String
    /// Whether this line is unchanged, inserted, or deleted.
    let annotation: Annotation
    /// Change ID for changed lines; nil for unchanged.
    let changeID: String?
    /// Group ID for changed lines; nil for unchanged.
    let groupID: String?
    /// 1-based badge number; non-nil only for the first line in
    /// each group.
    let groupIndex: Int?
  }

  enum Annotation {
    case unchanged
    case inserted
    case deleted
  }

  /// Computes a line-level diff between two code block contents.
  ///
  /// Returns `nil` when the line-level diff shows no changes (e.g.,
  /// only the language tag or fence style changed), signaling the
  /// caller to fall back to block-level handling.
  ///
  /// - Parameters:
  ///   - oldCode: Content of the old code block (without fences).
  ///   - newCode: Content of the new code block (without fences).
  ///   - oldLanguage: Language of the old code block (for highlighting).
  ///   - newLanguage: Language of the new code block (for highlighting).
  ///   - nextChangeID: Closure that returns the next global change ID.
  ///   - nextGroupID: Closure that returns the next global group ID
  ///     and its 1-based index.
  static func compute(
    oldCode: String, newCode: String,
    oldLanguage: String?, newLanguage: String?,
    wordDiffThreshold: Double = 0.25,
    nextChangeID: () -> String,
    nextGroupID: () -> (id: String, index: Int)
  ) -> CodeBlockDiff? {
    guard let raw = computeRaw(
      oldCode: oldCode, newCode: newCode,
      oldLanguage: oldLanguage, newLanguage: newLanguage,
      wordDiffThreshold: wordDiffThreshold
    ) else { return nil }

    var lines = raw.lines
    assignGroups(&lines, nextChangeID: nextChangeID,
                 nextGroupID: nextGroupID)
    return CodeBlockDiff(lines: lines)
  }
}

// MARK: - Raw computation (no IDs)

extension CodeBlockDiff {
  /// A raw line-level diff without change IDs or group IDs.
  /// Used internally; IDs are assigned in a separate pass.
  struct RawDiff {
    let lines: [CodeLine]
  }

  /// Computes a raw line-level diff (annotations + highlighted HTML,
  /// no change IDs or group IDs). Returns `nil` when no line changes
  /// exist.
  static func computeRaw(
    oldCode: String, newCode: String,
    oldLanguage: String?, newLanguage: String?,
    wordDiffThreshold: Double = 0.25
  ) -> RawDiff? {
    let oldLines = splitCode(oldCode)
    let newLines = splitCode(newCode)

    guard let entries = LineLevelDiff.diff(
      old: oldLines, new: newLines
    ) else { return nil }

    // Highlight both code blocks and split into per-line HTML.
    let oldHighlighted = highlightLines(
      oldLines, language: oldLanguage)
    let newHighlighted = highlightLines(
      newLines, language: newLanguage)

    // Build interleaved line list from diff entries.
    var result: [CodeLine] = []
    var idx = 0

    while idx < entries.count {
      if entries[idx].annotation == .unchanged {
        result.append(CodeLine(
          highlightedHTML: newHighlighted[entries[idx].sourceIndex],
          annotation: .unchanged,
          changeID: nil, groupID: nil, groupIndex: nil))
        idx += 1
        continue
      }

      // Collect the gap (consecutive changed entries).
      var gapOld: [Int] = []
      var gapNew: [Int] = []
      while idx < entries.count,
            entries[idx].annotation != .unchanged {
        switch entries[idx].annotation {
        case .deleted:
          gapOld.append(entries[idx].sourceIndex)
        case .inserted:
          gapNew.append(entries[idx].sourceIndex)
        case .unchanged:
          break
        }
        idx += 1
      }

      let oldRange = gapOld.isEmpty ? 0..<0
        : gapOld[0]..<(gapOld[gapOld.count - 1] + 1)
      let newRange = gapNew.isEmpty ? 0..<0
        : gapNew[0]..<(gapNew[gapNew.count - 1] + 1)

      emitGap(
        oldRange: oldRange, newRange: newRange,
        oldLines: oldLines, newLines: newLines,
        oldHighlighted: oldHighlighted,
        newHighlighted: newHighlighted,
        wordDiffThreshold: wordDiffThreshold,
        into: &result)
    }

    return RawDiff(lines: result)
  }

  /// Assigns change IDs and group IDs to a raw diff's lines.
  static func assignGroups(
    _ lines: inout [CodeLine],
    nextChangeID: () -> String,
    nextGroupID: () -> (id: String, index: Int)
  ) {
    assignChangeIDs(&lines, nextChangeID: nextChangeID)
    assignGroupIDs(&lines, nextGroupID: nextGroupID)
  }

  /// Assigns a change ID to each cluster of consecutive changed lines.
  ///
  /// Callers must mint cluster change IDs at gap-finalization time so
  /// that `CMarkDiffContext` and `CMarkLineDiffMap` number the same edit
  /// identically — a sidebar click finds its Down-mode target by
  /// matching `data-change-id` values.
  static func assignChangeIDs(
    _ lines: inout [CodeLine],
    nextChangeID: () -> String
  ) {
    var i = 0
    while i < lines.count {
      guard lines[i].annotation != .unchanged else {
        i += 1
        continue
      }

      // Found the start of a cluster.
      let changeID = nextChangeID()
      while i < lines.count && lines[i].annotation != .unchanged {
        lines[i] = CodeLine(
          highlightedHTML: lines[i].highlightedHTML,
          annotation: lines[i].annotation,
          changeID: changeID,
          groupID: lines[i].groupID,
          groupIndex: lines[i].groupIndex)
        i += 1
      }
    }
  }

  /// Assigns a group ID to each cluster of consecutive changed lines,
  /// with the badge index on the cluster's first line.
  static func assignGroupIDs(
    _ lines: inout [CodeLine],
    nextGroupID: () -> (id: String, index: Int)
  ) {
    var i = 0
    while i < lines.count {
      guard lines[i].annotation != .unchanged else {
        i += 1
        continue
      }

      // Found the start of a cluster.
      let group = nextGroupID()
      var isFirst = true
      while i < lines.count && lines[i].annotation != .unchanged {
        lines[i] = CodeLine(
          highlightedHTML: lines[i].highlightedHTML,
          annotation: lines[i].annotation,
          changeID: lines[i].changeID,
          groupID: group.id,
          groupIndex: isFirst ? group.index : nil)
        isFirst = false
        i += 1
      }
    }
  }
}

// MARK: - Private helpers

extension CodeBlockDiff {
  /// Splits code content into lines, trimming a trailing empty line
  /// caused by a trailing newline before the closing fence.
  private static func splitCode(_ code: String) -> [String] {
    var lines = code.split(
      separator: "\n", omittingEmptySubsequences: false
    ).map(String.init)
    // Trim trailing empty line from trailing newline.
    if lines.last == "" { lines.removeLast() }
    return lines
  }

  /// Highlights code lines and splits the result per line.
  private static func highlightLines(
    _ lines: [String], language: String?
  ) -> [String] {
    let joined = lines.joined(separator: "\n")
    if let highlighted = CodeHighlighter.highlight(
      joined, language: language
    ) {
      let split = HTMLLineSplitter.splitByLine(highlighted)
      // Ensure we have the right number of lines.
      if split.count == lines.count { return split }
      // Fallback if split count mismatches.
    }
    return lines.map { HTMLEscaping.escape($0) }
  }

  /// Emits deleted then inserted lines for a gap between anchors.
  /// Paired lines (first del with first ins, etc.) get word-level
  /// `<ins>` / `<del>` markers injected into their highlighted HTML.
  private static func emitGap(
    oldRange: Range<Int>, newRange: Range<Int>,
    oldLines: [String], newLines: [String],
    oldHighlighted: [String], newHighlighted: [String],
    wordDiffThreshold: Double,
    into result: inout [CodeLine]
  ) {
    let delIndices = Array(oldRange)
    let insIndices = Array(newRange)

    // Compute word-level markers for best-matched line pairs.
    var delMarked = [Int: String]()  // index → HTML with markers
    var insMarked = [Int: String]()

    let delTexts = delIndices.map { oldLines[$0] }
    let insTexts = insIndices.map { newLines[$0] }
    for pair in WordPairing.bestPairs(
      delLines: delTexts, insLines: insTexts) {
      let di = delIndices[pair.del]
      let ii = insIndices[pair.ins]
      let oldSrc = oldLines[di]
      let newSrc = newLines[ii]
      let spans = WordDiff.diff(old: oldSrc, new: newSrc)
      let hasWordChanges = WordDiff.hasSignificantChanges(
        spans, threshold: wordDiffThreshold)
      guard hasWordChanges else { continue }

      // Build markers for the deletion line.
      var delMarkers: [CMarkDownHTMLVisitor.WordMarker] = []
      var insMarkers: [CMarkDownHTMLVisitor.WordMarker] = []
      var oldPos = 0, newPos = 0
      for span in spans {
        switch span {
        case .unchanged(let text):
          oldPos += text.count
          newPos += text.count
        case .deleted(let text):
          delMarkers.append(.init(
            start: oldPos, end: oldPos + text.count, tag: "del"))
          oldPos += text.count
        case .inserted(let text):
          insMarkers.append(.init(
            start: newPos, end: newPos + text.count, tag: "ins"))
          newPos += text.count
        }
      }

      if !delMarkers.isEmpty {
        delMarked[di] = CMarkDownHTMLVisitor.injectMarkers(
          into: oldHighlighted[di], markers: delMarkers)
      }
      if !insMarkers.isEmpty {
        insMarked[ii] = CMarkDownHTMLVisitor.injectMarkers(
          into: newHighlighted[ii], markers: insMarkers)
      }
    }

    // Emit deletions first, then insertions.
    for i in oldRange {
      result.append(CodeLine(
        highlightedHTML: delMarked[i] ?? oldHighlighted[i],
        annotation: .deleted,
        changeID: nil, groupID: nil, groupIndex: nil))
    }
    for i in newRange {
      result.append(CodeLine(
        highlightedHTML: insMarked[i] ?? newHighlighted[i],
        annotation: .inserted,
        changeID: nil, groupID: nil, groupIndex: nil))
    }
  }
}
