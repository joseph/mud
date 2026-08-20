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
    // The read-side API literal declares resolveSubmission as a null slot so it
    // lists the whole Swift-callable surface, even though the write side
    // (mud-comments-edit.js) supplies the real function.
    let read = HTMLTemplate.mudCommentsJS
    #expect(read.contains("resolveSubmission"))
    let write = HTMLTemplate.mudCommentsEditJS
    #expect(write.contains("resolveSubmission"))
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

  @Test func quotationRuleIsSharedByBothSides() {
    // Which rendered characters a quotation may hold is decided once, by
    // `rangeSlices` in mud-comment-anchor.js. The write side builds the stored
    // text with it, and the read side leaves the same elements out of the flat
    // text it searches. If either side stops asking, a quotation carrying a
    // tracked change's removed words or a footnote's number is written to the
    // file and then never found again.
    let anchorJS = HTMLTemplate.loadResource("mud-comment-anchor", type: "js") ?? ""
    #expect(anchorJS.contains("function rangeSlices("))
    #expect(anchorJS.contains("rangeSlices: rangeSlices"))

    // Write side: the quotation, and the provisional highlight painted over the
    // selection while the comment is composed, are the same characters.
    #expect(HTMLTemplate.mudCommentsEditJS.contains(
      "anchor.slicesText(anchor.rangeSlices(range, container))"))
    let read = HTMLTemplate.mudCommentsJS
    #expect(read.contains("anchor.rangeSlices(range, container)"))

    // Read side: the flat text `buildIndex` searches applies the same rules.
    #expect(read.contains("if (isMarkerElement(node) || anchor.isSkippedSubtree(node)) return;"))
    #expect(read.contains("if (anchor.isBottomSection(node)) return;"))
  }

  @Test func avatarFallbackAgreesAcrossSwiftAndJS() {
    // A message with no avatar of its own is drawn with the same glyph on both
    // sides: CommentHTMLRenderer writes it into the bottom section, and
    // mud-comments.js supplies it when projecting a capsule from a message div
    // with no `data-mud-avatar`. Only Swift can state the constant, so the JS
    // repeats it — a change to one has to reach the other.
    #expect(HTMLTemplate.mudCommentsJS.contains(
      "|| \"\(CommentAvatar.fallback)\""))
  }

  @Test func stubHeightAgreesAcrossJSAndCSS() {
    // A folded section's comments collapse into one sliver capsule.
    // mud-comments.js places it (STUB_H, halved, so the sliver straddles the
    // heading's bottom edge) and mud-comments.css draws it. Only the CSS can
    // state a height and only the JS can do the arithmetic, so the number is
    // written twice; if the two drift the stub sits off its line. Read the JS
    // value and require the rule to use it.
    let js = HTMLTemplate.mudCommentsJS
    let css = HTMLTemplate.loadResource("mud-comments", type: "css") ?? ""

    guard let height = Self.number(in: js, after: "var STUB_H = ") else {
      Issue.record("mud-comments.js no longer declares `var STUB_H = <n>`")
      return
    }
    guard let rule = css.range(of: ".mud-capsule.is-stub {") else {
      Issue.record("mud-comments.css no longer has a `.mud-capsule.is-stub` rule")
      return
    }
    let body = css[rule.upperBound...].prefix { $0 != "}" }
    #expect(body.contains("height: \(height)px;"))
  }

  /// The run of digits following `marker`, or nil when `marker` isn't there.
  private static func number(in source: String, after marker: String) -> Int? {
    guard let start = source.range(of: marker)?.upperBound else { return nil }
    return Int(source[start...].prefix(while: \.isNumber))
  }
}
