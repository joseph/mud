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

  @Test func commentsJSCarriesSharedAnchorPart() {
    // mudCommentsJS concatenates mud-comment-anchor.js ahead of the read-side
    // file, so the one injected/inlined string publishes Mud.commentAnchor and
    // then Mud.comments. Both comment scripts consume the shared primitives.
    let read = HTMLTemplate.mudCommentsJS
    #expect(read.contains("Mud.commentAnchor"))
    #expect(read.contains("Mud.comments"))
    #expect(HTMLTemplate.mudCommentsEditJS.contains("commentAnchor"))
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

  @Test func readSideListsWriteSideSwiftCallableSlots() {
    // The read-side API literal declares resolveCompose as a null slot so it
    // lists the whole Swift-callable surface, even though the write side
    // (mud-comments-edit.js) supplies the real function.
    let read = HTMLTemplate.mudCommentsJS
    #expect(read.contains("resolveCompose"))
    let write = HTMLTemplate.mudCommentsEditJS
    #expect(write.contains("resolveCompose"))
  }

  @Test func composeFailedClassAgreesAcrossJSAndCSS() {
    // A submission that didn't land is marked by this class alone:
    // mud-comments-edit.js sets it, and mud-comments-edit.css turns the whole
    // form — textarea, Cancel, Done — the danger color off it. Nothing else
    // records the state, so a rename has to reach both files.
    var editable = RenderOptions()
    editable.commentsEditable = true
    let html = MudCore.renderUpModeDocument(
      "x[^comment-a].\n\n[^comment-a]: Note.\n", options: editable)
    #expect(html.contains(".mud-compose.is-failed"))
    #expect(html.contains("--mud-danger"))
    #expect(HTMLTemplate.mudCommentsEditJS.contains("\"is-failed\""))
  }

  @Test func markerClassAgreesWithTheJSLayer() {
    // The Swift emitter, the read-side projection (mud-comments.js), and the
    // shared anchor part (mud-comment-anchor.js) that the write-side locator
    // consumes all name the marker element by this class; a rename must reach
    // all three. mudCommentsJS bundles the anchor part ahead of the read side,
    // so it carries both JS uses.
    let marker = FootnoteProcessor.commentMarkerClass
    #expect(HTMLTemplate.mudCommentsJS.contains(marker))
    #expect(HTMLTemplate.loadResource("mud-comment-anchor", type: "js")?
      .contains(marker) == true)
  }
}
