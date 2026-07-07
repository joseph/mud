import AppKit
import WebKit
import MudCore

/// Hosts a transient `NSPopover` containing a small `WKWebView` that renders a
/// footnote body as Up-mode Markdown HTML. Anchored at the clicked footnote
/// marker. Links inside the footnote route through the same `openURL` handler
/// the main view uses (external → browser, `.md` → new Mud document).
final class FootnotePopoverController: NSObject, WKNavigationDelegate,
                                      NSPopoverDelegate {
    private let popover = NSPopover()
    /// The bridge to the popover's page: `mudOpen` link routing inbound, the
    /// height measurement outbound. Same type the document view uses.
    private let bridge = MudJSBridge()
    private var webView: WKWebView!
    private var onOpenURL: ((URL) -> Void)?
    private var baseURL: URL?

    /// Local event monitor that dismisses the popover when the host content
    /// scrolls (matching Safari's Lookup popover). Installed while showing,
    /// removed in `popoverDidClose`.
    private var scrollMonitor: Any?
    /// The view the popover is anchored to, used to tell host-content scrolls
    /// (which should dismiss) from scrolls inside the popover (which shouldn't).
    private weak var anchorView: NSView?
    /// Accumulated host-content scroll distance since showing. Small jitters
    /// (trackpad rest, a nudge) shouldn't dismiss; only a deliberate scroll
    /// past `scrollDismissThreshold` does.
    private var accumulatedScroll: CGFloat = 0
    private static let scrollDismissThreshold: CGFloat = 16

    /// Fixed content width; height grows to fit the body, clamped.
    private static let width: CGFloat = 360
    private static let minHeight: CGFloat = 32
    private static let maxHeight: CGFloat = 400
    /// Padding added to the measured scroll height for breathing room.
    private static let heightPadding: CGFloat = 8

    override init() {
        super.init()

        let config = MudJSBridge.makeConfiguration(
            scripts: [HTMLTemplate.mudJS, HTMLTemplate.mudUpJS])
        bridge.register([.open], on: config.userContentController)
        bridge.onMessage = { [weak self] message in
            guard case .open(let url) = message else { return }
            self?.popover.performClose(nil)
            self?.onOpenURL?(url)
        }

        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.maxHeight),
            configuration: config)
        webView.navigationDelegate = self
        bridge.webView = webView
        #if DEBUG
        webView.isInspectable = true
        #endif

        let viewController = NSViewController()
        viewController.view = webView
        popover.contentViewController = viewController
        popover.behavior = .transient
        popover.delegate = self
        popover.contentSize = NSSize(width: Self.width, height: Self.minHeight)
    }

    /// Loads `html` and shows the popover anchored to `rect` within `view`.
    func show(
        html: String, baseURL: URL?,
        relativeTo rect: NSRect, of view: NSView,
        onOpenURL: @escaping (URL) -> Void
    ) {
        self.onOpenURL = onOpenURL
        self.anchorView = view
        self.baseURL = baseURL
        accumulatedScroll = 0
        popover.contentSize = NSSize(width: Self.width, height: Self.minHeight)
        webView.loadHTMLString(html, baseURL: baseURL)
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxY)
        installScrollMonitor()
    }

    /// Watches for scroll-wheel events while the popover is open and dismisses
    /// it when the host content scrolls — scrolls inside the popover's own body
    /// (a different window) are ignored so its content stays scrollable.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
            [weak self] event in
            guard let self else { return event }
            if event.window === self.anchorView?.window {
                self.accumulatedScroll += abs(event.scrollingDeltaY)
                    + abs(event.scrollingDeltaX)
                if self.accumulatedScroll > Self.scrollDismissThreshold {
                    self.popover.performClose(nil)
                }
            }
            return event
        }
    }

    // MARK: NSPopoverDelegate

    func popoverDidClose(_ notification: Notification) {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // `scrollHeight` is in unzoomed layout pixels; multiply by the document
        // zoom baked into the HTML so we get the visual height (points) the
        // content actually occupies.
        let measureHeight =
            "document.body.scrollHeight"
            + " * (parseFloat(document.documentElement.style.zoom) || 1)"
        bridge.evaluate(measureHeight) { [weak self] result in
            guard let self, let raw = result as? CGFloat else { return }
            let height = min(max(raw + Self.heightPadding, Self.minHeight),
                             Self.maxHeight)
            self.popover.contentSize = NSSize(width: Self.width, height: height)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(MudJSBridge.navigationPolicy(
            for: navigationAction, baseURL: baseURL))
    }
}
