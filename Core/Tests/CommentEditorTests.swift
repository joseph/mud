import Foundation
import Testing

@testable import MudCore

@Suite("CommentEditor")
struct CommentEditorTests {

  private func ts(_ s: String) -> Date? {
    CommentSerialization.parseTimestamp(Substring(s))
  }

  // MARK: - nextLabel / scheme

  @Test func nextLabel_emptySource() {
    #expect(CommentEditor.nextLabel(in: "no comments here") == "💬-a")
  }

  @Test func nextLabel_incrementsGreatest() {
    #expect(CommentEditor.nextLabel(in: "x[^💬-a] y[^💬-b]") == "💬-c")
  }

  // Both prefixes name the same scheme, so a document written before the emoji
  // prefix keeps counting where it left off — under the new prefix.
  @Test func nextLabel_readsBothPrefixes() {
    #expect(
      CommentEditor.nextLabel(in: "x[^comment-a] y[^comment-b]") == "💬-c")
    #expect(CommentEditor.nextLabel(in: "x[^comment-a] y[^💬-b]") == "💬-c")
  }

  @Test func nextLabel_rollsOverAtZ() {
    #expect(CommentEditor.nextLabel(in: "[^💬-z]") == "💬-za")
    #expect(CommentEditor.nextLabel(in: "[^💬-zz]") == "💬-zza")
  }

  @Test func nextLabel_ignoresAnomalies() {
    // `ya` is not scheme-valid, so the basis is `b` → `c`.
    #expect(
      CommentEditor.nextLabel(in: "[^💬-a][^💬-b][^💬-ya]") == "💬-c")
    // `aa` is not scheme-valid → basis `a` → `b`.
    #expect(CommentEditor.nextLabel(in: "[^💬-a][^💬-aa]") == "💬-b")
    // Only anomalies present → start over at `a`.
    #expect(CommentEditor.nextLabel(in: "[^💬-1][^💬-foo]") == "💬-a")
  }

  @Test func increment_cases() {
    #expect(CommentEditor.increment("a") == "b")
    #expect(CommentEditor.increment("y") == "z")
    #expect(CommentEditor.increment("z") == "za")
    #expect(CommentEditor.increment("za") == "zb")
    #expect(CommentEditor.increment("zy") == "zz")
    #expect(CommentEditor.increment("zz") == "zza")
  }

  @Test func isSchemeValid_cases() {
    for valid in ["a", "y", "z", "za", "zy", "zz", "zza"] {
      #expect(CommentEditor.isSchemeValid(valid), "\(valid) should be valid")
    }
    for invalid in ["", "ya", "az", "aa", "1", "foo", "a-b", "Z"] {
      #expect(!CommentEditor.isSchemeValid(invalid), "\(invalid) should be invalid")
    }
  }

  // MARK: - insert

  @Test func insert_splicesMarkerAndAppendsDefinition() {
    let result = CommentEditor.insert(
      into: "Hello world.\n", markerByteOffset: 11, quotation: nil,
      message: CommentMessage(author: nil, created: nil, body: "Note."))

    #expect(result.comment.label == "💬-a")
    #expect(result.comment.quotation == nil)
    #expect(result.comment.messages.count == 1)
    // Marker spliced right before the period (the selection end).
    #expect(result.source.contains("Hello world[^💬-a]."))
    // Canonical definition appended, body four-space indented.
    #expect(result.source.contains("[^💬-a]:\n    Note."))
  }

  @Test func insert_atEndOfFileEndsWithSingleNewline() {
    let result = CommentEditor.insert(
      into: "Hello world.\n", markerByteOffset: 11, quotation: nil,
      message: CommentMessage(author: nil, created: nil, body: "Note."))

    #expect(result.source.hasSuffix("    Note.\n"))
    #expect(!result.source.hasSuffix("\n\n"))
  }

  @Test func insertThenDelete_restoresOriginal() throws {
    // The README round-trip: adding then removing a comment must leave the file
    // byte-for-byte unchanged, trailing newline and all.
    let original = "# Title\n\nBody text.\n"
    let inserted = CommentEditor.insert(
      into: original, markerByteOffset: 18, quotation: nil,
      message: CommentMessage(author: nil, created: nil, body: "Note."))
    let restored = try #require(CommentEditor.delete(
      inserted.source, label: inserted.comment.label))

    #expect(restored == original)
  }

  @Test func insert_withQuotationWritesLeadingBlockquote() {
    let result = CommentEditor.insert(
      into: "The quick brown fox.\n", markerByteOffset: 19,
      quotation: "quick brown",
      message: CommentMessage(
        avatar: "👤", author: "JP", created: ts("2026-06-01 18:33:00"),
        body: "Nice."))

    #expect(result.source.contains("brown fox[^💬-a]."))
    #expect(result.source.contains("[^💬-a]:\n    > quick brown"))
    #expect(result.source.contains("👤 {JP @ 2026-06-01 18:33:00}:"))
    #expect(result.source.contains("Nice."))
  }

  // MARK: - rewrite

  @Test func rewrite_replacesBodyKeepsMarker() throws {
    let inserted = CommentEditor.insert(
      into: "Hello world.\n", markerByteOffset: 11, quotation: nil,
      message: CommentMessage(author: nil, created: nil, body: "Note."))

    let rewritten = try #require(CommentEditor.rewrite(
      inserted.source, label: "💬-a", quotation: nil,
      messages: [
        CommentMessage(avatar: "👤", author: "JP",
          created: ts("2026-06-01 18:33:00"), body: "First."),
        CommentMessage(avatar: "🤖", author: "Claude",
          created: ts("2026-06-01 18:34:00"), body: "Second."),
      ]))

    #expect(rewritten.contains("Hello world[^💬-a]."))  // marker intact
    #expect(rewritten.contains("👤 {JP @ 2026-06-01 18:33:00}:"))
    #expect(rewritten.contains("🤖 {Claude @ 2026-06-01 18:34:00}:"))
    #expect(rewritten.contains("First."))
    #expect(rewritten.contains("Second."))
    #expect(!rewritten.contains("Note."))  // old body replaced
  }

  @Test func rewrite_keepsBlankLineBeforeFollowingBlock() throws {
    // A comment definition mid-document, with a following paragraph. Rewriting
    // its body must not swallow the blank line that separates the two.
    let source = """
      Text[^comment-a] here.

      [^comment-a]: > here

          A note.

      Following paragraph.
      """

    let rewritten = try #require(CommentEditor.rewrite(
      source, label: "comment-a", quotation: "here",
      messages: [
        CommentMessage(author: nil, created: nil, body: "A note."),
        CommentMessage(author: nil, created: nil, body: "A reply."),
      ]))

    // The reply is a distinct message (an avatar attribution, `💬:`), and the
    // following paragraph stays separated by a blank line rather than merging
    // into the definition.
    #expect(rewritten.contains("    💬:\n\n    A reply."))
    #expect(rewritten.contains("    A reply.\n\nFollowing paragraph."))
  }

  @Test func rewrite_atEndOfFileEndsWithSingleNewline() throws {
    let inserted = CommentEditor.insert(
      into: "Hello world.\n", markerByteOffset: 11, quotation: nil,
      message: CommentMessage(author: nil, created: nil, body: "Note."))

    let rewritten = try #require(CommentEditor.rewrite(
      inserted.source, label: "💬-a", quotation: nil,
      messages: [
        CommentMessage(author: nil, created: nil, body: "Note."),
        CommentMessage(author: nil, created: nil, body: "Reply."),
      ]))

    #expect(rewritten.hasSuffix("    💬:\n\n    Reply.\n"))
    #expect(!rewritten.hasSuffix("\n\n"))
  }

  // MARK: - delete

  // The sources below keep the `comment-` prefix: every edit path has to keep
  // working on a document written before the emoji prefix existed. The insert
  // tests above cover the same paths under the prefix Mud writes now.
  @Test func delete_removesOneCommentLeavesOthers() throws {
    let source = """
      Alpha[^comment-a] and beta[^comment-b].

      [^comment-a]: First comment.

      [^comment-b]: Second comment.
      """

    let after = try #require(CommentEditor.delete(source, label: "comment-a"))

    #expect(!after.contains("comment-a"))  // marker + definition gone
    #expect(after.contains("beta[^comment-b]."))  // other marker intact
    #expect(after.contains("[^comment-b]: Second comment."))  // other def intact
    #expect(after.contains("Alpha and beta"))  // surrounding text intact
  }

  @Test func delete_collapsesTrailingNewlinesToOne() throws {
    let source = """
      Body[^comment-a] text.

      [^comment-a]: A trailing comment.
      """ + "\n\n\n"

    let after = try #require(CommentEditor.delete(source, label: "comment-a"))

    #expect(after.hasSuffix("Body text.\n"))
    #expect(!after.hasSuffix("\n\n"))
  }

  @Test func delete_keepsTrailingNewlineWhenCommentNotLast() throws {
    // The definition is followed by more content, so its removal does not reach
    // end-of-file: the file's own trailing newline must survive.
    let source = """
      Body[^comment-a] text.

      [^comment-a]: A comment.

      More content.
      """ + "\n"

    let after = try #require(CommentEditor.delete(source, label: "comment-a"))

    #expect(!after.contains("comment-a"))
    #expect(after.contains("Body text."))
    #expect(after.hasSuffix("More content.\n"))
  }

  // MARK: - Missing label

  @Test func rewrite_missingLabelReturnsNil() {
    // A vanished definition must be reported, not papered over: returning the
    // source unchanged would let the caller write it back and claim success.
    let source = "Plain text, no comments.\n"
    let result = CommentEditor.rewrite(
      source, label: "comment-a", quotation: nil,
      messages: [CommentMessage(author: nil, created: nil, body: "Note.")])
    #expect(result == nil)
  }

  @Test func delete_missingLabelReturnsNil() {
    let source = "Plain text, no comments.\n"
    #expect(CommentEditor.delete(source, label: "comment-a") == nil)
  }
}
