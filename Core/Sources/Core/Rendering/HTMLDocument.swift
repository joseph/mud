import Foundation

/// A structured intermediate for assembling complete HTML documents.
///
/// Each document-level concern (CSP, scripts, styles, classes) is a
/// separate field. Post-processors modify these fields independently
/// before `render()` serializes everything into a single HTML string.
struct HTMLDocument {
    var title: String
    var baseURL: URL?
    var styles: [String] = []
    var cspImgSrc: [String] = []
    var cspScriptSrc: [String] = []
    var htmlClasses: [String]
    var htmlStyles: [String]
    var bodyContent: String = ""
    var bodyScripts: [Script] = []

    enum Script {
        case inline(String)
        case src(String)
    }

    init(options: RenderOptions) {
        self.title = options.title
        self.baseURL = options.includeBaseTag ? options.baseURL : nil
        self.htmlClasses = options.htmlClasses.isEmpty
            ? [] : options.htmlClasses.sorted()
        self.htmlStyles = options.zoomLevel != 1.0
            ? ["zoom: \(options.zoomLevel)"] : []
    }

    func render() -> String {
        let baseTag = baseURL.map { "<base href=\"\($0.absoluteString)\">" } ?? ""
        let csp = buildCSP()
        let styleBlock = styles.joined()
        let htmlAttrs = buildHTMLAttributes()
        let scriptBlock = buildScripts()

        return """
        <!DOCTYPE html>
        <html\(htmlAttrs)>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            \(csp)\(baseTag)
            <title>\(HTMLEscaping.escape(title))</title>
            <style>\(styleBlock)</style>
        </head>
        <body>
        \(bodyContent)\(scriptBlock)
        </body>
        </html>
        """
    }

    private func buildCSP() -> String {
        var directives: [String] = ["default-src 'none'"]
        if !cspImgSrc.isEmpty {
            directives.append("img-src \(cspImgSrc.joined(separator: " "))")
        }
        directives.append("style-src 'unsafe-inline'")
        if cspScriptSrc.isEmpty {
            directives.append("script-src 'none'")
        } else {
            directives.append("script-src \(cspScriptSrc.joined(separator: " "))")
        }
        let content = directives.joined(separator: "; ")
        return "<meta http-equiv=\"Content-Security-Policy\" content=\"\(content)\">\n        "
    }

    private func buildHTMLAttributes() -> String {
        var attrs: [String] = []
        if !htmlClasses.isEmpty {
            attrs.append("class=\"\(htmlClasses.joined(separator: " "))\"")
        }
        if !htmlStyles.isEmpty {
            attrs.append("style=\"\(htmlStyles.joined(separator: "; "))\"")
        }
        if attrs.isEmpty { return "" }
        return " \(attrs.joined(separator: " "))"
    }

    private func buildScripts() -> String {
        if bodyScripts.isEmpty { return "" }
        var parts: [String] = [""]
        for script in bodyScripts {
            switch script {
            case .inline(let source):
                parts.append("    <script>\(source)</script>")
            case .src(let url):
                parts.append("    <script src=\"\(url)\"></script>")
            }
        }
        return parts.joined(separator: "\n")
    }
}
