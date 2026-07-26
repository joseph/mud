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

    /// The zoom the loaded document currently carries, so a pane resize that
    /// doesn't cross the breakpoint costs nothing.
    private var appliedZoom: Double = 1.0

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

        var options = RenderOptions(snapshot: snapshot, baseURL: url)

        // A preview renders at a locked zoom, never the app's Up-mode zoom
        // preference that the shared snapshot mapping supplies. Zoom In / Out
        // is a command a reader gives one document window, and a preview pane
        // offers no way to give it back: inheriting it would leave every
        // preview at 200% with nothing on screen to say why. The pane's width
        // decides instead (see `zoom(paneWidth:)`).
        options.zoomLevel = Self.zoom(paneWidth: view.bounds.width)
        appliedZoom = options.zoomLevel
        // Tells mud-narrow.css that this document's type has already been
        // scaled for the pane, so the Tight tier leaves the root font-size
        // alone rather than shrinking it a second time. Set on every preview
        // rather than only a currently-scaled one: `lockZoom` changes the zoom
        // on resize without re-rendering, so a class baked in per value would
        // go stale the moment the pane crossed the breakpoint.
        options.htmlClasses.insert("is-zoom-locked")

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

    // MARK: Zoom

    /// The zoom a preview pane `paneWidth` points wide renders at: full size
    /// above the Compact tier, 80% at or below it.
    ///
    /// `Layout.compactBreakpoint` is where `mud-narrow.css` starts tightening
    /// the layout, so the two steps land together — a pane narrow enough to
    /// want tighter geometry is narrow enough to want smaller type as well,
    /// and the extra fifth is what buys back the line length a Finder column
    /// pane can't otherwise afford. Nothing between the two values: a preview
    /// is a fixed rendering of a file, not a view a reader is adjusting, so it
    /// should look the same in every pane of a given size.
    private static func zoom(paneWidth: CGFloat) -> Double {
        paneWidth <= CGFloat(Layout.compactBreakpoint) ? 0.8 : 1.0
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Only a resize that crosses the breakpoint is worth a script.
        if Self.zoom(paneWidth: view.bounds.width) != appliedZoom { lockZoom() }
    }

    /// Rewrites the document's zoom to match the current pane width.
    ///
    /// The zoom ships as an inline `zoom` style on `<html>` (`HTMLDocument`),
    /// baked in at render time; this rewrites that same style rather than
    /// re-rendering the file. The width is measured here in AppKit points
    /// rather than asked of the page, so the decision can't feed back into
    /// itself — a pane is never a different number of points because the
    /// document it holds scaled.
    private func lockZoom() {
        let zoom = Self.zoom(paneWidth: view.bounds.width)
        appliedZoom = zoom
        webView.evaluateJavaScript(
            "document.documentElement.style.zoom = '\(zoom)'"
        ) { _, error in
            if let error {
                log.error(
                    "zoom lock failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    // MARK: WKNavigationDelegate

    /// Re-lock the zoom against the pane's final width. The pane can be sized
    /// between the render and the load finishing, and a script evaluated at
    /// that point lands on the outgoing document and is lost with it, so this
    /// writes unconditionally rather than trusting `appliedZoom`.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        lockZoom()
    }

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
