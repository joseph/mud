import Testing
@testable import MudCore

@Suite("FootnoteProcessor")
struct FootnoteProcessorTests {

  // MARK: - Fast path

  @Test func noFootnoteSyntaxReturnsInputUnchanged() {
    let md = "# Title\n\nA paragraph with no footnotes at all.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.transformedMarkdown == md)
    #expect(result.footnotes.isEmpty)
  }

  // MARK: - Basic reference + definition

  @Test func basicReferenceBecomesMarkerAndDefinitionIsRemoved() {
    let md = "A sentence.[^1]\n\n[^1]: The first footnote.\n"
    let result = FootnoteProcessor.process(md, mode: .section)

    #expect(result.transformedMarkdown.contains("class=\"footnote-ref\""))
    #expect(result.transformedMarkdown.contains("data-fn-num=\"1\""))
    #expect(result.transformedMarkdown.contains("data-fn-label=\"1\""))
    // The definition line is gone (no literal "[^1]:" survives).
    #expect(!result.transformedMarkdown.contains("[^1]:"))

    #expect(result.footnotes.count == 1)
    #expect(result.footnotes[0].label == "1")
    #expect(result.footnotes[0].number == 1)
    #expect(result.footnotes[0].bodyMarkdown.contains("The first footnote."))
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

  @Test func danglingReferenceSurvivesAsLiteral() {
    let md = "A reference with no definition.[^missing]\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.transformedMarkdown.contains("[^missing]"))
    #expect(!result.transformedMarkdown.contains("footnote-ref"))
    #expect(result.footnotes.isEmpty)
  }

  // MARK: - Orphan definition

  @Test func orphanDefinitionIsRemoved() {
    let md = """
    A paragraph.

    [^orphan]: This is never referenced.

    Another paragraph.
    """
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(!result.transformedMarkdown.contains("[^orphan]"))
    #expect(!result.transformedMarkdown.contains("This is never referenced."))
    #expect(result.transformedMarkdown.contains("A paragraph."))
    #expect(result.transformedMarkdown.contains("Another paragraph."))
    #expect(result.footnotes.isEmpty)
  }

  // MARK: - Constructs that should NOT be footnotes

  @Test func referenceInsideCodeSpanIsNotAFootnote() {
    let md = "Inline `[^1]` code only.\n\n[^1]: orphaned by the code span.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(!result.transformedMarkdown.contains("footnote-ref"))
    #expect(result.footnotes.isEmpty)
  }

  @Test func referenceInsideFencedBlockIsNotAFootnote() {
    let md = "```\n[^1]\n[^1]: inside a fence\n```\n\nText after.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(!result.transformedMarkdown.contains("footnote-ref"))
    // The fenced content is untouched.
    #expect(result.transformedMarkdown.contains("[^1]: inside a fence"))
    #expect(result.footnotes.isEmpty)
  }

  @Test func escapedReferenceIsNotAFootnote() {
    let md = "Escaped \\[^1\\] reference.\n\n[^1]: would-be body.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(!result.transformedMarkdown.contains("footnote-ref"))
    #expect(result.footnotes.isEmpty)
  }

  @Test func emptyLabelIsNotAFootnote() {
    let md = "An empty label [^] here.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(!result.transformedMarkdown.contains("footnote-ref"))
    #expect(result.footnotes.isEmpty)
  }

  @Test func whitespaceLabelIsNotAFootnote() {
    let md = "A label with a space [^foo bar].\n\n[^foo bar]: nope.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(!result.transformedMarkdown.contains("footnote-ref"))
    #expect(result.footnotes.isEmpty)
  }

  // MARK: - Multibyte safety (sourcepos columns are byte offsets)

  @Test func multibyteCharBeforeReferenceReplacesExactRange() {
    let md = "café[^1] crème.\n\n[^1]: accented body.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    // The accented text on both sides of the marker is preserved, and the
    // marker replaces exactly the `[^1]` token (no stray brackets remain).
    #expect(result.transformedMarkdown.contains("café<sup class=\"footnote-ref\""))
    #expect(result.transformedMarkdown.contains("crème."))
    #expect(!result.transformedMarkdown.contains("[^1]"))
  }

  // MARK: - Multiple references to one definition

  @Test func repeatedReferencesShareNumberAndGetDistinctBackrefIDs() {
    let md = "First.[^r] Second.[^r] Third.[^r]\n\n[^r]: shared body.\n"
    let result = FootnoteProcessor.process(md, mode: .section)
    #expect(result.footnotes.count == 1)
    #expect(result.footnotes[0].number == 1)
    // First occurrence id="fnref-1"; later occurrences id="fnref-1-2", "-3".
    #expect(result.transformedMarkdown.contains("id=\"fnref-1\""))
    #expect(result.transformedMarkdown.contains("id=\"fnref-1-2\""))
    #expect(result.transformedMarkdown.contains("id=\"fnref-1-3\""))
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
}
