import Foundation
import Testing
@testable import MudCore

@Suite("Up mode change tracking")
struct UpModeChangeTrackingTests {
  // MARK: - No-op when waypoint is nil

  @Test func noWaypointProducesNoMarkers() {
    let html = MudCore.renderUpToHTML("Hello.\n")
    #expect(!html.contains("mud-change"))
    #expect(!html.contains("data-change-id"))
  }

  @Test func identicalContentProducesNoMarkers() {
    let md = "Hello.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(md)
    let html = MudCore.renderUpToHTML(md, options: opts)
    #expect(!html.contains("mud-change"))
  }

  // MARK: - Insertions on native elements

  @Test func insertedParagraphHasAttributesOnP() {
    let old = "First.\n"
    let new = "First.\n\nAdded.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<p class=\"mud-change-ins\""))
    #expect(html.contains("Added."))
    #expect(html.contains("data-change-id"))
    #expect(!html.contains("<ins"), "Insertions must not use <ins> wrappers")
  }

  @Test func insertedHeadingHasAttributesOnH() {
    let old = "Paragraph.\n"
    let new = "Paragraph.\n\n## New heading\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<h2"))
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("New heading"))
    #expect(!html.contains("<ins"), "Insertions must not use <ins> wrappers")
  }

  @Test func insertedCodeBlockHasAttributesOnPre() {
    let old = "Before.\n"
    let new = "Before.\n\n```\ncode\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<pre"))
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("code"))
    #expect(!html.contains("<ins"), "Insertions must not use <ins> wrappers")
  }

  @Test func insertedListItemHasAttributesOnLi() {
    let old = "- Alpha\n"
    let new = "- Alpha\n- Beta\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<li"))
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("Beta"))
    #expect(!html.contains("<ins"), "Insertions must not use <ins> wrappers")
  }

  // MARK: - Deletions as native elements

  @Test func deletedParagraphEmittedAsNativeP() {
    let old = "Keep.\n\nRemoved.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<p class=\"mud-change-del\""))
    #expect(html.contains("Removed."))
    #expect(html.contains("data-change-id"))
    #expect(!html.contains("<del"), "Deletions must not use <del> wrappers")
  }

  @Test func deletedUnorderedListItemEmittedAsNativeLi() {
    let old = "- Alpha\n- Beta\n- Gamma\n"
    let new = "- Alpha\n- Gamma\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("<li class=\"mud-change-del\""))
    #expect(html.contains("Beta"))
    #expect(!html.contains("<del"), "Deleted list item must not use a <del> wrapper")
  }

  @Test func deletedOrderedListItemEmittedAsNativeLi() {
    let old = "1. First\n2. Second\n3. Third\n"
    let new = "1. First\n3. Third\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("<li class=\"mud-change-del\""))
    #expect(html.contains("Second"))
    #expect(!html.contains("<del"), "Deleted list item must not use a <del> wrapper")
  }

  @Test func deletedListItemContentDoesNotLeakIntoSurvivor() {
    let old = "1. First\n2. Second\n3. Third\n"
    let new = "1. First\n3. Third\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // "Second" and "Third" must not appear in the same <li>.
    let liPattern = /<li>[^<]*Third[^<]*<\/li>/
    if let match = html.firstMatch(of: liPattern) {
      let liContent = String(html[match.range])
      #expect(!liContent.contains("Second"),
        "Surviving item must not contain deleted item's content")
    }
  }

  @Test func deletedItemBeforeComplexItemRendersAsSibling() {
    let old = "1. First\n2. Second\n3. Third\n   - Sub A\n   - Sub B\n"
    let new = "1. First\n3. Third\n   - Sub A\n   - Sub B\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("<li class=\"mud-change-del\""))
    #expect(html.contains("Second"))
    #expect(!html.contains("<del"), "Deleted list item must not use a <del> wrapper")
  }

  @Test func deletionAppearsBeforeSurvivingBlock() {
    let old = "First.\n\nRemoved.\n\nLast.\n"
    let new = "First.\n\nLast.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let delRange = html.range(of: "mud-change-del")!
    let lastRange = html.range(of: "Last.")!
    #expect(delRange.lowerBound < lastRange.lowerBound)
  }

  @Test func trailingDeletionAppearsAtEnd() {
    let old = "Keep.\n\nTrailing.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let keepRange = html.range(of: "Keep.")!
    let delRange = html.range(of: "Trailing.")!
    #expect(keepRange.lowerBound < delRange.lowerBound)
  }

  @Test func multipleDeletionsBeforeOneBlock() {
    let old = "Gone A.\n\nGone B.\n\nSurvivor.\n"
    let new = "Survivor.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("Gone A."))
    #expect(html.contains("Gone B."))
    let delA = html.range(of: "Gone A.")!
    let survivor = html.range(of: "Survivor.")!
    #expect(delA.lowerBound < survivor.lowerBound)
  }

  // MARK: - Replacements (del + ins as native elements)

  @Test func replacementOldVersionPrecedesNewVersion() {
    let old = "Original.\n"
    let new = "Changed.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let delRange = html.range(of: "Original.")!
    let insRange = html.range(of: "Changed.")!
    #expect(delRange.lowerBound < insRange.lowerBound)
  }

  // MARK: - Deletion HTML content

  @Test func deletionContainsRenderedHTML() {
    let old = "Keep.\n\n**Bold deleted.**\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<strong>Bold deleted.</strong>"))
    #expect(!html.contains("**Bold deleted.**"))
  }

  // MARK: - Change IDs

  @Test func changeIDsPresent() {
    let old = "First.\n"
    let new = "First.\n\nSecond.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("data-change-id=\"change-"))
  }

  @Test func multipleChangesHaveDistinctIDs() {
    let old = "Alpha.\n\nBeta.\n"
    let new = "Alpha changed.\n\nBeta changed.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let idPattern = /data-change-id="(change-\d+)"/
    let ids = html.matches(of: idPattern).map { String($0.1) }
    let unique = Set(ids)
    #expect(unique.count == ids.count)
    #expect(unique.count >= 4) // 2 replacements x (del + ins) each
  }

  // MARK: - Group attributes

  @Test func changedElementsCarryGroupID() {
    let old = "First.\n"
    let new = "First.\n\nAdded.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("data-group-id=\"group-"))
  }

  @Test func firstElementInGroupCarriesGroupIndex() {
    let old = "First.\n"
    let new = "First.\n\nAdded A.\n\nAdded B.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("data-group-index=\"1\""))
  }

  @Test func groupAttributesConsistentAcrossMultiBlockGroup() {
    let old = "Keep.\n"
    let new = "Keep.\n\nAdded A.\n\nAdded B.\n\nAdded C.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // All three inserted paragraphs should share the same group ID.
    let groupPattern = /data-group-id="(group-\d+)"/
    let groupIDs = html.matches(of: groupPattern).map { String($0.1) }
    #expect(groupIDs.count == 3)
    #expect(Set(groupIDs).count == 1)
  }

  @Test func separateGroupsGetDifferentIDs() {
    let old = "Alpha.\n\nKeep.\n\nGamma.\n"
    let new = "Alpha changed.\n\nKeep.\n\nGamma changed.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    let groupPattern = /data-group-id="(group-\d+)"/
    let groupIDs = html.matches(of: groupPattern).map { String($0.1) }
    let unique = Set(groupIDs)
    #expect(unique.count == 2)
  }

  @Test func deletionElementsCarryGroupID() {
    let old = "Keep.\n\nRemoved.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // The deleted <p> should carry a group ID.
    let groupPattern = /data-group-id="(group-\d+)"/
    let groupIDs = html.matches(of: groupPattern).map { String($0.1) }
    #expect(!groupIDs.isEmpty)
  }

  // MARK: - Table rows

  @Test func insertedTableRowHasAttributesOnTr() {
    let old = "| A |\n|---|\n| 1 |\n"
    let new = "| A |\n|---|\n| 1 |\n| 2 |\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<tr"))
    #expect(html.contains("mud-change-ins"))
    #expect(!html.contains("<ins"), "Inserted table row must not use <ins> wrapper")
  }

  @Test func deletedTableRowEmittedAsNativeTr() {
    let old = "| A |\n|---|\n| 1 |\n| 2 |\n"
    let new = "| A |\n|---|\n| 1 |\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<tr class=\"mud-change-del\""))
    #expect(!html.contains("<del"), "Deleted table row must not use <del> wrapper")
  }

  @Test func deletedTableRowAppearsAsSiblingInTbody() {
    // Deleted row between two surviving rows must appear as a <tr>
    // sibling inside <tbody>, not wrapped in <del>.
    let old = "| A |\n|---|\n| 1 |\n| 2 |\n| 3 |\n"
    let new = "| A |\n|---|\n| 1 |\n| 3 |\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    // The deleted row should be a <tr> with the deletion class.
    #expect(html.contains("<tr class=\"mud-change-del\""))
    #expect(html.contains("2"))
    #expect(!html.contains("<del"), "Deleted table row must not use <del> wrapper")

    // The deleted <tr> must be inside <tbody>, not outside the table.
    let tbodyRange = html.range(of: "<tbody>")!
    let tbodyEndRange = html.range(of: "</tbody>")!
    let delTrRange = html.range(of: "mud-change-del")!
    #expect(delTrRange.lowerBound > tbodyRange.lowerBound)
    #expect(delTrRange.upperBound < tbodyEndRange.upperBound)
  }

  @Test func deletedLastTableRowInsideOriginalTable() {
    // When the last row is deleted and content follows the table,
    // the deleted row must appear inside the original table's <tbody>,
    // not in a separate wrapper table (regression: bare <tr> outside
    // table was invisible in the browser).
    let old = "| A |\n|---|\n| 1 |\n| 2 |\n\nAfter.\n"
    let new = "| A |\n|---|\n| 1 |\n\nAfter.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("<tr class=\"mud-change-del\""))

    // Only one <table> — the deleted row is inside the original,
    // not a separate wrapper.
    let tableCount = html.components(separatedBy: "<table>").count - 1
    #expect(tableCount == 1, "Deleted row should be in the original table")

    // The deleted <tr> must be inside the open <tbody>.
    let delRange = html.range(of: "mud-change-del")!
    let before = html[html.startIndex..<delRange.lowerBound]
    let tbodyCount = before.components(separatedBy: "<tbody>").count - 1
    let tbodyEndCount = before.components(separatedBy: "</tbody>").count - 1
    #expect(tbodyCount > tbodyEndCount,
            "Deleted <tr> must be inside an open <tbody>")
  }

  @Test func deletedLastTableRowAsTrailingDeletion() {
    // When the deleted row is the last block in the document
    // (nothing follows the table), it becomes a trailing deletion.
    // It must still appear inside the original table's <tbody>.
    let old = "| A |\n|---|\n| 1 |\n| 2 |\n"
    let new = "| A |\n|---|\n| 1 |\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)

    #expect(html.contains("<tr class=\"mud-change-del\""))

    // Only one <table>.
    let tableCount = html.components(separatedBy: "<table>").count - 1
    #expect(tableCount == 1, "Deleted row should be in the original table")

    // The deleted <tr> must be inside the open <tbody>.
    let delRange = html.range(of: "mud-change-del")!
    let before = html[html.startIndex..<delRange.lowerBound]
    let tbodyCount = before.components(separatedBy: "<tbody>").count - 1
    let tbodyEndCount = before.components(separatedBy: "</tbody>").count - 1
    #expect(tbodyCount > tbodyEndCount,
            "Deleted <tr> must be inside an open <tbody>")
  }

  // MARK: - Edge cases

  @Test func allContentDeleted() {
    let old = "Gone.\n"
    let new = ""
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<p class=\"mud-change-del\""))
    #expect(html.contains("Gone."))
    #expect(!html.contains("<del"), "Must not use <del> wrappers")
  }

  @Test func allContentInserted() {
    let old = ""
    let new = "Brand new.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("<p class=\"mud-change-ins\""))
    #expect(html.contains("Brand new."))
    #expect(!html.contains("<ins"), "Must not use <ins> wrappers")
  }

  // MARK: - Word-level diffs in blue block (paired insertion)

  @Test func singleWordChangedShowsInlineMarkers() {
    let old = "The quick fox.\n"
    let new = "The slow fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // The blue block (insertion) should contain inline <del> and <ins>.
    #expect(html.contains("<del>"))
    #expect(html.contains("<ins>"))
    #expect(html.contains("quick"))
    #expect(html.contains("slow"))
  }

  @Test func wordAddedShowsInsOnly() {
    let old = "The fox.\n"
    let new = "The brown fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<ins>"))
      #expect(block.contains("brown"))
    }
  }

  @Test func wordRemovedShowsDelOnly() {
    let old = "The brown fox.\n"
    let new = "The fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    opts.showInlineDeletions = true
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<del>"))
      #expect(block.contains("brown"))
    }
  }

  @Test func formattedTextSameStructureShowsInlineMarkers() {
    let old = "Hello **beautiful** world.\n"
    let new = "Hello **wonderful** world.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // <ins>/<del> should nest inside <strong> correctly.
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<strong>"))
      #expect(block.contains("<del>") || block.contains("<ins>"))
    }
  }

  @Test func formattingOnlyChangeFallsBackToBlockLevel() {
    // Same words, different formatting → block-level only.
    let old = "Hello **bold** world.\n"
    let new = "Hello *bold* world.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(!block.contains("<ins>"),
        "Formatting-only change should not produce inline word markers")
      #expect(!block.contains("<del>"),
        "Formatting-only change should not produce inline word markers")
    }
  }

  @Test func wordChangedWithDivergentFormattingShowsInlineMarkers() {
    // Word changed AND formatting diverges → word-level markers present.
    let old = "Hello **bold** world.\n"
    let new = "Hello *italic* world.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    opts.showInlineDeletions = true
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<del>"), "Word change with formatting change should show <del>")
      #expect(block.contains("<ins>"), "Word change with formatting change should show <ins>")
      #expect(block.contains("bold"))
      #expect(block.contains("italic"))
    }
  }

  @Test func redBlockWithDivergentFormattingShowsDelOnly() {
    let old = "Hello **bold** world.\n"
    let new = "Hello *italic* world.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let delBlock = extractBlock(html, class: "mud-change-del")
    #expect(delBlock != nil)
    if let block = delBlock {
      #expect(block.contains("<del>"), "Red block should show deleted word")
      #expect(block.contains("bold"))
      #expect(!block.contains("<ins>"), "Red block must not contain <ins>")
      #expect(!block.contains("italic"),
        "Red block must not contain the inserted word")
    }
  }

  @Test func blueBlockWithFormattingAddedShowsMarkersInNewFormatting() {
    // Old: plain text. New: word changed and wrapped in emphasis.
    let old = "The quick fox.\n"
    let new = "The *slow* fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    opts.showInlineDeletions = true
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<em>"), "New formatting should be present")
      #expect(block.contains("<ins>"), "Inserted word should be marked")
      #expect(block.contains("<del>"), "Deleted word should be shown")
      #expect(block.contains("slow"))
      #expect(block.contains("quick"))
    }
  }

  @Test func redBlockWithFormattingAddedPreservesOldFormatting() {
    // Old: plain text. New: word changed and wrapped in emphasis.
    // Red block walks old AST → should have no <em>.
    let old = "The quick fox.\n"
    let new = "The *slow* fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let delBlock = extractBlock(html, class: "mud-change-del")
    #expect(delBlock != nil)
    if let block = delBlock {
      #expect(!block.contains("<em>"),
        "Red block uses old AST, which has no emphasis")
      #expect(block.contains("<del>"))
      #expect(block.contains("quick"))
      #expect(!block.contains("<ins>"))
    }
  }

  @Test func multiLineParagraphWordChangePreservesFullText() {
    // SoftBreaks contribute a space to plainText; the word span cursor
    // must account for it or the final characters get truncated.
    let old = "The quick brown\nfox jumps over.\n"
    let new = "The slow brown\nfox jumps over.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<ins>"))
      #expect(block.contains("slow"))
      // The full text after the SoftBreak must survive intact.
      #expect(block.contains("over."), "Text after SoftBreak must not be truncated")
    }
  }

  // MARK: - Word-level diff truncation guards
  //
  // These tests verify that paragraphs with inline formatting are not
  // truncated by word-level diffs. The word diff operates on plainText
  // (which flattens formatting) while the renderer walks the AST
  // (which has formatting nodes). Any discrepancy in character
  // counting causes text to be silently dropped.

  @Test func inlineCodeDoesNotCauseTruncation() {
    let old = "Call `foo()` and wait.\n"
    let new = "Call `foo()` and sleep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("foo()"), "Code content must survive")
      #expect(block.contains("sleep"), "Text after code must survive")
    }
  }

  @Test func multipleInlineCodesDoNotCauseTruncation() {
    let old = "Use `foo()` then `bar()` to finish.\n"
    let new = "Use `foo()` then `bar()` to start.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("foo()"), "First code must survive")
      #expect(block.contains("bar()"), "Second code must survive")
      #expect(block.contains("start"), "Text after codes must survive")
    }
  }

  @Test func boldTextDoesNotCauseTruncation() {
    let old = "The **important** value is high.\n"
    let new = "The **important** value is low.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("important"), "Bold content must survive")
      #expect(block.contains("low"), "Text after bold must survive")
    }
  }

  @Test func emphasisDoesNotCauseTruncation() {
    let old = "The *special* value is high.\n"
    let new = "The *special* value is low.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("special"), "Emphasis content must survive")
      #expect(block.contains("low"), "Text after emphasis must survive")
    }
  }

  @Test func mixedFormattingDoesNotCauseTruncation() {
    let old = "Call `render()` on the **main** thread now.\n"
    let new = "Call `render()` on the **main** thread later.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("render()"), "Code content must survive")
      #expect(block.contains("main"), "Bold content must survive")
      #expect(block.contains("later"), "Text after formatting must survive")
    }
  }

  @Test func inlineCodeAtStartDoesNotCauseTruncation() {
    let old = "`foo` is a function.\n"
    let new = "`foo` is a method.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("foo"), "Code at start must survive")
      #expect(block.contains("method"), "Text after code must survive")
    }
  }

  @Test func inlineCodeAtEndDoesNotCauseTruncation() {
    let old = "The function is `foo`.\n"
    let new = "The method is `foo`.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("method"), "Changed word must survive")
      #expect(block.contains("foo"), "Code at end must survive")
    }
  }

  // MARK: - Word-level diffs in red block (paired deletion)

  @Test func redBlockShowsDeletedWordsOnly() {
    let old = "The quick fox.\n"
    let new = "The slow fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let delBlock = extractBlock(html, class: "mud-change-del")
    #expect(delBlock != nil)
    if let block = delBlock {
      #expect(block.contains("<del>"))
      #expect(block.contains("quick"))
      // Red block must NOT contain <ins> — inserted words are skipped.
      #expect(!block.contains("<ins>"),
        "Red block must not show inserted words")
    }
  }

  @Test func redBlockWordAddedInNewHasNoMarkers() {
    // When a word is added in new, the old text has nothing to mark.
    let old = "The fox.\n"
    let new = "The brown fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let delBlock = extractBlock(html, class: "mud-change-del")
    #expect(delBlock != nil)
    if let block = delBlock {
      #expect(!block.contains("brown"),
        "Added word should not appear in the deletion block")
    }
  }

  // MARK: - Green block (pure insertion, no word-level markers)

  @Test func greenBlockHasNoWordLevelMarkers() {
    let old = "Keep.\n"
    let new = "Keep.\n\nBrand new paragraph.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // The pure insertion should have no inline <ins> or <del>.
    let insBlocks = extractAllBlocks(html, class: "mud-change-ins")
    for block in insBlocks where block.contains("Brand new") {
      #expect(!block.contains("<ins>"),
        "Pure insertion should not have word-level markers")
      #expect(!block.contains("<del>"),
        "Pure insertion should not have word-level markers")
    }
  }

  // MARK: - Word-level diffs in list items

  @Test func unorderedListItemWordChangeShowsInlineMarkers() {
    let old = "- The quick fox\n"
    let new = "- The slow fox\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    opts.showInlineDeletions = true
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<ins>"),
        "Changed list item should show word-level <ins> markers")
      #expect(block.contains("slow"))
      #expect(block.contains("<del>"),
        "Changed list item should show word-level <del> markers")
      #expect(block.contains("quick"))
    }
  }

  @Test func orderedListItemWordChangeShowsInlineMarkers() {
    let old = "1. The quick fox\n"
    let new = "1. The slow fox\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    opts.showInlineDeletions = true
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<ins>"),
        "Changed ordered list item should show word-level <ins> markers")
      #expect(block.contains("slow"))
      #expect(block.contains("<del>"),
        "Changed ordered list item should show word-level <del> markers")
      #expect(block.contains("quick"))
    }
  }

  @Test func listItemWordAppendShowsInlineMarkers() {
    let old = "- Alpha done\n"
    let new = "- Alpha done and more\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<ins>"),
        "Appended words in list item should be marked with <ins>")
      #expect(block.contains("more"))
    }
  }

  // MARK: - Inline deletions setting

  @Test func inlineDeletionsOffHidesDelInBlueBlock() {
    let old = "The quick fox.\n"
    let new = "The slow fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    opts.showInlineDeletions = false
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(!block.contains("<del>"),
        "Blue block should not show <del> when inline deletions is off")
      #expect(block.contains("<ins>"),
        "Blue block should still show <ins> markers")
      #expect(block.contains("slow"))
      #expect(!block.contains("quick"),
        "Old word should not appear when inline deletions is off")
    }
  }

  @Test func inlineDeletionsOnShowsDelInBlueBlock() {
    let old = "The quick fox.\n"
    let new = "The slow fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    opts.showInlineDeletions = true
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<del>"),
        "Blue block should show <del> when inline deletions is on")
      #expect(block.contains("quick"))
    }
  }

  // MARK: - Word diff threshold

  @Test func lowSimilarityBlockSuppressesWordMarkers() {
    // 4 of 5 words changed → similarity well below 0.25 →
    // block-level only, no inline <ins>/<del>.
    let old = "The quick brown fox jumps.\n"
    let new = "A slow red dog leaps.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(!block.contains("<ins>"),
        "Low-similarity block should not have word-level <ins>")
      #expect(!block.contains("<del>"),
        "Low-similarity block should not have word-level <del>")
    }
  }

  @Test func highSimilarityBlockShowsWordMarkers() {
    // 1 of 3 words changed → similarity well above 0.25 →
    // word-level markers present.
    let old = "The quick fox.\n"
    let new = "The slow fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<ins>"),
        "High-similarity block should have word-level <ins>")
    }
  }

  @Test func customThresholdOverridesDefault() {
    // 1 of 3 words changed (similarity ≈ 0.6). With threshold
    // raised to 0.8, word markers should be suppressed.
    let old = "The quick fox.\n"
    let new = "The slow fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    opts.wordDiffThreshold = 0.8
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(!block.contains("<ins>"),
        "Should suppress word markers when threshold is above similarity")
    }
  }

  // MARK: - Alerts and asides

  @Test func insertedGFMAlertHasChangeAttributes() {
    let old = "Keep.\n"
    let new = "Keep.\n\n> [!NOTE]\n> Added alert.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("data-change-id"))
    #expect(html.contains("Added alert."))
    #expect(!html.contains("<ins"), "Must not use <ins> wrappers")
  }

  /// The `[!TYPE]` tag is part of the paragraph cmark parses and so part of
  /// the text the word diff runs over, but it is never rendered — the title
  /// paragraph stands in for it. These three pin that the emitter is advanced
  /// past exactly that prefix: a marker landing early would sit against the
  /// generated title, and one landing late would shear every following word.

  @Test func rewordedGFMAlertMarksTheChangedWords() {
    let old = "> [!NOTE]\n> The report covers March results.\n"
    let new = "> [!NOTE]\n> The report covers April results.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    opts.showInlineDeletions = true
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<del>March</del>"))
      #expect(block.contains("<ins>April</ins>"))
      // The surrounding words are unmarked, and the tag never reaches the
      // body: the title paragraph is all that is emitted for it.
      #expect(block.contains("<p>The report covers <del>March</del>"))
      #expect(!block.contains("[!NOTE]"))
    }
  }

  @Test func rewordedGFMAlertMarksTheDeletedWordsInTheRedBlock() {
    let old = "> [!NOTE]\n> The report covers March results.\n"
    let new = "> [!NOTE]\n> The report covers April results.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let delBlock = extractBlock(html, class: "mud-change-del")
    #expect(delBlock != nil)
    if let block = delBlock {
      #expect(block.contains("<del>March</del>"))
      #expect(!block.contains("<ins>"), "Red block must not show the insertion")
      // The skipped prefix must not leave a marker before the alert title.
      #expect(!block.contains("<del>[!NOTE]"))
    }
  }

  @Test func rewordedGFMAlertTagLineMarksTheChangedWords() {
    // Content on the tag line is stripped along with the tag itself, so the
    // prefix the emitter skips is the tag *and* the space after it.
    let old = "> [!TIP] Ship the beta build.\n> Then tag it.\n"
    let new = "> [!TIP] Ship the final build.\n> Then tag it.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    opts.showInlineDeletions = true
    let html = MudCore.renderUpToHTML(new, options: opts)
    let insBlock = extractBlock(html, class: "mud-change-ins")
    #expect(insBlock != nil)
    if let block = insBlock {
      #expect(block.contains("<p>Ship the <del>beta</del><ins>final</ins>"))
      #expect(block.contains("Then tag it."))
    }
  }

  @Test func replacedDocCAsideHasChangeAttributes() {
    let old = "> Status: Planning\n"
    let new = "> Status: Underway\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // Content elements use mud-change-ins, not mud-change-mix.
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("data-change-id"))
  }

  @Test func insertedDocCAsideHasChangeAttributes() {
    let old = "Keep.\n"
    let new = "Keep.\n\n> Note: New aside.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    #expect(html.contains("mud-change-ins"))
    #expect(html.contains("data-change-id"))
    #expect(html.contains("New aside."))
  }

  @Test func deletedAsideRenderedAsAlert() {
    let old = "> Status: Planning\n\nKeep.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // The deleted aside should be a blockquote with alert styling.
    let pattern = /blockquote class="[^"]*alert-status[^"]*mud-change-del/
    #expect(html.contains(pattern),
      "Deleted aside should be a <blockquote> with alert-status class")
    #expect(html.contains("alert-title"),
      "Deleted aside should have alert title paragraph")
  }

  @Test func replacedAsideDeletedVersionRenderedAsAlert() {
    let old = "> Status: Planning\n"
    let new = "> Status: Underway\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // Both blocks should be blockquotes with alert styling.
    let delPattern = /blockquote class="[^"]*alert-status[^"]*mud-change-del/
    #expect(html.contains(delPattern),
      "Deleted aside should have alert-status class")
    #expect(html.contains("Planning"))
  }

  @Test func replacedAsideShowsWordLevelDiffInInsertedBlock() {
    let old = "> Status: Planning\n"
    let new = "> Status: Underway\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // The inserted aside should show inline word-level markers.
    let insPattern = /blockquote class="[^"]*mud-change-ins/
    #expect(html.contains(insPattern))
    #expect(html.contains("<del>"), "Blue block should show deleted word")
    #expect(html.contains("<ins>"), "Blue block should show inserted word")
    #expect(html.contains("Planning"))
    #expect(html.contains("Underway"))
  }

  @Test func replacedAsideShowsWordLevelDiffInDeletedBlock() {
    let old = "> Status: Planning\n"
    let new = "> Status: Underway\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let delBlock = extractBlock(html, class: "mud-change-del")
    #expect(delBlock != nil)
    if let block = delBlock {
      #expect(block.contains("<del>"), "Red block should mark deleted word")
      #expect(block.contains("Planning"))
      #expect(!block.contains("<ins>"), "Red block must not show inserted word")
    }
  }

  @Test func deletedGFMAlertRenderedAsAlert() {
    let old = "> [!NOTE]\n> Important info.\n\nKeep.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    let pattern = /blockquote class="[^"]*alert-note[^"]*mud-change-del/
    #expect(html.contains(pattern),
      "Deleted GFM alert should be a <blockquote> with alert-note class")
    #expect(html.contains("alert-title"))
  }

  @Test func alertChangeAttributeIsOnBlockquote() {
    let old = "> Status: Planning\n"
    let new = "> Status: Underway\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderUpToHTML(new, options: opts)
    // The change attributes should be on the <blockquote> tag.
    let pattern = /blockquote class="[^"]*mud-change-ins/
    #expect(html.contains(pattern))
  }
}

// MARK: - Test helpers

/// Extracts the first HTML block with the given class from rendered output.
private func extractBlock(_ html: String, class className: String) -> String? {
  // Find the tag containing this class, then extract to its closing tag.
  guard let classRange = html.range(of: className) else { return nil }
  // Walk backward to find the opening '<'.
  var start = classRange.lowerBound
  while start > html.startIndex && html[html.index(before: start)] != "<" {
    start = html.index(before: start)
  }
  if start > html.startIndex {
    start = html.index(before: start) // include the '<'
  }
  // Find the tag name.
  let afterOpen = html.index(after: start) // skip '<'
  let tagEnd = html[afterOpen...].firstIndex(where: { $0 == " " || $0 == ">" })
      ?? html.endIndex
  let tagName = String(html[afterOpen..<tagEnd])
  // Find the matching close tag.
  let closeTag = "</\(tagName)>"
  guard let closeRange = html.range(of: closeTag, range: classRange.upperBound..<html.endIndex)
  else { return nil }
  return String(html[start..<closeRange.upperBound])
}

/// Extracts all HTML blocks with the given class from rendered output.
private func extractAllBlocks(_ html: String, class className: String) -> [String] {
  var results: [String] = []
  var searchStart = html.startIndex
  while searchStart < html.endIndex {
    let remaining = html[searchStart...]
    guard let classRange = remaining.range(of: className) else { break }
    if let block = extractBlock(
        String(html[searchStart...]), class: className) {
      results.append(block)
    }
    searchStart = classRange.upperBound
  }
  return results
}
