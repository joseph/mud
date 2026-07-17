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
        // Theme CSS is embedded in the style block.
        let earthyCSS = HTMLTemplate.themeCSS(for: "earthy")
        #expect(doc.contains(earthyCSS))
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
        let doc = HTMLTemplate.wrapDown(bodyHTML: "<div>content</div>", options: .init())
        #expect(doc.contains("<!DOCTYPE html>"))
        #expect(doc.contains("<div class=\"down-mode-output\">"))
        #expect(doc.contains("<div>content</div>"))
    }

    @Test func downTitleEscaped() {
        var opts = RenderOptions()
        opts.title = "<script>"
        let doc = HTMLTemplate.wrapDown(bodyHTML: "", options: opts)
        #expect(doc.contains("<title>&lt;script&gt;</title>"))
    }

    // MARK: - HTML classes and zoom

    @Test func htmlClassesBakedIn() {
        var opts = RenderOptions()
        opts.htmlClasses = ["has-line-numbers", "is-readable-column"]
        let doc = HTMLTemplate.wrapUp(body: "", options: opts)
        #expect(doc.contains("<html class=\"has-line-numbers is-readable-column\">"))
    }

    @Test func zoomLevelBakedIn() {
        var opts = RenderOptions()
        opts.zoomLevel = 1.5
        let doc = HTMLTemplate.wrapUp(body: "", options: opts)
        #expect(doc.contains("<html style=\"zoom: 1.5\">"))
    }

    @Test func defaultZoomNoAttribute() {
        let doc = HTMLTemplate.wrapUp(body: "", options: .init())
        #expect(doc.contains("<html>"))
    }

    // MARK: - Extension embedding (mermaid)

    @Test func extensionMermaidAddsScripts() {
        var opts = RenderOptions()
        opts.standalone = true
        opts.extensions.insert("mermaid")
        let body = "<pre><code class=\"language-mermaid\">graph TD</code></pre>"
        let doc = HTMLTemplate.wrapUp(body: body, options: opts)
        #expect(doc.contains("<script src=\""))
        #expect(doc.contains("cdn.jsdelivr.net"))
    }

    @Test func extensionMermaidUpdatesCSP() {
        var opts = RenderOptions()
        opts.standalone = true
        opts.extensions.insert("mermaid")
        let body = "<pre><code class=\"language-mermaid\">graph TD</code></pre>"
        let doc = HTMLTemplate.wrapUp(body: body, options: opts)
        #expect(doc.contains("script-src https://cdn.jsdelivr.net"))
    }

    @Test func extensionMermaidNoopWithoutCodeBlocks() {
        var opts = RenderOptions()
        opts.extensions.insert("mermaid")
        let doc = HTMLTemplate.wrapUp(body: "<p>no mermaid</p>", options: opts)
        #expect(doc.contains("script-src 'none'"))
        #expect(!doc.contains("<script"))
    }

    @Test func noExtensionsByDefault() {
        let body = "<pre><code class=\"language-mermaid\">graph TD</code></pre>"
        let doc = HTMLTemplate.wrapUp(body: body, options: .init())
        #expect(doc.contains("script-src 'none'"))
        #expect(!doc.contains("<script"))
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

    // MARK: - Find styles

    @Test func findStylesLiveViewOnly() {
        // The live app view (standalone == false) carries the Find highlight
        // styles; a standalone export omits them (no Find bar there).
        let live = HTMLTemplate.wrapUp(body: "", options: .init())
        #expect(live.contains("mark.mud-match"))

        var export = RenderOptions()
        export.standalone = true
        let exported = HTMLTemplate.wrapUp(body: "", options: export)
        #expect(!exported.contains("mark.mud-match"))
    }

    @Test func findStylesInDownMode() {
        // Find works in both modes, so wrapDown carries the styles too.
        let live = HTMLTemplate.wrapDown(bodyHTML: "", options: .init())
        #expect(live.contains("mark.mud-match"))

        var export = RenderOptions()
        export.standalone = true
        let exported = HTMLTemplate.wrapDown(bodyHTML: "", options: export)
        #expect(!exported.contains("mark.mud-match"))
    }

    @Test func findStylesNotInJS() {
        // The color rules moved out of the mud.js self-injected <style> and into
        // mud-find.css, so mud.js no longer carries a `mark.mud-match` selector.
        // It still names the bare class to apply it to matches at runtime.
        #expect(!HTMLTemplate.mudJS.contains("mark.mud-match"))
    }

    // MARK: - Render extensions

    @Test func mermaidExtensionRuntimeJSNotEmpty() {
        guard let mermaid = RenderExtension.registry["mermaid"] else {
            Issue.record("mermaid extension not in registry")
            return
        }
        let scripts = mermaid.runtimeJS()
        #expect(scripts.count == 2)
        #expect(scripts.allSatisfy { !$0.isEmpty })
    }
}
