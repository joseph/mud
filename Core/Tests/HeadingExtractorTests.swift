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
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("id=\"\(headings[0].id)\""))
    }

    // MARK: - Slug deduplication and mixed segments

    @Test func deduplicatesRepeatedSlugs() {
        let md = """
        # Title
        ## Title
        ## Title
        """
        let headings = MudCore.extractHeadings(md)
        // First occurrence gets the bare slug; repeats get -1, -2, …
        #expect(headings.map(\.id) == ["title", "title-1", "title-2"])
        #expect(headings.map(\.level) == [1, 2, 2])
        #expect(headings.map(\.sourceLine) == [1, 2, 3])
    }

    @Test func mixedInlineSegmentsInOneHeading() {
        let headings = MudCore.extractHeadings("### Use `foo` for *bar* now\n")
        #expect(headings.count == 1)
        #expect(headings[0].level == 3)
        // Code spans stay `.code`; emphasis flattens to `.plain`.
        #expect(headings[0].segments == [
            .plain("Use "),
            .code("foo"),
            .plain(" for "),
            .plain("bar"),
            .plain(" now"),
        ])
        // Slug strips the backticks; `text` (plainText) keeps them.
        #expect(headings[0].id == "use-foo-for-bar-now")
        #expect(headings[0].text == "Use `foo` for bar now")
    }

    @Test func softBreakInHeadingBecomesSpaceSegment() {
        // A two-line setext heading carries a soft break between its lines.
        let headings = MudCore.extractHeadings("One\nTwo\n===\n")
        #expect(headings.count == 1)
        #expect(headings[0].level == 1)
        #expect(headings[0].segments == [
            .plain("One"),
            .plain(" "),
            .plain("Two"),
        ])
        #expect(headings[0].text == "One Two")
        #expect(headings[0].id == "one-two")
    }
}
