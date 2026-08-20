import Foundation
import Testing

@testable import MudCore

/// The anchoring contract, pinned: a comment anchors byte-exactly only when the
/// block text the JS locator computes from the rendered DOM (`endLocator` in
/// `mud-comments-edit.js`, via `Mud.commentAnchor.segmentAt`) equals the text
/// `CommentAnchor` computes from the cmark AST (`inlineText(of:)`, folded and
/// collapsed).
///
/// The JS cannot run here, so `logicalBlocks(_:)` below re-implements the shared
/// walker in `mud-comment-anchor.js` (`eachLogicalBlock`): every innermost leaf
/// block, plus every inline *segment* of a tight list item that also holds a
/// nested list — the shape issue #5 turned on — with the same exclusions
/// (`<pre>`, `.mermaid`, `.mud-html-block`, `.mud-change-del`, and the bottom
/// sections). This driver is the pinned mirror of those JS rules; the two sides
/// name each other. Each enumerated logical block must resolve through the
/// public `CommentAnchor.insertionOffset`, whose block-matching step *is* the
/// required equality. A corpus block that stops anchoring here would surface in
/// the app as a comment whose marker falls back to the block end or the
/// quotation-search path.
@Suite("CommentAnchor parity with the JS extraction")
struct CommentAnchorParityTests {

  // MARK: - Tests, over ParityCorpus

  @Test func paragraphsWithInlineSyntaxAnchor() {
    #expect(failingBlocks(ParityCorpus.paragraphsWithInlineSyntax.markdown).isEmpty)
  }

  @Test func hardBreakParagraphAnchors() {
    #expect(failingBlocks(ParityCorpus.hardBreakParagraph.markdown).isEmpty)
  }

  @Test func headingsAnchor() {
    #expect(failingBlocks(ParityCorpus.headings.markdown).isEmpty)
  }

  @Test func listItemsAnchor() {
    // The `listItems` corpus already holds a tight parent of a nested list
    // ("Second tight item with **bold**"). The old innermost-only driver never
    // exercised that parent; the logical-block driver anchors its segment,
    // covering the reported bug directly.
    #expect(failingBlocks(ParityCorpus.listItems.markdown).isEmpty)
  }

  @Test func tightNestedListsAnchor() {
    // The dedicated issue #5 corpus: two-level nesting, a multi-segment item,
    // and a duplicate sentence across the plain-paragraph and tight-segment
    // shapes.
    #expect(failingBlocks(ParityCorpus.tightNestedLists.markdown).isEmpty)
  }

  @Test func taskListItemsAnchor() {
    #expect(failingBlocks(ParityCorpus.taskListItems.markdown).isEmpty)
  }

  @Test func blockquoteParagraphsAnchor() {
    #expect(failingBlocks(ParityCorpus.blockquoteParagraphs.markdown).isEmpty)
  }

  @Test func alertBodyParagraphsAnchor() {
    // The alert title paragraph is renderer-generated (`p.alert-title`, no
    // matching source block) and is excluded below; the body paragraphs anchor
    // via CommentAnchor's in-blockquote suffix rule (the rendered body is a
    // suffix of cmark's paragraph, which still carries the title line).
    #expect(failingBlocks(ParityCorpus.alertBodyParagraphs.markdown).isEmpty)
  }

  @Test func tableCellsAnchor() {
    #expect(failingBlocks(ParityCorpus.tableCells.markdown).isEmpty)
  }

  @Test func duplicateBlocksAnchorByOccurrence() {
    // Identical-text blocks disambiguate by occurrence index; the JS counts
    // matching innermost leaves in document order, and so must Swift.
    #expect(failingBlocks(ParityCorpus.duplicateBlocks.markdown).isEmpty)
  }

  @Test func smartTypographyAnchors() {
    // Smart typography is exactly what CommentAnchor.fold() exists to undo:
    // curly quotes/dashes/ellipsis in the rendered DOM must still resolve
    // back to their straight ASCII source.
    #expect(failingBlocks(ParityCorpus.smartTypography.markdown).isEmpty)
  }

  @Test func footnoteReferenceInBlockAnchors() {
    // A paragraph carrying an authorial footnote reference: the shared skip rule
    // (mud-comment-anchor.js, matched by CommentAnchor) drops the reference's
    // superscript from the block text, so the block still anchors byte-exactly.
    // Before Slice 5 the read-side JS included the superscript and missed
    // (Phase 3e); this pins the Swift half of that contract.
    let markdown = """
      A paragraph with a footnote[^n] partway through the sentence.

      [^n]: The note body.
      """
    #expect(failingBlocks(markdown).isEmpty)
  }

  @Test func inlineMathParagraphsAnchor() {
    // A paragraph with inline `` $`…`$ `` math: the rendered DOM omits the
    // MathML subtree (skipped wholesale) and the bounding `$` delimiters
    // (stripped by the visitor), and CommentAnchor's inlineText/resolveByte
    // subtract the same three pieces — so prose selections in the paragraph
    // still match their block and anchor.
    let markdown = """
      The area $`\\pi r^2`$ is well known.

      Math at the start: $`a`$ then prose, and at the end $`b`$
      """
    #expect(failingBlocks(markdown).isEmpty)
  }

  // MARK: - Tests, over a change-tracked document

  /// One rewording of each shape that takes word-level change spans: a heading,
  /// a paragraph, a tight list item that also holds a nested list, and a
  /// multi-word table cell. Rendered against `changedBefore` with inline
  /// deletions on, every one of them carries the removed words in a bare
  /// `<del>` — text that is in the DOM and not in the source.
  private static let changedBefore = """
    # The Quarterly Notes

    The report covers March results.

    - Ship the beta build.
      - A nested detail.

    | Column | Status                 |
    | ------ | ---------------------- |
    | Build  | Now amber and slipping |
    """

  private static let changedAfter = """
    # The Monthly Notes

    The report covers April results.

    - Ship the final build.
      - A nested detail.

    | Column | Status                 |
    | ------ | ---------------------- |
    | Build  | Now green and shipping |
    """

  private static var inlineDeletionOptions: RenderOptions {
    var options = RenderOptions()
    options.waypoint = ParsedMarkdown(changedBefore)
    options.showInlineDeletions = true
    return options
  }

  @Test func changedBlocksWithInlineDeletionsAnchor() {
    let options = Self.inlineDeletionOptions
    // The fixture only says anything while it renders inline deletions.
    #expect(
      MudCore.renderUpToHTML(Self.changedAfter, options: options)
        .contains("<del>"))
    #expect(failingBlocks(Self.changedAfter, options: options).isEmpty)
  }

  @Test func inlineDeletionsContributeNoBlockText() {
    // The removed words are in the rendered DOM and not in the source, so a
    // block's text has to be the surviving text alone. Counting them made the
    // page post a block the file doesn't contain ("covers MarchApril results"),
    // which matched no cmark leaf and failed every comment on that block.
    let texts = blockTexts(Self.changedAfter, options: Self.inlineDeletionOptions)
    #expect(texts.contains("The report covers April results."))
    #expect(texts.contains("Now green and shipping"))
    #expect(texts.contains("The Monthly Notes"))
    // The tight item's inline run is still one segment: a mid-run `<del>`
    // contributes no text and must not break the run either.
    #expect(texts.contains("Ship the final build."))
    #expect(
      !texts.contains {
        $0.contains("Quarterly") || $0.contains("March") || $0.contains("beta")
          || $0.contains("amber")
      })
  }

  @Test func endInsideAnInlineDeletionAnchorsBeforeIt() {
    // A selection ending inside a removed word: the JS half (`anchorableEnd`)
    // walks back to the last surviving text before it — "The report covers",
    // trailing space trimmed — and the locator posts the block's marker-free
    // text with that offset. This pins the Swift half: the offset resolves to
    // the byte just after "covers", so the marker lands there.
    let source = Self.changedAfter
    let blockText = "The report covers April results."
    let surviving = "The report covers"
    let expected = source.utf8.distance(
      from: source.utf8.startIndex, to: source.range(of: surviving)!.upperBound)
    #expect(
      CommentAnchor.insertionOffset(
        in: source, blockText: blockText, offsetInBlock: surviving.count)
        == expected)
  }

  // MARK: - Driver

  /// Renders `markdown`, enumerates every logical block the way the JS locator
  /// does (`logicalBlocks`), and returns the (normalized) texts of blocks that
  /// fail to anchor. `<pre>`, `.mermaid`, `.mud-html-block`, and
  /// `.mud-change-del` are excluded inside the walker (no source byte to match);
  /// `p.alert-title` is renderer-generated (no matching source block) and is
  /// dropped here without counting, its unique text never colliding with a real
  /// block's occurrence.
  private func failingBlocks(
    _ markdown: String, options: RenderOptions = .init()
  ) -> [String] {
    let html = MudCore.renderUpToHTML(markdown, options: options)
    let root = parseHTML(html)
    var failures: [String] = []
    var seen: [String: Int] = [:]  // normalized text → occurrences so far
    for block in logicalBlocks(root) {
      if block.element.classes.contains("alert-title") { continue }
      // endLocator's whitespace rules: leading whitespace is dropped from the
      // block text, and the end offset backs over trailing whitespace.
      let text = String(block.text.drop(while: { $0.isWhitespace }))
      let normalized = normalizeWS(text)
      if normalized.isEmpty { continue }
      let occurrence = seen[normalized, default: 0]
      seen[normalized] = occurrence + 1
      var trimmed = text
      while let last = trimmed.last, last.isWhitespace { trimmed.removeLast() }
      if CommentAnchor.insertionOffset(
        in: markdown, blockText: text, offsetInBlock: trimmed.count,
        occurrenceIndex: occurrence) == nil
      {
        failures.append(normalized)
      }
    }
    return failures
  }

  /// The normalized text of every logical block, in document order: the strings
  /// the page would post as `blockText`. Same walk as `failingBlocks`, without
  /// the anchoring step, so a test can name the text it expects.
  private func blockTexts(
    _ markdown: String, options: RenderOptions = .init()
  ) -> [String] {
    logicalBlocks(parseHTML(MudCore.renderUpToHTML(markdown, options: options)))
      .filter { !$0.element.classes.contains("alert-title") }
      .map { normalizeWS($0.text) }
      .filter { !$0.isEmpty }
  }

  // MARK: - The JS DOM rules, re-implemented over rendered HTML

  /// `LEAF_BLOCK_TAGS` from `mud-comments.js` / `mud-comments-edit.js`.
  private static let leafTags: Set<String> = [
    "p", "li", "td", "th", "h1", "h2", "h3", "h4", "h5", "h6",
    "blockquote", "pre", "dd", "dt", "figcaption", "caption", "summary",
  ]

  /// `isMarkerElement` from `mud-comment-anchor.js`: elements whose text the
  /// locator skips (comment markers and footnote reference numbers).
  private static let markerClasses: Set<String> = [
    "mud-comment-marker", "footnote-ref",
  ]

  /// The other half of `isMarkerElement`: an inline `<del>`, the words a
  /// tracked change removed. It is a tag rather than a class, so it sits beside
  /// `markerClasses` instead of in it.
  private static let markerTag = "del"

  private final class Node {
    let tag: String  // "" for a text node
    let classes: Set<String>
    var children: [Node] = []
    var text: String = ""

    init(tag: String, classes: Set<String> = []) {
      self.tag = tag
      self.classes = classes
    }
  }

  /// The tags/classes the walker skips wholesale (no source byte to anchor):
  /// mirrors `isSkippedSubtree` in `mud-comment-anchor.js`. The lowercase
  /// `"math"` matches the JS's `localName` check — a MathML element's
  /// `tagName` never uppercases (it is not an HTML-namespace element).
  private func isSkippedSubtree(_ node: Node) -> Bool {
    node.tag == "pre" || node.tag == "math"
      || node.classes.contains("mermaid")
      || node.classes.contains("mud-html-block")
      || node.classes.contains("mud-change-del")
      || node.classes.contains("mud-math-block")
      || node.classes.contains("temml-error")
  }

  private func isBottomSection(_ node: Node) -> Bool {
    node.classes.contains("footnotes") || node.classes.contains("comments")
  }

  private func hasLeafDescendant(_ node: Node) -> Bool {
    node.children.contains { child in
      !child.tag.isEmpty
        && (Self.leafTags.contains(child.tag) || hasLeafDescendant(child))
    }
  }

  /// A child of a leaf block that breaks an inline run: a nested leaf block, an
  /// element holding one, or a skipped subtree. Mirrors `breaksSegment`.
  private func breaksSegment(_ node: Node) -> Bool {
    if node.tag.isEmpty { return false }
    if isSkippedSubtree(node) { return true }
    return Self.leafTags.contains(node.tag) || hasLeafDescendant(node)
  }

  /// A logical block: a whole innermost leaf, or one inline segment of a leaf
  /// block that also holds nested leaf blocks. `text` is its marker-free text;
  /// `element` is the enclosing leaf element (kept only to drop the generated
  /// `p.alert-title`). Occurrence is recounted by text in `failingBlocks`, so no
  /// child range is retained here.
  private struct LogicalBlock {
    let element: Node
    let text: String
  }

  /// The marker-free text of `element`'s children in [start, end), skipping
  /// marker elements and skipped subtrees. Mirrors `rangeText` / `markerFreeText`.
  private func markerFreeText(_ node: Node) -> String {
    if node.tag.isEmpty { return node.text }
    if node.tag == Self.markerTag { return "" }
    if !node.classes.isDisjoint(with: Self.markerClasses) { return "" }
    if isSkippedSubtree(node) { return "" }
    return node.children.map(markerFreeText).joined()
  }

  private func rangeText(_ element: Node, _ start: Int, _ end: Int) -> String {
    (start..<end).map { markerFreeText(element.children[$0]) }.joined()
  }

  /// Every logical block under `root` in document order — the Swift mirror of
  /// `eachLogicalBlock` in `mud-comment-anchor.js`.
  private func logicalBlocks(_ root: Node) -> [LogicalBlock] {
    var out: [LogicalBlock] = []

    func walk(_ node: Node, inLeaf: Bool) {
      let kids = node.children
      var runStart = -1
      var i = 0
      while i <= kids.count {
        let child = i < kids.count ? kids[i] : nil
        let isBreak = child == nil || breaksSegment(child!) || isBottomSection(child!)
        if !isBreak {
          if runStart < 0 { runStart = i }
          i += 1
          continue
        }
        // Close the pending inline run: a segment, if we're in a leaf block.
        if inLeaf, runStart >= 0 {
          let text = rangeText(node, runStart, i)
          if !normalizeWS(text).isEmpty {
            out.append(LogicalBlock(element: node, text: text))
          }
        }
        runStart = -1
        if let child, !isSkippedSubtree(child), !isBottomSection(child) {
          if Self.leafTags.contains(child.tag) {
            if hasLeafDescendant(child) {
              walk(child, inLeaf: true)   // leaf block with nested leaf blocks
            } else {
              out.append(LogicalBlock(
                element: child,
                text: rangeText(child, 0, child.children.count)))
            }
          } else {
            walk(child, inLeaf: false)    // plain container
          }
        }
        i += 1
      }
    }

    walk(root, inLeaf: false)
    return out
  }

  /// JS `normalizeWS(s).trim()`.
  private func normalizeWS(_ s: String) -> String {
    s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
  }

  // MARK: - Minimal HTML parsing (our own renderer's regular output)

  /// Void elements the renderer emits without closing tags.
  private static let voidTags: Set<String> = [
    "br", "hr", "img", "input", "path", "circle", "rect", "line",
    "polyline", "polygon", "use",
  ]

  private func parseHTML(_ html: String) -> Node {
    let root = Node(tag: "#root")
    var stack = [root]
    let chars = Array(html)
    var i = 0
    while i < chars.count {
      if chars[i] == "<" {
        if i + 1 < chars.count, chars[i + 1] == "!" {
          // Comment or doctype: skip to the closing `>`.
          while i < chars.count, chars[i] != ">" { i += 1 }
          i += 1
        } else if i + 1 < chars.count, chars[i + 1] == "/" {
          var j = i + 2
          while j < chars.count, chars[j] != ">" { j += 1 }
          if stack.count > 1 { stack.removeLast() }
          i = j + 1
        } else {
          // Opening tag: find its end, respecting quoted attribute values.
          var j = i + 1
          var quote: Character? = nil
          while j < chars.count {
            let c = chars[j]
            if let q = quote {
              if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
              quote = c
            } else if c == ">" {
              break
            }
            j += 1
          }
          let tagBody = String(chars[(i + 1)..<min(j, chars.count)])
          let name = tagBody
            .prefix(while: { !$0.isWhitespace && $0 != "/" }).lowercased()
          let node = Node(tag: name, classes: classAttr(tagBody))
          stack[stack.count - 1].children.append(node)
          if !tagBody.hasSuffix("/"), !Self.voidTags.contains(name) {
            stack.append(node)
          }
          i = j + 1
        }
      } else {
        var j = i
        while j < chars.count, chars[j] != "<" { j += 1 }
        let textNode = Node(tag: "")
        textNode.text = decodeEntities(String(chars[i..<j]))
        stack[stack.count - 1].children.append(textNode)
        i = j
      }
    }
    return root
  }

  private func classAttr(_ tagBody: String) -> Set<String> {
    guard let start = tagBody.range(of: "class=\"") else { return [] }
    let rest = tagBody[start.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return [] }
    return Set(rest[..<end].split(separator: " ").map(String.init))
  }

  private func decodeEntities(_ s: String) -> String {
    guard s.contains("&") else { return s }
    var out = ""
    var i = s.startIndex
    while i < s.endIndex {
      if s[i] == "&", let semi = s[i...].firstIndex(of: ";") {
        let entity = String(s[s.index(after: i)..<semi])
        let decoded: String?
        switch entity {
        case "amp": decoded = "&"
        case "lt": decoded = "<"
        case "gt": decoded = ">"
        case "quot": decoded = "\""
        case "#39", "apos": decoded = "'"
        default:
          if entity.hasPrefix("#"), let v = UInt32(entity.dropFirst()),
            let scalar = Unicode.Scalar(v)
          {
            decoded = String(Character(scalar))
          } else {
            decoded = nil
          }
        }
        if let decoded {
          out += decoded
          i = s.index(after: semi)
          continue
        }
      }
      out.append(s[i])
      i = s.index(after: i)
    }
    return out
  }
}
