import Testing
@testable import MudCore

@Suite("Down mode change tracking")
struct DownModeChangeTrackingTests {
  // MARK: - No-op when waypoint is nil

  @Test func noWaypointProducesNoMarkers() {
    let html = MudCore.renderDownToHTML("Hello.\n")
    #expect(!html.contains("dl-ins"))
    #expect(!html.contains("dl-del"))
    #expect(!html.contains("data-change-id"))
  }

  @Test func identicalContentProducesNoMarkers() {
    let md = "Hello.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(md)
    let html = MudCore.renderDownToHTML(md, options: opts)
    #expect(!html.contains("dl-ins"))
    #expect(!html.contains("dl-del"))
  }

  // MARK: - Insertions

  @Test func insertedParagraphLineMarkedAsInsertion() {
    let old = "First.\n"
    let new = "First.\n\nAdded.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("dl-ins"))
    #expect(html.contains("Added."))
    #expect(html.contains("data-change-id"))
  }

  @Test func multiLineInsertionMarksAllLines() {
    let old = "Keep.\n"
    let new = "Keep.\n\nLine one.\nLine two.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("Line one."))
    #expect(html.contains("Line two."))
    // Both content lines of the inserted paragraph should be marked.
    let insCount = html.components(separatedBy: "dl-ins").count - 1
    #expect(insCount >= 2)
  }

  // MARK: - Deletions

  @Test func deletedParagraphLineMarkedAsDeletion() {
    let old = "Keep.\n\nRemoved.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("dl-del"))
    #expect(html.contains("Removed."))
    #expect(html.contains("data-change-id"))
  }

  @Test func deletedLinesShowDashLineNumber() {
    let old = "Keep.\n\nRemoved.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // Deleted lines use an en dash instead of a number.
    #expect(html.contains("<span class=\"ln\">\u{2013}</span>"))
  }

  @Test func deletionAppearsAtCorrectPosition() {
    let old = "First.\n\nMiddle.\n\nLast.\n"
    let new = "First.\n\nLast.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // "Middle." should appear between "First." and "Last.".
    let firstRange = html.range(of: "First.")!
    let middleRange = html.range(of: "Middle.")!
    let lastRange = html.range(of: "Last.")!
    #expect(firstRange.lowerBound < middleRange.lowerBound)
    #expect(middleRange.lowerBound < lastRange.lowerBound)
  }

  @Test func trailingDeletionAppearsAtEnd() {
    let old = "Keep.\n\nTrailing.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let keepRange = html.range(of: "Keep.")!
    let delRange = html.range(of: "Trailing.")!
    #expect(keepRange.lowerBound < delRange.lowerBound)
  }

  // MARK: - Replacements (del + ins)

  @Test func replacedBlockShowsOldAndNewLines() {
    let old = "Original text.\n"
    let new = "Revised text.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("dl-del"))
    #expect(html.contains("Original"))
    #expect(html.contains("dl-ins"))
    #expect(html.contains("Revised"))
  }

  @Test func replacementOldLinesPrecedeNewLines() {
    let old = "Original.\n"
    let new = "Changed.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let delRange = html.range(of: "Original.")!
    let insRange = html.range(of: "Changed.")!
    #expect(delRange.lowerBound < insRange.lowerBound)
  }

  // MARK: - Line numbers

  @Test func survivingLinesKeepNewDocumentLineNumbers() {
    let old = "First.\n\nRemoved.\n\nThird.\n"
    let new = "First.\n\nThird.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // New doc: line 1 = "First.", line 2 = "", line 3 = "Third."
    // Deleted lines get "–", surviving lines keep their new-doc numbers.
    #expect(html.contains("<span class=\"ln\">1</span>"))
    #expect(html.contains("<span class=\"ln\">3</span>"))
  }

  // MARK: - Change IDs

  @Test func changeIDsOnChangedLines() {
    let old = "First.\n"
    let new = "First.\n\nSecond.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("data-change-id=\"change-"))
  }

  // MARK: - Syntax highlighting of deleted lines

  @Test func deletedHeadingRetainsSyntaxHighlighting() {
    let old = "# Heading\n\nKeep.\n"
    let new = "Keep.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // The deleted heading line should carry md-heading syntax spans.
    #expect(html.contains("md-heading"))
    #expect(html.contains("Heading"))
  }

  // MARK: - Word-level diffs

  @Test func wordChangedInPairedBlockShowsInlineMarkers() {
    let old = "The quick fox.\n"
    let new = "The slow fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // Insertion line should contain inline <ins> and <del>.
    #expect(html.contains("<ins>"))
    #expect(html.contains("<del>"))
    #expect(html.contains("slow"))
    #expect(html.contains("quick"))
  }

  @Test func deletionLineInPairedBlockShowsDelOnly() {
    let old = "The quick fox.\n"
    let new = "The slow fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // Isolate deletion divs — split on </div> and filter.
    let delDivs = html.components(separatedBy: "</div>")
      .filter { $0.contains("dl-del") }
    #expect(!delDivs.isEmpty, "Should have at least one deletion div")
    for div in delDivs {
      #expect(!div.contains("<ins>"),
        "Deletion line must not contain <ins>")
    }
  }

  @Test func unpairedInsertionHasNoInlineMarkers() {
    let old = "Keep.\n"
    let new = "Keep.\n\nAdded.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insLines = html.components(separatedBy: "\n")
      .filter { $0.contains("dl-ins") }
    for line in insLines {
      #expect(!line.contains("<ins>"),
        "Unpaired insertion should not have word-level markers")
      #expect(!line.contains("<del>"),
        "Unpaired insertion should not have word-level markers")
    }
  }

  // MARK: - Word markers and syntax spans don't cross

  @Test func wordMarkersDoNotCrossSyntaxSpans() {
    // When inline code is in a changed block, <ins>/<del> tags must
    // not cross <span> boundaries. Crossed tags cause the browser to
    // close the .lc span prematurely, breaking Down mode layout.
    let old = "The `quick` fox.\n"
    let new = "The `slow` fox.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // Extract all insertion divs' .lc content.
    let insLines = html.components(separatedBy: "</div>")
      .filter { $0.contains("dl-ins") }
    for line in insLines {
      // No <ins> or <del> should be open when a </span> is emitted.
      // Pattern: <ins>...<span...>...</ins> (crossing).
      // This regex detects <ins> opened AFTER <span> and closed before
      // </span>, or <ins> containing an unmatched </span>.
      let crossingPattern =
        /<ins>[^<]*<span[^>]*>[^<]*<\/ins>/
      #expect(!line.contains(crossingPattern),
        "Word markers must not cross syntax span boundaries")
    }
  }

  @Test func wordMarkersInsideCodeSpanProduceValidNesting() {
    // When inline code is in a changed block, <ins>/<del> tags must
    // not cross <span> boundaries. Crossed tags cause the browser to
    // close the .lc span prematurely, breaking Down mode layout.
    let old = "Call `foo` now.\n"
    let new = "Call `bar` now.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // Extract insertion divs and verify all content is inside .lc.
    let lines = html.components(separatedBy: "</div>")
      .filter { $0.contains("dl-ins") }
    for line in lines where line.contains("<ins>") {
      let lcStart = line.range(of: "<span class=\"lc\">")
      #expect(lcStart != nil, "Insertion line should have .lc span")
      if let start = lcStart {
        let afterLc = String(line[start.upperBound...])
        // The inner syntax spans should be balanced (the extra
        // </span> at the end is the .lc element itself).
        let innerOpens = afterLc.components(separatedBy: "<span").count - 1
        let innerCloses = afterLc.components(separatedBy: "</span>").count - 1
        #expect(innerOpens + 1 == innerCloses,
          "Inner spans plus .lc close should balance")
        // No syntax-highlight span should appear after .lc closes.
        // Split on the last </span> (the .lc close) and check.
        if let lastClose = afterLc.range(
          of: "</span>", options: .backwards
        ) {
          let afterLcClose = afterLc[lastClose.upperBound...]
          #expect(!afterLcClose.contains("<span"),
            "No content should spill outside .lc")
        }
      }
    }
  }

  // MARK: - Edge cases

  @Test func allContentDeleted() {
    let old = "Gone.\n"
    let new = ""
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("dl-del"))
    #expect(html.contains("Gone."))
  }

  @Test func allContentInserted() {
    let old = ""
    let new = "Brand new.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    #expect(html.contains("dl-ins"))
    #expect(html.contains("Brand new."))
  }

  // MARK: - Line-level diffs within paired blocks

  @Test func multiLineParagraphOnlyChangedLinesMarked() {
    // Three-line paragraph with only the middle line changed.
    // Only that line should be marked, not the entire block.
    let old = "Line one.\nLine two.\nLine three.\n"
    let new = "Line one.\nLine TWO.\nLine three.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insCount = html.components(separatedBy: "dl-ins").count - 1
    let delCount = html.components(separatedBy: "dl-del").count - 1
    #expect(insCount == 1, "Only the changed line should be inserted")
    #expect(delCount == 1, "Only the old line should be deleted")
  }

  @Test func unchangedLinesInModifiedBlockAreNormal() {
    // Unchanged lines within a modified multi-line block should
    // render as plain divs without change classes.
    let old = "Line one.\nLine two.\nLine three.\n"
    let new = "Line one.\nLine TWO.\nLine three.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let lineOneDivs = html.components(separatedBy: "</div>")
      .filter { $0.contains("Line one.") }
    for div in lineOneDivs {
      #expect(!div.contains("dl-ins"))
      #expect(!div.contains("dl-del"))
    }
  }

  @Test func lineLevelDeletionPrecedesInsertion() {
    let old = "Keep.\nOld line.\nKeep too.\n"
    let new = "Keep.\nNew line.\nKeep too.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // Word markers may split the text (e.g. "<del>Old</del> line.")
    // so search for the unique changed word instead of the full line.
    let delRange = html.range(of: "Old")!
    let insRange = html.range(of: "New")!
    #expect(delRange.lowerBound < insRange.lowerBound)
  }

  @Test func wordMarkersOnLinePairedContent() {
    // A multi-line paragraph where one line has a word-level edit.
    // The changed line should get inline <ins>/<del> markers.
    let old = "Start.\nThe quick fox.\nEnd.\n"
    let new = "Start.\nThe slow fox.\nEnd.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insLines = html.components(separatedBy: "</div>")
      .filter { $0.contains("dl-ins") }
    #expect(insLines.contains { $0.contains("<ins>") },
      "Changed line should have word-level markers")
  }

  @Test func wordMarkersPairByBestMatchNotPosition() {
    // 3 deleted lines, 1 inserted line. The insertion is most
    // similar to the third deletion. Word markers should compare
    // against the best-matching deletion, not the first one.
    let old = """
      Unrelated first line of text.\n\
      Another different line here.\n\
      The quick brown fox jumps over.\n
      """
    let new = """
      The quick red fox jumps over.\n
      """
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // With correct pairing (against "The quick brown fox jumps
    // over."), only "brown"→"red" differs — producing a narrow
    // <ins>red</ins> marker. With wrong pairing (against the
    // unrelated first deletion), all new content lands in one
    // big <ins> tag and <ins>red</ins> never appears alone.
    let insDivs = html.components(separatedBy: "</div>")
      .filter { $0.contains("dl-ins") }
    #expect(!insDivs.isEmpty)
    let insContent = insDivs.joined()
    #expect(insContent.contains("<ins>red</ins>"),
      "Should pair with the similar deletion and mark only 'red'")
  }

  @Test func allLinesChangedDegeneratesToFullReplacement() {
    // When every line changes, behavior matches block-level.
    let old = "Alpha.\nBeta.\nGamma.\n"
    let new = "One.\nTwo.\nThree.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insCount = html.components(separatedBy: "dl-ins").count - 1
    let delCount = html.components(separatedBy: "dl-del").count - 1
    #expect(insCount == 3)
    #expect(delCount == 3)
  }

  @Test func singleLineBlockBehaviorUnchanged() {
    // Single-line blocks produce trivially one del + one ins,
    // same as current behavior. Regression guard.
    let old = "Original.\n"
    let new = "Changed.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insCount = html.components(separatedBy: "dl-ins").count - 1
    let delCount = html.components(separatedBy: "dl-del").count - 1
    #expect(insCount == 1)
    #expect(delCount == 1)
  }

  @Test func changeIDOnlyOnChangedLines() {
    // In a multi-line block with one line changed, only the
    // changed lines carry data-change-id attributes.
    let old = "Alpha.\nBeta.\nGamma.\n"
    let new = "Alpha.\nBETA.\nGamma.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let idCount = html.components(separatedBy: "data-change-id").count - 1
    #expect(idCount == 2,
      "Only the deletion and insertion lines should have change IDs")
  }

  @Test func fencedCodeBlockLineLevelDiff() {
    // A fenced code block where only one content line changes.
    // Fence lines are unchanged anchors; only the changed
    // content line should be marked.
    let old = "```\nalpha\nbeta\ngamma\n```\n"
    let new = "```\nalpha\nBETA\ngamma\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insCount = html.components(separatedBy: "dl-ins").count - 1
    let delCount = html.components(separatedBy: "dl-del").count - 1
    #expect(insCount == 1)
    #expect(delCount == 1)
  }

  @Test func multiLineListItemLineLevelDiff() {
    // A list item spanning multiple source lines.
    let old = "- First line\n  second line\n  third line\n"
    let new = "- First line\n  SECOND line\n  third line\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insCount = html.components(separatedBy: "dl-ins").count - 1
    let delCount = html.components(separatedBy: "dl-del").count - 1
    #expect(insCount == 1)
    #expect(delCount == 1)
  }

  @Test func wordMarkersAlignOnIndentedListContinuation() {
    // Regression: leading indent on a list-item continuation line
    // must not shift word markers. Previously `WordDiff` discarded
    // leading whitespace, so <ins>/<del> landed two columns too early
    // (marking "se" instead of "SE" on this fixture).
    let old = "- First line\n  second line\n  third line\n"
    let new = "- First line\n  SECOND line\n  third line\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    // The marker must cover the whole changed word, not a
    // column-shifted prefix.
    #expect(html.contains("<ins>SECOND</ins>"),
      "Insertion marker should cover exactly 'SECOND'")
    #expect(html.contains("<del>second</del>"),
      "Deletion marker should cover exactly 'second'")
  }

  @Test func linesAddedWithinPairedBlock() {
    // Old paragraph: 2 lines. New: 3 lines (one inserted).
    // Only the new line should be marked. No deletions.
    let old = "First.\nSecond.\n"
    let new = "First.\nInserted.\nSecond.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insCount = html.components(separatedBy: "dl-ins").count - 1
    let delCount = html.components(separatedBy: "dl-del").count - 1
    #expect(insCount == 1, "Only the new line should be inserted")
    #expect(delCount == 0, "No lines were deleted")
  }

  @Test func linesDeletedWithinPairedBlock() {
    // Old paragraph: 3 lines. New: 2 lines (middle removed).
    // Only the removed line should be deleted. No insertions.
    let old = "First.\nMiddle.\nLast.\n"
    let new = "First.\nLast.\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insCount = html.components(separatedBy: "dl-ins").count - 1
    let delCount = html.components(separatedBy: "dl-del").count - 1
    #expect(insCount == 0, "No lines were inserted")
    #expect(delCount == 1, "Only the removed line should be deleted")
  }

  // MARK: - Code block word marker correctness

  @Test func codeBlockDeletionLinesHaveNoInsMarkers() {
    // Code block where the changed content line maps to the same
    // doc line in both old and new (triggers word data key
    // collision if del/ins share a map).
    let old = "```\nalpha\nbeta gamma\n```\n"
    let new = "```\nalpha\nBETA gamma\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let delDivs = html.components(separatedBy: "</div>")
      .filter { $0.contains("dl-del") }
    #expect(!delDivs.isEmpty, "Should have deletion lines")
    for div in delDivs {
      #expect(!div.contains("<ins>"),
        "Deletion lines must not contain <ins> markers")
    }
  }

  @Test func codeBlockInsertionLinesHaveNoDelMarkers() {
    let old = "```\nalpha\nbeta gamma\n```\n"
    let new = "```\nalpha\nBETA gamma\n```\n"
    var opts = RenderOptions()
    opts.waypoint = ParsedMarkdown(old)
    let html = MudCore.renderDownToHTML(new, options: opts)
    let insDivs = html.components(separatedBy: "</div>")
      .filter { $0.contains("dl-ins") }
    #expect(!insDivs.isEmpty, "Should have insertion lines")
    for div in insDivs {
      #expect(!div.contains("<del>"),
        "Insertion lines must not contain <del> markers")
    }
  }

  // MARK: - Sidebar and Down HTML change ID consistency

  @Test func sidebarAndDownHTMLChangeIDsMatch() {
    // The data-change-id values in Down mode HTML must match the
    // IDs from ChangeList for scroll-to-change to work.
    let old = ParsedMarkdown("Keep.\n\nOriginal.\n")
    let new = ParsedMarkdown("Keep.\n\nRevised.\n")
    let changes = MudCore.computeChanges(old: old, new: new)
    var opts = RenderOptions()
    opts.waypoint = old
    let html = MudCore.renderDownToHTML(new, options: opts)
    for change in changes {
      #expect(html.contains("data-change-id=\"\(change.id)\""),
        "Sidebar ID '\(change.id)' must appear in Down HTML")
    }
  }

  @Test func codeBlockSidebarAndDownHTMLChangeIDsMatch() {
    // Code block pairs get per-cluster IDs in DiffContext. The
    // Down mode HTML must use the same IDs.
    let old = ParsedMarkdown("```\nkeep\nold\n```\n")
    let new = ParsedMarkdown("```\nkeep\nnew\n```\n")
    let changes = MudCore.computeChanges(old: old, new: new)
    var opts = RenderOptions()
    opts.waypoint = old
    let html = MudCore.renderDownToHTML(new, options: opts)
    for change in changes {
      #expect(html.contains("data-change-id=\"\(change.id)\""),
        "Code block sidebar ID '\(change.id)' must appear in Down HTML")
    }
  }
}
