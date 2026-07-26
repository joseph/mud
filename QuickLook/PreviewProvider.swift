import AppKit
import Foundation
import OSLog
import QuickLookUI
import WebKit
import MudCore
import MudPreferences

private let log = Logger(
    subsystem: "org.josephpearson.Mud.QuickLook",
    category: "preview"
)

/// View-based Quick Look preview. Subclasses `NSViewController` and conforms
/// to `QLPreviewingController` so Finder can embed the preview directly into
/// the column-view preview pane (data-based `QLPreviewProvider` extensions
/// are only invoked for the spacebar window).
///
/// `@objc(MudPreviewProvider)` registers a stable Objective-C class name so
/// `NSExtensionPrincipalClass` in Info.plist resolves without depending on
/// Swift module-name mangling.
@objc(MudPreviewProvider)
final class MudPreviewProvider: NSViewController, QLPreviewingController,
    WKNavigationDelegate
{
    private let webView = WKWebView(
        frame: NSRect(x: 0, y: 0, width: 800, height: 600)
    )
    private var previewURL: URL?

    override func loadView() {
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        log.info("preparePreviewOfFile: \(url.path, privacy: .public)")
        previewURL = url
        let source = try String(contentsOf: url, encoding: .utf8)

        let config: MudPreferences
        if let suite = UserDefaults(
            suiteName: MudPreferences.appGroupSuiteName
        ) {
            config = MudPreferences(defaults: suite)
        } else {
            log.error("app-group suite unavailable; falling back to defaults")
            config = MudPreferences(defaults: .standard)
        }
        let snapshot = config.snapshot(
            defaultEnabledExtensions: Set(RenderExtension.registry.keys)
        )

        let options = RenderOptions(snapshot: snapshot, baseURL: url)

        // The shared export recipe: standalone wrapping and images inlined as
        // data URIs. Comments render as the bottom Comments section, never the
        // column: a preview pane is not the reader's to widen or toggle, and a
        // column that needs 700px would otherwise appear or vanish with the
        // Finder window. `commentsColumn: false` keeps the column class and its
        // script out of the document entirely.
        let html = MudCore.exportDocument(
            source, mode: .up, options: options, includeComments: true,
            commentsColumn: false)

        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
    }

    // MARK: WKNavigationDelegate

    /// Block outbound navigation from the preview. The QL extension sandbox
    /// doesn't reliably permit opening URLs via `NSWorkspace.open` or
    /// `extensionContext.open`, so rather than half-working links we cancel
    /// them entirely. The initial HTML load and same-document fragment
    /// scrolls are allowed through.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .other {
            decisionHandler(.allow)
            return
        }

        if let url = navigationAction.request.url,
           url.fragment != nil,
           url.path == previewURL?.path
        {
            decisionHandler(.allow)
            return
        }

        decisionHandler(.cancel)
    }
}
