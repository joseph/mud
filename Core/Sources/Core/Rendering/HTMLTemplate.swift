import Foundation

/// Generates complete HTML documents with embedded styles and scripts.
public enum HTMLTemplate {
    /// Wraps body HTML in an Up-mode document.
    static func wrapUp(body: String, options: RenderOptions) -> String {
        var doc = HTMLDocument(options: options)
        doc.styles = [themeCSS(for: options.theme), sharedCSS, upCSS]
        doc.cspImgSrc = options.blockRemoteContent
            ? ["mud-asset:", "data:"]
            : ["mud-asset:", "data:", "https:"]
        doc.bodyContent = "    <article class=\"up-mode-output\">\n\(body)\n    </article>"

        if options.embedMermaid && body.contains("language-mermaid") {
            doc.cspScriptSrc = ["https://cdn.jsdelivr.net", "'unsafe-inline'"]
            doc.bodyScripts = [.src(mermaidCDN), .inline(mermaidInitJS)]
        }

        return doc.render()
    }

    /// Wraps a pre-built table in a Down-mode document.
    static func wrapDown(tableHTML: String, options: RenderOptions) -> String {
        var doc = HTMLDocument(options: options)
        doc.styles = [themeCSS(for: options.theme), sharedCSS, downCSS]
        doc.bodyContent = """
            <div class="down-mode-output">
                \(tableHTML)
            </div>
        """
        return doc.render()
    }

    static let mermaidCDN =
        "https://cdn.jsdelivr.net/npm/mermaid@11.12.3/dist/mermaid.min.js"

    // MARK: - Embedded resources

    /// The shared CSS stylesheet (`mud.css`), containing alert color variables
    /// and other shared properties.
    public static var sharedCSS: String {
        loadResource("mud", type: "css") ?? ""
    }

    private static var upCSS: String {
        loadResource("mud-up", type: "css") ?? ""
    }

    private static var downCSS: String {
        loadResource("mud-down", type: "css") ?? ""
    }

    /// Returns the CSS custom-property block for the given theme name.
    /// Falls back to earthy if the name is not found.
    public static func themeCSS(for theme: String) -> String {
        loadResource("theme-\(theme)", type: "css")
            ?? loadResource("theme-earthy", type: "css")
            ?? ""
    }

    /// Shared JavaScript injected at runtime by WKWebView.
    public static var mudJS: String {
        loadResource("mud", type: "js") ?? ""
    }

    /// Up-mode JavaScript injected at runtime by WKWebView.
    public static var mudUpJS: String {
        loadResource("mud-up", type: "js") ?? ""
    }

    /// Down-mode JavaScript injected at runtime by WKWebView.
    public static var mudDownJS: String {
        loadResource("mud-down", type: "js") ?? ""
    }

    /// Mermaid diagram library injected at runtime by WKWebView.
    public static var mermaidJS: String {
        loadResource("mermaid.min", type: "js") ?? ""
    }

    /// Mermaid init script injected at runtime by WKWebView.
    public static var mermaidInitJS: String {
        loadResource("mermaid-init", type: "js") ?? ""
    }

    private static func loadResource(_ name: String, type: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: type),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return contents
    }
}
