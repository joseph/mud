import Testing

@testable import MudCore

/// Confirms the comment JS/CSS resources are bundled and reachable through
/// `HTMLTemplate`, so a packaging regression fails here rather than silently
/// in the app.
@Suite("Comment resources")
struct CommentResourcesTests {

  @Test func commentsJSIsBundled() {
    let js = HTMLTemplate.mudCommentsJS
    #expect(js.contains("Mud.comments"))
    #expect(js.contains("mudCommentDraft"))
    #expect(js.contains("mud-comment-highlight"))
  }

  @Test func commentCSSIsInlined() {
    // mud-up.css is inlined into every Up document via wrapUp.
    let html = MudCore.renderUpModeDocument(
      "x[^comment-a].\n\n[^comment-a]: Note.\n", options: RenderOptions())
    #expect(html.contains(".mud-comment-marker"))
    #expect(html.contains(".mud-comment-highlight.is-active"))
    #expect(html.contains(".comments.is-print-only"))
  }
}
