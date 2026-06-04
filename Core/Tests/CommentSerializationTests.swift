import Foundation
import Testing

@testable import MudCore

/// Mirrors the worked examples in `Doc/Examples/comments-spec.md`. Each `parse`
/// test feeds the **de-indented** definition body (what
/// `FootnoteProcessor.renderDefinitionBody` produces) and asserts the declared
/// properties; the round-trip tests assert
/// `parse(serialize(quotation, messages)) == (quotation, messages)`.
@Suite("CommentSerialization")
struct CommentSerializationTests {

  /// Builds a `Date` the same way the parser does, so comparisons are
  /// timezone-independent.
  private func ts(_ s: String) -> Date? {
    CommentSerialization.parseTimestamp(Substring(s))
  }

  // MARK: - Spec examples (parse)

  @Test func commentA_bareComment() {
    let (quotation, messages) = CommentSerialization.parse(
      "The simplest comment. No quotation, no author, no timestamp.")
    #expect(quotation == nil)
    #expect(messages.count == 1)
    #expect(messages[0].author == nil)
    #expect(messages[0].created == nil)
    #expect(messages[0].body
      == "The simplest comment. No quotation, no author, no timestamp.")
  }

  @Test func commentB_quotedNoProperties() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > fox

      A quoted comment, no properties.
      """)
    #expect(quotation == "fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == nil)
    #expect(messages[0].created == nil)
    #expect(messages[0].body == "A quoted comment, no properties.")
  }

  @Test func commentC_attributedInlineBody() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > brown fox

      JP (2026-06-01 18:33): A comment with author and timestamp.
      """)
    #expect(quotation == "brown fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].created == ts("2026-06-01 18:33"))
    #expect(messages[0].body == "A comment with author and timestamp.")
  }

  @Test func commentD_threadWithReplyBlockquote() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > quick brown fox

      💬 JP (2026-06-01 18:33):

      First comment in thread.

      💬 Claude Opus 4.8 (2026-06-01 18:33:13):

      > First comment in thread.

      Second comment in thread.
      """)
    #expect(quotation == "quick brown fox")
    #expect(messages.count == 2)
    #expect(messages[0].author == "JP")
    #expect(messages[0].created == ts("2026-06-01 18:33"))
    #expect(messages[0].body == "First comment in thread.")
    #expect(messages[1].author == "Claude Opus 4.8")
    #expect(messages[1].created == ts("2026-06-01 18:33:13"))
    // The reply's own blockquote stays in its body, not the root quotation.
    #expect(messages[1].body.contains("First comment in thread."))
    #expect(messages[1].body.contains("Second comment in thread."))
    #expect(messages[1].body.hasPrefix(">"))
  }

  @Test func commentE_looksThreadedButIsnt() {
    // Bare `Author (ts):` lines without `💬` do NOT split messages.
    let (quotation, messages) = CommentSerialization.parse(
      """
      > The quick brown fox

      JP (2026-06-01 18:33):

      First comment in thread.

      Claude Opus 4.8 (2026-06-01 18:33:13):

      Second comment in thread.
      """)
    #expect(quotation == "The quick brown fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].created == ts("2026-06-01 18:33"))
    // The second author line survives verbatim in the single message's body.
    #expect(messages[0].body.contains("Claude Opus 4.8 (2026-06-01 18:33:13):"))
    #expect(messages[0].body.contains("Second comment in thread."))
  }

  @Test func commentF_emojiInProseDoesNotSplit() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > fox

      💬 JP (2026-06-01 18:33):

      A single comment. The body mentions a 💬 mid-sentence, which must not split.
      """)
    #expect(quotation == "fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].body.contains("💬"))
  }

  @Test func commentG_headerWithoutColon() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > brown

      💬 JP (2026-06-01 18:33)

      The colon after the timestamp is optional; this header omits it.
      """)
    #expect(quotation == "brown")
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].created == ts("2026-06-01 18:33"))
    #expect(messages[0].body
      == "The colon after the timestamp is optional; this header omits it.")
  }

  @Test func commentH_generalAndThreaded() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      💬 JP (2026-06-01 18:33):

      A general comment with no quotation, but with a thread.

      💬 Claude Opus 4.8 (2026-06-01 18:33:13):

      A reply, also with no document quotation.
      """)
    #expect(quotation == nil)
    #expect(messages.count == 2)
    #expect(messages[0].author == "JP")
    #expect(messages[0].body
      == "A general comment with no quotation, but with a thread.")
    #expect(messages[1].author == "Claude Opus 4.8")
    #expect(messages[1].body == "A reply, also with no document quotation.")
  }

  // MARK: - Attribution / timestamp grammar

  @Test func attribution_parsesAuthorAndTimestamp() {
    let (author, created, body) = CommentSerialization.parseAttribution(
      "JP (2026-06-01 18:33): the body")
    #expect(author == "JP")
    #expect(created == ts("2026-06-01 18:33"))
    #expect(body == "the body")
  }

  @Test func attribution_nonTimestampParenthetical_isAllBody() {
    let (author, created, body) = CommentSerialization.parseAttribution(
      "A quoted comment, no properties.")
    #expect(author == nil)
    #expect(created == nil)
    #expect(body == "A quoted comment, no properties.")
  }

  @Test func timestamp_secondsOptional() {
    #expect(ts("2026-06-01 18:33") != nil)
    #expect(ts("2026-06-01 18:33:13") != nil)
    #expect(ts("not a timestamp") == nil)
    #expect(ts("2026-06-01") == nil)
  }

  // MARK: - Round trip

  private func roundTrip(quotation: String?, _ messages: [CommentMessage]) {
    let serialized = CommentSerialization.serialize(quotation: quotation, messages)
    let (q, m) = CommentSerialization.parse(serialized)
    #expect(q == quotation)
    #expect(m == messages)
  }

  @Test func roundTrip_generalUnattributed() {
    roundTrip(
      quotation: nil,
      [CommentMessage(author: nil, created: nil, body: "Just an observation.")])
  }

  @Test func roundTrip_quotedUnattributed() {
    roundTrip(
      quotation: "fox",
      [CommentMessage(author: nil, created: nil, body: "A note.")])
  }

  @Test func roundTrip_attributed() {
    roundTrip(
      quotation: "brown fox",
      [CommentMessage(
        author: "JP", created: ts("2026-06-01 18:33:00"), body: "A comment.")])
  }

  @Test func roundTrip_thread() {
    roundTrip(
      quotation: "quick brown fox",
      [
        CommentMessage(
          author: "JP", created: ts("2026-06-01 18:33:00"), body: "First."),
        CommentMessage(
          author: "Claude Opus 4.8", created: ts("2026-06-01 18:33:13"),
          body: "Second."),
      ])
  }

  @Test func roundTrip_replyWithBlockquoteBody() {
    roundTrip(
      quotation: "quick brown fox",
      [
        CommentMessage(
          author: "JP", created: ts("2026-06-01 18:33:00"), body: "First."),
        CommentMessage(
          author: "Claude Opus 4.8", created: ts("2026-06-01 18:33:13"),
          body: "> First.\n\nSecond."),
      ])
  }
}
