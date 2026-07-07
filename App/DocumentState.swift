import Foundation
import Combine
import MudPreferences
import MudCore

// MARK: - Scroll Target

struct ScrollTarget: Equatable {
    let id: UUID
    let heading: OutlineHeading
}

struct ChangeScrollTarget: Equatable {
    let id: UUID
    let changeIDs: [String]
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

/// The native acknowledgement of a comment submission, delivered back to the
/// page so the compose box knows whether to close (`success`) or stay open with
/// its text for another try (failure). A one-shot trigger: the `id` makes each
/// resolution distinct so `WebView` fires it exactly once.
struct ComposeResolution: Equatable {
    let id: UUID
    let success: Bool
    /// On failure, the short note to show inside the compose box (its inline red
    /// line). Nil on success, where the box just closes. Carries *why* the save
    /// failed — the text moved vs the file couldn't be written — so the box says
    /// the same thing the alert does instead of always guessing "text changed".
    var reason: String? = nil
}

// MARK: - Document State

class DocumentState: ObservableObject {
    @Published var mode: Mode = .up
    @Published var printID: UUID?
    @Published var openInBrowserID: UUID?
    @Published var openInEditorRequest: EditorLaunchRequest?
    @Published var reloadID: UUID?
    /// One-shot trigger for "Actual Size": resets the native pinch magnification
    /// in the webview (the CSS zoom is reset via the per-mode zoom level).
    @Published var actualSizeID: UUID?
    /// One-shot trigger for the toolbar "Comment" button: opens a compose box on
    /// the current selection (`Mud.comments.addFromSelection`).
    @Published var addCommentID: UUID?
    /// One-shot ack of a comment submission, pushed to the page so the compose
    /// box closes on success or stays open (text intact) on failure. Set by
    /// `DocumentContentView.handleCommentSubmit`; fired by `WebView`.
    @Published var composeResolution: ComposeResolution?
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
    @Published var scrollTarget: ScrollTarget?
    @Published var changeScrollTarget: ChangeScrollTarget?
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
