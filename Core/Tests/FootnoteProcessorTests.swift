import Testing
@testable import MudCore

@Suite("FootnoteProcessor")
struct FootnoteProcessorTests {

  // MARK: - Fast path

  @Test func noFootnoteSyntaxProducesNoFootnotes() {
    let md = "# Title\n\nA paragraph with no footnotes at all.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.isEmpty)
    #expect(result.comments.isEmpty)
  }

  // MARK: - Basic reference + definition

  @Test func basicReferenceIsNumberedAndRenderedAsAMarker() {
    let md = "A sentence.[^1]\n\n[^1]: The first footnote.\n"
    let result = FootnoteProcessor.process(md, mode: .section)

    // `process` classifies and numbers; it rewrites nothing.
    #expect(result.footnotes.count == 1)
    #expect(result.footnotes[0].label == "1")
    #expect(result.footnotes[0].number == 1)
    #expect(result.footnotes[0].bodyMarkdown.contains("The first footnote."))

    // The render — not `process` — emits the marker HTML.
    let body = MudCore.renderUpToHTML(md)
    #expect(body.contains("class=\"footnote-ref\""))
    #expect(body.contains("data-fn-num=\"1\""))
    #expect(body.contains("data-fn-label=\"1\""))
  }

  // MARK: - Multi-paragraph body

  @Test func multiParagraphBodyIsPreserved() {
    let md = """
    Text.[^m]

    [^m]: First paragraph.

        Second paragraph stays attached.

        Third paragraph too.
    """
    let result = FootnoteProcessor.process(md, mode: .section)

    #expect(result.footnotes.count == 1)
    let body = result.footnotes[0].bodyMarkdown
    #expect(body.contains("First paragraph."))
    #expect(body.contains("Second paragraph stays attached."))
    #expect(body.contains("Third paragraph too."))
  }

  // MARK: - Block content body

  @Test func blockContentBodyIsPreserved() {
    let md = """
    Text.[^b]

    [^b]: A footnote with a list:

        - first item
        - second item

        > and a quote.
    """
    let result = FootnoteProcessor.process(md, mode: .section)

    #expect(result.footnotes.count == 1)
    let body = result.footnotes[0].bodyMarkdown
    #expect(body.contains("first item"))
    #expect(body.contains("second item"))
    #expect(body.contains("and a quote."))
  }

  // MARK: - Dangling reference

  @Test func danglingReferenceProducesNoFootnote() {
    let md = "A reference with no definition.[^missing]\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.isEmpty)
    // No definition ⇒ cmark never makes a reference node, so the render emits
    // no marker and the text stays literal.
    let body = MudCore.renderUpToHTML(md)
    #expect(!body.contains("footnote-ref"))
    #expect(body.contains("[^missing]"))
  }

  // MARK: - Orphan definition

  @Test func orphanDefinitionProducesNoFootnote() {
    let md = """
    A paragraph.

    [^orphan]: This is never referenced.

    Another paragraph.
    """
    let result = FootnoteProcessor.process(md, mode: .section)
    // An unreferenced definition resolves to no footnote.
    #expect(result.footnotes.isEmpty)
    // The Up render draws nothing for a definition, so its body never reaches
    // the page, while the surrounding paragraphs do.
    let body = MudCore.renderUpToHTML(md)
    #expect(!body.contains("This is never referenced."))
    #expect(body.contains("A paragraph."))
    #expect(body.contains("Another paragraph."))
  }

  // MARK: - Constructs that should NOT be footnotes

  @Test func referenceInsideCodeSpanIsNotAFootnote() {
    let md = "Inline `[^1]` code only.\n\n[^1]: orphaned by the code span.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.isEmpty)
    #expect(!MudCore.renderUpToHTML(md).contains("footnote-ref"))
  }

  @Test func referenceInsideFencedBlockIsNotAFootnote() {
    let md = "```\n[^1]\n[^1]: inside a fence\n```\n\nText after.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.isEmpty)
    let body = MudCore.renderUpToHTML(md)
    #expect(!body.contains("footnote-ref"))
    // The fenced content renders verbatim as code.
    #expect(body.contains("[^1]: inside a fence"))
  }

  @Test func escapedReferenceIsNotAFootnote() {
    let md = "Escaped \\[^1\\] reference.\n\n[^1]: would-be body.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.isEmpty)
    #expect(!MudCore.renderUpToHTML(md).contains("footnote-ref"))
  }

  @Test func emptyLabelIsNotAFootnote() {
    let md = "An empty label [^] here.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.isEmpty)
    #expect(!MudCore.renderUpToHTML(md).contains("footnote-ref"))
  }

  @Test func whitespaceLabelIsNotAFootnote() {
    let md = "A label with a space [^foo bar].\n\n[^foo bar]: nope.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.isEmpty)
    #expect(!MudCore.renderUpToHTML(md).contains("footnote-ref"))
  }

  // MARK: - Multibyte safety (sourcepos columns are byte offsets)

  @Test func multibyteCharBeforeReferenceRendersMarkerInPlace() {
    let md = "café[^1] crème.\n\n[^1]: accented body.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.count == 1)
    #expect(result.footnotes[0].number == 1)

    // The accented text on both sides of the marker is preserved, and the
    // render replaces exactly the `[^1]` token (no stray brackets remain).
    let body = MudCore.renderUpToHTML(md)
    #expect(body.contains("café<sup class=\"footnote-ref\""))
    #expect(body.contains("crème."))
    #expect(!body.contains("[^1]"))
  }

  // MARK: - Multiple references to one definition

  @Test func repeatedReferencesShareNumberAndGetDistinctBackrefIDs() {
    let md = "First.[^r] Second.[^r] Third.[^r]\n\n[^r]: shared body.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.count == 1)
    #expect(result.footnotes[0].number == 1)
    // First occurrence id="fnref-1"; later occurrences id="fnref-1-2", "-3".
    let body = MudCore.renderUpToHTML(md)
    #expect(body.contains("id=\"fnref-1\""))
    #expect(body.contains("id=\"fnref-1-2\""))
    #expect(body.contains("id=\"fnref-1-3\""))
  }

  // MARK: - GFM extensions in bodies (round-trip faithfully)

  @Test func strikethroughInBodyIsPreservedUnescaped() {
    let md = "Text.[^s]\n\n[^s]: A ~~struck~~ word.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.count == 1)
    let body = result.footnotes[0].bodyMarkdown
    // The tildes survive unescaped (no `\~\~`), so the body re-parses as a real
    // strikethrough rather than literal text.
    #expect(body.contains("~~struck~~"))
    #expect(!body.contains("\\~"))
  }

  @Test func strikethroughInBodyRendersAsStrikeElement() {
    let md = "Text.[^s]\n\n[^s]: A ~~struck~~ word.\n"
    let html = MudCore.renderUpModeDocument(md)  // .section default
    #expect(html.contains("<s>struck</s>"))
  }

  @Test func tableInBodyIsPreserved() {
    let md = """
    Text.[^t]

    [^t]: A table:

        | A | B |
        | - | - |
        | 1 | 2 |
    """
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.count == 1)
    // The pipe table round-trips as Markdown (the extension renders it back as
    // a table rather than the body losing its structure).
    let body = result.footnotes[0].bodyMarkdown
    #expect(body.contains("|"))
    let html = MudCore.renderUpModeDocument(md)
    #expect(html.contains("<table>"))
  }

  // MARK: - Document-level rendering (.section default)

  @Test func sectionModeEmitsVisibleFootnotesSection() {
    let md = "A sentence.[^1]\n\n[^1]: The body.\n"
    let html = MudCore.renderUpModeDocument(md)  // .section default
    #expect(html.contains("<section class=\"footnotes\" data-footnotes>"))
    #expect(html.contains("<li id=\"fn-1\""))
    #expect(html.contains("data-footnote-ref"))
    // The section element itself must not be marked print-only (the CSS text
    // legitimately mentions `is-print-only`, so check the tag, not the string).
    #expect(!html.contains("class=\"footnotes is-print-only\""))
  }

  // MARK: - Document-level rendering (.popover)

  @Test func popoverModePopulatesFootnotesAndMarksSectionPrintOnly() {
    let md = "A sentence.[^1]\n\n[^1]: The body.\n"
    var options = RenderOptions()
    options.footnoteMode = .popover
    let document = MudCore.renderUpModeDocumentWithFootnotes(md, options: options)

    #expect(document.html.contains("data-footnote-ref"))
    #expect(document.html.contains("class=\"footnotes is-print-only\""))
    #expect(document.footnotes.count == 1)
    #expect(document.footnotes[0].label == "1")
    #expect(document.footnotes[0].number == 1)
    #expect(document.footnotes[0].html.contains("The body."))
  }

  /// A footnote popover is its own mini-document in a separate WebView; it must
  /// not inherit the host document's comments-column state, or the popover body
  /// is squished into a narrow band beside an empty 324px gutter.
  @Test func popoverDocumentOmitsCommentsColumn() {
    let md = "A sentence.[^1]\n\n[^1]: The body.\n"
    var options = RenderOptions()
    options.footnoteMode = .popover
    options.commentMode = .interactive
    options.commentsEditable = true
    options.htmlClasses.insert("is-comments-column")
    let document = MudCore.renderUpModeDocumentWithFootnotes(md, options: options)

    #expect(document.footnotes.count == 1)
    // The host document still shows the column...
    #expect(htmlOpeningTag(document.html).contains("comments-column"))
    // ...but the popover document does not (the check catches both
    // `comments-column` and `is-comments-column` on the root element).
    #expect(!htmlOpeningTag(document.footnotes[0].html).contains("comments-column"))
  }

  /// The opening `<html …>` tag, where the column classes land. The inlined CSS
  /// also mentions `comments-column`, so inspect only the root element's tag.
  private func htmlOpeningTag(_ html: String) -> Substring {
    guard let start = html.range(of: "<html"),
          let end = html[start.lowerBound...].firstIndex(of: ">")
    else { return "" }
    return html[start.lowerBound...end]
  }
}
