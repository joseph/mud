import AppKit
import Combine
import MudPreferences

/// The per-window facts app-level menus need about the key document window.
/// `nil` (on the observer) means no document window is key — Settings is
/// frontmost, or no windows are open — so document menu items disable rather
/// than act on a window that isn't there.
struct ActiveDocumentSnapshot: Equatable {
    let mode: Mode
    /// False for bundled read-only documents (the guides, release notes).
    let editable: Bool
    /// Whether "Add Comment" applies right now: Up mode, editable document,
    /// commentable selection. Matches the toolbar Comment button's condition.
    let canAddComment: Bool
    let commentsColumnVisible: Bool
}

/// Watches the key window and publishes an `ActiveDocumentSnapshot` for the
/// app menus. This one observer replaces the per-controller writes that used
/// to mirror window state into `AppState`: on every key-window change it
/// re-resolves the key `DocumentWindowController` and re-subscribes to that
/// window's state, so the snapshot follows the key window and clears when
/// none is left instead of going stale.
final class ActiveDocumentObserver: ObservableObject {
    static let shared = ActiveDocumentObserver()

    @Published private(set) var snapshot: ActiveDocumentSnapshot?

    /// The window the current state subscription belongs to.
    private weak var attachedWindow: NSWindow?
    private var windowSubscriptions = Set<AnyCancellable>()
    private var stateSubscription: AnyCancellable?

    private init(center: NotificationCenter = .default) {
        center.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] note in
                self?.attach(to: note.object as? NSWindow)
            }
            .store(in: &windowSubscriptions)
        // The last window's close resigns key without another window becoming
        // key, so no `didBecomeKey` follows — drop the snapshot here.
        center.publisher(for: NSWindow.willCloseNotification)
            .sink { [weak self] note in
                guard let self, let window = note.object as? NSWindow,
                      window === self.attachedWindow else { return }
                self.attach(to: nil)
            }
            .store(in: &windowSubscriptions)
    }

    /// Points the snapshot at `window`: a document window gets a live
    /// subscription to its state; anything else (Settings, no window) clears
    /// the snapshot.
    private func attach(to window: NSWindow?) {
        attachedWindow = window
        stateSubscription = nil
        guard let controller = window?.windowController
                as? DocumentWindowController else {
            if snapshot != nil { snapshot = nil }
            return
        }
        let state = controller.state
        let editable = !controller.fileURL.isBundleResource
        stateSubscription = state.$mode
            .combineLatest(state.commentableSelection,
                           state.$commentsColumnVisible)
            .sink { [weak self] mode, commentable, columnVisible in
                let snapshot = ActiveDocumentSnapshot(
                    mode: mode,
                    editable: editable,
                    canAddComment: mode == .up && commentable && editable,
                    commentsColumnVisible: columnVisible)
                // These publishers fire on `willSet`, sometimes mid view
                // update (the Mark Up/Down menu toggles mutate `mode` from a
                // Binding setter), so defer the publish like the mirror
                // writes this replaces did.
                deferMutation { self?.snapshot = snapshot }
            }
    }
}
