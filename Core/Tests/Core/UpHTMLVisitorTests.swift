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

    @Test func gfmAlertStatus() {
        let html = MudCore.renderUpToHTML("> [!STATUS]\n> Content here\n")
        #expect(html.contains("class=\"alert alert-status\""))
        #expect(html.contains("class=\"alert-title\""))
        #expect(html.contains("Content here"))
    }

    @Test func plainBlockquoteUnchanged() {
        let html = MudCore.renderUpToHTML("> Just a quote\n")
        #expect(html.contains("<blockquote>"))
        #expect(!html.contains("class=\"alert"))
    }

    @Test func statusAsideSingleLine() {
        let html = MudCore.renderUpToHTML("> Status: Planning\n")
        #expect(html.contains("class=\"alert alert-status\""))
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

    @Test func statusAsideNoSameLineValue() {
        // Value on the next line: still a Status aside, but title carries no bold.
        let html = MudCore.renderUpToHTML("> Status:\n> Complete\n")
        #expect(html.contains("class=\"alert alert-status\""))
        #expect(!html.contains(": <strong>"))
        #expect(html.contains("Complete"))
    }

    @Test func statusAsideLongValueNotInlined() {
        // Value ≥60 characters: plain "Status" title, value falls to body.
        let value = String(repeating: "x", count: 60)
        let html = MudCore.renderUpToHTML("> Status: \(value)\n")
        #expect(html.contains("class=\"alert alert-status\""))
        #expect(!html.contains("<strong>\(value)</strong>"))
        #expect(html.contains(value))
    }

    // MARK: - DocC asides

    @Test func doccAsideNoSameLineContent() {
        // No content on the tag line: title carries no bold inline.
        let html = MudCore.renderUpToHTML("> Note:\n> Body text here\n")
        #expect(html.contains("class=\"alert alert-note\""))
        #expect(html.contains("class=\"alert-title\""))
        #expect(!html.contains(": <strong>"))
        #expect(html.contains("Body text here"))
    }

    @Test func doccAsideShortSameLineInlined() {
        let html = MudCore.renderUpToHTML("> Note: Short label\n")
        #expect(html.contains("class=\"alert alert-note\""))
        #expect(html.contains("Note: <strong>Short label</strong>"))
    }

    @Test func doccAsideLongSameLineNotInlined() {
        // ≥60 characters on the tag line: falls to body, title has no bold.
        let label = String(repeating: "x", count: 60)
        let html = MudCore.renderUpToHTML("> Note: \(label)\n")
        #expect(html.contains("class=\"alert alert-note\""))
        #expect(!html.contains("<strong>"))
        #expect(html.contains(label))
    }

    @Test func doccAsideSameLineWithPeriodInlined() {
        // Terminal punctuation does not disqualify short same-line content.
        let html = MudCore.renderUpToHTML("> Note: A complete sentence.\n")
        #expect(html.contains("Note: <strong>A complete sentence.</strong>"))
    }

    @Test func doccAsideSameLineWithContinuation() {
        // Short same-line label bolded; continuation line becomes roman paragraph.
        let html = MudCore.renderUpToHTML("> Note: Short label\n> Explanatory prose below.\n")
        #expect(html.contains("Note: <strong>Short label</strong>"))
        #expect(html.contains("<p>Explanatory prose below.</p>"))
    }

    @Test func doccAsideSameLineWithSecondParagraph() {
        // Short same-line label bolded; blank-line-separated paragraph rendered below.
        let html = MudCore.renderUpToHTML("> Note: Summary\n>\n> Second paragraph.\n")
        #expect(html.contains("Note: <strong>Summary</strong>"))
        #expect(html.contains("<p>Second paragraph.</p>"))
    }

    @Test func doccAsideWarningCategory() {
        let html = MudCore.renderUpToHTML("> Warning: Be careful\n")
        #expect(html.contains("class=\"alert alert-warning\""))
        #expect(html.contains("Warning: <strong>Be careful</strong>"))
    }

    @Test func doccAsideTipCategory() {
        let html = MudCore.renderUpToHTML("> Tip: A helpful hint\n")
        #expect(html.contains("class=\"alert alert-tip\""))
        #expect(html.contains("Tip: <strong>A helpful hint</strong>"))
    }

    @Test func doccAsideToDoMapsToStatus() {
        // ToDo: must map to .status, not .note (was falling through to catch-all).
        let html = MudCore.renderUpToHTML("> ToDo: Fix this later\n")
        #expect(html.contains("class=\"alert alert-status\""))
        #expect(html.contains("To Do: <strong>Fix this later</strong>"))
    }

    @Test func doccAsideMutatingVariantMapsToNote() {
        // MutatingVariant: maps to .note; displayName is "Mutating Variant".
        let html = MudCore.renderUpToHTML("> MutatingVariant: Use sort() to sort in place\n")
        #expect(html.contains("class=\"alert alert-note\""))
        #expect(html.contains("Mutating Variant: <strong>"))
    }

    // MARK: - DocC alert mode

    @Test func coreAliasRendersWhenModeCommon() {
        // Core DocC kinds always render as styled alerts in .common mode.
        var opts = RenderOptions()
        opts.doccAlertMode = .common
        let html = MudCore.renderUpToHTML("> Note: Core note\n", options: opts)
        #expect(html.contains("class=\"alert alert-note\""))
    }

    @Test func extendedAliasPlainWhenModeCommon() {
        // Extended aliases fall back to plain blockquotes in .common mode.
        var opts = RenderOptions()
        opts.doccAlertMode = .common
        let html = MudCore.renderUpToHTML("> Remark: An observation\n", options: opts)
        #expect(html.contains("<blockquote>"))
        #expect(!html.contains("class=\"alert"))
    }

    @Test func coreAliasPlainWhenModeOff() {
        // No DocC asides are processed in .off mode.
        var opts = RenderOptions()
        opts.doccAlertMode = .off
        let html = MudCore.renderUpToHTML("> Note: Core note\n", options: opts)
        #expect(html.contains("<blockquote>"))
        #expect(!html.contains("class=\"alert"))
    }

    @Test func extendedAliasPlainWhenModeOff() {
        var opts = RenderOptions()
        opts.doccAlertMode = .off
        let html = MudCore.renderUpToHTML("> Remark: An observation\n", options: opts)
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

    // MARK: - Emoji shortcodes

    @Test func emojiShortcodeReplaced() {
        let html = MudCore.renderUpToHTML(":rocket: launch\n")
        #expect(html.contains("🚀 launch"))
    }

    @Test func unknownShortcodeLeftAsIs() {
        let html = MudCore.renderUpToHTML(":not_real: text\n")
        #expect(html.contains(":not_real: text"))
    }

    @Test func shortcodeNotReplacedInInlineCode() {
        let html = MudCore.renderUpToHTML("`:smile:`\n")
        #expect(html.contains("<code>:smile:</code>"))
    }

    @Test func shortcodeNotReplacedInCodeBlock() {
        let md = """
        ```
        :rocket:
        ```
        """
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains(":rocket:"))
        #expect(!html.contains("🚀"))
    }

    @Test func consecutiveShortcodes() {
        let html = MudCore.renderUpToHTML(":smile::+1:\n")
        #expect(html.contains("😄👍"))
    }

    @Test func shortcodeInsideStrong() {
        let html = MudCore.renderUpToHTML("**:rocket:**\n")
        #expect(html.contains("<strong>🚀</strong>"))
    }

    // MARK: - Mermaid code block fallback

    @Test func mermaidCodeBlockFallback() {
        let md = """
        ```mermaid
        graph TD
            A --> B
        ```
        """
        let html = MudCore.renderUpToHTML(md)
        #expect(html.contains("<pre><code class=\"language-mermaid\">"))
        #expect(html.contains("graph TD"))
    }

    // MARK: - Image source resolution

    @Test func imageSourceResolution() {
        let base = URL(fileURLWithPath: "/tmp/test.md")
        var opts = RenderOptions()
        opts.baseURL = base
        let html = MudCore.renderUpToHTML(
            "![](photo.png)\n",
            options: opts,
            resolveImageSource: { source, _ in "resolved-\(source)" }
        )
        #expect(html.contains("src=\"resolved-photo.png\""))
    }
}
