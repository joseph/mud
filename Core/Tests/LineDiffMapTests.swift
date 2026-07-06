import Testing
@testable import MudCore

/// Direct unit tests for `LineDiffMap` — previously it was tested only
/// through rendered-HTML assertions in `DownModeChangeTrackingTests`.
@Suite("LineDiffMap")
struct LineDiffMapTests {
  private func map(old: String, new: String) -> LineDiffMap {
    LineDiffMap(plan: ChangePlan.plan(
      old: ParsedMarkdown(old), new: ParsedMarkdown(new)))
  }

  // MARK: - Baseline

  @Test func unchangedDocumentHasNoAnnotations() {
    let md = "Alpha.\n\nBeta.\n"
    let m = map(old: md, new: md)
    for line in 1...3 {
      #expect(m.annotation(forLine: line) == nil)
    }
    #expect(m.deletionGroups.isEmpty)
  }

  // MARK: - Insertions

  @Test func insertionAnnotatesAllItsLines() {
    let m = map(
      old: "Alpha.\n",
      new: "Alpha.\n\nAdded line one\nAdded line two\n")
    #expect(m.annotation(forLine: 1) == nil)
    #expect(m.annotation(forLine: 3)?.changeID == "change-1")
    #expect(m.annotation(forLine: 4)?.changeID == "change-1")
  }

  // MARK: - Deletions

  @Test func deletionGroupSitsBeforeTheNextAnchor() {
    let m = map(old: "Gone.\n\nKeep.\n", new: "Keep.\n")
    #expect(m.deletionGroups.count == 1)
    let group = m.deletionGroups[0]
    #expect(group.beforeNewLine == 1)
    #expect(group.oldLineRange == 1...1)
    #expect(group.changeID == "change-1")
  }

  @Test func trailingDeletionGroupUsesIntMax() {
    let m = map(old: "Keep.\n\nGone.\n", new: "Keep.\n")
    #expect(m.deletionGroups.count == 1)
    #expect(m.deletionGroups[0].beforeNewLine == Int.max)
    #expect(m.deletionGroups[0].oldLineRange == 3...3)
  }

  // MARK: - Paired blocks (line-level treatment)

  @Test func pairedBlockAnnotatesOnlyChangedLines() {
    let m = map(
      old: "One.\nTwo.\nThree.\n",
      new: "One.\nTwo changed.\nThree.\n")
    #expect(m.annotation(forLine: 1) == nil)
    #expect(m.annotation(forLine: 2) != nil)
    #expect(m.annotation(forLine: 3) == nil)
    #expect(m.deletionGroups.count == 1)
    #expect(m.deletionGroups[0].oldLineRange == 2...2)
    #expect(m.deletionGroups[0].beforeNewLine == 2)
  }

  @Test func pairedSimilarLinesCarryWordData() {
    let m = map(
      old: "The quick fox jumps.\n",
      new: "The slow fox jumps.\n")
    // Block IDs: change-1 (deletion), change-2 (insertion).
    let ins = m.insertionWordData(for: "change-2", line: 1)
    let del = m.deletionWordData(for: "change-1", line: 1)
    #expect(ins != nil)
    #expect(del != nil)
    #expect(ins?.isInsertion == true)
    #expect(del?.isInsertion == false)
    #expect(ins?.spans.contains(where: \.isInserted) == true)
  }

  // MARK: - Code block pairs

  @Test func codeBlockPairUsesClusterChangeIDs() {
    let m = map(
      old: "```\nkeep\nold\n```\n",
      new: "```\nkeep\nnew\n```\n")
    // change-1/change-2 are the block-level IDs; the edited line's
    // cluster mints change-3 — the ID Up mode and the sidebar use.
    #expect(m.annotation(forLine: 2) == nil)  // "keep"
    #expect(m.annotation(forLine: 3)?.changeID == "change-3")
    #expect(m.deletionGroups.count == 1)
    #expect(m.deletionGroups[0].changeID == "change-3")
    #expect(m.deletionGroups[0].beforeNewLine == 3)
    #expect(m.deletionGroups[0].oldLineRange == 3...3)
  }

  // MARK: - Mixed gap (unified pairing policy)

  @Test func mixedGapPairsCodeWithCodeAndTextWithText() {
    // One gap holding a deleted paragraph, an edited code block, and an
    // inserted paragraph, in crossing positions. The plan pairs the code
    // blocks by type and the paragraphs positionally — the old
    // positional-only policy paired the paragraph with the code block.
    let m = map(
      old: "Intro.\n\nAlpha beta gamma.\n\n```\nkeep\nold\n```\n\nTail.\n",
      new: "Intro.\n\n```\nkeep\nnew\n```\n\nDelta epsilon zeta.\n\nTail.\n")

    // IDs: change-1 del paragraph, change-2 del code, change-3 ins code,
    // change-4 ins paragraph, change-5 the code cluster.
    #expect(m.annotation(forLine: 5)?.changeID == "change-5")  // "new"
    #expect(m.annotation(forLine: 8)?.changeID == "change-4")  // paragraph

    // Deletion groups arrive in ascending beforeNewLine order — the
    // Down-mode layout consumes them with a sequential merge.
    let befores = m.deletionGroups.map(\.beforeNewLine)
    #expect(befores == befores.sorted())
    #expect(m.deletionGroups.contains { $0.changeID == "change-5" })
    #expect(m.deletionGroups.contains { $0.changeID == "change-1" })
  }
}
