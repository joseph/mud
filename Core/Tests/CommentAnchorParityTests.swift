import Foundation
import Testing

@testable import MudCore

/// The anchoring contract, pinned (Phase 3e): a comment anchors byte-exactly
/// only when the block text the JS locator computes from the rendered DOM
/// (`endLocator` in `mud-comments-edit.js`: `textContent` of the innermost
/// leaf block, marker elements skipped) equals the text `CommentAnchor`
/// computes from the cmark AST (`inlineText(of:)`, folded and collapsed).
///
/// The JS cannot run here, so these tests re-implement its extraction over the
/// rendered Up-mode HTML — the DOM rules it applies are small and fixed — and
/// assert that every extracted leaf block resolves through the public
/// `CommentAnchor.insertionOffset`, whose block-matching step *is* the
/// required equality. A corpus block that stops anchoring here would surface
/// in the app as a comment whose marker falls back to the block end or the
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
    #expect(failingBlocks(ParityCorpus.listItems.markdown).isEmpty)
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

  // MARK: - Driver

  /// Renders `markdown`, extracts every leaf block the way the JS locator
  /// does, and returns the (normalized) texts of blocks that fail to anchor.
  /// Excluded, with reasons:
  /// - `pre`: code blocks are not commentable (`commentableDraft` refuses
  ///   them) and `CommentAnchor.isLeafBlock` excludes them by design.
  /// - `p.alert-title`: renderer-generated, no matching source block.
  private func failingBlocks(
    _ markdown: String, options: RenderOptions = .init()
  ) -> [String] {
    let html = MudCore.renderUpToHTML(markdown, options: options)
    let root = parseHTML(html)
    var failures: [String] = []
    var seen: [String: Int] = [:]  // normalized text → occurrences so far
    for block in leafBlocks(root) {
      if block.tag == "pre" || block.classes.contains("alert-title") {
        continue
      }
      // endLocator's whitespace rules: leading whitespace is dropped from the
      // block text, and the end offset backs over trailing whitespace. (The
      // corpus keeps code-block text distinct from other blocks, so skipping
      // `pre` above cannot shift the occurrence counts the JS would compute.)
      let text = String(markerFreeText(block).drop(while: { $0.isWhitespace }))
      let normalized = normalizeWS(text)
      let occurrence = seen[normalized, default: 0]
      seen[normalized] = occurrence + 1
      if normalized.isEmpty { continue }
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

  // MARK: - The JS DOM rules, re-implemented over rendered HTML

  /// `LEAF_BLOCK_TAGS` from `mud-comments.js` / `mud-comments-edit.js`.
  private static let leafTags: Set<String> = [
    "p", "li", "td", "th", "h1", "h2", "h3", "h4", "h5", "h6",
    "blockquote", "pre", "dd", "dt", "figcaption", "caption", "summary",
  ]

  /// `isMarkerElement` from `mud-comments-edit.js`: elements whose text the
  /// locator skips (comment markers and footnote reference numbers).
  private static let markerClasses: Set<String> = [
    "mud-comment-marker", "footnote-ref",
  ]

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

  /// Innermost leaf blocks in document order, skipping the bottom footnotes
  /// and comments sections like the JS walk does.
  private func leafBlocks(_ node: Node) -> [Node] {
    if node.classes.contains("footnotes") || node.classes.contains("comments") {
      return []
    }
    if !node.tag.isEmpty, Self.leafTags.contains(node.tag),
      !hasLeafDescendant(node)
    {
      return [node]
    }
    return node.children.flatMap(leafBlocks)
  }

  private func hasLeafDescendant(_ node: Node) -> Bool {
    node.children.contains { child in
      !child.tag.isEmpty
        && (Self.leafTags.contains(child.tag) || hasLeafDescendant(child))
    }
  }

  /// The DOM's `textContent` with marker elements skipped.
  private func markerFreeText(_ node: Node) -> String {
    if node.tag.isEmpty { return node.text }
    if !node.classes.isDisjoint(with: Self.markerClasses) { return "" }
    return node.children.map(markerFreeText).joined()
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
