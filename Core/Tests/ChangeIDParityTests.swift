import Testing
@testable import MudCore

/// Change IDs (`change-N`) are minted by two independent counters:
/// `DiffContext` (used by the Up-mode overlay and, via `ChangeList`,
/// the sidebar) and `LineDiffMap` (Down mode). A sidebar click finds
/// its document target by matching `data-change-id`, so both counters
/// must assign the same ID to the same change. These tests pin that
/// contract over an edit corpus.
///
/// Up mode and the sidebar share one `DiffContext`, so their IDs are
/// compared in full document order. Down mode is compared on (a) the
/// complete ID set and (b) the document order of insertion IDs — not
/// deletion positions, because a deletion may legitimately render at a
/// different position in a line-oriented view than in the sidebar list
/// (e.g. an unpaired deletion sharing a gap with a code-block pair).
/// Since both counters number sequentially, any divergence shifts every
/// later ID, so these two checks catch a numbering split.
///
/// The corpus avoids gaps where the two code-block pairing policies
/// differ (`DiffContext` pairs code blocks by type anywhere in a gap;
/// `LineDiffMap` pairs the i-th deletion with the i-th insertion).
/// Unifying that policy is Phase 2 of the architecture plan.
@Suite("Change ID parity between modes and the sidebar")
struct ChangeIDParityTests {
  struct EditCase: CustomTestStringConvertible, Sendable {
    let label: String
    let old: String
    let new: String
    var testDescription: String { label }
  }

  static let corpus: [EditCase] = [
    EditCase(
      label: "paragraph edit",
      old: "Alpha one.\n\nBeta.\n",
      new: "Alpha two.\n\nBeta.\n"),
    EditCase(
      label: "insertion only",
      old: "Alpha.\n",
      new: "Alpha.\n\nAdded.\n"),
    EditCase(
      label: "deletion only (trailing)",
      old: "Alpha.\n\nGone.\n",
      new: "Alpha.\n"),
    EditCase(
      label: "code block edit alone",
      old: "```\nkeep\nold\n```\n",
      new: "```\nkeep\nnew\n```\n"),
    EditCase(
      label: "code block edit then paragraph edit",
      old: "```\nkeep\nold\n```\n\nMiddle.\n\nTail one.\n",
      new: "```\nkeep\nnew\n```\n\nMiddle.\n\nTail two.\n"),
    EditCase(
      label: "paragraph edit then code block edit",
      old: "Head one.\n\nMiddle.\n\n```\nkeep\nold\n```\n",
      new: "Head two.\n\nMiddle.\n\n```\nkeep\nnew\n```\n"),
    EditCase(
      label: "two code block edits",
      old: "```\na\nold1\n```\n\nMid.\n\n```\nb\nold2\n```\n",
      new: "```\na\nnew1\n```\n\nMid.\n\n```\nb\nnew2\n```\n"),
    EditCase(
      label: "code block edit and insertion in the same gap",
      old: "```\nkeep\nold\n```\n\nTail.\n",
      new: "```\nkeep\nnew\n```\n\nAdded.\n\nTail.\n"),
    EditCase(
      label: "multi-cluster code block edit then paragraph edit",
      old: "```\na\nb\nc\nd\ne\n```\n\nTail one.\n",
      new: "```\na\nB\nc\nD\ne\n```\n\nTail two.\n"),
  ]

  @Test("Down-mode IDs match sidebar IDs", arguments: corpus)
  func downMatchesSidebar(_ c: EditCase) {
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(c.old)
    let html = MudCore.renderDownToHTML(c.new, options: opts)
    let sidebar = MudCore.computeChanges(
      old: ParsedMarkdown(c.old), new: ParsedMarkdown(c.new))

    let sidebarIDs = Self.uniqueInOrder(sidebar.map(\.id))
    #expect(!sidebarIDs.isEmpty, "Corpus case should produce changes")
    #expect(Set(Self.idSequence(in: html)) == Set(sidebarIDs),
      "Down mode and sidebar must use the same change-ID set")

    let downInsertions = Self.idSequence(
      in: html, after: "dl-ins\" data-change-id=\"")
    let sidebarInsertions = Self.uniqueInOrder(
      sidebar.filter { $0.type == .insertion }.map(\.id))
    #expect(downInsertions == sidebarInsertions,
      "Down mode and sidebar must number insertions identically")
  }

  @Test("Up-mode IDs match sidebar IDs", arguments: corpus)
  func upMatchesSidebar(_ c: EditCase) {
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(c.old)
    let up = Self.idSequence(
      in: MudCore.renderUpToHTML(c.new, options: opts))
    let sidebar = Self.uniqueInOrder(
      MudCore.computeChanges(
        old: ParsedMarkdown(c.old), new: ParsedMarkdown(c.new)
      ).map(\.id))
    #expect(up == sidebar,
      "Up mode and sidebar must agree on change IDs and order")
  }

  // MARK: - Helpers

  private static func uniqueInOrder(_ ids: [String]) -> [String] {
    var seen = Set<String>()
    return ids.filter { seen.insert($0).inserted }
  }

  /// Collects distinct change IDs from rendered HTML in document order:
  /// the value following each occurrence of `marker`, up to the closing
  /// quote. The default marker matches every `data-change-id` attribute;
  /// `dl-ins" data-change-id="` narrows it to Down-mode insertion lines.
  private static func idSequence(
    in html: String, after marker: String = "data-change-id=\""
  ) -> [String] {
    var ids: [String] = []
    var seen = Set<String>()
    var search = html.startIndex
    while let match = html.range(
      of: marker, range: search..<html.endIndex) {
      guard let close = html.range(
        of: "\"", range: match.upperBound..<html.endIndex)
      else { break }
      let id = String(html[match.upperBound..<close.lowerBound])
      if id.hasPrefix("change-"), seen.insert(id).inserted {
        ids.append(id)
      }
      search = close.upperBound
    }
    return ids
  }
}
