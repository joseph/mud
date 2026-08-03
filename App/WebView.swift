import Combine
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
        } else if isSelectionMenu(menu) {
            menu.insertItem(addCommentItem(), at: 0)
            menu.insertItem(.separator(), at: 1)
        }
        super.willOpenMenu(menu, with: event)
    }

    /// Whether this is the menu for a text selection. A WKWebView selection
    /// menu carries a Copy item (`WKMenuItemIdentifierCopy`); its presence is
    /// what tells us the menu belongs to selected text rather than to some
    /// other page element.
    private func isSelectionMenu(_ menu: NSMenu) -> Bool {
        menu.items.contains {
            $0.identifier?.rawValue == "WKMenuItemIdentifierCopy"
        }
    }

    /// "Add Comment…" for the top of a selection menu. Like the toolbar button
    /// and the Edit menu item, it is always shown and live only when the
    /// selection can actually take a comment — Up mode, a writable document,
    /// and text that maps back to a source byte (so not inside a code block, a
    /// Mermaid diagram, math, or a deletion overlay).
    /// `DocumentWindowController.canAddComment(for:)` holds that rule; this
    /// window's own controller answers it, because a control-click opens the
    /// menu without making the window key.
    ///
    /// A disabled item gets no action: an item with a nil action greys out
    /// under menu auto-enabling, and `isEnabled` covers the menu that has
    /// auto-enabling off. Either way it stays visible, so the reader sees that
    /// commenting exists here and just doesn't apply to this selection.
    private func addCommentItem() -> NSMenuItem {
        let enabled = (window?.windowController as? DocumentWindowController)?
            .canAddComment() ?? false
        let item = NSMenuItem(title: "Add Comment\u{2026}",
                              action: enabled ? #selector(postAddComment) : nil,
                              keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        item.image = NSImage(systemSymbolName: "plus.message",
                             accessibilityDescription: nil)
        return item
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
    /// The Comments Column's inner content width, pushed to the page like zoom
    /// (no reload). The drag handle reports changes back via `onColumnWidthChange`.
    var commentColumnWidth: Double = 300
    var searchQuery: SearchQuery?
    /// The window's command channel: one-shot page actions (print, scroll,
    /// compose acknowledgements, …) sent by menu/toolbar/sidebar handlers.
    /// The coordinator subscribes in `makeNSView` and runs each command as it
    /// arrives, so `updateNSView` diffs only the declarative state below.
    let commands: PassthroughSubject<WebCommand, Never>
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
    /// The Comments Column was resized via its drag handle (the applied width,
    /// already clamped to 200–400 by the page). Persisted by the caller.
    var onColumnWidthChange: ((Double) -> Void)?
    /// A comment marker was clicked. The page waits on the caller to make room
    /// for the column, persist the per-window visibility toggle, and send the
    /// comment back over `.revealComment`.
    var onRevealColumn: ((String) -> Void)?
    var onSearchResult: ((MatchInfo?) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        // Inject JS files; they auto-detect context via DOM.
        // Mermaid is injected on demand via the bridge.
        //
        // Each file builds `window.Mud` with a defensive merge, so this order is
        // not load-bearing for the namespace existing. It still matters for two
        // runtime relationships:
        //   - mud.js is first: it seeds the shared `Mud.*` helpers (setClass,
        //     scroll, zoom) that the later files call while the page runs.
        //   - mud-comments-edit.js (write side) follows mud-comments.js (read
        //     side): it fills in the read side's hooks and API slots, so the
        //     read side must have published `Mud.comments` first. The read-side
        //     string also carries the shared `Mud.commentAnchor` primitives
        //     (mudCommentsJS concatenates mud-comment-anchor.js ahead of it),
        //     which the write side depends on.
        let config = MudJSBridge.makeConfiguration(scripts: [
            HTMLTemplate.mudJS,
            HTMLTemplate.mudChangesJS,
            HTMLTemplate.mudUpJS,
            HTMLTemplate.mudDownJS,
            HTMLTemplate.mudCommentsJS,
            HTMLTemplate.mudCommentsEditJS,
        ])
        context.coordinator.bridge.register(
            MudJSBridge.Handler.allCases, on: config.userContentController)

        let webView = MudWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Safari-style trackpad pinch-zoom: a viewport magnification, separate
        // from and stacking on top of the CSS `zoom` the toolbar/menu drive.
        // Transient (not persisted); "Actual Size" resets it via the
        // `.resetMagnification` command.
        webView.allowsMagnification = true
        context.coordinator.webView = webView
        context.coordinator.bridge.webView = webView
        context.coordinator.subscribe(to: commands)
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
        context.coordinator.onColumnWidthChange = onColumnWidthChange
        context.coordinator.onRevealColumn = onRevealColumn
        context.coordinator.commentColumnWidth = commentColumnWidth
        context.coordinator.commentTheme = theme

        // Handle search. The coordinator keeps the current query so didFinish
        // can re-apply it to a freshly loaded page.
        context.coordinator.currentSearchQuery = searchQuery
        if let query = searchQuery,
           context.coordinator.lastSearchID != query.id,
           !query.text.isEmpty {
            context.coordinator.runSearch(query)
        } else if searchQuery == nil && context.coordinator.lastSearchID != nil {
            context.coordinator.lastSearchID = nil
            context.coordinator.bridge.call("findClear")
        }

        // Reload content if the contentID or mode changed. (A forced reload —
        // Cmd+R with unchanged text — arrives as a new contentID: the model
        // appends its load token to it.)
        let modeChanged = context.coordinator.lastMode != mode
        let contentChanged = context.coordinator.lastContentID != contentID

        if !modeChanged && !contentChanged {
            // Only theme/zoom/classes/width changed — apply without reload.
            context.coordinator.applyTheme(theme)
            context.coordinator.applyBodyClasses(bodyClasses)
            context.coordinator.applyZoom(zoomLevel)
            if context.coordinator.lastCommentColumnWidth != commentColumnWidth {
                context.coordinator.applyCommentColumnWidth(commentColumnWidth)
            }
            // A comment add/remove changes the comment set but not the (Up-mode
            // comment-invariant) contentID, so no reload fires. Re-push the
            // comment data so `mud-comments.js` inserts/removes the marker and
            // re-anchors the highlight in place.
            if context.coordinator.lastCommentSignature
                != Coordinator.commentSignature(comments) {
                context.coordinator.applyComments()
            }
            return
        }

        // Save scroll fraction before loading new content
        context.coordinator.saveScrollPosition()
        context.coordinator.lastContentID = contentID
        context.coordinator.lastMode = mode
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

    class Coordinator: NSObject, WKNavigationDelegate {
        /// The Swift ↔ page JS bridge: outbound `Mud.*` calls and the typed
        /// inbound messages, routed to the callbacks below via `handle(_:)`.
        let bridge = MudJSBridge()
        var lastContentID: String?
        var lastMode: Mode?
        var lastSearchID: UUID?
        /// The active find query, mirrored from `updateNSView` so `didFinish`
        /// can re-apply it to a freshly loaded page (a reload discards the
        /// DOM highlights).
        var currentSearchQuery: SearchQuery?
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
        var onColumnWidthChange: ((Double) -> Void)?
        var onRevealColumn: ((String) -> Void)?
        /// The width last requested by updateNSView; `applyCommentColumnWidth`
        /// pushes only on a change, and `didFinish` reapplies it after a reload.
        var commentColumnWidth: Double = 300
        var lastCommentColumnWidth: Double?
        var commentTheme: Theme = .earthy
        /// The headings the page currently has folded, by slug. A reload
        /// discards the page's own copy, so the set is kept here — alongside
        /// the saved scroll position, the other page fact that has to survive
        /// one — and replayed in `didFinish`. Per window and never persisted:
        /// closing the window forgets the folds. The page is the only author;
        /// it reports the whole set over `mudFolds` after every change.
        var foldedHeadings: [String] = []
        weak var webView: WKWebView?
        private var savedFraction: CGFloat?
        private let baseURL: URL?
        private lazy var footnotePopover = FootnotePopoverController()
        private var commandSubscription: AnyCancellable?

        init(baseURL: URL?) {
            self.baseURL = baseURL
            super.init()
            bridge.onMessage = { [weak self] message in
                self?.handle(message)
            }
        }

        /// Routes a decoded page message to its consumer callback.
        private func handle(_ message: MudJSMessage) {
            switch message {
            case .open(let url):
                openURL(url)
            case .footnoteClick(let click):
                presentFootnote(click)
            case .commentSubmit(let submission):
                onCommentSubmit?(submission)
            case .composing(let composing):
                onComposing?(composing)
            case .commentableSelection(let has):
                onCommentableSelection?(has)
            case .columnWidth(let width):
                onColumnWidthChange?(width)
            case .revealColumn(let label):
                onRevealColumn?(label)
            case .folds(let slugs):
                foldedHeadings = slugs
            }
        }

        // MARK: Command channel

        func subscribe(to commands: PassthroughSubject<WebCommand, Never>) {
            commandSubscription = commands
                .sink { [weak self] command in self?.handle(command) }
        }

        /// Runs a one-shot page command. Commands arrive from menu, toolbar,
        /// and sidebar handlers — outside SwiftUI's update pass, so the print
        /// modal's nested run loop can't stall a view update.
        private func handle(_ command: WebCommand) {
            guard let webView else { return }
            switch command {
            case .print:
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
            case .resetMagnification:
                // The per-mode CSS zoom is reset separately via the zoomLevel
                // path; pinch magnification stacks on top of it, so a true
                // reset clears both.
                webView.setMagnification(1, centeredAt: .zero)
            case .addCommentFromSelection:
                // The JS reveals the column itself (native has persisted the
                // toggle), so this works even when the column was hidden.
                bridge.call("comments.addFromSelection")
            case .resolveSubmission(let success):
                bridge.call("comments.resolveSubmission", success)
            case .scrollToHeading(let heading):
                // Keyed off the loaded page's mode (`lastMode`), which is what
                // the scroll JS must match.
                if lastMode == .down {
                    bridge.call("scrollToLine", heading.sourceLine)
                } else {
                    bridge.call("scrollToHeading", heading.id)
                }
            case .scrollToChanges(let ids):
                bridge.call("scrollToChange", ids)
            case .foldAllHeadings:
                bridge.call("folds.foldAll")
            case .unfoldAllHeadings:
                bridge.call("folds.unfoldAll")
            case .revealComment(let label):
                bridge.call("comments.openToComment", label)
            case .scrollToComments(let label):
                bridge.call("comments.scrollToSection", label)
            }
        }

        /// Runs a find query in the page and reports the match counts back.
        /// All three origins rebuild highlights when the page has none
        /// (a fresh load), so this doubles as the after-reload re-apply.
        func runSearch(_ query: SearchQuery) {
            lastSearchID = query.id
            let callback = onSearchResult
            let report: (Any?) -> Void = { result in
                callback?(WebView.parseMatchInfo(result))
            }
            switch query.origin {
            case .top:
                bridge.call("findFromTop", query.text, completion: report)
            case .refine:
                bridge.call("findRefine", query.text, completion: report)
            case .advance:
                let direction = query.direction == .backward
                    ? "backward" : "forward"
                bridge.call("findAdvance", query.text, direction,
                            completion: report)
            }
        }

        func saveScrollPosition() {
            bridge.call("getScrollFraction", completion: { [weak self] result in
                if let fraction = result as? CGFloat {
                    self?.savedFraction = fraction
                }
            })
        }

        func restoreScrollPosition() {
            guard let fraction = savedFraction, fraction > 0 else { return }
            bridge.call("setScrollFraction", fraction)
            savedFraction = nil
        }

        func applyTheme(_ theme: Theme) {
            bridge.call("setTheme", HTMLTemplate.themeCSS(for: theme))
        }

        func applyZoom(_ level: Double) {
            bridge.call("setZoom", level)
        }

        /// Push the persisted Comments Column width to the page. A fresh load
        /// resets the column to its CSS default, so `didFinish` always reapplies;
        /// the no-reload path applies only on a change. The page re-clamps.
        func applyCommentColumnWidth(_ width: Double) {
            lastCommentColumnWidth = width
            bridge.call("comments.setColumnWidth", width)
        }

        func applyBodyClasses(_ classes: Set<String>) {
            // The persisted view-toggle classes, plus `is-comments-column`
            // (per-window state) and the `comment-return-saves` /
            // `show-comment-markers` preferences — none a `ViewToggle`, but
            // applied the same way.
            let names = ViewToggle.allCases.map(\.className)
                + ["is-comments-column", "comment-return-saves",
                   "show-comment-markers"]
            for name in names {
                bridge.call("setClass", name, classes.contains(name))
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // A fresh page has no find highlights: re-run the active query
            // here, deterministically, so matches and the match counter
            // survive a reload. (Nil-ing `lastSearchID` and letting the next
            // `updateNSView` re-apply is not enough — after an external-edit
            // reload no further SwiftUI update may come.)
            if let query = currentSearchQuery, !query.text.isEmpty {
                runSearch(query)
            } else {
                lastSearchID = nil
            }
            // A fresh page starts unfolded; put back the folds this window had.
            // No-ops in Down mode, where `Mud.folds` doesn't exist. This has to
            // come before the scroll restore: the saved fraction was measured
            // against the folded document's height, and `setScrollFraction`
            // multiplies it by the height it finds. Restore first and the page
            // shrinks under the reader.
            if !foldedHeadings.isEmpty {
                bridge.call("folds.apply", foldedHeadings)
            }
            restoreScrollPosition()
            applyComments()
            applyCommentColumnWidth(commentColumnWidth)
            for ext in activeExtensions {
                injectExtension(ext)
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
        /// the `💬` markers and (re-)anchors the hover-revealed highlights. Each
        /// entry carries its quotation plus, for a just-added comment, the
        /// DOM-derived locator so the live marker lands byte-exactly.
        fileprivate func applyComments() {
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
                        resolveImageSource: DocumentModel.mudAssetResolver),
                    blockText: locator?.blockText, offset: locator?.offset,
                    occurrence: locator?.occurrence)
            }
            // `Mud.comments` exists only in Up mode (mud-comments.js
            // early-returns in Down mode), so the namespaced call no-ops there.
            bridge.call("comments.setData", payload)
        }

        private func injectExtension(_ ext: RenderExtension) {
            injectSequentially(ext.runtimeJS())
        }

        private func injectSequentially(_ scripts: [String]) {
            guard let first = scripts.first else { return }
            bridge.evaluate(first) { [weak self] _ in
                self?.injectSequentially(Array(scripts.dropFirst()))
            }
        }

        /// Converts the JS click rect (top-left origin, zoom-normalized CSS
        /// pixels) into an `NSRect` in the WebView's AppKit space.
        private func anchorRect(
            from rect: FootnoteClick.Rect, in webView: WKWebView
        ) -> NSRect {
            let appKitY = webView.isFlipped
                ? rect.y : webView.bounds.height - (rect.y + rect.height)
            return NSRect(x: rect.x, y: appKitY,
                          width: rect.width, height: rect.height)
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

        /// Shows the footnote popover anchored at the clicked marker.
        private func presentFootnote(_ click: FootnoteClick) {
            guard let html = footnoteHTML[click.label.lowercased()],
                  let webView = webView else { return }

            footnotePopover.show(
                html: html, baseURL: baseURL,
                relativeTo: anchorRect(from: click.rect, in: webView),
                of: webView,
                onOpenURL: { [weak self] url in self?.openURL(url) })
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(MudJSBridge.navigationPolicy(
                for: navigationAction, baseURL: baseURL))
        }
    }
}
