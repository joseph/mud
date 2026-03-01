import MudCore
import SwiftUI
import WebKit

// MARK: - WKWebView subclass (context menu)

class MudWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        if menu.items.count <= 2 {
            menu.removeAllItems()
            if !isSandboxed {
                menu.addItem(withTitle: "Open in Browser",
                             action: #selector(postOpenInBrowser),
                             keyEquivalent: "")
            }
            menu.addItem(withTitle: "Print\u{2026}",
                         action: #selector(postPrintDocument),
                         keyEquivalent: "")
            menu.addItem(withTitle: "Reload",
                         action: #selector(postReloadDocument),
                         keyEquivalent: "")
            for item in menu.items { item.target = self }
        }
        super.willOpenMenu(menu, with: event)
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
    var printID: UUID?
    var onSearchResult: ((MatchInfo?) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(),
                                   forURLScheme: "mud-asset")

        // Inject JS files; they auto-detect context via DOM.
        // Mermaid is injected on demand via evaluateJavaScript.
        let scripts = [
            HTMLTemplate.mudJS,
            HTMLTemplate.mudUpJS,
            HTMLTemplate.mudDownJS,
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

        // Reload content if contentID or mode changed
        let modeChanged = context.coordinator.lastMode != mode
        let contentChanged = context.coordinator.lastContentID != contentID

        if !modeChanged && !contentChanged {
            // Only theme/zoom/classes changed — apply without reload.
            context.coordinator.applyTheme(to: webView, theme: theme)
            context.coordinator.applyBodyClasses(to: webView, classes: bodyClasses)
            context.coordinator.applyZoom(to: webView, level: zoomLevel)
            return
        }

        // Save scroll fraction before loading new content
        context.coordinator.saveScrollPosition(from: webView)
        context.coordinator.lastContentID = contentID
        context.coordinator.lastMode = mode
        context.coordinator.needsMermaid = html.contains("language-mermaid")
        let statedHTML = Self.injectState(
            into: html,
            bodyClasses: bodyClasses,
            zoomLevel: zoomLevel
        )
        webView.loadHTMLString(statedHTML, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL)
    }

    /// Injects view state (body classes, zoom) into the `<html>` tag so the
    /// page renders correctly from first paint.
    static func injectState(
        into html: String,
        bodyClasses: Set<String>,
        zoomLevel: Double
    ) -> String {
        var attrs: [String] = []

        if !bodyClasses.isEmpty {
            let sorted = bodyClasses.sorted()
            attrs.append("class=\"\(sorted.joined(separator: " "))\"")
        }

        if zoomLevel != 1.0 {
            attrs.append("style=\"zoom: \(zoomLevel)\"")
        }

        if attrs.isEmpty { return html }
        let tag = "<html \(attrs.joined(separator: " "))>"
        return html.replacingOccurrences(of: "<html>", with: tag)
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
        var lastPrintID: UUID?
        var needsMermaid = false
        var onSearchResult: ((MatchInfo?) -> Void)?
        weak var webView: WKWebView?
        private var savedFraction: CGFloat?
        private let baseURL: URL?

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
            for toggle in ViewToggle.allCases {
                let on = classes.contains(toggle.className)
                webView.evaluateJavaScript(
                    "Mud.setBodyClass('\(toggle.className)', \(on))"
                )
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastSearchID = nil
            restoreScrollPosition(to: webView)
            if needsMermaid {
                injectMermaid(into: webView)
            }
            if webView.alphaValue == 0 {
                webView.alphaValue = 1
            }
        }

        private func injectMermaid(into webView: WKWebView) {
            webView.evaluateJavaScript(HTMLTemplate.mermaidJS) { _, _ in
                webView.evaluateJavaScript(HTMLTemplate.mermaidInitJS)
            }
        }

        // MARK: WKScriptMessageHandler — link routing from JS

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard message.name == "mudOpen",
                  let urlString = message.body as? String,
                  let url = URL(string: urlString) else { return }

            let mdExtensions = ["md", "markdown"]
            if url.isFileURL, mdExtensions.contains(url.pathExtension.lowercased()) {
                NSDocumentController.shared.openDocument(
                    withContentsOf: url, display: true
                ) { _, _, _ in }
            } else {
                NSWorkspace.shared.open(url)
            }
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
