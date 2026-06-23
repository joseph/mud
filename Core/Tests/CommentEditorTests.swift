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
    #expect(CommentEditor.nextLabel(in: "no comments here") == "comment-a")
  }

  @Test func nextLabel_incrementsGreatest() {
    #expect(
      CommentEditor.nextLabel(in: "x[^comment-a] y[^comment-b]") == "comment-c")
  }

  @Test func nextLabel_rollsOverAtZ() {
    #expect(CommentEditor.nextLabel(in: "[^comment-z]") == "comment-za")
    #expect(CommentEditor.nextLabel(in: "[^comment-zz]") == "comment-zza")
  }

  @Test func nextLabel_ignoresAnomalies() {
    // `ya` is not scheme-valid, so the basis is `b` → `c`.
    #expect(
      CommentEditor.nextLabel(in: "[^comment-a][^comment-b][^comment-ya]")
        == "comment-c")
    // `aa` is not scheme-valid → basis `a` → `b`.
    #expect(
      CommentEditor.nextLabel(in: "[^comment-a][^comment-aa]") == "comment-b")
    // Only anomalies present → start over at `a`.
    #expect(
      CommentEditor.nextLabel(in: "[^comment-1][^comment-foo]") == "comment-a")
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

    #expect(result.comment.label == "comment-a")
    #expect(result.comment.quotation == nil)
    #expect(result.comment.messages.count == 1)
    // Marker spliced right before the period (the selection end).
    #expect(result.source.contains("Hello world[^comment-a]."))
    // Canonical definition appended, body four-space indented.
    #expect(result.source.contains("[^comment-a]:\n    Note."))
  }

  @Test func insert_withQuotationWritesLeadingBlockquote() {
    let result = CommentEditor.insert(
      into: "The quick brown fox.\n", markerByteOffset: 19,
      quotation: "quick brown",
      message: CommentMessage(
        author: "JP", created: ts("2026-06-01 18:33:00"), body: "Nice."))

    #expect(result.source.contains("brown fox[^comment-a]."))
    #expect(result.source.contains("[^comment-a]:\n    > quick brown"))
    #expect(result.source.contains("💬 JP (2026-06-01 18:33:00):"))
    #expect(result.source.contains("Nice."))
  }

  // MARK: - rewrite

  @Test func rewrite_replacesBodyKeepsMarker() {
    let inserted = CommentEditor.insert(
      into: "Hello world.\n", markerByteOffset: 11, quotation: nil,
      message: CommentMessage(author: nil, created: nil, body: "Note."))

    let rewritten = CommentEditor.rewrite(
      inserted.source, label: "comment-a", quotation: nil,
      messages: [
        CommentMessage(author: "JP", created: ts("2026-06-01 18:33:00"),
          body: "First."),
        CommentMessage(author: "Claude", created: ts("2026-06-01 18:34:00"),
          body: "Second."),
      ])

    #expect(rewritten.contains("Hello world[^comment-a]."))  // marker intact
    #expect(rewritten.contains("💬 JP (2026-06-01 18:33:00):"))
    #expect(rewritten.contains("💬 Claude (2026-06-01 18:34:00):"))
    #expect(rewritten.contains("First."))
    #expect(rewritten.contains("Second."))
    #expect(!rewritten.contains("Note."))  // old body replaced
  }

  // MARK: - delete

  @Test func delete_removesOneCommentLeavesOthers() {
    let source = """
      Alpha[^comment-a] and beta[^comment-b].

      [^comment-a]: First comment.

      [^comment-b]: Second comment.
      """

    let after = CommentEditor.delete(source, label: "comment-a")

    #expect(!after.contains("comment-a"))  // marker + definition gone
    #expect(after.contains("beta[^comment-b]."))  // other marker intact
    #expect(after.contains("[^comment-b]: Second comment."))  // other def intact
    #expect(after.contains("Alpha and beta"))  // surrounding text intact
  }
}
