import Foundation
import Testing
@testable import MudCore

@Suite("UpHTMLVisitor")
struct UpHTMLVisitorTests {
    // MARK: - Headings

    @Test func headingWithID() {
        let html = MudCore.renderUpToHTML("# Hello\n")
        #expect(html.contains("<h1 id=\"hello\">Hello</h1>"))
    }

    @Test func headingLevels() {
        #expect(MudCore.renderUpToHTML("## Two\n").contains("<h2"))
        #expect(MudCore.renderUpToHTML("### Three\n").contains("<h3"))
        #expect(MudCore.renderUpToHTML("#### Four\n").contains("<h4"))
    }

    @Test func headingSlugFromComplexText() {
        let html = MudCore.renderUpToHTML("## Hello World\n")
        #expect(html.contains("id=\"hello-world\""))
    }

    // MARK: - Inline formatting

    @Test func emphasis() {
        let html = MudCore.renderUpToHTML("*em*\n")
        #expect(html.contains("<em>em</em>"))
    }

    @Test func strong() {
        let html = MudCore.renderUpToHTML("**bold**\n")
        #expect(html.contains("<strong>bold</strong>"))
    }

    @Test func strikethrough() {
        let html = MudCore.renderUpToHTML("~~deleted~~\n")
        #expect(html.contains("<del>deleted</del>"))
    }

    @Test func inlineCode() {
        let html = MudCore.renderUpToHTML("`code`\n")
        #expect(html.contains("<code>code</code>"))
    }

    @Test func inlineCodeWithSpecialChars() {
        let html = MudCore.renderUpToHTML("`<div>`\n")
        #expect(html.contains("<code>&lt;div&gt;</code>"))
    }

    // MARK: - Links and images

    @Test func link() {
        let html = MudCore.renderUpToHTML("[text](http://example.com)\n")
        #expect(html.contains("<a href=\"http://example.com\">text</a>"))
    }

    @Test func linkWithTitle() {
        let html = MudCore.renderUpToHTML("[text](url \"title\")\n")
        #expect(html.contains("title=\"title\""))
    }

    @Test func image() {
        let html = MudCore.renderUpToHTML("![alt](img.png)\n")
        #expect(html.contains("<img src=\"img.png\" alt=\"alt\" />"))
    }

    @Test func imageWithTitle() {
        let html = MudCore.renderUpToHTML("![alt](img.png \"title\")\n")
        #expect(html.contains("title=\"title\""))
    }

    // MARK: - Code blocks

    @Test func fencedCodeBlockWithLanguage() {
        let md = """
        ```swift
        let x = 1
        ```
        """
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("class=\"language-swift\""))
    }

    @Test func fencedCodeBlockWithoutLanguage() {
        let md = """
        ```
        plain
        ```
        """
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("<pre><code>"))
    }

    @Test func codeBlockEscapesHTML() {
        let md = """
        ```
        <div>&amp;</div>
        ```
        """
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("&lt;div&gt;") || html.contains("hljs"))
    }

    // MARK: - Lists

    @Test func unorderedList() {
        let md = """
        - one
        - two
        """
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("<ul>"))
        #expect(html.contains("<li>"))
    }

    @Test func orderedListWithStartIndex() {
        let md = """
        3. three
        4. four
        """
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("<ol start=\"3\">"))
    }

    @Test func tightListNoParagraphs() {
        let md = """
        - one
        - two
        """
        let html = MudCore.renderUpToHTML(md)
        #expect(!html.contains("<p>"))
    }

    @Test func looseListHasParagraphs() {
        let md = "- one\n\n- two\n"
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("<p>"))
    }

    @Test func taskListChecked() {
        let html = MudCore.renderUpToHTML("- [x] done\n")
        #expect(html.contains("checked=\"\""))
        #expect(html.contains("disabled=\"\""))
    }

    @Test func taskListUnchecked() {
        let html = MudCore.renderUpToHTML("- [ ] todo\n")
        #expect(html.contains("type=\"checkbox\""))
        #expect(!html.contains("checked"))
    }

    // MARK: - Blockquotes

    @Test func blockquote() {
        let html = MudCore.renderUpToHTML("> quoted\n")
        #expect(html.contains("<blockquote>"))
    }

    @Test func gfmAlertNote() {
        let html = MudCore.renderUpToHTML("> [!NOTE]\n> Content here\n")
        #expect(html.contains("class=\"alert alert-note\""))
        #expect(html.contains("class=\"alert-title\""))
        #expect(html.contains("Content here"))
    }

    @Test func gfmAlertInlineContent() {
        let html = MudCore.renderUpToHTML("> [!TIP] Inline content\n")
        #expect(html.contains("class=\"alert alert-tip\""))
        #expect(html.contains("Inline content"))
    }

    @Test func plainBlockquoteUnchanged() {
        let html = MudCore.renderUpToHTML("> Just a quote\n")
        #expect(html.contains("<blockquote>"))
        #expect(!html.contains("class=\"alert"))
    }

    @Test func statusAsideSingleLine() {
        let html = MudCore.renderUpToHTML("> Status: Planning\n")
        #expect(html.contains("class=\"alert alert-important\""))
        #expect(html.contains("class=\"alert-title\""))
        #expect(html.contains("Status: <strong>Planning</strong>"))
    }

    @Test func statusAsideMultiLine() {
        let md = "> Status: In Progress\n> Detail text here\n"
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("Status: <strong>In Progress</strong>"))
        #expect(html.contains("<p>Detail text here</p>"))
    }

    @Test func statusAsideMultiParagraph() {
        let md = "> Status: Complete\n>\n> Everything is done.\n"
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("Status: <strong>Complete</strong>"))
        #expect(html.contains("<p>Everything is done.</p>"))
    }

    @Test func statusWithoutValueIsPlainBlockquote() {
        let html = MudCore.renderUpToHTML("> Status:\n")
        #expect(html.contains("<blockquote>"))
        #expect(!html.contains("class=\"alert"))
    }

    // MARK: - Tables

    @Test func table() {
        let md = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let html = MudCore.renderUpToHTML(md)
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
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("align=\"left\""))
        #expect(html.contains("align=\"center\""))
        #expect(html.contains("align=\"right\""))
    }

    // MARK: - Other block elements

    @Test func thematicBreak() {
        let html = MudCore.renderUpToHTML("---\n")
        #expect(html.contains("<hr />"))
    }

    @Test func htmlPassthrough() {
        let html = MudCore.renderUpToHTML("<div>raw</div>\n")
        #expect(html.contains("<div>raw</div>"))
    }

    @Test func hardBreak() {
        let html = MudCore.renderUpToHTML("line one  \nline two\n")
        #expect(html.contains("<br />"))
    }

    // MARK: - Image source resolution

    @Test func imageSourceResolution() {
        let base = URL(fileURLWithPath: "/tmp/test.md")
        let html = MudCore.renderUpToHTML(
            "![](photo.png)\n",
            baseURL: base,
            resolveImageSource: { source, _ in "resolved-\(source)" }
        )
        #expect(html.contains("src=\"resolved-photo.png\""))
    }
}
