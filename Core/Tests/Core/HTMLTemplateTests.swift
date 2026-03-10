import Foundation
import Testing
@testable import MudCore

@Suite("HTMLTemplate")
struct HTMLTemplateTests {
    // MARK: - wrapUp()

    @Test func upDocumentStructure() {
        let doc = HTMLTemplate.wrapUp(body: "<p>hi</p>", options: .init())
        #expect(doc.contains("<!DOCTYPE html>"))
        #expect(doc.contains("<html>"))
        #expect(doc.contains("</html>"))
        #expect(doc.contains("<head>"))
        #expect(doc.contains("<body>"))
        #expect(doc.contains("<article class=\"up-mode-output\">"))
    }

    @Test func titleIsEscaped() {
        var opts = RenderOptions()
        opts.title = "A & B <C>"
        let doc = HTMLTemplate.wrapUp(body: "", options: opts)
        #expect(doc.contains("<title>A &amp; B &lt;C&gt;</title>"))
    }

    @Test func baseTagPresent() {
        var opts = RenderOptions()
        opts.baseURL = URL(fileURLWithPath: "/tmp/test.md")
        let doc = HTMLTemplate.wrapUp(body: "", options: opts)
        #expect(doc.contains("<base href="))
    }

    @Test func baseTagAbsent() {
        let doc = HTMLTemplate.wrapUp(body: "", options: .init())
        #expect(!doc.contains("<base"))
    }

    @Test func cspMetaTag() {
        let doc = HTMLTemplate.wrapUp(body: "", options: .init())
        #expect(doc.contains("Content-Security-Policy"))
    }

    @Test func cspAllowsRemoteImagesByDefault() {
        let doc = HTMLTemplate.wrapUp(body: "", options: .init())
        #expect(doc.contains("img-src mud-asset: data: https:"))
    }

    @Test func cspBlocksRemoteImagesWhenRequested() {
        var opts = RenderOptions()
        opts.blockRemoteContent = true
        let doc = HTMLTemplate.wrapUp(body: "", options: opts)
        #expect(doc.contains("img-src mud-asset: data:"))
        #expect(!doc.contains("https:"))
    }

    @Test func themeCSS() {
        let doc = HTMLTemplate.wrapUp(body: "", options: .init())
        #expect(doc.contains("id=\"mud-theme\""))
    }

    @Test func unknownThemeFallsBackToEarthy() {
        let unknown = HTMLTemplate.themeCSS(for: "nonexistent")
        let earthy = HTMLTemplate.themeCSS(for: "earthy")
        #expect(unknown == earthy)
    }

    @Test func cssEmbedded() {
        let doc = HTMLTemplate.wrapUp(body: "", options: .init())
        // The shared CSS should be non-trivially present.
        #expect(doc.contains("<style"))
        #expect(doc.contains("up-mode-output"))
    }

    // MARK: - wrapDown()

    @Test func downDocumentStructure() {
        let doc = HTMLTemplate.wrapDown(tableHTML: "<table></table>", options: .init())
        #expect(doc.contains("<!DOCTYPE html>"))
        #expect(doc.contains("<div class=\"down-mode-output\">"))
        #expect(doc.contains("<table></table>"))
    }

    @Test func downTitleEscaped() {
        var opts = RenderOptions()
        opts.title = "<script>"
        let doc = HTMLTemplate.wrapDown(tableHTML: "", options: opts)
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

    @Test func mermaidJSNotEmpty() {
        #expect(!HTMLTemplate.mermaidJS.isEmpty)
    }

    @Test func mermaidInitJSNotEmpty() {
        #expect(!HTMLTemplate.mermaidInitJS.isEmpty)
    }
}
