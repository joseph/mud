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

// MARK: - Document State

class DocumentState: ObservableObject {
    @Published var mode: Mode = .up
    @Published var printID: UUID?
    @Published var openInBrowserID: UUID?
    @Published var openInEditorRequest: EditorLaunchRequest?
    @Published var reloadID: UUID?
    @Published var draftCommentID: UUID?
    /// Parsed comments for the Comments sidebar, refreshed on load.
    @Published var comments: [Comment] = []
    /// The comment thread currently open in the Comments sidebar (and revealed
    /// in the document). `nil` shows the list.
    @Published var activeCommentLabel: String?
    /// A captured selection awaiting a first message in the sidebar's create
    /// flow. Non-`nil` opens the sidebar's thread view in create mode.
    @Published var pendingDraft: CommentDraft?
    /// Whether the rendered (Up-mode) body currently has a non-empty selection.
    /// Mirrored to `AppState` for the Edit-menu "Add Comment" gate.
    @Published var hasUpSelection: Bool = false
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

    /// True while the Comments sidebar is showing a thread or a create compose
    /// (its `TextEditor` should hold first responder). `DocumentContentView`'s
    /// focus trap exempts this so the sidebar can be typed into.
    var isComposingComment: Bool {
        pendingDraft != nil || activeCommentLabel != nil
    }

    func toggleMode() {
        mode = mode.toggled()
    }
}
