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
    #expect(js.contains("mud-capsule"))
    #expect(js.contains("mud-comment-highlight"))
  }

  @Test func commentsEditJSIsBundled() {
    let js = HTMLTemplate.mudCommentsEditJS
    #expect(js.contains("mudCommentSubmit"))
    #expect(js.contains("addFromSelection"))
  }

  @Test func readCommentCSSIsAlwaysInlined() {
    // mud-comments.css (read side) is inlined into every Up document via wrapUp,
    // exports included — so the marker, highlight, and bottom section render.
    let html = MudCore.renderUpModeDocument(
      "x[^comment-a].\n\n[^comment-a]: Note.\n", options: RenderOptions())
    #expect(html.contains(".mud-comment-marker"))
    #expect(html.contains(".mud-comment-highlight.is-active"))
    #expect(html.contains(".comments.is-print-only"))
  }

  @Test func editCommentCSSIsGatedOnCommentsEditable() {
    let markdown = "x[^comment-a].\n\n[^comment-a]: Note.\n"
    // A read-only export omits the write-side styles (compose box, puff, etc.).
    let readOnly = MudCore.renderUpModeDocument(markdown, options: RenderOptions())
    #expect(!readOnly.contains("mud-capsule-puff"))
    #expect(!readOnly.contains(".mud-compose"))

    // The app's editable view embeds them.
    var editable = RenderOptions()
    editable.commentsEditable = true
    let html = MudCore.renderUpModeDocument(markdown, options: editable)
    #expect(html.contains("mud-capsule-puff"))
    #expect(html.contains(".mud-compose"))
  }

  @Test func markerClassAgreesWithTheJSLayer() {
    // The Swift emitter, the read-side projection (mud-comments.js), and the
    // write-side locator (mud-comments-edit.js) all name the marker element by
    // this class; a rename must reach all three.
    #expect(HTMLTemplate.mudCommentsJS.contains(
      FootnoteProcessor.commentMarkerClass))
    #expect(HTMLTemplate.mudCommentsEditJS.contains(
      FootnoteProcessor.commentMarkerClass))
  }
}
