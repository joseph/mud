import Testing

@testable import MudCore

/// Covers `FootnoteProcessor.process` classifying comment definitions apart from
/// authorial footnotes: comment references become `[⋯]` markers, comment
/// definitions are surfaced as `Comment`s, and authorial footnote numbers count
/// only authorial references (so comments leave no gap).
@Suite("Comment classification")
struct CommentClassificationTests {

  @Test func commentReferenceBecomesMarkerNotFootnote() {
    let md = """
      The quick brown fox[^comment-a] jumped.

      [^comment-a]: > brown fox

          {JP @ 2026-06-01 18:33}: Nice.
      """
    let result = FootnoteProcessor.process(md, mode: .section)

    // Diverted to the comment marker, not a numbered footnote sup.
    #expect(result.transformedMarkdown.contains("class=\"mud-comment-marker\""))
    #expect(result.transformedMarkdown.contains("data-mud-label=\"comment-a\""))
    #expect(result.transformedMarkdown.contains("href=\"#cmt-comment-a\""))
    #expect(!result.transformedMarkdown.contains("footnote-ref"))
    // Both the reference and the definition are gone from the body.
    #expect(!result.transformedMarkdown.contains("[^comment-a]"))
    #expect(result.footnotes.isEmpty)

    // The comment is parsed into the model.
    #expect(result.comments.count == 1)
    #expect(result.comments[0].label == "comment-a")
    #expect(result.comments[0].ordinal == 1)
    #expect(result.comments[0].quotation == "brown fox")
    #expect(result.comments[0].messages.count == 1)
    #expect(result.comments[0].messages[0].author == "JP")
    #expect(result.comments[0].messages[0].body == "Nice.")
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
    #expect(result.transformedMarkdown.contains("data-fn-num=\"1\""))
    #expect(result.transformedMarkdown.contains("data-fn-num=\"2\""))
    #expect(!result.transformedMarkdown.contains("data-fn-num=\"3\""))
    #expect(result.transformedMarkdown.contains("class=\"mud-comment-marker\""))

    #expect(result.comments.count == 1)
    #expect(result.comments[0].label == "comment-a")
    #expect(result.comments[0].messages[0].body == "A note.")
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
