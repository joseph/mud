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

/// A DOM-derived anchor for placing a comment's `[⋯]` marker live, without a
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
    @Published var printID: UUID?
    @Published var openInBrowserID: UUID?
    @Published var openInEditorRequest: EditorLaunchRequest?
    @Published var reloadID: UUID?
    /// Parsed comments, refreshed on load; drive the Comments column.
    @Published var comments: [Comment] = []
    /// DOM-derived locators for just-added comments, keyed by label, so the live
    /// `[⋯]` marker lands byte-exactly without a reload. Pruned to live labels on
    /// each load; a stale entry is harmless (the JS skips insert when the marker
    /// already exists). Plain bookkeeping, read during the view's render.
    var pendingCommentLocators: [String: CommentLocator] = [:]
    /// True while an in-column compose box (new comment, reply, or edit) owns the
    /// keyboard. Set from the page over the `mudComposing` bridge; folded into
    /// `isComposingComment` so the focus trap leaves the textarea alone.
    @Published var isColumnComposing: Bool = false
    @Published var outlineHeadings: [OutlineHeading] = []
    @Published var scrollTarget: ScrollTarget?
    @Published var changeScrollTarget: ChangeScrollTarget?
    @Published var contentTitle: String?
    @Published var hasBackgroundReload: Bool = false
    weak var windowController: DocumentWindowController?
    let find = FindState()
    let changeTracker = ChangeTracker()

    /// Hashes of file contents Mud has just written itself (comment edits), each
    /// awaiting its file-watcher echo. The watcher reload consumes a match and
    /// suppresses the background-reload badge — the change is ours, not
    /// external. Plain (non-`@Published`) bookkeeping, mutated only on the main
    /// thread where both the comment write and the watcher fire.
    private var pendingSelfWrites: Set<Int> = []

    /// Record that Mud just wrote `content` to disk, so the matching watcher
    /// event is recognized as a self-write rather than an external edit.
    func registerSelfWrite(_ content: String) {
        pendingSelfWrites.insert(content.hashValue)
        // Bound the set: an echo that never lands (e.g. a failed re-watch)
        // mustn't accumulate. Comment writes are serial, so a few is plenty.
        if pendingSelfWrites.count > 8 { pendingSelfWrites.removeFirst() }
    }

    /// Consume a pending self-write matching `content`. Returns true when this
    /// load is the echo of a write Mud made (the caller then skips the
    /// external-change badge); false for a genuine external edit, which also
    /// clears any stale pending entries (the file has moved past them).
    func consumeSelfWrite(_ content: String) -> Bool {
        if pendingSelfWrites.remove(content.hashValue) != nil { return true }
        pendingSelfWrites.removeAll()
        return false
    }

    /// True while an in-column compose box owns first responder.
    /// `DocumentContentView`'s focus trap exempts this so the textarea can be
    /// typed into.
    var isComposingComment: Bool { isColumnComposing }

    func toggleMode() {
        mode = mode.toggled()
    }
}
