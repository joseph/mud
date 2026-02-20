import Testing
@testable import MudCore

@Suite("HeadingExtractor")
struct HeadingExtractorTests {
    @Test func singleHeading() {
        let headings = MudCore.extractHeadings("# Hello\n")
        #expect(headings.count == 1)
        #expect(headings[0].level == 1)
        #expect(headings[0].text == "Hello")
        #expect(headings[0].id == "hello")
        #expect(headings[0].sourceLine == 1)
    }

    @Test func multipleHeadingsAtDifferentLevels() {
        let md = """
        # One
        ## Two
        ### Three
        """
        let headings = MudCore.extractHeadings(md)
        #expect(headings.count == 3)
        #expect(headings[0].level == 1)
        #expect(headings[1].level == 2)
        #expect(headings[2].level == 3)
    }

    @Test func headingWithInlineCode() {
        let headings = MudCore.extractHeadings("## The `foo` method\n")
        #expect(headings.count == 1)
        #expect(headings[0].segments == [
            .plain("The "),
            .code("foo"),
            .plain(" method"),
        ])
    }

    @Test func headingWithEmphasis() {
        let headings = MudCore.extractHeadings("## An *important* note\n")
        #expect(headings.count == 1)
        // Emphasis is flattened to plain text segments.
        #expect(headings[0].segments == [
            .plain("An "),
            .plain("important"),
            .plain(" note"),
        ])
    }

    @Test func headingWithLink() {
        let headings = MudCore.extractHeadings("## See [this](url)\n")
        #expect(headings.count == 1)
        #expect(headings[0].segments == [
            .plain("See "),
            .plain("this"),
        ])
    }

    @Test func emptyDocument() {
        #expect(MudCore.extractHeadings("").isEmpty)
        #expect(MudCore.extractHeadings("No headings here.\n").isEmpty)
    }

    @Test func slugMatchesUpVisitor() {
        let md = "## Hello World\n"
        let headings = MudCore.extractHeadings(md)
        let html = MudCore.renderToHTML(md)
        #expect(html.contains("id=\"\(headings[0].id)\""))
    }
}
