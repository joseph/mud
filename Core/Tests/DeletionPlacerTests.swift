import Foundation
import Testing

@testable import MudCore

/// Pins the exactly-once bookkeeping of `DeletionPlacer` (Phase 3f).
/// The visitor asks for the same deletions at more than one point in
/// its walk (peeked ahead of a list item, hoisted out of a table, then
/// again at the keyed node); the consumed set must make the second
/// lookup empty, and `<tr>` deletions surfacing outside a table must
/// be wrapped in their own `<table><tbody>`. Rendering end-to-end is
/// covered by `UpModeChangeTrackingTests`; these drive the placer
/// directly.
@Suite("DeletionPlacer")
struct DeletionPlacerTests {

  private func makePlacer(
    old: String, new: ParsedMarkdown
  ) -> DeletionPlacer {
    DeletionPlacer(
      diffContext: DiffContext(old: ParsedMarkdown(old), new: new))
  }

  @Test func peekedListItemDeletionIsNotReEmittedAtItsKeyedNode() throws {
    // A deleted simple item before a complex item keys to the complex
    // item's first paragraph. The visitor peeks it before opening the
    // <li>; when it later renders that paragraph, the placer must
    // return nothing.
    let old = "1. First\n2. Second\n3. Third\n   - Sub A\n   - Sub B\n"
    let parsed = ParsedMarkdown("1. First\n3. Third\n   - Sub A\n   - Sub B\n")
    var placer = makePlacer(old: old, new: parsed)

    let list = try #require(parsed.document.child(at: 0))
    let complexItem = try #require(list.child(at: 1))
    let firstChild = try #require(complexItem.child(at: 0))

    let peeked = placer.listItemHTML(before: firstChild)
    #expect(peeked.contains("<li class=\"mud-change-del\""))
    #expect(peeked.contains("Second"))
    #expect(placer.precedingHTML(before: firstChild).isEmpty)
  }

  @Test func hoistedDeletionIsNotReEmittedAtTheHeadRow() throws {
    // A deleted paragraph before an unchanged table keys to the head
    // row. The visitor hoists it before <table>; the head row's own
    // lookup must then come back empty.
    let old = "Gone paragraph.\n\n| H |\n| - |\n| 1 |\n"
    let parsed = ParsedMarkdown("| H |\n| - |\n| 1 |\n")
    var placer = makePlacer(old: old, new: parsed)

    let table = try #require(parsed.document.child(at: 0))
    let head = try #require(table.child(at: 0))

    let hoisted = placer.hoistedHTML(beforeHead: head)
    #expect(hoisted.contains("<p class=\"mud-change-del\""))
    #expect(hoisted.contains("Gone paragraph."))
    #expect(placer.precedingHTML(before: head).isEmpty)
  }

  @Test func trailingRowDeletionsAreWrappedInTheirOwnTable() {
    // A fully deleted table at the end of the document surfaces as
    // trailing <tr> deletions outside any table context; the placer
    // wraps the run in a single <table><tbody> so the HTML is valid.
    let old = "Intro.\n\n| H |\n| - |\n| 1 |\n"
    let parsed = ParsedMarkdown("Intro.\n")
    let placer = makePlacer(old: old, new: parsed)

    let trailing = placer.trailingHTML()
    #expect(trailing.hasPrefix("<table>\n<tbody>\n<tr"))
    #expect(trailing.hasSuffix("</tbody>\n</table>\n"))
    #expect(trailing.components(separatedBy: "<table>").count - 1 == 1)
    #expect(trailing.components(separatedBy: "<tr").count - 1 == 2)
  }
}
