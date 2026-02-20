import Foundation
import Testing
@testable import MudCore

@Suite("HTMLTemplate")
struct HTMLTemplateTests {
    // MARK: - wrapUp()

    @Test func upDocumentStructure() {
        let doc = HTMLTemplate.wrapUp(body: "<p>hi</p>")
        #expect(doc.contains("<!DOCTYPE html>"))
        #expect(doc.contains("<html>"))
        #expect(doc.contains("</html>"))
        #expect(doc.contains("<head>"))
        #expect(doc.contains("<body>"))
        #expect(doc.contains("<article class=\"up-mode-output\">"))
    }

    @Test func titleIsEscaped() {
        let doc = HTMLTemplate.wrapUp(body: "", title: "A & B <C>")
        #expect(doc.contains("<title>A &amp; B &lt;C&gt;</title>"))
    }

    @Test func baseTagPresent() {
        let url = URL(fileURLWithPath: "/tmp/test.md")
        let doc = HTMLTemplate.wrapUp(body: "", baseURL: url)
        #expect(doc.contains("<base href="))
    }

    @Test func baseTagAbsent() {
        let doc = HTMLTemplate.wrapUp(body: "")
        #expect(!doc.contains("<base"))
    }

    @Test func cspMetaTag() {
        let doc = HTMLTemplate.wrapUp(body: "")
        #expect(doc.contains("Content-Security-Policy"))
    }

    @Test func themeCSS() {
        let doc = HTMLTemplate.wrapUp(body: "", theme: "earthy")
        #expect(doc.contains("id=\"mud-theme\""))
    }

    @Test func unknownThemeFallsBackToEarthy() {
        let unknown = HTMLTemplate.themeCSS(for: "nonexistent")
        let earthy = HTMLTemplate.themeCSS(for: "earthy")
        #expect(unknown == earthy)
    }

    @Test func cssEmbedded() {
        let doc = HTMLTemplate.wrapUp(body: "")
        // The shared CSS should be non-trivially present.
        #expect(doc.contains("<style"))
        #expect(doc.contains("up-mode-output"))
    }

    // MARK: - wrapDown()

    @Test func downDocumentStructure() {
        let doc = HTMLTemplate.wrapDown(tableHTML: "<table></table>")
        #expect(doc.contains("<!DOCTYPE html>"))
        #expect(doc.contains("<div class=\"down-mode-output\">"))
        #expect(doc.contains("<table></table>"))
    }

    @Test func downTitleEscaped() {
        let doc = HTMLTemplate.wrapDown(tableHTML: "", title: "<script>")
        #expect(doc.contains("<title>&lt;script&gt;</title>"))
    }

    // MARK: - JS resources

    @Test func mudJSNotEmpty() {
        #expect(!HTMLTemplate.mudJS.isEmpty)
    }

    @Test func mudUpJSNotEmpty() {
        #expect(!HTMLTemplate.mudUpJS.isEmpty)
    }

    @Test func mudDownJSNotEmpty() {
        #expect(!HTMLTemplate.mudDownJS.isEmpty)
    }
}
