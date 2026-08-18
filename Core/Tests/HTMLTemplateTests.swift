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
        let earthyCSS = HTMLTemplate.themeCSS(for: .earthy)
        #expect(doc.contains(earthyCSS))
    }

    @Test func systemThemeLoadsSystemCSS() {
        // The internal `.system` theme (error pages) loads its own file, not
        // the earthy fallback.
        let system = HTMLTemplate.themeCSS(for: .system)
        let earthy = HTMLTemplate.themeCSS(for: .earthy)
        #expect(!system.isEmpty)
        #expect(system != earthy)
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

    // MARK: - Diagram styles

    /// `data-mud-wash` is the marker unique to mud-diagram.css, which both
    /// looks carry.
    @Test func diagramCSSRidesAlongWithADiagram() {
        var opts = RenderOptions()
        opts.extensions.insert("mermaid")
        let body = "<pre><code class=\"language-mermaid\">graph TD</code></pre>"
        let doc = HTMLTemplate.wrapUp(body: body, options: opts)
        #expect(doc.contains("data-mud-wash"))
    }

    /// Only the Handwritten look ships a font, so only its document carries the
    /// `@font-face` and the `font-src` the embedded data URI needs. Simplicity
    /// letters its labels in a stack the page already has.
    @Test func embeddedFontShipsWithTheHandwrittenLookOnly() {
        var opts = RenderOptions()
        opts.extensions.insert("mermaid")
        let body = "<pre><code class=\"language-mermaid\">graph TD</code></pre>"

        #expect(opts.diagramLook == .simplicity)
        let simplicity = HTMLTemplate.wrapUp(body: body, options: opts)
        #expect(!simplicity.contains("@font-face"))
        #expect(!simplicity.contains("font-src"))

        opts.diagramLook = .handwritten
        let handwritten = HTMLTemplate.wrapUp(body: body, options: opts)
        #expect(handwritten.contains("@font-face"))
        #expect(handwritten.contains("font-src data:"))
    }

    /// The look reaches Mermaid as a custom property: each stylesheet names
    /// `--diagram-font`, the Handwritten one after (and so over) the other, and
    /// `mermaid-init.js` reads it. Rename it in one place and the labels fall
    /// back to the script's own default with nothing else failing.
    @Test func diagramFontIsNamedByTheStylesheetsAndReadByTheScript() {
        var opts = RenderOptions()
        opts.extensions.insert("mermaid")
        let body = "<pre><code class=\"language-mermaid\">graph TD</code></pre>"

        let simplicity = HTMLTemplate.wrapUp(body: body, options: opts)
        #expect(simplicity.contains("--diagram-font: system-ui"))

        opts.diagramLook = .handwritten
        let handwritten = HTMLTemplate.wrapUp(body: body, options: opts)
        #expect(handwritten.contains("--diagram-font: \"Caveat\""))
        // Loaded second, so it wins the cascade.
        let rules = handwritten.components(separatedBy: "--diagram-font")
        #expect(rules.count == 3)
        #expect(rules[2].hasPrefix(": \"Caveat\""))

        let script = RenderExtension.registry["mermaid"]?.runtimeJS().joined() ?? ""
        #expect(script.contains("--diagram-font"))
    }

    @Test func diagramCSSAbsentWithoutADiagram() {
        var opts = RenderOptions()
        opts.extensions.insert("mermaid")
        let doc = HTMLTemplate.wrapUp(body: "<p>no diagram</p>", options: opts)
        #expect(!doc.contains("data-mud-wash"))
        #expect(!doc.contains("font-src"))
    }

    /// With the extension off the block stays a highlighted code block, so the
    /// styles — and the font they embed — have nothing to do.
    @Test func diagramCSSAbsentWhenTheExtensionIsOff() {
        let body = "<pre><code class=\"language-mermaid\">graph TD</code></pre>"
        let doc = HTMLTemplate.wrapUp(body: body, options: .init())
        #expect(!doc.contains("data-mud-wash"))
        #expect(!doc.contains("font-src"))
    }

    // MARK: - The Comments footer

    /// The bottom Comments section is the article's sibling, not its last
    /// child, so the template appends it after the closing tag.
    @Test func commentsFooterIsPlacedAfterTheArticle() {
        let doc = HTMLTemplate.wrapUp(
            body: "<p>hi</p>",
            footer: "<footer class=\"comments\" data-comments></footer>",
            options: .init())
        #expect(doc.contains("</article>\n<footer class=\"comments\""))
    }

    /// A comment body is rendered Markdown, so the footer can hold math or a
    /// diagram the article doesn't — and every "document contains X" test in
    /// the template has to see it, or the document ships without the styles or
    /// scripts that content needs.
    @Test func footerContentDrivesConditionalResources() {
        // `tml-display` is the marker unique to mud-math.css.
        let math = HTMLTemplate.wrapUp(
            body: "<p>hi</p>",
            footer: "<footer class=\"comments\"><math></math></footer>",
            options: .init())
        #expect(math.contains("tml-display"))
        #expect(!HTMLTemplate.wrapUp(body: "<p>hi</p>", options: .init())
            .contains("tml-display"))

        var opts = RenderOptions()
        opts.standalone = true
        opts.extensions.insert("mermaid")
        let mermaid = HTMLTemplate.wrapUp(
            body: "<p>hi</p>",
            footer: "<footer class=\"comments\"><pre><code "
                + "class=\"language-mermaid\">graph TD</code></pre></footer>",
            options: opts)
        #expect(mermaid.contains("cdn.jsdelivr.net"))
        #expect(mermaid.contains("data-mud-wash"))
    }

    // MARK: - JS resources

    @Test func mudJSNotEmpty() {
        #expect(!HTMLTemplate.mudJS.isEmpty)
    }

    @Test func mudUpJSNotEmpty() {
        #expect(!HTMLTemplate.mudUpJS.isEmpty)
    }

    /// The fold arrow's markup is substituted into `mud-up.js` from
    /// `fold-arrow.svg`. Renaming the placeholder on either side would ship a
    /// heading button holding the literal placeholder text instead of an arrow
    /// — visible only by looking at a rendered page, so pin it here.
    @Test func mudUpJSCarriesTheFoldArrow() {
        let js = HTMLTemplate.mudUpJS
        #expect(!js.contains("__MUD_FOLD_ARROW_SVG__"))
        // The SVG arrives as a JS string literal: quotes and newlines escaped.
        #expect(js.contains(#"<svg version=\"1.1\""#))
        #expect(js.contains("polyline"))
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

    // MARK: - Narrow-viewport styles

    /// The narrow tiers are unconditional — unlike the Find styles, an export
    /// gets them too. Quick Look renders through `exportDocument`, and a
    /// Finder column-view pane is the narrowest viewport Mud draws into.
    @Test func narrowStylesInEveryDocument() {
        var export = RenderOptions()
        export.standalone = true

        for doc in [
            HTMLTemplate.wrapUp(body: "", options: .init()),
            HTMLTemplate.wrapUp(body: "", options: export),
            HTMLTemplate.wrapDown(bodyHTML: "", options: .init()),
            HTMLTemplate.wrapDown(bodyHTML: "", options: export),
        ] {
            #expect(doc.contains("@media screen and (max-width: 700px)"))
            #expect(doc.contains("@media screen and (max-width: 420px)"))
        }
    }

    /// The whole design rests on this cascade order: the narrow tiers tighten
    /// the base layout, and the print overrides then win over both. Same-
    /// specificity selectors appear in all three, so document order decides.
    @Test func narrowStylesPrecedePrintStyles() {
        let doc = HTMLTemplate.wrapUp(body: "", options: .init())
        // The braces matter: the bare at-rule names also appear in the
        // stylesheets' prose comments.
        let narrow = doc.range(of: "@media screen and (max-width: 700px) {")
        let paged = doc.range(of: "@media print {")
        #expect(narrow != nil)
        #expect(paged != nil)
        if let narrow, let paged {
            #expect(narrow.lowerBound < paged.lowerBound)
        }
    }

    /// Every narrow query must be screen-scoped. A width test in paged output
    /// is measured against the page box, and the `@page` margin in
    /// mud-print.css leaves US Letter near 680 CSS px and A4 near 660 — an
    /// unscoped `(max-width: 700px)` would fire on every printed page.
    ///
    /// The stylesheet holds exactly the two tiers and nothing else, so the
    /// check is total: every query in the file is accounted for.
    @Test func narrowStylesAreScreenScoped() {
        let stylesheet = HTMLTemplate.loadResource("mud-narrow", type: "css") ?? ""
        #expect(!stylesheet.isEmpty)

        let queries = stylesheet.components(separatedBy: "@media").dropFirst()
        #expect(queries.count == 2)
        for query in queries {
            #expect(query.hasPrefix(" screen and (max-width: "))
        }
    }

    /// `Layout.compactBreakpoint` is what the app measures its content pane
    /// against before offering to write a comment. A media query can only be
    /// written in CSS, so the number is stated twice; if they drift, the app
    /// opens a compose box into a column the stylesheet has already hidden.
    @Test func compactBreakpointMatchesTheStylesheet() {
        let stylesheet = HTMLTemplate.loadResource("mud-narrow", type: "css") ?? ""
        let px = Int(Layout.compactBreakpoint)
        #expect(stylesheet.contains("@media screen and (max-width: \(px)px) {"))

        // And the guards the column's own stylesheets pair with it.
        for name in ["mud-comments", "mud-comments-edit"] {
            let css = HTMLTemplate.loadResource(name, type: "css") ?? ""
            #expect(css.contains("@media screen and (min-width: \(px).02px) {"))
        }
    }

    /// Every screen-scoped block in the column's own stylesheets must carry the
    /// `min-width` guard — an unguarded one would reserve the gutter below the
    /// Compact tier, leaving a blank strip with no column in it.
    @Test func noCommentColumnBlockIsLeftUnguarded() {
        for name in ["mud-comments", "mud-comments-edit"] {
            let css = HTMLTemplate.loadResource(name, type: "css") ?? ""
            #expect(!css.contains("@media screen {"))
        }
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
