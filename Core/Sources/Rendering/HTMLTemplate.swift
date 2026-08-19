import Foundation

/// Generates complete HTML documents with embedded styles and scripts.
public enum HTMLTemplate {
    /// Wraps body HTML in an Up-mode document.
    ///
    /// `footer` is the bottom Comments section (empty when the document has no
    /// comments). It is placed after `</article>`, as the article's next
    /// sibling: the comments are commentary *on* the document, not part of it.
    /// Since it no longer inherits the article's page box, `mud-comments.css`
    /// gives `footer.comments` a matching one.
    static func wrapUp(
        body: String, footer: String = "", options: RenderOptions
    ) -> String {
        // Every "does this document contain X" test below scans the footer too:
        // a comment body is rendered Markdown, so it can carry math or a
        // diagram just as the article can. Testing the two separately rather
        // than joining them keeps a large body from being copied per render.
        func renders(anyOf needles: String...) -> Bool {
            needles.contains { body.contains($0) || footer.contains($0) }
        }
        var doc = HTMLDocument(options: options)
        // The theme goes last of the base sheets, and the order is
        // load-bearing: a theme file is nothing but `:root` custom properties,
        // light and dark, so the only thing that lets it override a default one
        // of the sheets above declares is coming after them. Pinned by
        // `themeOverridesSharedDefaults`.
        //
        // The conditional sheets appended below still follow the theme, and two
        // of them beat it on purpose: `mud-narrow.css` re-tightens the page box
        // per width tier, and `mud-diagram-font.css` names `--diagram-font` for
        // the Handwritten look. Both are settings the reader chose, not palette
        // the theme owns.
        doc.styles = [sharedCSS, upCSS, commentsCSS, themeCSS(for: options.theme)]
        // The write-side comment styles ride along only in the app's editable
        // view; a read-only export omits them (see commentsEditCSS).
        if options.commentsEditable { doc.styles.append(commentsEditCSS) }
        if options.waypoint != nil { doc.styles.append(changesCSS) }
        // Find styles only in the live app view — exports have no Find bar.
        if !options.standalone { doc.styles.append(findCSS) }
        // Math styles only when the body actually contains math: a `<math>`
        // element, a `mud-math-block` div (present even when the renderer is
        // unavailable and the block falls back to escaped TeX), or a
        // `temml-error` span from invalid TeX. A math-free
        // document carries none of this.
        if renders(anyOf: "<math", "mud-math-block", "temml-error") {
            doc.styles.append(mathCSS)
        }
        // Diagram styles only for a document that will actually draw one: the
        // body holds a Mermaid block *and* the extension is on. With it off
        // the block stays a highlighted code block, which needs none of this.
        // One document has a use for these rules and no block to draw: the
        // popover a diagram's INVALID badge opens, which is the parser's
        // message alone. `mud-diagram-error` is the marker it matches on.
        let drawsDiagram = renders(anyOf: RenderExtension.mermaid.marker)
        if options.extensions.contains(RenderExtension.mermaid.name),
           drawsDiagram || renders(anyOf: "mud-diagram-error") {
            doc.styles.append(diagramCSS)
            // The Handwritten look is the only one that ships a font, carried
            // as a data URI — so the CSP has to allow that font, and the
            // Simplicity look's document carries neither. The error popover
            // letters no diagram labels, so it takes neither whatever the look.
            if options.diagramLook == .handwritten, drawsDiagram {
                doc.styles.append(diagramFontCSS)
                doc.cspFontSrc = ["data:"]
            }
        }
        // Narrow-viewport overrides come after every base stylesheet they
        // tighten, and before the print overrides, which win over both.
        doc.styles.append(narrowCSS)
        doc.styles.append(printCSS)
        doc.cspImgSrc = options.blockRemoteContent
            ? ["mud-asset:", "data:"]
            : ["mud-asset:", "data:", "https:"]
        doc.bodyContent = "    <article class=\"up-mode-output\">\n\(body)\n    </article>"
        if !footer.isEmpty { doc.bodyContent += "\n\(footer)" }

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
                      renders(anyOf: ext.marker) else { continue }
                doc.cspScriptSrc.append(contentsOf: ext.cspSources)
                doc.bodyScripts.append(contentsOf: ext.embeddedScripts)
            }
        }

        return doc.render()
    }

    /// Wraps pre-built body HTML in a Down-mode document.
    static func wrapDown(bodyHTML: String, options: RenderOptions) -> String {
        var doc = HTMLDocument(options: options)
        // Theme last, so it can override every default above it — see the note
        // in `wrapUp`.
        doc.styles = [sharedCSS, downCSS, themeCSS(for: options.theme)]
        if options.waypoint != nil { doc.styles.append(changesCSS) }
        // Find styles only in the live app view — exports have no Find bar.
        if !options.standalone { doc.styles.append(findCSS) }
        // Narrow-viewport overrides come after every base stylesheet they
        // tighten, and before the print overrides, which win over both.
        doc.styles.append(narrowCSS)
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

    /// Math styles (`mud-math.css`): display-block layout plus the adapted
    /// Temml per-engine rules. Appended in `wrapUp` only when the body
    /// contains math, so a math-free document never carries them.
    private static var mathCSS: String {
        loadResource("mud-math", type: "css") ?? ""
    }

    /// Diagram styles (`mud-diagram.css`): the `.mermaid` layout rules, the
    /// watercolor wash opacities, and the Simplicity look's label font.
    /// Appended in `wrapUp` only when the body contains a Mermaid block, so a
    /// diagram-free document carries none of it.
    private static var diagramCSS: String {
        loadResource("mud-diagram", type: "css") ?? ""
    }

    /// The Handwritten look's label font (`mud-diagram-font.css`): the Caveat
    /// `@font-face`, embedded as a data URI, and the `--diagram-font` name that
    /// puts it in front of the Simplicity stack. Appended after `diagramCSS`,
    /// which is what lets it win; ~100 KB, so it ships for that look alone.
    private static var diagramFontCSS: String {
        loadResource("mud-diagram-font", type: "css") ?? ""
    }

    /// Find highlight styles (`mud-find.css`): the search-match colors, themed
    /// via the lighting variables in mud.css. Appended only when
    /// `!options.standalone` — the live app view is the only place the Find bar
    /// runs, so exports never carry these styles.
    private static var findCSS: String {
        loadResource("mud-find", type: "css") ?? ""
    }

    /// Narrow-viewport overrides (`mud-narrow.css`): every width-based rule for
    /// both modes, gathered out of the mode and comments stylesheets. Included
    /// second-to-last in both modes, so these rules win over the on-screen
    /// defaults and the print overrides win over these.
    private static var narrowCSS: String {
        loadResource("mud-narrow", type: "css") ?? ""
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
    ///
    /// The fold arrow's markup is substituted in from `fold-arrow.svg`, so the
    /// shape is drawn in one file rather than restated in JS. Same shape as
    /// `mudCommentsJS`, which also assembles its script from more than one
    /// resource.
    public static var mudUpJS: String {
        let js = loadResource("mud-up", type: "js") ?? ""
        let svg = (loadResource("fold-arrow", type: "svg") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return js.replacingOccurrences(
            of: "\"__MUD_FOLD_ARROW_SVG__\"", with: jsStringLiteral(svg))
    }

    /// A string as a JS string literal, quotes included. JSON's string escaping
    /// is JS's, so the encoder does the work; it goes through a one-element
    /// array to sidestep top-level-fragment limits (as `MudJSBridge.script`
    /// does).
    private static func jsStringLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode([value]) else { return "\"\"" }
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
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
