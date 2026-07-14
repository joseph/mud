import Testing

@testable import MudCore

/// Pins the word-span cursor machine extracted from `CMarkUpHTMLVisitor`
/// (Phase 3f). The emitter's contract with the visitor: the character
/// stream fed through `advance` is exactly `WordDiff.inlineText(of:)`
/// for the block, consuming spans concatenate to that same text, and
/// consecutive same-type spans merge into a single `<ins>`/`<del>` tag.
@Suite("WordSpanEmitter")
struct WordSpanEmitterTests {

  // Spans for "The quick fox." → "The brown fox." (one substitution):
  // [unchanged("The"), unchanged(" "), deleted("quick"),
  //  inserted("brown"), unchanged(" "), unchanged("fox.")]
  private var substitutionSpans: [WordSpan] {
    WordDiff.diff(old: "The quick fox.", new: "The brown fox.")
  }

  // MARK: - Roles

  @Test func insertionRoleEmitsGroupedMarkers() {
    var emitter = WordSpanEmitter(
      spans: substitutionSpans, role: .insertion, showInlineDeletions: true)
    var out = emitter.advance(by: "The brown fox.".count, emit: true)
    out += emitter.finish()
    #expect(out == "The <del>quick</del><ins>brown</ins> fox.")
  }

  @Test func insertionRoleSkipsDeletionsWhenHidden() {
    var emitter = WordSpanEmitter(
      spans: substitutionSpans, role: .insertion, showInlineDeletions: false)
    var out = emitter.advance(by: "The brown fox.".count, emit: true)
    out += emitter.finish()
    #expect(out == "The <ins>brown</ins> fox.")
  }

  @Test func deletionRoleEmitsDelAndSkipsInsertions() {
    // The red block consumes the OLD text; inserted spans are skipped
    // regardless of showInlineDeletions.
    var emitter = WordSpanEmitter(
      spans: substitutionSpans, role: .deletion, showInlineDeletions: false)
    var out = emitter.advance(by: "The quick fox.".count, emit: true)
    out += emitter.finish()
    #expect(out == "The <del>quick</del> fox.")
  }

  // MARK: - The visitor's feeding pattern

  @Test func spansSplitAcrossInlineNodeBoundaries() {
    // For `re*mark*able` the visitor feeds one advance per Text node
    // ("re", "mark", "able") and closes the open tag at each boundary
    // so a marker never spans the visitor's own <em> tags. A span
    // straddling the boundary is split and resumes at the next call.
    let spans = WordDiff.diff(old: "notable", new: "remarkable")
    var emitter = WordSpanEmitter(
      spans: spans, role: .insertion, showInlineDeletions: false)
    var pieces: [String] = []
    for count in [2, 4, 4] {
      var out = emitter.advance(by: count, emit: true)
      out += emitter.closeOpenTag()
      pieces.append(out)
    }
    #expect(pieces == ["<ins>re</ins>", "<ins>mark</ins>", "<ins>able</ins>"])
  }

  @Test func breaksConsumeSilently() {
    // A SoftBreak consumes its one character with emit: false — the
    // visitor's own "\n" provides the whitespace. Spans for
    // "alpha beta" → "alpha gamma", fed as Text / SoftBreak / Text.
    let spans = WordDiff.diff(old: "alpha beta", new: "alpha gamma")
    var emitter = WordSpanEmitter(
      spans: spans, role: .insertion, showInlineDeletions: false)
    var pieces: [String] = []
    var out = emitter.advance(by: 5, emit: true)
    out += emitter.closeOpenTag()
    pieces.append(out)
    out = emitter.advance(by: 1, emit: false)
    out += emitter.closeOpenTag()
    pieces.append(out)
    out = emitter.advance(by: 5, emit: true)
    out += emitter.closeOpenTag()
    pieces.append(out)
    #expect(pieces == ["alpha", "", "<ins>gamma</ins>"])
  }

  @Test func finishFlushesSpansAfterTheLastTextNode() {
    // A block can end with non-consuming spans still pending (e.g. no
    // text survives into the new block): finish emits what remains.
    let spans: [WordSpan] = [.deleted("Bye")]
    var shown = WordSpanEmitter(
      spans: spans, role: .insertion, showInlineDeletions: true)
    #expect(shown.finish() == "<del>Bye</del>")
    var hidden = WordSpanEmitter(
      spans: spans, role: .insertion, showInlineDeletions: false)
    #expect(hidden.finish() == "")
  }

  // MARK: - Aside prefix skipping

  @Test func skipPrefixConsumesSilentlyAndSkipsNonConsumingSpans() {
    // The Aside parser strips the "Note: " prefix from the rendered
    // content but the spans still carry it; skipPrefix drops it
    // without emitting, and non-consuming spans inside the prefix
    // never surface (no <del> before the alert title).
    let spans: [WordSpan] = [
      .deleted("Old"), .unchanged("Note:"), .unchanged(" "),
      .inserted("new"), .unchanged(" "), .unchanged("body"),
    ]
    var emitter = WordSpanEmitter(
      spans: spans, role: .insertion, showInlineDeletions: true)
    emitter.skipPrefix(charCount: "Note: ".count)
    var out = emitter.advance(by: "new body".count, emit: true)
    out += emitter.finish()
    #expect(out == "<ins>new</ins> body")
  }

  @Test func skipPrefixSplitsASpanMidway() {
    let spans: [WordSpan] = [.unchanged("Note: body")]
    var emitter = WordSpanEmitter(
      spans: spans, role: .insertion, showInlineDeletions: false)
    emitter.skipPrefix(charCount: "Note: ".count)
    var out = emitter.advance(by: "body".count, emit: true)
    out += emitter.finish()
    #expect(out == "body")
  }

  // MARK: - Emission escaping

  @Test func escapesAndSubstitutesShortcodesAtEmission() {
    // Span text is raw source text; HTML escaping and emoji shortcode
    // substitution happen at emission, exactly like the visitor's
    // plain-text path. (Substitution never shifts the cursor — counts
    // are in pre-substitution characters on both sides.)
    let spans: [WordSpan] = [.inserted("a<b & :tada:")]
    var emitter = WordSpanEmitter(
      spans: spans, role: .insertion, showInlineDeletions: false)
    var out = emitter.advance(by: "a<b & :tada:".count, emit: true)
    out += emitter.finish()
    #expect(out == "<ins>a&lt;b &amp; 🎉</ins>")
  }

  // MARK: - Alignment with WordDiff.inlineText

  @Test func consumingSpansReproduceInlineTextExactly() throws {
    // The emitter's cursor arithmetic assumes the visitor's character
    // stream equals the concatenation of consuming spans. Both hold
    // by construction — the diff is computed between the two blocks'
    // `inlineText` — so for any pair: non-deleted spans join to the
    // new text (blue block) and non-inserted spans join to the old
    // text (red block). Formatting, inline code, emoji shortcodes,
    // and soft breaks all participate.
    let oldSource = "The quick brown fox jumped over the `lazy` dog\n"
      + "across :tada: **two** long lines."
    let newSource = "The slow brown fox leapt over the `lazy` cat\n"
      + "across :tada: **three** long lines."
    let oldDocument = try #require(ParsedMarkdown(oldSource).cmarkDocument)
    let newDocument = try #require(ParsedMarkdown(newSource).cmarkDocument)
    let oldPara = try #require(oldDocument.root.children.first)
    let newPara = try #require(newDocument.root.children.first)
    let oldText = WordDiff.inlineText(of: oldPara)
    let newText = WordDiff.inlineText(of: newPara)
    let spans = WordDiff.diff(old: oldText, new: newText)
    #expect(spans.filter { !$0.isDeleted }.map(\.text).joined() == newText)
    #expect(spans.filter { !$0.isInserted }.map(\.text).joined() == oldText)
  }
}
