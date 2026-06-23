import Testing

@testable import MudCore

/// Covers MudCore emitting the bottom `<section class="comments">` for export
/// paths and marking it `is-print-only` in `.interactive` mode.
@Suite("Comment section rendering")
struct CommentSectionRenderingTests {

  @Test func exportRendersCommentsSectionAfterFootnotes() {
    let md = """
      Body[^1] with a comment[^comment-a].

      [^1]: A footnote.

      [^comment-a]: > body

          JP (2026-06-01 18:33): Nice.
      """
    let html = MudCore.renderUpModeDocument(md, options: RenderOptions())

    #expect(html.contains("<section class=\"comments\""))
    #expect(html.contains("id=\"cmt-comment-a\""))
    #expect(html.contains("mud-comment-quote"))
    #expect(html.contains("mud-comment-attribution"))
    #expect(html.contains("JP"))

    // The footnotes section precedes the comments section.
    let fn = html.range(of: "class=\"footnotes")
    let cmt = html.range(of: "class=\"comments")
    #expect(fn != nil && cmt != nil)
    if let fn, let cmt { #expect(fn.lowerBound < cmt.lowerBound) }
  }

  @Test func interactiveModeMarksSectionPrintOnly() {
    let md = "x[^comment-a].\n\n[^comment-a]: Note.\n"
    var options = RenderOptions()
    options.commentMode = .interactive
    let html = MudCore.renderUpModeDocument(md, options: options)

    #expect(html.contains("class=\"comments is-print-only\""))
  }

  @Test func sectionModeIsVisible() {
    let md = "x[^comment-a].\n\n[^comment-a]: Note.\n"
    let html = MudCore.renderUpModeDocument(md, options: RenderOptions())

    #expect(html.contains("<section class=\"comments\" data-comments>"))
    #expect(!html.contains("comments is-print-only"))
  }

  @Test func threadDocumentRendersQuotationAndMessages() {
    let comment = Comment(
      label: "comment-a", ordinal: 1, quotation: "the quoted text",
      messages: [CommentMessage(author: "JP", created: nil, body: "A remark.")])
    let doc = MudCore.renderCommentThreadDocument(
      comment, options: RenderOptions())

    #expect(doc.contains("comment-thread-popover"))
    #expect(doc.contains("mud-comment-quote"))
    #expect(doc.contains("the quoted text"))
    #expect(doc.contains("A remark."))
    #expect(doc.contains("JP"))
    // A self-contained document, not a fragment.
    #expect(doc.contains("<body"))
  }

  @Test func threadDocumentForNewCommentShowsQuotationOnly() {
    let comment = Comment(
      label: "", ordinal: 0, quotation: "what is being commented on",
      messages: [])
    let doc = MudCore.renderCommentThreadDocument(
      comment, options: RenderOptions())

    #expect(doc.contains("what is being commented on"))
    // No message block emitted (the CSS selector mentions the class, so match
    // the element's attribute form, not a bare substring).
    #expect(!doc.contains("class=\"mud-comment-message\""))
  }

  @Test func parseCommentsReturnsModel() {
    let md = """
      Body[^comment-a].

      [^comment-a]: > quoted text

          JP (2026-06-01 18:33): A remark.
      """
    let comments = MudCore.parseComments(md)

    #expect(comments.count == 1)
    #expect(comments.first?.label == "comment-a")
    #expect(comments.first?.quotation?.contains("quoted text") == true)
    #expect(comments.first?.messages.isEmpty == false)
  }
}
