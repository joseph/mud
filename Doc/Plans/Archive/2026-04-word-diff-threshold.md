Plan: Word Diff Similarity Threshold
===============================================================================

> Status: Complete


## Context

Word-level diff highlighting (inline `<ins>` and `<del>` tags within paired
blocks) was always shown when any word differed, regardless of how much had
changed. When most words in a block changed, the markers covered nearly all the
text and became visual noise — the reader was better served by plain
block-level coloring (red/green/blue overlays) without inline markers.


## Design

### Metric

The similarity ratio measures the fraction of the longer side's character count
that is unchanged:

```
similarity = unchangedChars / max(oldChars, newChars)
```

Whitespace spans count toward their respective totals.


### Threshold

**0.25** — at least 25% of the longer side must be unchanged text for
word-level markers to appear. Configurable via `defaults`:

```
defaults write org.josephpearson.Mud Mud-WordDiffThreshold -float 0.4
```


### Call sites

All five sites where `WordDiff.diff()` results are checked for changes now use
`WordDiff.hasSignificantChanges(_:threshold:)`, which combines the "has any
change" check with the similarity threshold:

| #   | File                  | Mode | Granularity                   |
| --- | --------------------- | ---- | ----------------------------- |
| 1   | `DiffContext.swift`   | Up   | Block-level word spans        |
| 2   | `LineDiffMap.swift`   | Down | Line-level within blocks      |
| 3   | `LineDiffMap.swift`   | Down | Line-level within code blocks |
| 4   | `LineDiffMap.swift`   | Down | Block-level fallback          |
| 5   | `CodeBlockDiff.swift` | Up   | Line-level within code blocks |


## Implementation

`WordDiff.similarity(_:)` and `WordDiff.hasSignificantChanges(_:threshold:)`
were added to `WordDiff.swift`. A `wordDiffThreshold` field (default 0.25) was
added to `RenderOptions` and threaded through the rendering pipeline:

- **Up mode**: `RenderOptions` → `DiffContext.init` →
  `CodeBlockDiff.computeRaw`
- **Down mode**: `RenderOptions` → `DownHTMLVisitor.highlightWithChanges` →
  `LineDiffMap.init`

`AppState` reads the threshold from UserDefaults (key
`"Mud-WordDiffThreshold"`), and `DocumentContentView` sets it on
`RenderOptions`.

All five call sites now use `hasWordChanges` as the local variable name.
