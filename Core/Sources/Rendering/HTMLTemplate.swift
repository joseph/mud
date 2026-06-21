import Foundation

/// Generates complete HTML documents with embedded styles and scripts.
public enum HTMLTemplate {
    /// Wraps body HTML in an Up-mode document.
    static func wrapUp(body: String, options: RenderOptions) -> String {
        var doc = HTMLDocument(options: options)
        doc.styles = [themeCSS(for: options.theme), sharedCSS, upCSS]
        if options.waypoint != nil { doc.styles.append(changesCSS) }
        doc.cspImgSrc = options.blockRemoteContent
            ? ["mud-asset:", "data:"]
            : ["mud-asset:", "data:", "https:"]
        doc.bodyContent = "    <article class=\"up-mode-output\">\n\(body)\n    </article>"

        // Column mode hides the bottom section and the quote markers on screen
        // and draws the Comments column instead; the JS keys off this class to
        // decide whether to project the column.
        if options.commentMode == .interactive {
            doc.htmlClasses.append("comments-column")
        }

        if options.standalone {
            for name in options.extensions {
                guard let ext = RenderExtension.registry[name],
                      body.contains(ext.marker) else { continue }
                doc.cspScriptSrc.append(contentsOf: ext.cspSources)
                doc.bodyScripts.append(contentsOf: ext.embeddedScripts)
            }
        }

        return doc.render()
    }

    /// Wraps pre-built body HTML in a Down-mode document.
    static func wrapDown(bodyHTML: String, options: RenderOptions) -> String {
        var doc = HTMLDocument(options: options)
        doc.styles = [themeCSS(for: options.theme), sharedCSS, downCSS]
        if options.waypoint != nil { doc.styles.append(changesCSS) }
        doc.bodyContent = """
            <div class="down-mode-output">
                \(bodyHTML)
            </div>
        """
        return doc.render()
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

    public static var changesCSS: String {
        loadResource("mud-changes", type: "css") ?? ""
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

    /// Change tracking JavaScript injected at runtime by WKWebView.
    public static var mudChangesJS: String {
        loadResource("mud-changes", type: "js") ?? ""
    }

    /// Up-mode JavaScript injected at runtime by WKWebView.
    public static var mudUpJS: String {
        loadResource("mud-up", type: "js") ?? ""
    }

    /// Comment column (read side): projection from the hidden section, highlight
    /// anchoring, the slot solver, hover/activate. Injected at runtime by
    /// WKWebView; also the file inlined into HTML exports for a read-only column.
    public static var mudCommentsJS: String {
        loadResource("mud-comments", type: "js") ?? ""
    }

    /// Comment column (write side): the Add button, compose box, and
    /// submit/reply/edit/delete bridge. Injected by the app only — exports load
    /// just `mudCommentsJS` and are read-only.
    public static var mudCommentsEditJS: String {
        loadResource("mud-comments-edit", type: "js") ?? ""
    }

    /// Down-mode JavaScript injected at runtime by WKWebView.
    public static var mudDownJS: String {
        loadResource("mud-down", type: "js") ?? ""
    }


    static func loadResource(_ name: String, type: String) -> String? {
        guard let url = Bundle.module.url(forResource: name, withExtension: type),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return contents
    }
}
