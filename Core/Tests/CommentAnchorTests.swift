import Testing

@testable import MudCore

/// Covers the DOM-selection-end → source-byte mapping that places a comment
/// marker at the quotation's end.
@Suite("CommentAnchor")
struct CommentAnchorTests {

  @Test func plainParagraphOffsetMapsToByte() {
    // "The quick brown fox" is 19 characters; the marker lands at byte 19, just
    // after "fox".
    let source = "The quick brown fox jumped.\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "The quick brown fox jumped.", offsetInBlock: 19)
    #expect(offset == 19)
  }

  @Test func blockStartAndEnd() {
    let source = "Hello world.\n"
    #expect(
      CommentAnchor.insertionOffset(
        in: source, blockText: "Hello world.", offsetInBlock: 0) == 0)
    #expect(
      CommentAnchor.insertionOffset(
        in: source, blockText: "Hello world.", offsetInBlock: 12) == 12)
  }

  @Test func offsetInsideEmphasisResolvesThroughInlineSyntax() {
    // Rendered "A bold word."; offset 6 ("A bold") is inside the `**bold**`
    // source, mapping to byte 8 — right after "bold", before the closing `**`.
    let source = "A **bold** word.\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "A bold word.", offsetInBlock: 6)
    #expect(offset == 8)
  }

  @Test func picksMatchingBlockAmongSeveral() {
    let source = """
      First paragraph here.

      Second paragraph here.
      """
    // "Second" is 6 chars; the second paragraph starts at byte 23.
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "Second paragraph here.", offsetInBlock: 6)
    #expect(offset == 29)
  }

  @Test func resolvesOffsetInBlockContainingAMarker() {
    // The block already carries a comment marker. cmark sees `[^comment-a]` as a
    // zero-width reference, so the rendered (marker-free) "The quick brown fox
    // jumped." matches and offset 19 ("…fox") maps to the raw byte before the
    // existing marker.
    let source = """
      The quick brown fox[^comment-a] jumped.

      [^comment-a]: A note.
      """
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "The quick brown fox jumped.", offsetInBlock: 19)
    #expect(offset == 19)
  }

  @Test func headingResolvesOffset() {
    // "Hello" is 5 chars; in "## Hello world" the text starts at byte 3, so the
    // offset lands at byte 8 (just after "Hello").
    let offset = CommentAnchor.insertionOffset(
      in: "## Hello world\n", blockText: "Hello world", offsetInBlock: 5)
    #expect(offset == 8)
  }

  @Test func anchorsInsideListItem() {
    let source = "- Alpha\n- Beta\n"
    #expect(
      CommentAnchor.insertionOffset(
        in: source, blockText: "Alpha", offsetInBlock: 5) != nil)
    #expect(
      CommentAnchor.insertionOffset(
        in: source, blockText: "Beta", offsetInBlock: 4) != nil)
  }

  @Test func anchorsInsideBlockquote() {
    #expect(
      CommentAnchor.insertionOffset(
        in: "> Quoted text here.\n", blockText: "Quoted text here.",
        offsetInBlock: 6) != nil)
  }

  @Test func anchorsInsideTableCell() {
    let source = """
      | A | B |
      |---|---|
      | foo | bar |
      """
    #expect(
      CommentAnchor.insertionOffset(
        in: source, blockText: "foo", offsetInBlock: 3) != nil)
  }

  @Test func occurrenceIndexDisambiguatesIdenticalBlocks() {
    let source = """
      Repeated text here.

      Repeated text here.
      """
    let first = CommentAnchor.insertionOffset(
      in: source, blockText: "Repeated text here.", offsetInBlock: 8,
      occurrenceIndex: 0)
    let second = CommentAnchor.insertionOffset(
      in: source, blockText: "Repeated text here.", offsetInBlock: 8,
      occurrenceIndex: 1)
    #expect(first != nil && second != nil)
    #expect(first! < second!)  // the second occurrence is later in the source
  }

  @Test func skipsBlocksInsideDefinitions() {
    // "Hidden quote text" exists only inside a comment definition, so it must
    // not anchor (the definition is the hidden bottom section).
    let source = """
      Some unrelated body.

      [^comment-a]: > Hidden quote text

          💬 {JP @ 2026-06-01 18:33}:
      """
    #expect(
      CommentAnchor.insertionOffset(
        in: source, blockText: "Hidden quote text", offsetInBlock: 5) == nil)
  }

  @Test func anchorsInGFMAlertBody() {
    // The rendered body ("Take note.") is a suffix of cmark's paragraph
    // ("[!NOTE] Take note."); the marker must land after "note", skipping the
    // stripped `[!NOTE]` title. The body text "Take note." begins at byte 12
    // (after "> [!NOTE]\n> "), so offset 9 ("…note") resolves to byte 21 — the
    // '.' — placing the marker as "Take note[^…].".
    let source = "> [!NOTE]\n> Take note.\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "Take note.", offsetInBlock: 9)
    #expect(offset == 21)
  }

  @Test func anchorsInDocCAsideBody() {
    // "Use DocC." is a suffix of cmark's "Note: Use DocC."; the offset skips the
    // stripped "Note:" title.
    let source = "> Note: Use DocC.\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "Use DocC.", offsetInBlock: 8)
    #expect(offset != nil)
  }

  @Test func matchesSmartQuotedRenderedText() {
    // The rendered DOM smart-quotes straight quotes (`"` → `“`/`”`), but the
    // source the anchor parses keeps them straight. The block text must still
    // match after folding, and the offset resolves against the raw source.
    let source = "> \"Quoted words here.\"\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "\u{201C}Quoted words here.\u{201D}", offsetInBlock: 7)
    #expect(offset != nil)
  }

  @Test func matchesSmartApostropheRenderedText() {
    // "don't" renders as "don’t" (curly apostrophe); folding keeps it matchable
    // and, being length-preserving, the offset stays aligned.
    let source = "It doesn't matter.\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "It doesn\u{2019}t matter.", offsetInBlock: 11)
    #expect(offset == 11)
  }

  @Test func inlineCodeSnapsToAfterTheSpan() {
    // Offset 6 falls inside `code`; the marker must land after the closing
    // backtick (byte 10), not inside the span.
    let offset = CommentAnchor.insertionOffset(
      in: "Use `code` here.\n", blockText: "Use code here.", offsetInBlock: 6)
    #expect(offset == 10)
  }

  @Test func noMatchingBlockReturnsNil() {
    let source = "Just one paragraph.\n"
    #expect(
      CommentAnchor.insertionOffset(
        in: source, blockText: "A totally different block.", offsetInBlock: 3)
        == nil)
  }

  @Test func collapsedWhitespaceStillMatches() {
    // The DOM block text may differ in whitespace from the source; matching
    // collapses both.
    let source = "Spaced   out    words.\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "Spaced out words.", offsetInBlock: 6)
    #expect(offset != nil)
  }

  @Test func emojiShortcodeBlockMatchesAndOffsetSkipsTheSpan() {
    // The DOM shows "Hi 🎉 world" (10 chars) where the source has
    // "Hi :tada: world" (15 bytes). Selecting through "world" must match the
    // block and map past the substituted `:tada:` to byte 15.
    let source = "Hi :tada: world\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "Hi \u{1F389} world", offsetInBlock: 10)
    #expect(offset == 15)
  }

  @Test func offsetJustAfterEmojiLandsAfterTheShortcode() {
    // Selecting "Hi 🎉" (offset 4) places the marker right after `:tada:`
    // (byte 9), as "Hi :tada:[^…] world".
    let source = "Hi :tada: world\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "Hi \u{1F389} world", offsetInBlock: 4)
    #expect(offset == 9)
  }

  @Test func offsetBeforeEmojiNeverSplitsTheShortcode() {
    // Selecting just "Hi " (offset 3, ending right before the emoji) must anchor
    // before `:tada:` (byte 3), never inside it — splitting it would corrupt
    // both the emoji and the marker.
    let source = "Hi :tada: world\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "Hi \u{1F389} world", offsetInBlock: 3)
    #expect(offset == 3)
  }

  @Test func unresolvableOffsetFallsBackToBlockEnd() {
    // The block matches but the offset overruns its text. Rather than refusing,
    // the anchor degrades to the block's end (byte 12, just after the period).
    let source = "Hello world.\n"
    let offset = CommentAnchor.insertionOffset(
      in: source, blockText: "Hello world.", offsetInBlock: 999)
    #expect(offset == 12)
  }
}
