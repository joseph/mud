import Foundation
import Combine
import MudPreferences
import MudCore

// MARK: - Web Commands

/// A one-shot command for the document's web page, sent over
/// `DocumentState.webCommands` and executed by `WebView.Coordinator` (which
/// holds the `WKWebView`). Fire-and-forget: nothing is queued for a page
/// that doesn't exist yet, and nothing re-fires after a reload. Sustained
/// facts (theme, zoom, body classes, the hold banner) are declarative
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
    /// Acknowledge a comment submission to the page: close the compose box
    /// on success, or re-enable it (text intact) on failure. On failure,
    /// `reason` is the short note shown inside the box (its inline red line)
    /// — carrying *why* the save failed, so the box says the same thing the
    /// alert does instead of always guessing "text changed".
    case resolveCompose(success: Bool, reason: String?)
    /// Scroll to a heading (sidebar click). Mode-dependent: Down mode
    /// scrolls to the heading's source line, Up mode to its slug ID.
    case scrollToHeading(OutlineHeading)
    /// Scroll to the first visible change of a sidebar group and flash it.
    case scrollToChanges([String])
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
    @Published var openInBrowserID: UUID?
    @Published var openInEditorRequest: EditorLaunchRequest?
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
    @Published var isColumnComposing: Bool = false
    @Published var outlineHeadings: [OutlineHeading] = []
    @Published var contentTitle: String?
    weak var windowController: DocumentWindowController?
    let find = FindState()
    let changeTracker = ChangeTracker()

    /// True while an in-column compose box owns first responder.
    /// `DocumentContentView`'s focus trap exempts this so the textarea can be
    /// typed into.
    var isComposingComment: Bool { isColumnComposing }

    func toggleMode() {
        mode = mode.toggled()
    }
}
