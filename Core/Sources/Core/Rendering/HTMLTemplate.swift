import Foundation

/// Generates complete HTML documents with embedded styles and scripts.
public enum HTMLTemplate {
    /// Wraps body HTML in an Up-mode document.
    static func wrapUp(body: String, options: RenderOptions) -> String {
        let baseTag = options.baseURL.map { "<base href=\"\($0.absoluteString)\">" } ?? ""
        let imgSrc = options.blockRemoteContent ? "mud-asset: data:" : "mud-asset: data: https:"
        let hasMermaid = options.embedMermaid && body.contains("language-mermaid")
        let scriptSrc = hasMermaid
            ? "https://cdn.jsdelivr.net 'unsafe-inline'"
            : "'none'"
        let mermaidScripts = hasMermaid ? """

            <script src="\(mermaidCDN)"></script>
            <script>\(mermaidInitJS)</script>
        """ : ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src \(imgSrc); style-src 'unsafe-inline'; script-src \(scriptSrc)">
            \(baseTag)
            <title>\(escapeHTML(options.title))</title>
            <style id="mud-theme">\(themeCSS(for: options.theme))</style>
            <style>\(sharedCSS)\(upCSS)</style>
        </head>
        <body>
            <article class="up-mode-output">
        \(body)
            </article>\(mermaidScripts)
        </body>
        </html>
        """
    }

    /// Wraps a pre-built table in a Down-mode document.
    static func wrapDown(tableHTML: String, options: RenderOptions) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(escapeHTML(options.title))</title>
            <style id="mud-theme">\(themeCSS(for: options.theme))</style>
            <style>\(sharedCSS)\(downCSS)</style>
        </head>
        <body>
            <div class="down-mode-output">
                \(tableHTML)
            </div>
        </body>
        </html>
        """
    }

    static let mermaidCDN =
        "https://cdn.jsdelivr.net/npm/mermaid@11.12.3/dist/mermaid.min.js"

    private static func escapeHTML(_ string: String) -> String {
        HTMLEscaping.escape(string)
    }

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
