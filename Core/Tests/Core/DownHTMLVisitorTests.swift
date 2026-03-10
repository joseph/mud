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

    // MARK: - Alerts

    @Test func gfmAlertNote() {
        let html = visitor.highlightAsTable("> [!NOTE]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-note"))
    }

    @Test func gfmAlertTip() {
        let html = visitor.highlightAsTable("> [!TIP]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-tip"))
    }

    @Test func gfmAlertImportant() {
        let html = visitor.highlightAsTable("> [!IMPORTANT]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-important"))
    }

    @Test func gfmAlertStatus() {
        let html = visitor.highlightAsTable("> [!STATUS]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-status"))
    }

    @Test func gfmAlertWarning() {
        let html = visitor.highlightAsTable("> [!WARNING]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-warning"))
    }

    @Test func gfmAlertCaution() {
        let html = visitor.highlightAsTable("> [!CAUTION]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-caution"))
    }

    @Test func doccAlertNote() {
        let html = visitor.highlightAsTable("> Note: Content\n")
        #expect(html.contains("md-blockquote md-alert-note"))
    }

    @Test func doccAlertWarning() {
        let html = visitor.highlightAsTable("> Warning: Be careful\n")
        #expect(html.contains("md-blockquote md-alert-warning"))
    }

    @Test func plainBlockquoteNoAlertClass() {
        let html = visitor.highlightAsTable("> Just a quote\n")
        #expect(html.contains("md-blockquote"))
        #expect(!html.contains("md-alert-"))
    }

    @Test func gfmAlertTagSpan() {
        // The [!NOTE] text is wrapped in md-alert-tag.
        let html = visitor.highlightAsTable("> [!NOTE]\n> Content\n")
        #expect(html.contains("md-alert-tag"))
    }

    @Test func doccAlertTagSpan() {
        // The "Note:" text is wrapped in md-alert-tag.
        let html = visitor.highlightAsTable("> Note: Content\n")
        #expect(html.contains("md-alert-tag"))
    }

    @Test func extendedAliasRendersAlertWhenModeExtended() {
        let html = visitor.highlightAsTable("> Remark: An observation\n", doccAlertMode: .extended)
        #expect(html.contains("md-alert-note"))
    }

    @Test func extendedAliasPlainWhenModeCommon() {
        let html = visitor.highlightAsTable("> Remark: An observation\n", doccAlertMode: .common)
        #expect(html.contains("md-blockquote"))
        #expect(!html.contains("md-alert-"))
    }

    @Test func coreAliasRendersAlertWhenModeCommon() {
        // Core DocC kinds always render as alerts in .common mode.
        let html = visitor.highlightAsTable("> Note: Content\n", doccAlertMode: .common)
        #expect(html.contains("md-alert-note"))
    }

    @Test func coreAliasPlainWhenModeOff() {
        // No DocC asides are processed in .off mode.
        let html = visitor.highlightAsTable("> Note: Content\n", doccAlertMode: .off)
        #expect(html.contains("md-blockquote"))
        #expect(!html.contains("md-alert-"))
    }

    // MARK: - Table structure

    @Test func wrappedInTable() {
        let html = visitor.highlightAsTable("hello\n")
        #expect(html.hasPrefix("<table class=\"down-lines\">"))
        #expect(html.hasSuffix("</tbody></table>"))
    }
}
