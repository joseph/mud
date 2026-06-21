import MudPreferences
import MudCore
import SwiftUI
import WebKit

// MARK: - WKWebView subclass (context menu)

class MudWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        if menu.items.count <= 2 {
            menu.removeAllItems()
            let openIn = NSMenuItem(title: "Open In…", action: nil, keyEquivalent: "")
            openIn.submenu = buildOpenInSubmenu()
            menu.addItem(openIn)
            if !isSandboxed {
                menu.addItem(withTitle: "Open In Browser",
                             action: #selector(postOpenInBrowser),
                             keyEquivalent: "")
            }
            menu.addItem(withTitle: "Print\u{2026}",
                         action: #selector(postPrintDocument),
                         keyEquivalent: "")
            menu.addItem(withTitle: "Reload",
                         action: #selector(postReloadDocument),
                         keyEquivalent: "")
            for item in menu.items where item.action != nil { item.target = self }
        } else if canAddComment(in: menu) {
            // Selection menu (Copy etc.): offer "Add Comment…" at the top.
            let item = NSMenuItem(title: "Add Comment\u{2026}",
                                  action: #selector(postAddComment),
                                  keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: "plus.bubble",
                                 accessibilityDescription: nil)
            menu.insertItem(item, at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        super.willOpenMenu(menu, with: event)
    }

    /// The opened document's URL, via the AppKit window controller.
    private var documentURL: URL? {
        (window?.windowController as? DocumentWindowController)?.fileURL
    }

    /// "Add Comment…" applies only to a text selection in the rendered (Up-mode)
    /// view of a writable document. A WKWebView selection menu carries a Copy
    /// item (`WKMenuItemIdentifierCopy`); its presence is our selection signal.
    private func canAddComment(in menu: NSMenu) -> Bool {
        guard AppState.shared.modeInActiveTab == .up,
              let url = documentURL, !url.isBundleResource else { return false }
        return menu.items.contains {
            $0.identifier?.rawValue == "WKMenuItemIdentifierCopy"
        }
    }

    /// Reveals the Comments column and opens a compose for the selection, via the
    /// window controller so the per-window visibility state is set (otherwise the
    /// next class-sync would tear the column down).
    @objc private func postAddComment() {
        sendActionToController(#selector(DocumentWindowController.addComment(_:)))
    }

    private func buildOpenInSubmenu() -> NSMenu {
        let model = OpenInMenuModel.shared
        model.refresh()
        let submenu = NSMenu(title: "Open In…")
        if let configured = model.configured {
            submenu.addItem(handlerItem(
                handler: configured,
                title: "\(configured.displayName)  (default)"
            ))
            submenu.addItem(.separator())
        }
        for handler in model.others {
            submenu.addItem(handlerItem(handler: handler, title: handler.displayName))
        }
        submenu.addItem(.separator())
        let choose = NSMenuItem(
            title: "Choose…",
            action: #selector(postChooseEditor),
            keyEquivalent: ""
        )
        choose.target = self
        submenu.addItem(choose)
        return submenu
    }

    private func handlerItem(handler: RegisteredMarkdownHandler, title: String) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(postLaunchEditor(_:)),
            keyEquivalent: ""
        )
        item.image = handler.icon
        item.representedObject = handler
        item.target = self
        return item
    }

    private func sendActionToController(_ action: Selector) {
        guard let controller = window?.windowController else { return }
        window?.makeKeyAndOrderFront(nil)
        NSApp.sendAction(action, to: controller, from: self)
    }

    @objc private func postOpenInBrowser() {
        sendActionToController(#selector(DocumentWindowController.openInBrowser(_:)))
    }

    @objc private func postPrintDocument() {
        sendActionToController(#selector(DocumentWindowController.printCurrentDocument(_:)))
    }

    @objc private func postReloadDocument() {
        sendActionToController(#selector(DocumentWindowController.reloadDocument(_:)))
    }

    @objc private func postLaunchEditor(_ sender: NSMenuItem) {
        guard let handler = sender.representedObject as? RegisteredMarkdownHandler else { return }
        window?.makeKeyAndOrderFront(nil)
        OpenInMenuModel.shared.launch(with: handler)
    }

    @objc private func postChooseEditor() {
        window?.makeKeyAndOrderFront(nil)
        OpenInMenuModel.shared.chooseEditor()
    }
}

// MARK: - WebView (NSViewRepresentable)

struct WebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let contentID: String
    var mode: Mode = .up
    var theme: Theme = .earthy
    var bodyClasses: Set<String> = []
    var zoomLevel: Double = 1.0
    var searchQuery: SearchQuery?
    var scrollTarget: ScrollTarget?
    var changeScrollTarget: ChangeScrollTarget?
    var reloadID: UUID?
    var printID: UUID?
    var addCommentID: UUID?
    var extensions: Set<String> = []
    var footnoteHTML: [String: String] = [:]
    var comments: [Comment] = []
    /// DOM-derived locators for just-added comments, keyed by label, merged into
    /// the `setData` payload so a live marker insert lands byte-exactly.
    var commentLocators: [String: CommentLocator] = [:]
    /// A column edit (add/reply/edit/delete) to write through `CommentController`.
    var onCommentSubmit: ((CommentSubmission) -> Void)?
    /// Whether the in-column compose box currently owns the keyboard.
    var onComposing: ((Bool) -> Void)?
    /// Whether the rendered view holds a commentable selection (enables the
    /// toolbar "Comment" button).
    var onCommentableSelection: ((Bool) -> Void)?
    var onSearchResult: ((MatchInfo?) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(),
                                   forURLScheme: "mud-asset")

        // Inject JS files; they auto-detect context via DOM.
        // Mermaid is injected on demand via evaluateJavaScript.
        let scripts = [
            HTMLTemplate.mudJS,
            HTMLTemplate.mudChangesJS,
            HTMLTemplate.mudUpJS,
            HTMLTemplate.mudDownJS,
            HTMLTemplate.mudCommentsJS,
            HTMLTemplate.mudCommentsEditJS,
        ]
        for source in scripts {
            let script = WKUserScript(
                source: source,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            config.userContentController.addUserScript(script)
        }

        config.userContentController.add(context.coordinator, name: "mudOpen")
        config.userContentController.add(context.coordinator, name: "mudFootnote")
        config.userContentController.add(context.coordinator, name: "mudCommentSubmit")
        config.userContentController.add(context.coordinator, name: "mudComposing")
        config.userContentController.add(context.coordinator, name: "mudSelection")

        let webView = MudWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        #if DEBUG
        webView.isInspectable = true
        #endif
        webView.alphaValue = 0

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onSearchResult = onSearchResult
        context.coordinator.footnoteHTML = footnoteHTML
        context.coordinator.comments = comments
        context.coordinator.commentLocators = commentLocators
        context.coordinator.onCommentSubmit = onCommentSubmit
        context.coordinator.onComposing = onComposing
        context.coordinator.onCommentableSelection = onCommentableSelection
        context.coordinator.commentTheme = theme.rawValue

        // Handle search
        if let query = searchQuery,
           context.coordinator.lastSearchID != query.id,
           !query.text.isEmpty {
            context.coordinator.lastSearchID = query.id
            let escaped = query.text
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let js: String
            switch query.origin {
            case .top:
                js = "Mud.findFromTop('\(escaped)')"
            case .refine:
                js = "Mud.findRefine('\(escaped)')"
            case .advance:
                let dir = query.direction == .backward ? "backward" : "forward"
                js = "Mud.findAdvance('\(escaped)', '\(dir)')"
            }
            let callback = onSearchResult
            webView.evaluateJavaScript(js) { result, _ in
                let info = Self.parseMatchInfo(result)
                DispatchQueue.main.async {
                    callback?(info)
                }
            }
        } else if searchQuery == nil && context.coordinator.lastSearchID != nil {
            context.coordinator.lastSearchID = nil
            webView.evaluateJavaScript("Mud.findClear()")
        }

        // Handle outline scroll target
        if let target = scrollTarget,
           context.coordinator.lastScrollTargetID != target.id {
            context.coordinator.lastScrollTargetID = target.id
            let js: String
            if mode == .down {
                js = "Mud.scrollToLine(\(target.heading.sourceLine))"
            } else {
                let escaped = target.heading.id
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                js = "Mud.scrollToHeading('\(escaped)')"
            }
            webView.evaluateJavaScript(js)
        }

        // Handle change scroll target
        if let target = changeScrollTarget,
           context.coordinator.lastChangeScrollTargetID != target.id {
            context.coordinator.lastChangeScrollTargetID = target.id
            let idsJSON = "[" + target.changeIDs.map { id in
                let escaped = id
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")
                return "'\(escaped)'"
            }.joined(separator: ",") + "]"
            webView.evaluateJavaScript("Mud.scrollToChange(\(idsJSON))")
        }

        // Handle print via WKWebView.printOperation(with:)
        if let printID = printID,
           context.coordinator.lastPrintID != printID {
            context.coordinator.lastPrintID = printID
            let printOp = webView.printOperation(with: .shared)
            printOp.view?.frame = webView.bounds
            if let window = webView.window {
                printOp.runModal(
                    for: window,
                    delegate: nil,
                    didRun: nil,
                    contextInfo: nil
                )
            }
        }

        // Handle the toolbar "Comment" action: open a compose box on the current
        // selection. The JS reveals the column itself (native has persisted the
        // toggle), so this works even when the column was hidden.
        if let addCommentID = addCommentID,
           context.coordinator.lastAddCommentID != addCommentID {
            context.coordinator.lastAddCommentID = addCommentID
            webView.evaluateJavaScript(
                "window.Mud && Mud.comments && Mud.comments.addFromSelection"
                + " && Mud.comments.addFromSelection()")
        }

        // Reload content if contentID, mode, or reloadID changed
        let modeChanged = context.coordinator.lastMode != mode
        let contentChanged = context.coordinator.lastContentID != contentID
        let reloadForced = reloadID != nil && context.coordinator.lastReloadID != reloadID

        if !modeChanged && !contentChanged && !reloadForced {
            // Only theme/zoom/classes changed — apply without reload.
            context.coordinator.applyTheme(to: webView, theme: theme)
            context.coordinator.applyBodyClasses(to: webView, classes: bodyClasses)
            context.coordinator.applyZoom(to: webView, level: zoomLevel)
            // A comment add/remove changes the comment set but not the (Up-mode
            // comment-invariant) contentID, so no reload fires. Re-push the
            // comment data so `mud-comments.js` inserts/removes the marker and
            // re-anchors the highlight in place.
            if context.coordinator.lastCommentSignature
                != Coordinator.commentSignature(comments) {
                context.coordinator.applyComments(to: webView)
            }
            return
        }

        // Save scroll fraction before loading new content
        context.coordinator.saveScrollPosition(from: webView)
        context.coordinator.lastContentID = contentID
        context.coordinator.lastMode = mode
        context.coordinator.lastReloadID = reloadID
        context.coordinator.activeExtensions = extensions.compactMap {
                RenderExtension.registry[$0]
            }
            .filter { html.contains($0.marker) }
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL)
    }

    static func parseMatchInfo(_ result: Any?) -> MatchInfo? {
        guard let dict = result as? [String: Any],
              let total = dict["total"] as? Int,
              let current = dict["current"] as? Int else {
            return nil
        }
        return MatchInfo(current: current, total: total)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastContentID: String?
        var lastMode: Mode?
        var lastSearchID: UUID?
        var lastScrollTargetID: UUID?
        var lastChangeScrollTargetID: UUID?
        var lastPrintID: UUID?
        var lastReloadID: UUID?
        var lastAddCommentID: UUID?
        var activeExtensions: [RenderExtension] = []
        var onSearchResult: ((MatchInfo?) -> Void)?
        var footnoteHTML: [String: String] = [:]
        var comments: [Comment] = []
        var commentLocators: [String: CommentLocator] = [:]
        /// Signature (label + quotation per comment) of the last `setData` push,
        /// so a comment-only change re-anchors without a reload.
        var lastCommentSignature: [String] = []
        var onCommentSubmit: ((CommentSubmission) -> Void)?
        var onComposing: ((Bool) -> Void)?
        var onCommentableSelection: ((Bool) -> Void)?
        var commentTheme: String = "earthy"
        weak var webView: WKWebView?
        private var savedFraction: CGFloat?
        private let baseURL: URL?
        private lazy var footnotePopover = FootnotePopoverController()

        init(baseURL: URL?) {
            self.baseURL = baseURL
        }

        func saveScrollPosition(from webView: WKWebView) {
            webView.evaluateJavaScript("Mud.getScrollFraction()") { [weak self] result, _ in
                if let fraction = result as? CGFloat {
                    self?.savedFraction = fraction
                }
            }
        }

        func restoreScrollPosition(to webView: WKWebView) {
            guard let fraction = savedFraction, fraction > 0 else { return }
            webView.evaluateJavaScript("Mud.setScrollFraction(\(fraction))")
            savedFraction = nil
        }

        func applyTheme(to webView: WKWebView, theme: Theme) {
            let css = HTMLTemplate.themeCSS(for: theme.rawValue)
            let escaped = css
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
            webView.evaluateJavaScript("Mud.setTheme('\(escaped)')")
        }

        func applyZoom(to webView: WKWebView, level: Double) {
            webView.evaluateJavaScript("Mud.setZoom(\(level))")
        }

        func applyBodyClasses(to webView: WKWebView, classes: Set<String>) {
            // The persisted view-toggle classes, plus `is-comments-column`
            // (per-window state) and `comment-return-saves` (a preference) —
            // neither a `ViewToggle`, but applied the same way.
            let names = ViewToggle.allCases.map(\.className)
                + ["is-comments-column", "comment-return-saves"]
            for name in names {
                let on = classes.contains(name)
                webView.evaluateJavaScript("Mud.setClass('\(name)', \(on))")
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastSearchID = nil
            restoreScrollPosition(to: webView)
            applyComments(to: webView)
            for ext in activeExtensions {
                injectExtension(ext, into: webView)
            }
            if webView.alphaValue == 0 {
                webView.alphaValue = 1
            }
        }

        /// A content fingerprint of a comment list — the change unit for the
        /// no-reload column refresh. Covers label, quotation, and every message
        /// (author, time, body) so a reply or edit re-pushes; an unrelated body
        /// edit elsewhere keeps it stable and does no DOM work.
        static func commentSignature(_ comments: [Comment]) -> [String] {
            comments.map { comment in
                let messages = comment.messages.map {
                    "\($0.author ?? "")\u{2}\($0.created?.timeIntervalSince1970 ?? 0)\u{2}\($0.body)"
                }.joined(separator: "\u{3}")
                return "\(comment.label)\u{1}\(comment.quotation ?? "")\u{1}\(messages)"
            }
        }

        /// Hands the parsed comments to `mud-comments.js`, which inserts/removes
        /// the `[⋯]` markers and (re-)anchors the hover-revealed highlights. Each
        /// entry carries its quotation plus, for a just-added comment, the
        /// DOM-derived locator so the live marker lands byte-exactly.
        fileprivate func applyComments(to webView: WKWebView) {
            lastCommentSignature = Self.commentSignature(comments)
            struct Payload: Encodable {
                let label: String
                let quotation: String
                let html: String
                let blockText: String?
                let offset: Int?
                let occurrence: Int?
            }
            var opts = RenderOptions()
            opts.baseURL = baseURL
            opts.theme = commentTheme
            // The column projects from this rebuilt section and Edit reads each
            // message's raw Markdown off its data-mud-body — emitted only in
            // interactive mode. Without this the live re-render drops it.
            opts.commentMode = .interactive
            let payload = comments.map { comment -> Payload in
                let locator = commentLocators[comment.label]
                return Payload(
                    label: comment.label, quotation: comment.quotation ?? "",
                    html: MudCore.renderCommentItem(
                        comment, options: opts,
                        resolveImageSource: DocumentContentView.mudAssetResolver),
                    blockText: locator?.blockText, offset: locator?.offset,
                    occurrence: locator?.occurrence)
            }
            guard let data = try? JSONEncoder().encode(payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            // `Mud.comments` exists only in Up mode (mud-comments.js early-returns
            // in Down mode), so guard before calling.
            webView.evaluateJavaScript(
                "window.Mud && Mud.comments && Mud.comments.setData(\(json))")
        }

        private func injectExtension(_ ext: RenderExtension, into webView: WKWebView) {
            let scripts = ext.runtimeJS()
            injectSequentially(scripts, into: webView)
        }

        private func injectSequentially(_ scripts: [String], into webView: WKWebView) {
            guard let first = scripts.first else { return }
            webView.evaluateJavaScript(first) { _, _ in
                self.injectSequentially(Array(scripts.dropFirst()), into: webView)
            }
        }

        // MARK: WKScriptMessageHandler — link routing and footnotes from JS

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            switch message.name {
            case "mudOpen":
                if let urlString = message.body as? String,
                   let url = URL(string: urlString) {
                    openURL(url)
                }
            case "mudFootnote":
                presentFootnote(message.body)
            case "mudCommentSubmit":
                handleCommentSubmit(message.body)
            case "mudComposing":
                onComposing?((message.body as? Bool) ?? false)
            case "mudSelection":
                onCommentableSelection?((message.body as? Bool) ?? false)
            default:
                break
            }
        }

        /// Parses the `mudCommentSubmit` payload into a `CommentSubmission` and
        /// hands it to the write path. `.add` carries `quotation` + a `locator`;
        /// reply/edit/delete carry only `label`.
        private func handleCommentSubmit(_ body: Any) {
            guard let dict = body as? [String: Any],
                  let actionRaw = dict["action"] as? String,
                  let action = CommentSubmission.Action(rawValue: actionRaw)
            else { return }
            var draft: CommentDraft?
            if action == .add,
               let quotation = dict["quotation"] as? String,
               let locator = dict["locator"] as? [String: Any],
               let blockText = locator["blockText"] as? String,
               let offset = locator["offset"] as? Int {
                draft = CommentDraft(
                    quotation: quotation, blockText: blockText,
                    offsetInBlock: offset,
                    occurrence: locator["occurrence"] as? Int ?? 0)
            }
            onCommentSubmit?(CommentSubmission(
                action: action,
                label: dict["label"] as? String,
                body: dict["body"] as? String,
                draft: draft))
        }

        /// Converts a JS `{x,y,width,height}` rect (top-left origin, viewport
        /// coordinates in the visual/zoomed space, which map 1:1 to AppKit
        /// points) into an `NSRect` in the WebView's AppKit space.
        private func anchorRect(
            from rectDict: [String: Any], in webView: WKWebView
        ) -> NSRect {
            func value(_ key: String) -> CGFloat {
                CGFloat((rectDict[key] as? Double) ?? 0)
            }
            let x = value("x"), y = value("y")
            let w = value("width"), h = value("height")
            let appKitY = webView.isFlipped ? y : webView.bounds.height - (y + h)
            return NSRect(x: x, y: appKitY, width: w, height: h)
        }

        /// Routes a link: local `.md`/`.markdown` open a new Mud document;
        /// everything else goes to the system handler (browser, etc.).
        func openURL(_ url: URL) {
            let mdExtensions = ["md", "markdown"]
            if url.isFileURL, mdExtensions.contains(url.pathExtension.lowercased()) {
                NSDocumentController.shared.openDocument(
                    withContentsOf: url, display: true
                ) { _, _, _ in }
            } else {
                NSWorkspace.shared.open(url)
            }
        }

        /// Shows the footnote popover anchored at the clicked marker. `body` is
        /// the JS payload `{label, num, rect:{x,y,width,height}}` where the rect
        /// is in visual (zoomed) viewport coordinates with a top-left origin.
        private func presentFootnote(_ body: Any) {
            guard let dict = body as? [String: Any],
                  let label = dict["label"] as? String,
                  let rectDict = dict["rect"] as? [String: Any],
                  let html = footnoteHTML[label.lowercased()],
                  let webView = webView else { return }

            footnotePopover.show(
                html: html, baseURL: baseURL,
                relativeTo: anchorRect(from: rectDict, in: webView), of: webView,
                onOpenURL: { [weak self] url in self?.openURL(url) })
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Allow initial page load and same-document navigation
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            // Allow anchor scrolls
            if let url = navigationAction.request.url,
               url.fragment != nil, url.path == baseURL?.path {
                decisionHandler(.allow)
                return
            }

            // Everything else is handled by the JS click interceptor;
            // cancel as a safety net.
            decisionHandler(.cancel)
        }
    }
}
