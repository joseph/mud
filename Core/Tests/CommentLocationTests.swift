import Foundation
import Testing

@testable import MudCore

/// Pins the byte semantics of `CommentLocation` (Phase 3e) — the spans
/// `CommentEditor` splices by. `defStart..<defContentEnd` must cover exactly
/// the definition (opener line through the body's last content byte),
/// `defStart..<defDeleteEnd` the definition plus its trailing blanks, and
/// `refRanges` exactly the `[^label]` markers — or the editor writes a
/// corrupted file.
@Suite("CommentLocation byte semantics")
struct CommentLocationTests {

  private func ts(_ s: String) -> Date? {
    CommentSerialization.parseTimestamp(Substring(s))
  }

  private var message: CommentMessage {
    CommentMessage(
      author: "JP", created: ts("2026-06-01 18:33:00"), body: "First.")
  }

  @Test func defSliceCoversExactlyTheDefinition() throws {
    let inserted = CommentEditor.insert(
      into: "# Title\n\nThe quick brown fox.\n", markerByteOffset: 28,
      quotation: "quick brown", message: message)
    let loc = try #require(
      FootnoteProcessor.locateComments(inserted.source).first)

    let bytes = Array(inserted.source.utf8)
    let slice = String(
      decoding: bytes[loc.defStart..<loc.defContentEnd], as: UTF8.self)
    #expect(slice.hasPrefix("[^comment-a]:"))
    #expect(slice.hasSuffix("First."))  // content end excludes the newline
  }

  @Test func defSliceReparsesToTheSameComment() throws {
    let inserted = CommentEditor.insert(
      into: "# Title\n\nThe quick brown fox.\n", markerByteOffset: 28,
      quotation: "quick brown", message: message)
    let original = try #require(
      MudCore.parseComments(inserted.source).first)
    let loc = try #require(
      FootnoteProcessor.locateComments(inserted.source).first)

    // Rebuild a minimal document around the slice (a reference so the
    // definition is kept) and parse it back: the slice must contain the whole
    // definition — nothing cut off, nothing dragged in from the neighbors.
    let bytes = Array(inserted.source.utf8)
    let slice = String(
      decoding: bytes[loc.defStart..<loc.defContentEnd], as: UTF8.self)
    let rebuilt = "x[^\(loc.label)]\n\n" + slice + "\n"
    let reparsed = try #require(MudCore.parseComments(rebuilt).first)
    #expect(reparsed == original)
  }

  @Test func rewriteWithTheSameContentIsIdentity() throws {
    // Pins defStart..<defContentEnd from the write side: replacing the
    // definition with a freshly serialized copy of the same thread must not
    // move a byte anywhere in the file.
    let inserted = CommentEditor.insert(
      into: "# Title\n\nBody text.\n", markerByteOffset: 18,
      quotation: nil, message: message)
    let rewritten = try #require(CommentEditor.rewrite(
      inserted.source, label: inserted.comment.label,
      quotation: nil, messages: [message]))
    #expect(rewritten == inserted.source)
  }

  @Test func midFileDefinitionRoundTrips() throws {
    // A hand-written definition with a block after it: rewrite is an identity,
    // and delete removes the definition plus its trailing blank line while
    // leaving the following block byte-exact.
    let source = """
      Alpha[^comment-a] one.

      [^comment-a]:
          > Alpha

          💬 {JP @ 2026-06-01 18:33:00}:

          First.

      Beta two.
      """
    let rewritten = try #require(CommentEditor.rewrite(
      source, label: "comment-a",
      quotation: "Alpha", messages: [message]))
    #expect(rewritten == source)

    let deleted = try #require(CommentEditor.delete(source, label: "comment-a"))
    #expect(deleted == "Alpha one.\n\nBeta two.")
  }

  @Test func deleteThenReinsertRestoresBytes() throws {
    // The inverse of the insert→delete round-trip CommentEditorTests pins:
    // deleting a comment and re-inserting the same thread at the same marker
    // byte must reproduce the file exactly, refRanges included.
    let original = "# Title\n\nBody text.\n"
    let inserted = CommentEditor.insert(
      into: original, markerByteOffset: 18, quotation: "Body",
      message: message)
    let deleted = try #require(CommentEditor.delete(
      inserted.source, label: inserted.comment.label))
    #expect(deleted == original)

    let reinserted = CommentEditor.insert(
      into: deleted, markerByteOffset: 18, quotation: "Body",
      message: message)
    #expect(reinserted.source == inserted.source)
  }
}
