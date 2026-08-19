import Foundation
import Testing

@testable import MudCore

/// Mirrors the worked examples in `Doc/Guides/spec-comments.md`. Each `parse`
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

  @Test func commentB_quotedNoAttributes() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > fox

      A quoted comment, no attributes.
      """)
    #expect(quotation == "fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == nil)
    #expect(messages[0].created == nil)
    #expect(messages[0].body == "A quoted comment, no attributes.")
  }

  @Test func commentC_attributedInlineBody() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > brown fox

      {JP @ 2026-06-01 18:33}: A message with author and timestamp.
      """)
    #expect(quotation == "brown fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].created == ts("2026-06-01 18:33"))
    #expect(messages[0].body == "A message with author and timestamp.")
  }

  @Test func commentD_threadWithReplyBlockquote() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > quick brown fox

      💬 {JP @ 2026-06-01 18:33}:

      First message in the thread.

      💬 {Claude Opus 4.8 @ 2026-06-01 18:33:13}:

      > First message in the thread.

      Second message in the thread.
      """)
    #expect(quotation == "quick brown fox")
    #expect(messages.count == 2)
    #expect(messages[0].author == "JP")
    #expect(messages[0].created == ts("2026-06-01 18:33"))
    #expect(messages[0].body == "First message in the thread.")
    #expect(messages[1].author == "Claude Opus 4.8")
    #expect(messages[1].created == ts("2026-06-01 18:33:13"))
    // The reply's own blockquote stays in its body, not the root quotation.
    #expect(messages[1].body.contains("First message in the thread."))
    #expect(messages[1].body.contains("Second message in the thread."))
    #expect(messages[1].body.hasPrefix(">"))
  }

  @Test func commentE_braceHeaderSplitsWithoutEmoji() {
    // A `{…}:` block with no leading `💬` still begins a new message, so this
    // parses as two messages (reverses the original "only 💬 splits" rule).
    let (quotation, messages) = CommentSerialization.parse(
      """
      > The quick brown fox

      {JP @ 2026-06-01 18:33}:

      First message in the thread.

      {Claude Opus 4.8 @ 2026-06-01 18:33:13}:

      Second message in the thread.
      """)
    #expect(quotation == "The quick brown fox")
    #expect(messages.count == 2)
    #expect(messages[0].author == "JP")
    #expect(messages[0].created == ts("2026-06-01 18:33"))
    #expect(messages[0].body == "First message in the thread.")
    #expect(messages[1].author == "Claude Opus 4.8")
    #expect(messages[1].created == ts("2026-06-01 18:33:13"))
    #expect(messages[1].body == "Second message in the thread.")
  }

  @Test func commentF_emojiInProseDoesNotSplit() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > fox

      💬 {JP @ 2026-06-01 18:33}:

      A single message. The body mentions a 💬 mid-sentence, which must not split.
      """)
    #expect(quotation == "fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].body.contains("💬"))
  }

  @Test func commentG_headerWithoutColon() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > brown fox

      💬 {JP @ 2026-06-01 18:33}

      The colon after the closing brace is optional; this block omits it.
      """)
    #expect(quotation == "brown fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].created == ts("2026-06-01 18:33"))
    #expect(messages[0].body
      == "The colon after the closing brace is optional; this block omits it.")
  }

  @Test func commentH_generalAndThreaded() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      💬 {JP @ 2026-06-01 18:33}:

      A general message with no quotation, but part of a thread.

      💬 {Claude Opus 4.8 @ 2026-06-01 18:33:13}:

      A reply, also with no document quotation.
      """)
    #expect(quotation == nil)
    #expect(messages.count == 2)
    #expect(messages[0].author == "JP")
    #expect(messages[0].body
      == "A general message with no quotation, but part of a thread.")
    #expect(messages[1].author == "Claude Opus 4.8")
    #expect(messages[1].body == "A reply, also with no document quotation.")
  }

  @Test func commentI_authorOnly() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > fox

      {JP}: A message with an author but no timestamp.
      """)
    #expect(quotation == "fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].created == nil)
    #expect(messages[0].body == "A message with an author but no timestamp.")
  }

  @Test func commentJ_dateOnlyNoAuthor() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > fox

      {@ 2026-06-01}: A message with a timestamp but no author.
      """)
    #expect(quotation == "fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == nil)
    #expect(messages[0].created == ts("2026-06-01"))
    #expect(messages[0].body == "A message with a timestamp but no author.")
  }

  @Test func commentK_authorContainingAt() {
    // The only `@` is followed by `jp`, which is not a timestamp, so nothing
    // splits and the whole interior is the author.
    let (quotation, messages) = CommentSerialization.parse(
      """
      > fox

      {@jp}: An author that is an @-handle.
      """)
    #expect(quotation == "fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == "@jp")
    #expect(messages[0].created == nil)
    #expect(messages[0].body == "An author that is an @-handle.")
  }

  @Test func commentL_emptyBraces() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > fox

      {}: Empty braces carry no attributes.
      """)
    #expect(quotation == "fox")
    #expect(messages.count == 1)
    #expect(messages[0].author == nil)
    #expect(messages[0].created == nil)
    #expect(messages[0].body == "Empty braces carry no attributes.")
  }

  @Test func commentM_bareEmojiUnattributedThread() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > fox

      💬

      A threaded message with no author or timestamp.

      💬

      A reply, also unattributed.
      """)
    #expect(quotation == "fox")
    #expect(messages.count == 2)
    #expect(messages[0].author == nil)
    #expect(messages[0].created == nil)
    #expect(messages[0].body == "A threaded message with no author or timestamp.")
    #expect(messages[1].author == nil)
    #expect(messages[1].body == "A reply, also unattributed.")
  }

  // MARK: - Attributes / timestamp grammar

  @Test func attribution_braceAuthorAndTimestamp() {
    let (author, created, body, isHeader) = CommentSerialization.parseAttribution(
      "{JP @ 2026-06-01 18:33}: the body")
    #expect(isHeader)
    #expect(author == "JP")
    #expect(created == ts("2026-06-01 18:33"))
    #expect(body == "the body")
  }

  @Test func attribution_lastAtSplits_authorMayContainAt() {
    let (author, created, body, isHeader) = CommentSerialization.parseAttribution(
      "{jp@example.com @ 2026-06-01 18:33}: hi")
    #expect(isHeader)
    #expect(author == "jp@example.com")
    #expect(created == ts("2026-06-01 18:33"))
    #expect(body == "hi")
  }

  @Test func attribution_authorOnly() {
    let (author, created, _, isHeader) = CommentSerialization.parseAttribution("{JP}:")
    #expect(isHeader)
    #expect(author == "JP")
    #expect(created == nil)
  }

  @Test func attribution_dateOnlyNoAuthor() {
    let (author, created, _, isHeader) = CommentSerialization.parseAttribution(
      "{@ 2026-06-01}")
    #expect(isHeader)
    #expect(author == nil)
    #expect(created == ts("2026-06-01"))
  }

  @Test func attribution_emptyBracesIsHeaderNoAttributes() {
    let (author, created, body, isHeader) = CommentSerialization.parseAttribution(
      "{}: body")
    #expect(isHeader)
    #expect(author == nil)
    #expect(created == nil)
    #expect(body == "body")
  }

  @Test func attribution_spaceBeforeColonMakesItContent() {
    let (author, _, body, isHeader) = CommentSerialization.parseAttribution(
      "{JP} : the body")
    #expect(isHeader)
    #expect(author == "JP")
    #expect(body == ": the body")
  }

  @Test func attribution_bareEmojiIsHeader() {
    let (author, created, body, isHeader) = CommentSerialization.parseAttribution(
      "💬 hello")
    #expect(isHeader)
    #expect(author == nil)
    #expect(created == nil)
    #expect(body == "hello")
  }

  @Test func attribution_noHeader_isAllBody() {
    let (author, created, body, isHeader) = CommentSerialization.parseAttribution(
      "A quoted comment, no attributes.")
    #expect(!isHeader)
    #expect(author == nil)
    #expect(created == nil)
    #expect(body == "A quoted comment, no attributes.")
  }

  @Test func timestamp_formsAndDateOnly() {
    #expect(ts("2026-06-01 18:33") != nil)
    #expect(ts("2026-06-01 18:33:13") != nil)
    #expect(ts("2026-06-01") != nil)  // date-only is accepted
    #expect(ts("not a timestamp") == nil)
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

  // A truncated quotation is just plain blockquote text; the spaced ellipsis
  // must survive serialize/parse untouched. Matching the truncation is a
  // render-time concern (mud-comments.js), not the codec's.
  @Test func roundTrip_truncatedQuotation() {
    roundTrip(
      quotation: "Anchoring by verbatim echo … computed in JS, never stored.",
      [CommentMessage(
        author: "JP", created: ts("2026-06-22 20:52:00"),
        body: "A truncated quotation.")])
  }

  @Test func roundTrip_authorOnly() {
    roundTrip(
      quotation: "fox",
      [CommentMessage(author: "JP", created: nil, body: "A note.")])
  }

  @Test func roundTrip_timestampOnly() {
    roundTrip(
      quotation: nil,
      [CommentMessage(
        author: nil, created: ts("2026-06-01 18:33:00"), body: "A note.")])
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

  // A thread of consecutive unattributed messages must keep its boundaries: each
  // message after the first serializes with a bare `💬`, or the two would merge
  // back into one on re-parse.
  @Test func roundTrip_unattributedThread() {
    roundTrip(
      quotation: "fox",
      [
        CommentMessage(author: nil, created: nil, body: "First, unattributed."),
        CommentMessage(author: nil, created: nil, body: "Reply, also unattributed."),
      ])
  }

  // A reply added to an unattributed first message keeps both distinct.
  @Test func roundTrip_unattributedThenAttributedReply() {
    roundTrip(
      quotation: nil,
      [
        CommentMessage(author: nil, created: nil, body: "An open observation."),
        CommentMessage(
          author: "JP", created: ts("2026-06-01 18:33:00"), body: "A reply."),
      ])
  }

  // MARK: - Byte identity

  // `parse` slices each
  // message body verbatim out of the source instead of re-serializing it
  // through a Markdown formatter. So a message no one has touched must survive a
  // reply byte-for-byte — including formatting a formatter would have
  // normalized (`_emphasis_` over `*emphasis*`, the exact list marker, the
  // blank-line spacing). The old `format()`-based parse failed this by design.
  @Test func replyLeavesTheEarlierMessageBytesUnchanged() {
    let fixture = """
      💬 {JP @ 2026-06-01 18:33:00}:

      A body with:

      * a bullet
      * another bullet

      and some _emphasis_.
      """
    let expectedBody = """
      A body with:

      * a bullet
      * another bullet

      and some _emphasis_.
      """

    var (quotation, messages) = CommentSerialization.parse(fixture)
    #expect(messages.count == 1)
    #expect(messages[0].body == expectedBody)

    // Add a reply and serialize the whole thread, as `CommentEditor` would.
    messages.append(
      CommentMessage(
        author: "Claude", created: ts("2026-06-01 18:40:00"),
        body: "A reply."))
    let serialized = CommentSerialization.serialize(
      quotation: quotation, messages)

    // Re-parsing the rewritten thread returns the first body byte-for-byte.
    let (_, reparsed) = CommentSerialization.parse(serialized)
    #expect(reparsed.count == 2)
    #expect(reparsed[0].body == expectedBody)
    #expect(reparsed[1].body == "A reply.")
  }
}
