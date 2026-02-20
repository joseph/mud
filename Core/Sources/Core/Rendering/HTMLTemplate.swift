import Foundation

/// Generates complete HTML documents with embedded styles and scripts.
public enum HTMLTemplate {
    /// Wraps body HTML in an Up-mode document.
    static func wrapUp(body: String, title: String = "", baseURL: URL? = nil,
                     theme: String = "earthy") -> String {
        let baseTag = baseURL.map { "<base href=\"\($0.absoluteString)\">" } ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src mud-asset: data: https:; style-src 'unsafe-inline'; script-src 'none'">
            \(baseTag)
            <title>\(escapeHTML(title))</title>
            <style id="mud-theme">\(themeCSS(for: theme))</style>
            <style>\(sharedCSS)\(upCSS)</style>
        </head>
        <body>
            <article class="up-mode-output">
        \(body)
            </article>
        </body>
        </html>
        """
    }

    /// Wraps a pre-built table in a Down-mode document.
    static func wrapDown(tableHTML: String, title: String = "",
                        theme: String = "earthy") -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>\(escapeHTML(title))</title>
            <style id="mud-theme">\(themeCSS(for: theme))</style>
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

    private static func escapeHTML(_ string: String) -> String {
        HTMLEscaping.escape(string)
    }

    // MARK: - Embedded resources

    private static var sharedCSS: String {
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

    private static func loadResource(_ name: String, type: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: type),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return contents
    }
}
