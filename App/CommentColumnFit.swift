import AppKit
import MudCore

/// Whether a document window has room on screen for the Comments column, and
/// how to make room when it doesn't.
///
/// Below `Layout.compactBreakpoint` the column stands down (see
/// `mud-narrow.css`), taking the compose box, which sits inside it, with it. So
/// both commands that need the column — Add Comment and Show Comments — route
/// through `makeRoom` first: it widens the window on its own, asks before
/// giving up the sidebar, and reports back when neither is possible so the
/// caller can fall back to the bottom Comments section.
struct CommentColumnFit {
    private let window: NSWindow
    private let splitVC: NSSplitViewController

    /// Nil before the window's content is set up, which no user action can
    /// reach; the caller treats that as "no obstacle" and proceeds.
    init?(window: NSWindow?, splitVC: NSSplitViewController?) {
        guard let window, let splitVC else { return nil }
        self.window = window
        self.splitVC = splitVC
    }

    // MARK: - Geometry

    /// `Layout.compactBreakpoint` in points, for comparison against view widths.
    private static let breakpoint = CGFloat(Layout.compactBreakpoint)

    /// The content pane width `widen` aims for. Comfortably past the breakpoint
    /// rather than one point over it, so the document keeps a readable width
    /// beside the column and a small later drag doesn't tip the column straight
    /// back out.
    private static let targetWidth: CGFloat = 720

    /// The width of the split view's content item — the WebView's host, so this
    /// is the page's CSS viewport width, which is what `mud-narrow.css`'s media
    /// queries are measured against. (On macOS a CSS pixel is one point.)
    private var contentPaneWidth: CGFloat {
        splitVC.splitViewItems.last?.viewController.view.bounds.width ?? 0
    }

    /// Whether the Comments column — and with it the compose box — already has
    /// somewhere to sit.
    var hasRoom: Bool { contentPaneWidth > Self.breakpoint }

    // MARK: - Remedies

    /// What would actually give the Comments column room to open.
    enum Remedy: Equatable {
        /// Grow the window until the content pane is this wide.
        case widen(contentWidth: CGFloat)
        /// The window is already as wide as the screen; the sidebar is what's
        /// taking the room.
        case hideSidebar
        /// Neither would help — the display itself is too narrow.
        case unavailable
    }

    /// The geometry behind the choice, as a pure function of four widths so it
    /// can be tested as a truth table (`CommentColumnFitTests`).
    ///
    /// Widening wins whenever the screen has room for it, even if it can only
    /// reach part of the way to `targetWidth` — clearing the breakpoint is
    /// what matters. `windowChromeWidth` is everything outside the content pane
    /// (the sidebar plus the window's own borders), which keeps its width as
    /// the window grows. `expandedSidebarWidth` is nil when the sidebar is
    /// collapsed or absent.
    static func remedy(
        contentPaneWidth: CGFloat,
        windowChromeWidth: CGFloat,
        visibleScreenWidth: CGFloat,
        expandedSidebarWidth: CGFloat?
    ) -> Remedy {
        let widestHere = visibleScreenWidth - windowChromeWidth
        if widestHere > breakpoint {
            return .widen(contentWidth: min(targetWidth, widestHere))
        }
        // No room to grow. Collapsing the sidebar hands its whole thickness to
        // the content pane, which may be enough on its own.
        if let sidebarWidth = expandedSidebarWidth,
           contentPaneWidth + sidebarWidth > breakpoint {
            return .hideSidebar
        }
        return .unavailable
    }

    /// The remedy for this window's current geometry.
    private var remedy: Remedy {
        guard let screen = window.screen ?? NSScreen.main else {
            return .unavailable
        }
        let sidebar = splitVC.splitViewItems.first
        return Self.remedy(
            contentPaneWidth: contentPaneWidth,
            windowChromeWidth: window.frame.width - contentPaneWidth,
            visibleScreenWidth: screen.visibleFrame.width,
            expandedSidebarWidth: sidebar.flatMap { item -> CGFloat? in
                item.isCollapsed ? nil : item.viewController.view.bounds.width
            })
    }

    // MARK: - Making room

    /// Runs `show` with the Comments column able to fit, making room first if
    /// the window is too narrow.
    ///
    /// Widening happens on its own: the window is the app's to size, and asking
    /// permission to grow it for content the user just asked for is a step with
    /// no real decision in it. Collapsing the sidebar does ask, because which
    /// panes are open is the user's own layout choice, not a consequence of
    /// showing comments.
    ///
    /// `otherwise` runs when neither remedy is available or the user keeps the
    /// sidebar — the caller's cue to fall back to the bottom Comments section,
    /// which is what a narrow window shows in the column's place.
    func makeRoom(then show: @escaping () -> Void,
                  otherwise: @escaping () -> Void) {
        guard !hasRoom else {
            show()
            return
        }
        switch remedy {
        case .widen(let contentWidth):
            widen(toContentWidth: contentWidth)
            onceResized(show)
        case .hideSidebar:
            askToHideSidebar(then: show, otherwise: otherwise)
        case .unavailable:
            otherwise()
        }
    }

    private func widen(toContentWidth contentWidth: CGFloat) {
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.width = contentWidth + (window.frame.width - contentPaneWidth)
        // Keep the wider window on screen: pull its left edge in if the extra
        // width would push it past the right edge.
        frame.origin.x = min(frame.origin.x, visible.maxX - frame.width)
        frame.origin.x = max(frame.origin.x, visible.minX)
        // Blocks for the resize animation, so layout has settled on return.
        window.setFrame(frame, display: true, animate: true)
    }

    /// The one prompt: the window already fills the screen, so the sidebar is
    /// the only place the column's width can come from.
    ///
    /// The second button is "Continue", not "Cancel" — declining the sidebar
    /// isn't abandoning the comments, it's taking them in the bottom section
    /// (`otherwise`) instead, which the informative text says. Escape is wired
    /// to it by hand, since AppKit only adopts a button titled "Cancel".
    private func askToHideSidebar(then show: @escaping () -> Void,
                                  otherwise: @escaping () -> Void) {
        guard let sidebar = splitVC.splitViewItems.first else {
            otherwise()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Hide the sidebar to make room for comments?"
        alert.informativeText = """
            Comments appear in a column beside the text. This window is \
            already as wide as the screen, so the column has nowhere to go \
            unless the sidebar closes. Click Continue to read the comments at \
            the end of the document instead.
            """
        alert.addButton(withTitle: "Hide Sidebar")
        alert.addButton(withTitle: "Continue")
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else {
                otherwise()
                return
            }
            // Collapse through the animator rather than `toggleSidebar`, whose
            // animation gives no completion to wait on — running `show`
            // mid-slide would measure a content pane still growing.
            NSAnimationContext.runAnimationGroup { _ in
                sidebar.animator().isCollapsed = true
            } completionHandler: {
                self.onceResized(show)
            }
        }
    }

    /// AppKit's layout is settled by the time this is called, but the web
    /// process resizes its viewport over an IPC hop, so the media query may not
    /// have flipped yet. One run-loop turn covers the common case; if the page
    /// is still catching up, its own ResizeObserver reflows the column into
    /// place a moment later.
    private func onceResized(_ show: @escaping () -> Void) {
        DispatchQueue.main.async(execute: show)
    }
}
