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

  // The colon is required, so a colon-less attribution is not one: the whole
  // definition body is a single unattributed message whose text happens to open
  // with an avatar and a brace group.
  @Test func commentG_headerWithoutColonIsContent() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > brown fox

      💬 {JP @ 2026-06-01 18:33}

      The colon after the closing brace is missing.
      """)
    #expect(quotation == "brown fox")
    #expect(messages.count == 1)
    #expect(messages[0].avatar == nil)
    #expect(messages[0].author == nil)
    #expect(messages[0].created == nil)
    #expect(messages[0].body
      == """
      💬 {JP @ 2026-06-01 18:33}

      The colon after the closing brace is missing.
      """)
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

  @Test func commentM_avatarOnlyUnattributedThread() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > fox

      💬: A threaded message with no author or timestamp.

      💬: A reply, also unattributed.
      """)
    #expect(quotation == "fox")
    #expect(messages.count == 2)
    #expect(messages[0].avatar == "💬")
    #expect(messages[0].author == nil)
    #expect(messages[0].created == nil)
    #expect(messages[0].body == "A threaded message with no author or timestamp.")
    #expect(messages[1].avatar == "💬")
    #expect(messages[1].author == nil)
    #expect(messages[1].body == "A reply, also unattributed.")
  }

  // A message may be nothing but an emoji: `✨` reaches no colon, so it is not
  // an attribution and begins no second message.
  @Test func commentP_emojiOnlyBody() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > lazy dog

      👤 {JP @ 2026-06-01 18:33}:

      ✨
      """)
    #expect(quotation == "lazy dog")
    #expect(messages.count == 1)
    #expect(messages[0].avatar == "👤")
    #expect(messages[0].author == "JP")
    #expect(messages[0].created == ts("2026-06-01 18:33"))
    #expect(messages[0].body == "✨")
  }

  // An attribution never closes an empty message, so an attribution-shaped
  // paragraph that is a message's whole content stays content.
  @Test func commentQ_attributionShapedContent() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > brown

      👤 {JP @ 2026-06-01 18:33}:

      {x: 1}: the default mapping
      """)
    #expect(quotation == "brown")
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].body == "{x: 1}: the default mapping")
  }

  // The documented limit of that rescue: once the message has content, the same
  // paragraph does begin a second message, authored by `x: 1`.
  @Test func commentQ_attributionShapedContentAfterASentence() {
    let (_, messages) = CommentSerialization.parse(
      """
      👤 {JP @ 2026-06-01 18:33}:

      A sentence first.

      {x: 1}: the default mapping
      """)
    #expect(messages.count == 2)
    #expect(messages[0].body == "A sentence first.")
    #expect(messages[1].author == "x: 1")
    #expect(messages[1].body == "the default mapping")
  }

  // Inline code is opaque to the attribution grammar, which is what makes the
  // documented workaround true: backtick the thing and it stays content. Here
  // the emoji form, which otherwise reads as an avatar attribution.
  @Test func commentR_backtickedEmojiIsContent() {
    let body = """
      Here's the start of my comment.

      `🌚`: foo

      `🐲`: bar
      """
    let (_, messages) = CommentSerialization.parse(
      """
      👤 {JP @ 2026-08-17 08:19:45}:

      \(body)
      """)
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].body == body)
  }

  // The same for the brace form. A sentence stands above it so the rescue is
  // the backticks and not the empty-message tie-break — contrast
  // `commentQ_attributionShapedContentAfterASentence`, which does split.
  @Test func commentR_backtickedBracesAreContent() {
    let (_, messages) = CommentSerialization.parse(
      """
      👤 {JP @ 2026-06-01 18:33}:

      A sentence first.

      `{x: 1}`: the default mapping
      """)
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].body == """
      A sentence first.

      `{x: 1}`: the default mapping
      """)
  }

  // MARK: - The one-line form

  // A message written on one line keeps the Markdown in its body: the remainder
  // after the colon is sliced from the source like every other block, not read
  // off the flattened inline text (which would hand back
  // "See the doc for details.").
  @Test func inlineBody_keepsItsMarkdown() {
    let (_, messages) = CommentSerialization.parse(
      "{JP @ 2026-06-01 18:33}: See [the doc](x) for *details*.")
    #expect(messages.count == 1)
    #expect(messages[0].author == "JP")
    #expect(messages[0].body == "See [the doc](x) for *details*.")
  }

  // Inline code in a one-line body keeps its backticks too — the same slice,
  // and the same reason the grammar can't be fooled by code.
  @Test func inlineBody_keepsInlineCode() {
    let (_, messages) = CommentSerialization.parse(
      "👤 {JP @ 2026-06-01 18:33}: try `mud -u` first.")
    #expect(messages.count == 1)
    #expect(messages[0].avatar == "👤")
    #expect(messages[0].body == "try `mud -u` first.")
  }

  // A header paragraph that wraps keeps its line break: the slice runs to the
  // paragraph's last line, not its first.
  @Test func inlineBody_spansTheWholeParagraph() {
    let (_, messages) = CommentSerialization.parse(
      """
      {JP @ 2026-06-01 18:33}: first line
      second line
      """)
    #expect(messages.count == 1)
    #expect(messages[0].body == "first line\nsecond line")
  }

  // The one-line form and a following block still join with a blank line.
  @Test func inlineBody_joinsTheBlocksBelowIt() {
    let (_, messages) = CommentSerialization.parse(
      """
      {JP @ 2026-06-01 18:33}: An opening line.

      * a bullet
      * another bullet
      """)
    #expect(messages.count == 1)
    #expect(messages[0].body == """
      An opening line.

      * a bullet
      * another bullet
      """)
  }

  // MARK: - Attribution escaping (write side)

  private static let zwsp = "\u{200B}"

  // A body paragraph shaped like an attribution is written with a leading
  // zero-width space, so a message the reader wrote as one cannot come back as
  // two. Without it this body parses as two messages, the second authored by
  // nobody and avatared ❌.
  @Test func escape_attributionShapedParagraph() {
    let serialized = CommentSerialization.serialize(
      quotation: nil,
      [CommentMessage(
        author: "JP", created: ts("2026-06-01 18:33:00"),
        body: "A sentence first.\n\n❌: wrong")])
    #expect(serialized.contains("\(Self.zwsp)❌: wrong"))

    let (_, reparsed) = CommentSerialization.parse(serialized)
    #expect(reparsed.count == 1)
    #expect(reparsed[0].author == "JP")
    #expect(reparsed[0].body == "A sentence first.\n\n\(Self.zwsp)❌: wrong")
  }

  // The brace form, and the colon-at-end form that has no separator to alter —
  // one rule covers both, which is why the escape leads the line.
  @Test func escape_coversEveryAttributionForm() {
    for shape in ["{TODO}: fix this", "❌:", "👤 {JP @ 2026-06-01}: hello"] {
      let serialized = CommentSerialization.serialize(
        quotation: nil,
        [CommentMessage(
          author: "JP", created: ts("2026-06-01 18:33:00"),
          body: "A sentence first.\n\n\(shape)")])
      #expect(
        serialized.contains("\(Self.zwsp)\(shape)"),
        "\(shape) must be escaped")

      let (_, reparsed) = CommentSerialization.parse(serialized)
      #expect(reparsed.count == 1, "\(shape) must not split the message")
    }
  }

  // Idempotent: the check is `parseAttribution` itself, so escaped text no
  // longer trips it and a rewrite adds nothing. This is what makes an unescape
  // on read unnecessary.
  @Test func escape_isIdempotent() {
    let message = CommentMessage(
      author: "JP", created: ts("2026-06-01 18:33:00"),
      body: "A sentence first.\n\n❌: wrong")
    let once = CommentSerialization.serialize(quotation: nil, [message])
    let (_, reparsed) = CommentSerialization.parse(once)
    let twice = CommentSerialization.serialize(quotation: nil, reparsed)
    #expect(twice == once)
    #expect(!twice.contains("\(Self.zwsp)\(Self.zwsp)"))
  }

  // Only a paragraph can be an attribution, so a fenced code block is left
  // alone. Injecting a zero-width space into the reader's code would be silent
  // corruption — this is why the escape parses the body instead of splitting it
  // on blank lines.
  @Test func escape_leavesFencedCodeAlone() {
    let body = """
      Try this:

      ```
      {x: 1}: not prose
      ```
      """
    let serialized = CommentSerialization.serialize(
      quotation: nil,
      [CommentMessage(
        author: "JP", created: ts("2026-06-01 18:33:00"), body: body)])
    #expect(!serialized.contains(Self.zwsp))

    let (_, reparsed) = CommentSerialization.parse(serialized)
    #expect(reparsed.count == 1)
    #expect(reparsed[0].body == body)
  }

  // An ordinary body is written untouched: the escape costs nothing where it
  // isn't needed.
  @Test func escape_leavesOrdinaryProseAlone() {
    let serialized = CommentSerialization.serialize(
      quotation: "fox",
      [CommentMessage(
        author: "JP", created: ts("2026-06-01 18:33:00"),
        body: "A note.\n\nAnd a second paragraph.")])
    #expect(!serialized.contains(Self.zwsp))
  }

  // MARK: - Quotation

  // A quotation is matched against the document's *rendered* text, so it keeps
  // giving up its backticks even though the attribution grammar no longer does.
  @Test func quotationDropsItsBackticks() {
    let (quotation, messages) = CommentSerialization.parse(
      """
      > the `foo` value

      A note.
      """)
    #expect(quotation == "the foo value")
    #expect(messages.count == 1)
    #expect(messages[0].body == "A note.")
  }

  // MARK: - Attributes / timestamp grammar

  @Test func attribution_braceAuthorAndTimestamp() {
    let (_, author, created, body, isHeader) =
      CommentSerialization.parseAttribution(
        "{JP @ 2026-06-01 18:33}: the body")
    #expect(isHeader)
    #expect(author == "JP")
    #expect(created == ts("2026-06-01 18:33"))
    #expect(body == "the body")
  }

  @Test func attribution_lastAtSplits_authorMayContainAt() {
    let (_, author, created, body, isHeader) =
      CommentSerialization.parseAttribution(
        "{jp@example.com @ 2026-06-01 18:33}: hi")
    #expect(isHeader)
    #expect(author == "jp@example.com")
    #expect(created == ts("2026-06-01 18:33"))
    #expect(body == "hi")
  }

  @Test func attribution_authorOnly() {
    let (_, author, created, _, isHeader) =
      CommentSerialization.parseAttribution("{JP}:")
    #expect(isHeader)
    #expect(author == "JP")
    #expect(created == nil)
  }

  @Test func attribution_dateOnlyNoAuthor() {
    let (_, author, created, _, isHeader) =
      CommentSerialization.parseAttribution(
        "{@ 2026-06-01}:")
    #expect(isHeader)
    #expect(author == nil)
    #expect(created == ts("2026-06-01"))
  }

  @Test func attribution_emptyBracesIsHeaderNoAttributes() {
    let (_, author, created, body, isHeader) =
      CommentSerialization.parseAttribution(
        "{}: body")
    #expect(isHeader)
    #expect(author == nil)
    #expect(created == nil)
    #expect(body == "body")
  }

  // No whitespace may stand between the closing `}` and the `:`. Written apart,
  // the paragraph carries no attribution at all and the whole of it is content.
  @Test func attribution_spaceBeforeColonMakesItContent() {
    let (avatar, author, _, body, isHeader) =
      CommentSerialization.parseAttribution(
        "{JP} : the body")
    #expect(!isHeader)
    #expect(avatar == nil)
    #expect(author == nil)
    #expect(body == "{JP} : the body")
  }

  // The colon is what makes an attribution one. Without it a paragraph-leading
  // emoji or brace group is ordinary content, and needs no escaping.
  @Test func attribution_withoutAColonIsContent() {
    for text in ["💬 hello", "🎉 We shipped it!", "✨", "{x: 1} is the default"] {
      let (avatar, author, created, body, isHeader) =
        CommentSerialization.parseAttribution(text)
      #expect(!isHeader, "\(text) must not be an attribution")
      #expect(avatar == nil)
      #expect(author == nil)
      #expect(created == nil)
      #expect(body == text)
    }
  }

  // The colon must be followed by a space or the end of the paragraph.
  @Test func attribution_colonNeedsASpaceAfterIt() {
    let (_, _, _, body, isHeader) =
      CommentSerialization.parseAttribution("{JP}:hello")
    #expect(!isHeader)
    #expect(body == "{JP}:hello")
  }

  // An avatar and a colon, with no braces, is the shortest valid attribution.
  @Test func attribution_avatarAndColonAlone() {
    let (avatar, author, created, body, isHeader) =
      CommentSerialization.parseAttribution("💬: hello")
    #expect(isHeader)
    #expect(avatar == "💬")
    #expect(author == nil)
    #expect(created == nil)
    #expect(body == "hello")
  }

  // A colon on its own is not an attribution: one of the avatar and the braces
  // must be there.
  @Test func attribution_colonAloneIsContent() {
    let (_, _, _, body, isHeader) =
      CommentSerialization.parseAttribution(": not an attribution")
    #expect(!isHeader)
    #expect(body == ": not an attribution")
  }

  @Test func attribution_noHeader_isAllBody() {
    let (_, author, created, body, isHeader) =
      CommentSerialization.parseAttribution(
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
  // message after the first serializes with an avatar attribution (`💬:`), or
  // the two would merge back into one on re-parse. That marker is the one thing
  // serialize adds, so the reply comes back carrying `CommentAvatar.fallback` —
  // the avatar it rendered as all along.
  @Test func roundTrip_unattributedThread() {
    roundTrip(
      quotation: "fox",
      [
        CommentMessage(author: nil, created: nil, body: "First, unattributed."),
        CommentMessage(
          avatar: CommentAvatar.fallback, author: nil, created: nil,
          body: "Reply, also unattributed."),
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

  // MARK: - Avatars

  // Any single emoji leads an attributes block, and is kept on the message so a
  // thread rewrite puts each one back where it was.
  @Test func avatar_anyEmojiLeadsTheAttribution() {
    let (_, messages) = CommentSerialization.parse(
      """
      > fox

      🤖 {Claude @ 2026-06-01 18:33}:

      A message from a robot.

      👤 {JP @ 2026-06-01 18:40}:

      A message from a person.
      """)
    #expect(messages.count == 2)
    #expect(messages[0].avatar == "🤖")
    #expect(messages[0].author == "Claude")
    #expect(messages[1].avatar == "👤")
    #expect(messages[1].author == "JP")
  }

  // The avatar stays optional: a brace-only attribution parses to no avatar and
  // serializes back without one, so a document that never had avatars keeps its
  // bytes when Mud rewrites the thread.
  @Test func avatar_absentStaysAbsent() {
    let (_, messages) = CommentSerialization.parse(
      "{JP @ 2026-06-01 18:33}: A message with no avatar.")
    #expect(messages.count == 1)
    #expect(messages[0].avatar == nil)
    #expect(
      CommentSerialization.serialize(quotation: nil, messages)
        == "{JP @ 2026-06-01 18:33:00}:\n\nA message with no avatar.")
  }

  // An avatar-and-colon attribution takes any emoji, not just `💬`.
  @Test func avatar_anyEmojiLeadsABracelessAttribution() {
    let (avatar, author, created, body, isHeader) =
      CommentSerialization.parseAttribution("🎩: hello")
    #expect(isHeader)
    #expect(avatar == "🎩")
    #expect(author == nil)
    #expect(created == nil)
    #expect(body == "hello")
  }

  // An avatar with no attributes serializes as `👤:` on its own line, so the
  // first message of a thread keeps the avatar it came with.
  @Test func avatar_withoutAttributesRoundTrips() {
    roundTrip(
      quotation: "fox",
      [CommentMessage(
        avatar: "🎩", author: nil, created: nil, body: "A note.")])
    #expect(
      CommentSerialization.serialize(
        quotation: nil,
        [CommentMessage(
          avatar: "🎩", author: nil, created: nil, body: "A note.")])
        == "🎩:\n\nA note.")
  }

  @Test func avatar_roundTripsThroughAThread() {
    roundTrip(
      quotation: "quick brown fox",
      [
        CommentMessage(
          avatar: "👤", author: "JP", created: ts("2026-06-01 18:33:00"),
          body: "First."),
        CommentMessage(
          avatar: "🤖", author: "Claude", created: ts("2026-06-01 18:33:13"),
          body: "Second."),
      ])
  }

  // A digit is not an avatar even though Unicode gives it the Emoji property:
  // it needs the keycap sequence to present as one.
  @Test func avatar_validity() {
    #expect(CommentAvatar.isValid("👤"))
    #expect(CommentAvatar.isValid("🤖"))
    #expect(CommentAvatar.isValid("✍️"))     // emoji presentation selector
    #expect(CommentAvatar.isValid("1️⃣"))     // keycap sequence
    #expect(!CommentAvatar.isValid("1"))
    #expect(!CommentAvatar.isValid("#"))
    #expect(!CommentAvatar.isValid("JP"))
    #expect(!CommentAvatar.isValid(""))
    #expect(!CommentAvatar.isValid("👤👤"))
    #expect(CommentAvatar.resolve("🤖") == "🤖")
    #expect(CommentAvatar.resolve("nope") == CommentAvatar.standard)
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
