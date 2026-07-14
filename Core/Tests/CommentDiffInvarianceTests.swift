import Testing

@testable import MudCore

/// Comments are metadata, not document content: adding or removing one must be
/// invisible to change tracking across every diff consumer. The shared fix
/// lives in `CMarkBlockMatcher.collectLeafBlocks` (skip comment-def blocks,
/// normalize comment tokens out of fingerprints), so these exercise the matcher
/// directly plus the Down-mode render and the `removeComments` /
/// `commentDefinitionLineRanges` / `stripCommentTokens` helpers it relies on.
@Suite("Comment diff invariance")
struct CommentDiffInvarianceTests {

  // MARK: - CMarkBlockMatcher (covers sidebar + Down, RAW source)

  /// The Down/sidebar policy: plain footnote definitions diff like ordinary
  /// content; comment definitions stay invisible. (No plain footnote
  /// definitions appear in these cases, so `.skipAll` would agree.)
  private static let rawPolicy: CMarkDefinitionDiffPolicy = .descendPlainFootnotes

  @Test func addingACommentLeavesAllBlocksUnchanged() {
    let old = "The quick brown fox jumped.\n"
    let new = """
      The quick brown fox[^comment-a] jumped.

      [^comment-a]: A note.
      """
    let matches = CMarkBlockMatcher.match(
      old: CMarkDocument(parsing: old)!, new: CMarkDocument(parsing: new)!,
      definitionPolicy: Self.rawPolicy)
    #expect(matches.count == 1)
    #expect(matches.allSatisfy { $0.isUnchanged })
  }

  @Test func removingACommentLeavesAllBlocksUnchanged() {
    let old = """
      The quick brown fox[^comment-a] jumped.

      [^comment-a]: A note.
      """
    let new = "The quick brown fox jumped.\n"
    let matches = CMarkBlockMatcher.match(
      old: CMarkDocument(parsing: old)!, new: CMarkDocument(parsing: new)!,
      definitionPolicy: Self.rawPolicy)
    #expect(matches.count == 1)
    #expect(matches.allSatisfy { $0.isUnchanged })
  }

  @Test func realEditAlongsideACommentReportsOnlyTheBodyChange() {
    // A genuine word change plus a comment added in the same save: the diff
    // must match what the word change alone would produce.
    let oldPlain = "The fox ran.\n\nSecond para.\n"
    let newPlain = "The fox jumped.\n\nSecond para.\n"
    let newCommented = """
      The fox[^comment-a] jumped.

      Second para.

      [^comment-a]: A note.
      """
    let plain = CMarkBlockMatcher.match(
      old: CMarkDocument(parsing: oldPlain)!,
      new: CMarkDocument(parsing: newPlain)!, definitionPolicy: Self.rawPolicy)
    let commented = CMarkBlockMatcher.match(
      old: CMarkDocument(parsing: oldPlain)!,
      new: CMarkDocument(parsing: newCommented)!, definitionPolicy: Self.rawPolicy)
    #expect(commented.count == plain.count)
    #expect(commented.filter { $0.isUnchanged }.count
      == plain.filter { $0.isUnchanged }.count)
    // The second paragraph survives unchanged either way.
    #expect(commented.contains { $0.isUnchanged })
  }

  @Test func leafBlockCountUnaffectedByACommentDefinition() {
    let plain = "Para one.\n\nPara two.\n"
    let commented = """
      Para one.[^comment-a]

      Para two.

      [^comment-a]: A note.
      """
    #expect(CMarkBlockMatcher.collectLeafBlocks(
      from: CMarkDocument(parsing: plain)!, policy: Self.rawPolicy).count
      == CMarkBlockMatcher.collectLeafBlocks(
        from: CMarkDocument(parsing: commented)!, policy: Self.rawPolicy).count)
  }

  // MARK: - Down-mode render

  @Test func addingACommentProducesNoDownModeMarkers() {
    let old = "The fox jumped.\n"
    let new = """
      The fox[^comment-a] jumped.

      [^comment-a]: A note.
      """
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    // Body fragment (not the wrapped document) so inlined CSS selectors don't
    // mask the signal.
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(!html.contains("dl-ins"))
    #expect(!html.contains("dl-del"))
    #expect(!html.contains("data-change-id"))
  }

  @Test func realDownModeEditStillHighlightedAlongsideAComment() {
    let old = "The fox ran.\n"
    let new = """
      The fox[^comment-a] jumped.

      [^comment-a]: A note.
      """
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("data-change-id"))
  }

  // MARK: - removeComments

  @Test func removeCommentsLeavesCommentFreeSourceUnchanged() {
    let src = "Plain text.\n\nMore text.\n"
    #expect(MudCore.removeComments(src) == src)
  }

  @Test func removeCommentsStripsRefsAndDefinitions() {
    let src = "Fox[^comment-a] ran.\n\n[^comment-a]: A note.\n"
    let stripped = MudCore.removeComments(src)
    #expect(!stripped.contains("comment-a"))
    #expect(!stripped.contains("[^"))
    #expect(stripped.contains("Fox ran."))
  }

  @Test func removeCommentsIsIdempotent() {
    let src = "Fox[^comment-a] ran.\n\n[^comment-a]: A note.\n"
    let once = MudCore.removeComments(src)
    #expect(MudCore.removeComments(once) == once)
  }

  @Test func removeCommentsKeepsAuthorialFootnotes() {
    let src = "A line[^1] and a fox[^comment-a].\n\n[^1]: real.\n\n[^comment-a]: note.\n"
    let stripped = MudCore.removeComments(src)
    #expect(stripped.contains("[^1]"))
    #expect(stripped.contains("[^1]: real."))
    #expect(!stripped.contains("comment-a"))
  }

  // MARK: - commentDefinitionLineRanges

  @Test func commentDefinitionLineRangesEmptyWhenCommentFree() {
    #expect(FootnoteProcessor.commentDefinitionLineRanges("Plain.\n").isEmpty)
    #expect(FootnoteProcessor.commentDefinitionLineRanges(
      "A line[^1].\n\n[^1]: real footnote.\n").isEmpty)
  }

  @Test func commentDefinitionLineRangesCoversTheDefinition() {
    let src = "Fox[^comment-a] ran.\n\n[^comment-a]: A note.\n"
    let ranges = FootnoteProcessor.commentDefinitionLineRanges(src)
    #expect(ranges.count == 1)
    #expect(ranges.first?.contains(3) == true)  // the `[^comment-a]:` line
  }

  // MARK: - stripCommentTokens

  @Test func stripCommentTokensIsNoOpOffThePath() {
    #expect(FootnoteProcessor.stripCommentTokens("plain text") == "plain text")
  }

  @Test func stripCommentTokensRemovesRawRef() {
    #expect(FootnoteProcessor.stripCommentTokens("Fox[^comment-a] ran.")
      == "Fox ran.")
  }

  @Test func stripCommentTokensRemovesBakedMarker() {
    let baked = "Fox<a class=\"mud-comment-marker\" id=\"cmtref-comment-a\""
      + " data-mud-label=\"comment-a\" href=\"#cmt-comment-a\">💬</a> ran."
    #expect(FootnoteProcessor.stripCommentTokens(baked) == "Fox ran.")
  }

  @Test func stripCommentTokensRemovesTheMarkerTheEmitterEmits() {
    // The strip pattern is built from the same constants the emitter uses;
    // this pins that derivation against the real marker the render emits (via
    // `commentMarkerHTML`, the same function the Up visitor calls), not a
    // hand-copied marker string — label variants included.
    for label in ["comment-a", "comment-intro_2-b"] {
      let marker = FootnoteProcessor.commentMarkerHTML(label: label)
      #expect(marker.contains(FootnoteProcessor.commentMarkerClass))
      #expect(FootnoteProcessor.stripCommentTokens("Fox\(marker) ran.")
        == "Fox ran.")
    }
  }
}

private extension CMarkBlockMatch {
  /// True when this match is an unchanged pair (the legacy `BlockMatch`
  /// exposed the same convenience).
  var isUnchanged: Bool {
    if case .unchanged = self { return true }
    return false
  }
}
