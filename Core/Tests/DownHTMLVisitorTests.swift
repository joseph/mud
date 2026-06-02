import Testing
@testable import MudCore

@Suite("DownHTMLVisitor")
struct DownHTMLVisitorTests {
    private let visitor = DownHTMLVisitor()

    private func lineCount(in html: String) -> Int {
        html.components(separatedBy: "class=\"dl").count - 1
    }

    // MARK: - Line numbers

    @Test func singleLine() {
        let html = visitor.highlight("hello\n")
        #expect(lineCount(in: html) == 1)
        #expect(html.contains("<span class=\"ln\">1</span>"))
    }

    @Test func multipleLines() {
        let html = visitor.highlight("one\ntwo\nthree\n")
        #expect(lineCount(in: html) == 3)
        #expect(html.contains("<span class=\"ln\">1</span>"))
        #expect(html.contains("<span class=\"ln\">2</span>"))
        #expect(html.contains("<span class=\"ln\">3</span>"))
    }

    @Test func emptyLinesPreserved() {
        let html = visitor.highlight("a\n\nb\n")
        #expect(lineCount(in: html) == 3)
    }

    // MARK: - Syntax span classes

    @Test func headingSpan() {
        let html = visitor.highlight("# Title\n")
        #expect(html.contains("md-heading"))
    }

    @Test func emphasisSpan() {
        let html = visitor.highlight("*em*\n")
        #expect(html.contains("md-emphasis"))
    }

    @Test func strongSpan() {
        let html = visitor.highlight("**bold**\n")
        #expect(html.contains("md-strong"))
    }

    @Test func strongInsideStrikethroughCoversFullRange() {
        let html = visitor.highlight("~~**JS + WebView** done~~\n")
        let lc = html.components(separatedBy: "<span class=\"lc\">")
            .last?.components(separatedBy: "</span></div>").first ?? ""
        let strongOpen = lc.range(of: "<span class=\"md-strong\">")
        let strongClose = lc.range(of: "</span>",
            range: (strongOpen?.upperBound ?? lc.startIndex)..<lc.endIndex)
        #expect(strongOpen != nil, "md-strong span must exist")
        if let open = strongOpen, let close = strongClose {
            let inside = String(lc[open.upperBound..<close.lowerBound])
            #expect(inside.contains("WebView"),
                "WebView must be inside md-strong span, got: \(inside)")
        }
    }

    @Test func strongInMultiLineStrikethroughListItem() {
        // cmark-gfm reports incorrect ranges for multi-line
        // strikethrough — the child's close position fix ensures
        // the parent span covers all content.
        let md = "8. ~~**JS + WebView** — wire to sidebar\n   selection.~~\n"
        let html = visitor.highlight(md)
        let lines = html.components(separatedBy: "</div>")
            .filter { $0.contains("class=\"dl") }
        let line1 = lines.first ?? ""
        let lc = line1.components(separatedBy: "<span class=\"lc\">")
            .last ?? ""
        let strongOpen = lc.range(of: "<span class=\"md-strong\">")
        let strongClose = lc.range(of: "</span>",
            range: (strongOpen?.upperBound ?? lc.startIndex)..<lc.endIndex)
        #expect(strongOpen != nil, "md-strong span must exist on line 1")
        if let open = strongOpen, let close = strongClose {
            let inside = String(lc[open.upperBound..<close.lowerBound])
            #expect(inside.contains("WebView"),
                "WebView must be inside md-strong, got: \(inside)")
        }
    }

    @Test func inlineCodeSpan() {
        let html = visitor.highlight("`code`\n")
        #expect(html.contains("md-code"))
    }

    @Test func linkSpan() {
        let html = visitor.highlight("[text](url)\n")
        #expect(html.contains("md-link"))
    }

    @Test func strikethroughSpan() {
        let html = visitor.highlight("~~del~~\n")
        #expect(html.contains("md-strikethrough"))
    }

    @Test func thematicBreakSpan() {
        let html = visitor.highlight("---\n")
        #expect(html.contains("md-hr"))
    }

    // MARK: - Fenced code blocks

    @Test func fencedCodeBlockStructure() {
        let md = "```swift\nlet x = 1\n```\n"
        let html = visitor.highlight(md)
        #expect(html.contains("md-code-fence"))
        #expect(html.contains("md-code-info"))
        #expect(html.contains("md-code-block"))
    }

    @Test func fencedCodeBlockLineCount() {
        let md = "```\na\nb\n```\n"
        let html = visitor.highlight(md)
        #expect(lineCount(in: html) == 4)
    }

    @Test func fencedCodeBlockLayout() {
        let md = "```\nfoo\nbar\n```\n"
        let html = visitor.highlight(md)
        // Opening fence gets dc-fence class.
        #expect(html.contains("class=\"dl dc-fence\""))
        // Content lines are wrapped in dc-scroll.
        #expect(html.contains("<div class=\"dc-scroll\">"))
        // Content lines get dc-code class.
        #expect(html.contains("class=\"dl dc-code\""))
    }

    @Test func emptyFencedCodeBlockLayout() {
        let md = "```\n```\n"
        let html = visitor.highlight(md)
        // Two fence lines inside a dc-scroll wrapper, no dc-code.
        #expect(html.contains("class=\"dl dc-fence\""))
        #expect(html.contains("dc-scroll"))
        #expect(!html.contains("dc-code"))
    }

    @Test func indentedCodeBlockLayout() {
        let md = "    indented\n    code\n"
        let html = visitor.highlight(md)
        // Wrapped in dc-scroll with dc-code lines, no dc-fence.
        #expect(html.contains("<div class=\"dc-scroll\">"))
        #expect(html.contains("class=\"dl dc-code\""))
        #expect(!html.contains("dc-fence"))
    }

    // MARK: - HTML escaping

    @Test func contentIsEscaped() {
        let html = visitor.highlight("<div>\n")
        #expect(html.contains("&lt;div&gt;"))
    }

    // MARK: - Alerts

    @Test func gfmAlertNote() {
        let html = visitor.highlight("> [!NOTE]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-note"))
    }

    @Test func gfmAlertTip() {
        let html = visitor.highlight("> [!TIP]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-tip"))
    }

    @Test func gfmAlertImportant() {
        let html = visitor.highlight("> [!IMPORTANT]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-important"))
    }

    @Test func gfmAlertStatus() {
        let html = visitor.highlight("> [!STATUS]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-status"))
    }

    @Test func gfmAlertWarning() {
        let html = visitor.highlight("> [!WARNING]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-warning"))
    }

    @Test func gfmAlertCaution() {
        let html = visitor.highlight("> [!CAUTION]\n> Content\n")
        #expect(html.contains("md-blockquote md-alert-caution"))
    }

    @Test func doccAlertNote() {
        let html = visitor.highlight("> Note: Content\n")
        #expect(html.contains("md-blockquote md-alert-note"))
    }

    @Test func doccAlertWarning() {
        let html = visitor.highlight("> Warning: Be careful\n")
        #expect(html.contains("md-blockquote md-alert-warning"))
    }

    @Test func plainBlockquoteNoAlertClass() {
        let html = visitor.highlight("> Just a quote\n")
        #expect(html.contains("md-blockquote"))
        #expect(!html.contains("md-alert-"))
    }

    @Test func gfmAlertTagSpan() {
        // The [!NOTE] text is wrapped in md-alert-tag.
        let html = visitor.highlight("> [!NOTE]\n> Content\n")
        #expect(html.contains("md-alert-tag"))
    }

    @Test func doccAlertTagSpan() {
        // The "Note:" text is wrapped in md-alert-tag.
        let html = visitor.highlight("> Note: Content\n")
        #expect(html.contains("md-alert-tag"))
    }

    @Test func extendedAliasRendersAlertWhenModeExtended() {
        let html = visitor.highlight("> Remark: An observation\n", docCAlertMode: .extended)
        #expect(html.contains("md-alert-note"))
    }

    @Test func extendedAliasPlainWhenModeCommon() {
        let html = visitor.highlight("> Remark: An observation\n", docCAlertMode: .common)
        #expect(html.contains("md-blockquote"))
        #expect(!html.contains("md-alert-"))
    }

    @Test func coreAliasRendersAlertWhenModeCommon() {
        // Core DocC kinds always render as alerts in .common mode.
        let html = visitor.highlight("> Note: Content\n", docCAlertMode: .common)
        #expect(html.contains("md-alert-note"))
    }

    @Test func coreAliasPlainWhenModeOff() {
        // No DocC asides are processed in .off mode.
        let html = visitor.highlight("> Note: Content\n", docCAlertMode: .off)
        #expect(html.contains("md-blockquote"))
        #expect(!html.contains("md-alert-"))
    }

    // MARK: - Container structure

    @Test func wrappedInContainer() {
        let html = visitor.highlight("hello\n")
        #expect(html.hasPrefix("<div class=\"down-lines\">"))
        #expect(html.hasSuffix("</div>"))
    }

    // MARK: - Footnotes

    /// Isolates the `.lc` content of the Nth (1-based) source line.
    private func lineContent(_ html: String, line n: Int) -> String {
        let parts = html.components(separatedBy: "<span class=\"lc\">")
        guard n < parts.count else { return "" }
        return parts[n].components(separatedBy: "</span></div>").first ?? ""
    }

    @Test func footnoteReferenceHighlighted() {
        let html = visitor.highlight("A claim.[^1]\n\n[^1]: A note.\n")
        #expect(html.contains("md-footnote-ref"))
        // The reference marker spans `[^1]` on the first line.
        let first = lineContent(html, line: 1)
        #expect(first.contains("<span class=\"md-footnote-ref\">[^1]</span>"))
    }

    @Test func footnoteDefinitionMarkerHighlighted() {
        let html = visitor.highlight("Text.[^1]\n\n[^1]: A note.\n")
        #expect(html.contains("md-footnote-def"))
        let def = lineContent(html, line: 3)
        #expect(def.contains("<span class=\"md-footnote-def\">[^1]:</span>"))
    }

    @Test func singleLineDefinitionBodyHighlightsInline() {
        // Even a one-line definition: swift-markdown would consume
        // `[^1]: **bold**` as a failed link-ref-def, losing the bold.
        let html = visitor.highlight("Text.[^1]\n\n[^1]: a **bold** note.\n")
        let def = lineContent(html, line: 3)
        #expect(def.contains("md-footnote-def"))
        #expect(def.contains("<span class=\"md-strong\">**bold**</span>"))
    }

    @Test func multiParagraphDefinitionBodyIsNotCode() {
        let md = """
        Text.[^1]

        [^1]: First paragraph.

            Second paragraph.
        """ + "\n"
        let html = visitor.highlight(md)
        // The indented continuation must NOT be treated as a code block.
        #expect(!html.contains("dc-code"))
        #expect(!html.contains("md-code-block"))
        // Indentation is retained verbatim in the source line.
        #expect(html.contains("    Second paragraph."))
    }

    @Test func definitionBodyInlineConstructsHighlight() {
        let md = """
        Text.[^1]

        [^1]: A note with **bold**, _em_, and a [link](https://e.com).
        """ + "\n"
        let html = visitor.highlight(md)
        let def = lineContent(html, line: 3)
        #expect(def.contains("md-strong"))
        #expect(def.contains("md-emphasis"))
        #expect(def.contains("md-link"))
    }

    @Test func definitionBodyBlockquoteHighlights() {
        let md = """
        Text.[^1]

        [^1]: A note.

            > a quote
        """ + "\n"
        let html = visitor.highlight(md)
        #expect(html.contains("md-blockquote"))
        #expect(!html.contains("dc-code"))
    }

    @Test func footnoteRefInCodeBlockNotHighlighted() {
        // cmark never treats `[^1]` inside a fence as a footnote, so the
        // scan yields no reference there.
        let md = "```\n[^1]\n```\n"
        let html = visitor.highlight(md)
        #expect(!html.contains("md-footnote-ref"))
    }

    @Test func documentWithoutFootnotesUnaffected() {
        let html = visitor.highlight("# Title\n\nA paragraph.\n")
        #expect(!html.contains("md-footnote"))
    }
}
