import Testing
@testable import MudCore

@Suite("WordDiff")
struct WordDiffTests {
  // MARK: - Diff algorithm

  @Test func identicalStrings() {
    let spans = WordDiff.diff(old: "hello world", new: "hello world")
    let allUnchanged = spans.allSatisfy(\.isUnchanged)
    #expect(allUnchanged)
    #expect(reconstructNew(spans) == "hello world")
  }

  @Test func singleWordChanged() {
    let spans = WordDiff.diff(old: "the quick fox", new: "the slow fox")
    // Transition separator between gap and anchor is unchanged.
    #expect(spans == [
      .unchanged("the"), .unchanged(" "),
      .deleted("quick"),
      .inserted("slow"),
      .unchanged(" "),
      .unchanged("fox"),
    ])
  }

  @Test func wordAddedInMiddle() {
    let spans = WordDiff.diff(old: "the fox", new: "the brown fox")
    // Pure insertion: separator stays with the inserted word.
    #expect(spans == [
      .unchanged("the"), .unchanged(" "),
      .inserted("brown"), .inserted(" "),
      .unchanged("fox"),
    ])
  }

  @Test func wordRemovedFromMiddle() {
    let spans = WordDiff.diff(old: "the brown fox", new: "the fox")
    // Pure deletion: separator stays with the deleted word.
    #expect(spans == [
      .unchanged("the"), .unchanged(" "),
      .deleted("brown"), .deleted(" "),
      .unchanged("fox"),
    ])
  }

  @Test func multipleChanges() {
    let spans = WordDiff.diff(
      old: "the quick brown fox jumps",
      new: "the slow brown dog leaps")
    #expect(reconstructOld(spans) == "the quick brown fox jumps")
    #expect(reconstructNew(spans) == "the slow brown dog leaps")
    let deletedWords = spans.filter(\.isDeleted)
      .filter { !$0.text.allSatisfy(\.isWhitespace) }
    let insertedWords = spans.filter(\.isInserted)
      .filter { !$0.text.allSatisfy(\.isWhitespace) }
    #expect(deletedWords.count == 3)
    #expect(insertedWords.count == 3)
  }

  @Test func completelyDifferent() {
    let spans = WordDiff.diff(old: "alpha beta", new: "gamma delta")
    // The space is the same in both, so it's unchanged.
    #expect(reconstructOld(spans) == "alpha beta")
    #expect(reconstructNew(spans) == "gamma delta")
  }

  @Test func emptyOld() {
    let spans = WordDiff.diff(old: "", new: "hello world")
    let allInserted = spans.allSatisfy(\.isInserted)
    #expect(allInserted)
    #expect(reconstructNew(spans) == "hello world")
  }

  @Test func emptyNew() {
    let spans = WordDiff.diff(old: "hello world", new: "")
    let allDeleted = spans.allSatisfy(\.isDeleted)
    #expect(allDeleted)
    #expect(reconstructOld(spans) == "hello world")
  }

  @Test func bothEmpty() {
    let spans = WordDiff.diff(old: "", new: "")
    #expect(spans.isEmpty)
  }

  @Test func whitespacePreservation() {
    let spans = WordDiff.diff(
      old: "one two three", new: "one changed three")
    #expect(reconstructOld(spans) == "one two three")
    #expect(reconstructNew(spans) == "one changed three")
  }

  @Test func multipleConsecutiveSpaces() {
    // Double-space is its own token, distinct from single space.
    let spans = WordDiff.diff(
      old: "hello  world", new: "hello  earth")
    #expect(reconstructOld(spans) == "hello  world")
    #expect(reconstructNew(spans) == "hello  earth")
    let hasDeleted = spans.contains(where: \.isDeleted)
    let hasInserted = spans.contains(where: \.isInserted)
    #expect(hasDeleted)
    #expect(hasInserted)
  }

  @Test func wordsRemovedFromEnd() {
    // A word at the end of one text matches the same word in the
    // middle of the other — no trailing whitespace mismatch because
    // words and whitespace are separate tokens.
    let spans = WordDiff.diff(
      old: "hello world end", new: "hello world")
    #expect(reconstructNew(spans) == "hello world")
    #expect(reconstructOld(spans) == "hello world end")
    let deletedWords = spans.filter(\.isDeleted)
      .filter { !$0.text.allSatisfy(\.isWhitespace) }
    #expect(deletedWords.count == 1)
    #expect(deletedWords[0].text == "end")
  }

  // MARK: - Similarity

  @Test func similarityAllUnchanged() {
    let spans = WordDiff.diff(old: "hello world", new: "hello world")
    #expect(WordDiff.similarity(spans) == 1.0)
  }

  @Test func similarityCompletelyDifferent() {
    // "alpha beta" → "gamma delta": all words differ, but the
    // space between them is unchanged. Similarity should be low.
    let spans: [WordSpan] = [
      .deleted("alpha"), .deleted(" "),
      .inserted("gamma"), .inserted(" "),
      .deleted("beta"),
      .inserted("delta"),
    ]
    #expect(WordDiff.similarity(spans) == 0.0)
  }

  @Test func similarityEmptySpans() {
    #expect(WordDiff.similarity([]) == 1.0)
  }

  @Test func similarityMixedCase() {
    // "the quick fox" → "the slow fox": 2 of 3 words unchanged.
    let spans = WordDiff.diff(old: "the quick fox", new: "the slow fox")
    let sim = WordDiff.similarity(spans)
    // unchanged: "the" (3) + " " (1) + " " (1) + "fox" (3) = 8
    // old total: 8 + "quick" (5) = 13
    // new total: 8 + "slow" (4) = 12
    // similarity = 8 / 13 ≈ 0.615
    #expect(sim > 0.6)
    #expect(sim < 0.7)
  }

  @Test func similarityAllDeleted() {
    let spans = WordDiff.diff(old: "hello world", new: "")
    #expect(WordDiff.similarity(spans) == 0.0)
  }

  @Test func similarityAllInserted() {
    let spans = WordDiff.diff(old: "", new: "hello world")
    #expect(WordDiff.similarity(spans) == 0.0)
  }

  // MARK: - hasSignificantChanges

  @Test func significantChangesAllUnchanged() {
    let spans = WordDiff.diff(old: "hello world", new: "hello world")
    #expect(!WordDiff.hasSignificantChanges(spans, threshold: 0.25))
  }

  @Test func significantChangesBelowThreshold() {
    // 4 of 5 words changed → low similarity → not significant.
    let spans = WordDiff.diff(
      old: "the quick brown fox jumps",
      new: "the slow red dog leaps")
    #expect(!WordDiff.hasSignificantChanges(spans, threshold: 0.25))
  }

  @Test func significantChangesAboveThreshold() {
    // 1 of 3 words changed → high similarity → significant.
    let spans = WordDiff.diff(old: "the quick fox", new: "the slow fox")
    #expect(WordDiff.hasSignificantChanges(spans, threshold: 0.25))
  }

  @Test func significantChangesRespectsCustomThreshold() {
    // 1 of 3 words changed (similarity ≈ 0.615). Passes at 0.5,
    // fails at 0.7.
    let spans = WordDiff.diff(old: "the quick fox", new: "the slow fox")
    #expect(WordDiff.hasSignificantChanges(spans, threshold: 0.5))
    #expect(!WordDiff.hasSignificantChanges(spans, threshold: 0.7))
  }

  // MARK: - inlineText extraction

  @Test func inlineTextStripsInlineCodeBackticks() throws {
    // inlineText(of:) reproduces the character stream the rendering visitor
    // consumes: text and inline-code literals verbatim (no backticks), a soft
    // break as a single space, formatting containers flattened to their
    // contents. plainText would keep the backticks around inline code; these
    // golden strings never contain one.
    let cases: [(markdown: String, inlineText: String)] = [
      ("Call `foo()` and wait.\n", "Call foo() and wait."),
      ("The **important** value is high.\n", "The important value is high."),
      ("Use `foo()` then `bar()` to finish.\n",
        "Use foo() then bar() to finish."),
      ("A *special* and `coded` thing.\n", "A special and coded thing."),
      ("Multi line\nparagraph here.\n", "Multi line paragraph here."),
      ("`start` middle `end`.\n", "start middle end."),
    ]
    for (markdown, expected) in cases {
      let root = try #require(ParsedMarkdown(markdown).cmarkDocument?.root)
      let paragraph = try #require(
        root.children.first { $0.kind == .paragraph })
      let text = WordDiff.inlineText(of: paragraph)
      #expect(text == expected, "inlineText mismatch for: \(markdown.dropLast())")
      #expect(!text.contains("`"))
    }
  }

}

// MARK: - Test helpers

/// Reconstructs the new text from a span list by concatenating
/// unchanged and inserted spans.
private func reconstructNew(_ spans: [WordSpan]) -> String {
  spans.filter { !$0.isDeleted }.map(\.text).joined()
}

/// Reconstructs the old text from a span list by concatenating
/// unchanged and deleted spans.
private func reconstructOld(_ spans: [WordSpan]) -> String {
  spans.filter { !$0.isInserted }.map(\.text).joined()
}
