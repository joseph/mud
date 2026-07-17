import Foundation

/// Generates complete HTML documents with embedded styles and scripts.
public enum HTMLTemplate {
    /// Wraps body HTML in an Up-mode document.
    static func wrapUp(body: String, options: RenderOptions) -> String {
        var doc = HTMLDocument(options: options)
        doc.styles = [themeCSS(for: options.theme), sharedCSS, upCSS, commentsCSS]
        // The write-side comment styles ride along only in the app's editable
        // view; a read-only export omits them (see commentsEditCSS).
        if options.commentsEditable { doc.styles.append(commentsEditCSS) }
        if options.waypoint != nil { doc.styles.append(changesCSS) }
        // Find styles only in the live app view — exports have no Find bar.
        if !options.standalone { doc.styles.append(findCSS) }
        // Print overrides come last so they win over the on-screen defaults.
        doc.styles.append(printCSS)
        doc.cspImgSrc = options.blockRemoteContent
            ? ["mud-asset:", "data:"]
            : ["mud-asset:", "data:", "https:"]
        doc.bodyContent = "    <article class=\"up-mode-output\">\n\(body)\n    </article>"

        // Column mode hides the bottom section and the quote markers on screen
        // and draws the Comments column instead; the JS keys off this class to
        // decide whether to project the column.
        if options.commentMode == .interactive {
            doc.htmlClasses.append("comments-column")
            // The app's live, editable view injects the read-side column JS at
            // runtime via WKUserScript (WebView.swift). A read-only export has
            // no WKWebView to do that, so inline mud-comments.js here; on load
            // it projects the column from the hidden bottom section. Mirrors how
            // commentsEditCSS rides along only for the editable view.
            if !options.commentsEditable {
                doc.cspScriptSrc.append("'unsafe-inline'")
                doc.bodyScripts.append(.inline(mudCommentsJS))
            }
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
        // Find styles only in the live app view — exports have no Find bar.
        if !options.standalone { doc.styles.append(findCSS) }
        // Print overrides come last so they win over the on-screen defaults.
        doc.styles.append(printCSS)
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

    /// Read-side comment styles (`mud-comments.css`): the markers, the quotation
    /// highlights, the bottom Comments section, and the projected column.
    /// Bundled into every Up document, exports included.
    private static var commentsCSS: String {
        loadResource("mud-comments", type: "css") ?? ""
    }

    /// Write-side comment styles (`mud-comments-edit.css`): the compose box and
    /// the add / reply / edit / delete controls. Embedded only when
    /// `RenderOptions.commentsEditable` is set — the app's live view, never an
    /// export. Mirrors the `mudCommentsJS` / `mudCommentsEditJS` split.
    private static var commentsEditCSS: String {
        loadResource("mud-comments-edit", type: "css") ?? ""
    }

    public static var changesCSS: String {
        loadResource("mud-changes", type: "css") ?? ""
    }

    /// Find highlight styles (`mud-find.css`): the search-match colors, themed
    /// via the lighting variables in mud.css. Appended only when
    /// `!options.standalone` — the live app view is the only place the Find bar
    /// runs, so exports never carry these styles.
    private static var findCSS: String {
        loadResource("mud-find", type: "css") ?? ""
    }

    /// Print overrides (`mud-print.css`): every `@media print` rule, gathered
    /// out of the mode and comments stylesheets. Included last in both modes so
    /// these rules win over the on-screen defaults.
    private static var printCSS: String {
        loadResource("mud-print", type: "css") ?? ""
    }

    /// Returns the CSS custom-property block for the given theme.
    /// Falls back to earthy if the resource file is not found.
    public static func themeCSS(for theme: Theme) -> String {
        loadResource("theme-\(theme.rawValue)", type: "css")
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
    ///
    /// The shared anchoring primitives (`mud-comment-anchor.js`) are concatenated
    /// ahead of the read-side file so this one string carries both. The write
    /// side (`mudCommentsEditJS`, app only) is injected separately and depends on
    /// `Mud.commentAnchor` being published here first.
    public static var mudCommentsJS: String {
        let anchor = loadResource("mud-comment-anchor", type: "js") ?? ""
        let comments = loadResource("mud-comments", type: "js") ?? ""
        return anchor + "\n" + comments
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


    private static let resourceLock = NSLock()
    nonisolated(unsafe) private static var resourceCache: [String: String?] = [:]

    /// Loads a bundle resource, memoized for the process lifetime: resources
    /// are immutable once the bundle is built, and one render of a
    /// footnote-heavy document used to re-read the same CSS/JS files over a
    /// hundred times.
    static func loadResource(_ name: String, type: String) -> String? {
        let key = "\(name).\(type)"
        resourceLock.lock()
        if let cached = resourceCache[key] {
            resourceLock.unlock()
            return cached
        }
        resourceLock.unlock()

        let contents: String?
        if let url = Bundle.module.url(forResource: name, withExtension: type) {
            contents = try? String(contentsOf: url, encoding: .utf8)
        } else {
            contents = nil
        }

        resourceLock.lock()
        resourceCache[key] = contents
        resourceLock.unlock()
        return contents
    }
}
