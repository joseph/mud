import Foundation
import Combine
import MudCore
import MudPreferences

// MARK: - Web Commands

/// A one-shot command for the document's web page, sent over
/// `DocumentState.webCommands` and executed by `WebView.Coordinator` (which
/// holds the `WKWebView`). Fire-and-forget: nothing is queued for a page
/// that doesn't exist yet, and nothing re-fires after a reload. Sustained
/// facts (theme, zoom, body classes, the comment data) are declarative
/// `WebView` parameters instead, diffed in `updateNSView`.
enum WebCommand {
    /// Run the print panel for the current page (Cmd+P).
    case print
    /// Reset the native pinch magnification to 1. Fired by "Actual Size";
    /// the per-mode CSS-zoom reset travels the declarative zoom path, and a
    /// true reset needs both because pinch magnification stacks on CSS zoom.
    case resetMagnification
    /// Open a compose box on the current selection (the toolbar "Comment"
    /// button and menu equivalents). The JS reveals the column itself.
    case addCommentFromSelection
    /// Answer the comment submission the page has in flight. For an add /
    /// reply / edit that closes the compose box on success, or re-enables it
    /// (text intact) and marks it failed on failure. A delete has no box: the
    /// page puffs the message away before the file has agreed to lose it, so a
    /// false is what puts it back. Only the outcome crosses — why a save
    /// failed is the info bar's to say.
    case resolveSubmission(success: Bool)
    /// Fold every foldable heading in the page (h2 down to h6), or unfold
    /// them all — the View menu's Fold Headings and Unfold Headings. Those
    /// items only appear while the "Foldable headings" setting is on and only
    /// enable in Up mode; `Mud.folds` checks the setting again on its side.
    case foldAllHeadings
    case unfoldAllHeadings
    /// Scroll to a heading (sidebar click). Mode-dependent: Down mode
    /// scrolls to the heading's source line, Up mode to its slug ID.
    case scrollToHeading(OutlineHeading)
    /// Scroll to the first visible change of a sidebar group and flash it.
    case scrollToChanges([String])
    /// Open the Comments column to one comment, expanded and scrolled into
    /// view. Sent after a marker click, once the window has room for the
    /// column (`CommentColumnFit`).
    case revealComment(label: String)
    /// Scroll to the bottom Comments section, or to one comment within it. The
    /// fallback for "show comments" in a window too narrow to fit the column,
    /// which is exactly where `mud-narrow.css` reveals that section in the
    /// column's place.
    case scrollToComments(label: String?)
}

/// A DOM-derived anchor for placing a comment's `💬` marker live, without a
/// reload. Captured from the rendered selection (`endLocator`), so it matches
/// the DOM exactly — `mud-comments.js` replays the same walk to place the
/// marker byte-accurately.
struct CommentLocator: Equatable {
    let blockText: String
    let offset: Int
    let occurrence: Int
}

// MARK: - Document State

class DocumentState: ObservableObject {
    @Published var mode: Mode = .up
    /// Per-window CSS zoom for Mark Up mode, seeded from the persisted value
    /// when the window is created; each change re-persists it, so the next
    /// new window opens at the most-recently-used zoom. From here on it's
    /// independent per window — zooming one window no longer zooms another.
    @Published var upModeZoomLevel: Double = MudPreferences.shared.upModeZoomLevel {
        didSet { MudPreferences.shared.upModeZoomLevel = upModeZoomLevel }
    }
    /// Per-window CSS zoom for Mark Down mode. See `upModeZoomLevel`.
    @Published var downModeZoomLevel: Double = MudPreferences.shared.downModeZoomLevel {
        didSet { MudPreferences.shared.downModeZoomLevel = downModeZoomLevel }
    }
    /// Which sidebar tab (Outline or Changes) this window shows, seeded from
    /// the persisted value when the window is created; each change
    /// re-persists it, so the next new window opens on the most-recently-used
    /// tab. Independent per window from here on — switching tabs in one
    /// window no longer switches every other open window's sidebar too.
    @Published var sidebarPane: SidebarPane = MudPreferences.shared.sidebarPane {
        didSet { MudPreferences.shared.sidebarPane = sidebarPane }
    }
    /// The command channel to this window's web page. Senders (menu and
    /// toolbar actions, sidebar clicks, the comment write path) fire and
    /// forget; the WebView coordinator subscribes and runs the JS.
    let webCommands = PassthroughSubject<WebCommand, Never>()
    /// Whether the rendered (Up-mode) view currently holds a commentable
    /// selection. Pushed from the page over the `mudSelection` bridge and read by
    /// the window controller to enable the toolbar "Comment" button. A plain
    /// subject, not `@Published`, so selection churn doesn't re-render the
    /// document view (which would re-run the markdown render).
    let commentableSelection = CurrentValueSubject<Bool, Never>(false)
    /// Whether the Comments column is shown in this window. Per-window and not
    /// persisted (unlike the app's view toggles): revealed when a document with
    /// comments first opens or when you add a comment, toggled via the View menu,
    /// and gone again on the next document that has none. Feeds the
    /// `is-comments-column` body class for this window's webview.
    @Published var commentsColumnVisible: Bool = false
    /// True while an in-column compose box (new comment, reply, or edit) owns the
    /// keyboard. Set from the page over the `mudComposing` bridge; folded into
    /// `isComposingComment` so the focus trap leaves the textarea alone.
    @Published var isColumnComposing: Bool = false {
        didSet {
            // Closing the box answers a write failure raised about it: the
            // reader gave up on that text, so the explanation goes with it.
            // Every way out of a compose box — Cancel, Escape, hiding the
            // column — arrives here as the same false. Only the transition
            // counts: a delete failure is raised with no box open, and must
            // not be swept away by a later false that changes nothing.
            guard oldValue, !isColumnComposing else { return }
            clear(.commentWriteFailed)
        }
    }
    @Published var outlineHeadings: [OutlineHeading] = []
    @Published var contentTitle: String?
    /// The non-blocking message about this document currently on screen in the
    /// info bar (`DocumentNoticeBar`), or nil for no bar. One at a time:
    /// raising replaces whatever is showing. Two conditions rarely hold at
    /// once, and ranking the kinds against each other would be more machinery
    /// than that is worth.
    @Published private(set) var notice: DocumentNotice?
    weak var windowController: DocumentWindowController?
    let find = FindState()
    let changeTracker = ChangeTracker()

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Keep the change tracker's sidebar policy aligned with this window's
        // mode. `$mode` publishes in `willSet`, so act on the emitted value
        // (not `self.mode`, still the old one here). The sink fires
        // synchronously on the mode assignment — which happens outside the
        // view-update pipeline (a deferred space toggle or an AppKit menu /
        // toolbar action) — so `changeTracker.changes` is refreshed for the
        // new mode before SwiftUI's deferred re-render reads it.
        $mode
            .sink { [weak self] newMode in
                self?.changeTracker.setMode(newMode)
            }
            .store(in: &cancellables)
    }

    /// True while an in-column compose box owns first responder.
    /// `DocumentContentView`'s focus trap exempts this so the textarea can be
    /// typed into.
    var isComposingComment: Bool { isColumnComposing }

    func raise(_ notice: DocumentNotice) {
        self.notice = notice
    }

    /// Take down `kind`'s notice, but only if it is the one showing. Clearing
    /// is by kind, not a blanket reset, so a condition ending can never take
    /// down a notice some other condition raised.
    func clear(_ kind: DocumentNotice.Kind) {
        guard notice?.kind == kind else { return }
        notice = nil
    }

    /// Take down whatever is showing, because the reader asked. Unlike
    /// `clear(_:)` this names no kind: the × belongs to the bar in front of
    /// them, not to the condition behind it.
    func dismissNotice() {
        notice = nil
    }

    func toggleMode() {
        mode = mode.toggled()
    }
}
