import Foundation
import Testing
@testable import MudCore

@Suite("UpHTMLVisitor")
struct UpHTMLVisitorTests {
    // MARK: - Headings

    @Test func headingWithID() {
        let html = MudCore.renderToHTML("# Hello\n")
        #expect(html.contains("<h1 id=\"hello\">Hello</h1>"))
    }

    @Test func headingLevels() {
        #expect(MudCore.renderToHTML("## Two\n").contains("<h2"))
        #expect(MudCore.renderToHTML("### Three\n").contains("<h3"))
        #expect(MudCore.renderToHTML("#### Four\n").contains("<h4"))
    }

    @Test func headingSlugFromComplexText() {
        let html = MudCore.renderToHTML("## Hello World\n")
        #expect(html.contains("id=\"hello-world\""))
    }

    // MARK: - Inline formatting

    @Test func emphasis() {
        let html = MudCore.renderToHTML("*em*\n")
        #expect(html.contains("<em>em</em>"))
    }

    @Test func strong() {
        let html = MudCore.renderToHTML("**bold**\n")
        #expect(html.contains("<strong>bold</strong>"))
    }

    @Test func strikethrough() {
        let html = MudCore.renderToHTML("~~deleted~~\n")
        #expect(html.contains("<del>deleted</del>"))
    }

    @Test func inlineCode() {
        let html = MudCore.renderToHTML("`code`\n")
        #expect(html.contains("<code>code</code>"))
    }

    @Test func inlineCodeWithSpecialChars() {
        let html = MudCore.renderToHTML("`<div>`\n")
        #expect(html.contains("<code>&lt;div&gt;</code>"))
    }

    // MARK: - Links and images

    @Test func link() {
        let html = MudCore.renderToHTML("[text](http://example.com)\n")
        #expect(html.contains("<a href=\"http://example.com\">text</a>"))
    }

    @Test func linkWithTitle() {
        let html = MudCore.renderToHTML("[text](url \"title\")\n")
        #expect(html.contains("title=\"title\""))
    }

    @Test func image() {
        let html = MudCore.renderToHTML("![alt](img.png)\n")
        #expect(html.contains("<img src=\"img.png\" alt=\"alt\" />"))
    }

    @Test func imageWithTitle() {
        let html = MudCore.renderToHTML("![alt](img.png \"title\")\n")
        #expect(html.contains("title=\"title\""))
    }

    // MARK: - Code blocks

    @Test func fencedCodeBlockWithLanguage() {
        let md = """
        ```swift
        let x = 1
        ```
        """
        let html = MudCore.renderToHTML(md)
        #expect(html.contains("class=\"language-swift\""))
    }

    @Test func fencedCodeBlockWithoutLanguage() {
        let md = """
        ```
        plain
        ```
        """
        let html = MudCore.renderToHTML(md)
        #expect(html.contains("<pre><code>"))
    }

    @Test func codeBlockEscapesHTML() {
        let md = """
        ```
        <div>&amp;</div>
        ```
        """
        let html = MudCore.renderToHTML(md)
        #expect(html.contains("&lt;div&gt;") || html.contains("hljs"))
    }

    // MARK: - Lists

    @Test func unorderedList() {
        let md = """
        - one
        - two
        """
        let html = MudCore.renderToHTML(md)
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>"))
    }

    @Test func orderedListWithStartIndex() {
        let md = """
        3. three
        4. four
        """
        let html = MudCore.renderToHTML(md)
        #expect(html.contains("<ol start=\"3\">"))
    }

    @Test func tightListNoParagraphs() {
        let md = """
        - one
        - two
        """
        let html = MudCore.renderToHTML(md)
        #expect(!html.contains("<p>"))
    }

    @Test func looseListHasParagraphs() {
        let md = "- one\n\n- two\n"
        let html = MudCore.renderToHTML(md)
        #expect(html.contains("<p>"))
    }

    @Test func taskListChecked() {
        let html = MudCore.renderToHTML("- [x] done\n")
        #expect(html.contains("checked=\"\""))
        #expect(html.contains("disabled=\"\""))
    }

    @Test func taskListUnchecked() {
        let html = MudCore.renderToHTML("- [ ] todo\n")
        #expect(html.contains("type=\"checkbox\""))
        #expect(!html.contains("checked"))
    }

    // MARK: - Blockquotes

    @Test func blockquote() {
        let html = MudCore.renderToHTML("> quoted\n")
        #expect(html.contains("<blockquote>"))
    }

    // MARK: - Tables

    @Test func table() {
        let md = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let html = MudCore.renderToHTML(md)
        #expect(html.contains("<table>"))
        #expect(html.contains("<thead>"))
        #expect(html.contains("<th>"))
        #expect(html.contains("<td>"))
    }

    @Test func tableAlignment() {
        let md = """
        | L | C | R |
        |:--|:-:|--:|
        | a | b | c |
        """
        let html = MudCore.renderToHTML(md)
        #expect(html.contains("align=\"left\""))
        #expect(html.contains("align=\"center\""))
        #expect(html.contains("align=\"right\""))
    }

    // MARK: - Other block elements

    @Test func thematicBreak() {
        let html = MudCore.renderToHTML("---\n")
        #expect(html.contains("<hr />"))
    }

    @Test func htmlPassthrough() {
        let html = MudCore.renderToHTML("<div>raw</div>\n")
        #expect(html.contains("<div>raw</div>"))
    }

    @Test func hardBreak() {
        let html = MudCore.renderToHTML("line one  \nline two\n")
        #expect(html.contains("<br />"))
    }

    // MARK: - Image source resolution

    @Test func imageSourceResolution() {
        let base = URL(fileURLWithPath: "/tmp/test.md")
        let html = MudCore.renderToHTML(
            "![](photo.png)\n",
            baseURL: base,
            resolveImageSource: { source, _ in "resolved-\(source)" }
        )
        #expect(html.contains("src=\"resolved-photo.png\""))
    }
}
