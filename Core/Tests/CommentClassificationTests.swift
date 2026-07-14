import Testing

@testable import MudCore

/// Covers `FootnoteProcessor.process` classifying comment definitions apart from
/// authorial footnotes, and the render emitting the matching markers: `process`
/// surfaces comment definitions as `Comment`s and numbers authorial footnotes
/// counting only authorial references (so comments leave no gap), while the
/// render draws a `💬` marker for a comment reference and a numbered `<sup>` for
/// a footnote reference.
@Suite("Comment classification")
struct CommentClassificationTests {

  @Test func commentReferenceBecomesMarkerNotFootnote() {
    let md = """
      The quick brown fox[^comment-a] jumped.

      [^comment-a]: > brown fox

          {JP @ 2026-06-01 18:33}: Nice.
      """
    let result = FootnoteProcessor.process(md, mode: .section)

    // Classified as a comment, not an authorial footnote.
    #expect(result.footnotes.isEmpty)
    #expect(result.comments.count == 1)
    #expect(result.comments[0].label == "comment-a")
    #expect(result.comments[0].ordinal == 1)
    #expect(result.comments[0].quotation == "brown fox")
    #expect(result.comments[0].messages.count == 1)
    #expect(result.comments[0].messages[0].author == "JP")
    #expect(result.comments[0].messages[0].body == "Nice.")

    // The render diverts the reference to the comment marker, not a numbered
    // footnote sup, and consumes the raw `[^comment-a]` token.
    let body = MudCore.renderUpToHTML(md)
    #expect(body.contains("class=\"mud-comment-marker\""))
    #expect(body.contains("data-mud-label=\"comment-a\""))
    #expect(body.contains("href=\"#cmt-comment-a\""))
    #expect(!body.contains("footnote-ref"))
    #expect(!body.contains("[^comment-a]"))
  }

  @Test func authorialNumbersSkipComments() {
    // C8: footnote numbers count only authorial references; the comment occupies
    // no number, so the footnotes are 1 and 2 (not 1 and 3).
    let md = """
      First[^1] then a comment[^comment-a] then second[^2].

      [^1]: One.

      [^comment-a]: A note.

      [^2]: Two.
      """
    let result = FootnoteProcessor.process(md, mode: .section)

    #expect(result.footnotes.map(\.label) == ["1", "2"])
    #expect(result.footnotes.map(\.number) == [1, 2])
    #expect(result.comments.count == 1)
    #expect(result.comments[0].label == "comment-a")
    #expect(result.comments[0].messages[0].body == "A note.")

    // The render numbers the authorial markers 1 and 2 with no gap for the
    // comment, and draws the comment as a `💬` marker.
    let body = MudCore.renderUpToHTML(md)
    #expect(body.contains("data-fn-num=\"1\""))
    #expect(body.contains("data-fn-num=\"2\""))
    #expect(!body.contains("data-fn-num=\"3\""))
    #expect(body.contains("class=\"mud-comment-marker\""))
  }

  @Test func commentOrdinalsFollowReferenceOrder() {
    // Definitions are listed a-then-b but referenced b-then-a; ordinals follow
    // the reference (rendered) order.
    let md = """
      Beta[^comment-b] then alpha[^comment-a].

      [^comment-a]: First.

      [^comment-b]: Second.
      """
    let result = FootnoteProcessor.process(md, mode: .section)

    #expect(result.comments.map(\.label) == ["comment-b", "comment-a"])
    #expect(result.comments.map(\.ordinal) == [1, 2])
  }
}
