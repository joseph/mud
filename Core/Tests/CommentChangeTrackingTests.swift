import Testing

@testable import MudCore

/// Up-mode change tracking diffs the (footnote/comment-processed) new render
/// against the waypoint. The waypoint must be processed the same way, else the
/// injected markers diff against the raw `[^label]` syntax and every unchanged
/// footnote/comment is flagged as a spurious change.
@Suite("Comment change tracking")
struct CommentChangeTrackingTests {

  @Test func unchangedCommentIsNotFlagged() {
    let md = """
      The quick brown fox[^comment-a] jumped.

      [^comment-a]: > brown fox

          A note.
      """
    var options = RenderOptions()
    options.waypoint = ParsedMarkdown(md)  // identical previous version

    // Body fragment, not the wrapped document — the full document inlines
    // mud-changes.css (whose selectors contain "mud-change") whenever a
    // waypoint is set, which would mask the real signal.
    let body = MudCore.renderUpToHTML(md, options: options)
    #expect(!body.contains("mud-change"))
    #expect(!body.contains("data-change-id"))
  }

  @Test func unchangedFootnoteIsNotFlagged() {
    let md = "A sentence[^1].\n\n[^1]: A footnote.\n"
    var options = RenderOptions()
    options.waypoint = ParsedMarkdown(md)

    let body = MudCore.renderUpToHTML(md, options: options)
    #expect(!body.contains("mud-change"))
  }

  @Test func realEditStillFlaggedAlongsideComment() {
    let old = "The fox[^comment-a] ran.\n\n[^comment-a]: A note.\n"
    let new = "The fox[^comment-a] jumped.\n\n[^comment-a]: A note.\n"
    var options = RenderOptions()
    options.waypoint = ParsedMarkdown(old)

    let body = MudCore.renderUpToHTML(new, options: options)
    // The text edit is still tracked; the unchanged comment doesn't break it.
    #expect(body.contains("mud-change"))
  }
}
