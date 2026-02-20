import Testing
@testable import MudCore

@Suite("DownHTMLVisitor")
struct DownHTMLVisitorTests {
    private let visitor = DownHTMLVisitor()

    private func lineCount(in html: String) -> Int {
        html.components(separatedBy: "<tr>").count - 1
    }

    // MARK: - Line numbers

    @Test func singleLine() {
        let html = visitor.highlightAsTable("hello\n")
        #expect(lineCount(in: html) == 1)
        #expect(html.contains("<td class=\"ln\">1</td>"))
    }

    @Test func multipleLines() {
        let html = visitor.highlightAsTable("one\ntwo\nthree\n")
        #expect(lineCount(in: html) == 3)
        #expect(html.contains("<td class=\"ln\">1</td>"))
        #expect(html.contains("<td class=\"ln\">2</td>"))
        #expect(html.contains("<td class=\"ln\">3</td>"))
    }

    @Test func emptyLinesPreserved() {
        let html = visitor.highlightAsTable("a\n\nb\n")
        #expect(lineCount(in: html) == 3)
    }

    // MARK: - Syntax span classes

    @Test func headingSpan() {
        let html = visitor.highlightAsTable("# Title\n")
        #expect(html.contains("md-heading"))
    }

    @Test func emphasisSpan() {
        let html = visitor.highlightAsTable("*em*\n")
        #expect(html.contains("md-emphasis"))
    }

    @Test func strongSpan() {
        let html = visitor.highlightAsTable("**bold**\n")
        #expect(html.contains("md-strong"))
    }

    @Test func inlineCodeSpan() {
        let html = visitor.highlightAsTable("`code`\n")
        #expect(html.contains("md-code"))
    }

    @Test func linkSpan() {
        let html = visitor.highlightAsTable("[text](url)\n")
        #expect(html.contains("md-link"))
    }

    @Test func strikethroughSpan() {
        let html = visitor.highlightAsTable("~~del~~\n")
        #expect(html.contains("md-strikethrough"))
    }

    @Test func thematicBreakSpan() {
        let html = visitor.highlightAsTable("---\n")
        #expect(html.contains("md-hr"))
    }

    // MARK: - Fenced code blocks

    @Test func fencedCodeBlockStructure() {
        let md = "```swift\nlet x = 1\n```\n"
        let html = visitor.highlightAsTable(md)
        #expect(html.contains("md-code-fence"))
        #expect(html.contains("md-code-info"))
        #expect(html.contains("md-code-block"))
    }

    @Test func fencedCodeBlockLineCount() {
        let md = "```\na\nb\n```\n"
        let html = visitor.highlightAsTable(md)
        #expect(lineCount(in: html) == 4)
    }

    // MARK: - HTML escaping

    @Test func contentIsEscaped() {
        let html = visitor.highlightAsTable("<div>\n")
        #expect(html.contains("&lt;div&gt;"))
    }

    // MARK: - Table structure

    @Test func wrappedInTable() {
        let html = visitor.highlightAsTable("hello\n")
        #expect(html.hasPrefix("<table class=\"down-lines\">"))
        #expect(html.hasSuffix("</tbody></table>"))
    }
}
