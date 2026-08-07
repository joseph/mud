import AppKit
import Combine

// MARK: - Asset Access Store

/// The folders the reader has let Mud read local content from, and the
/// security-scoped bookmarks that make those grants outlive the app's run.
///
/// The sandboxed build is handed one file at a time: opening a document grants
/// access to that file and nothing else, so an image beside it can't be read.
/// Choosing a folder in an `NSOpenPanel` grants its whole subtree, and a
/// bookmark taken while that grant is live can be resolved on a later launch
/// to get it back. Without a bookmark the grant dies with the process, which
/// is what made the "open the folder first" workaround a chore rather than a
/// fix.
///
/// One instance for the app (`shared`), observed by the settings pane and by
/// every document window: a grant made from one window's info bar unblocks the
/// images in all of them.
final class AssetAccessStore: ObservableObject {
    static let shared = AssetAccessStore()

    /// A folder the reader has granted.
    ///
    /// A grant outlives the folder being reachable. `path` is what the grant
    /// names and is always there, because a bookmark records the path whether
    /// or not the volume holding it is mounted; `url` is the folder itself and
    /// is only there once access to it is held.
    struct Grant: Identifiable, Equatable {
        /// The folder this grant names, as the reader chose it.
        let path: String
        /// The folder itself, while access to it is held. `nil` for a grant
        /// whose bookmark wouldn't resolve this launch — most often a volume
        /// that wasn't attached.
        let url: URL?
        /// The bookmark that will find the folder again next launch.
        let bookmark: Data

        var id: String { path }

        /// The folder as a URL, resolved or not. Containment is decided on
        /// this, so an unreachable grant still covers what it covers and a
        /// grant made below it while it is away is still a no-op.
        var folder: URL { url ?? URL(fileURLWithPath: path, isDirectory: true) }

        /// Whether Mud can read through this grant right now.
        var isAvailable: Bool { url != nil }
    }

    /// The live grants, in the order they were made.
    @Published private(set) var grants: [Grant] = []

    /// Fires whenever the reader has done something that may change what Mud
    /// can read — a grant, a revocation, or a grant of a folder already
    /// covered by another.
    ///
    /// Separate from `$grants` because the two answer different questions. The
    /// settings list wants the folders, and only cares when they change; a
    /// document window wants to know it should look at its images again, which
    /// is true even when the list came out identical. Asking to be shown a
    /// folder Mud already has is still asking.
    let accessChanged = PassthroughSubject<Void, Never>()

    var folders: [URL] { grants.map(\.folder) }

    private let defaults: UserDefaults
    private static let storageKey = "granted-folder-bookmarks"

    /// The URLs `startAccessingSecurityScopedResource` returned true for, so
    /// the matching stop call is only made where it is owed. Keyed by the
    /// standardized URL, holding the *instance* access was started on: the
    /// sandbox extension belongs to that object, so an equal URL rebuilt from
    /// the same path is not something `stopAccessing…` can be called on.
    private var accessing: [URL: URL] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: At launch

    /// Resolves every saved bookmark and takes access to the folders it finds.
    /// Called once from `AppDelegate`, before any document opens, so a
    /// document's images are readable the first time it renders.
    ///
    /// Access is taken for the process's lifetime and never given back — these
    /// are folders the reader has said Mud may read, and there is no later
    /// moment when that stops being true.
    ///
    /// A bookmark that won't resolve is **kept**, as a grant with no `url`.
    /// Not resolving usually means the volume isn't mounted, and a reader who
    /// keeps their notes on an external drive should not lose the grant every
    /// time they start Mud without it plugged in. The reader took the grant;
    /// only the reader takes it back. A blob that isn't a bookmark at all is
    /// the one thing dropped, since there is nothing there to keep.
    ///
    /// Resolution asks for no UI, so nothing here can hold up launch.
    func resolveSavedGrants() {
        let blobs = defaults.array(forKey: Self.storageKey) as? [Data] ?? []
        let resolved: [Grant] = blobs.compactMap { blob -> Grant? in
            var isStale = false
            guard
                let url = try? URL(
                    resolvingBookmarkData: blob,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale),
                startAccessing(url)
            else {
                // Unreachable this launch. The path is still readable straight
                // out of the blob, which is what lets the settings pane name
                // the folder and offer to forget it.
                return Self.recordedPath(of: blob).map {
                    Grant(path: $0, url: nil, bookmark: blob)
                }
            }
            // A stale bookmark still points at the right folder; it just needs
            // rewriting, which we can only do while holding access.
            let bookmark = isStale ? (Self.makeBookmark(for: url) ?? blob) : blob
            let folder = url.standardizedFileURL
            return Grant(path: folder.path, url: folder, bookmark: bookmark)
        }
        grants = resolved
        // Only rewrite storage when this pass actually dropped or rewrote
        // something. Launch is the one moment this runs unbidden, and a store
        // with nothing to say shouldn't touch the reader's defaults — which
        // includes every run under the test host.
        if storedBookmarks != blobs { persist() }
    }

    // MARK: Granting

    /// Asks the reader to choose a folder to grant, then grants it.
    ///
    /// `folder` is where the panel opens, not what it returns — the reader can
    /// go anywhere. Presented as a sheet when there is a window to hang it on
    /// (the document window whose info bar was clicked, or the settings
    /// window), and modally when there isn't.
    func requestAccess(startingAt folder: URL? = nil, in window: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.message = "Choose a folder to allow Mud to show local content from. "
            + "Mud will be able to read every file inside it."
        panel.prompt = "Grant Access"

        let complete: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.grant(url)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: complete)
        } else {
            complete(panel.runModal())
        }
    }

    /// Records a grant on `url` and takes a bookmark for it. Returns whether
    /// the grant will still be there next launch.
    ///
    /// A folder already covered by a wider grant adds no row — the access is
    /// held either way, and a second row saying so would be noise. A folder
    /// that covers existing grants replaces them. Either way `accessChanged`
    /// fires: the reader asked to be shown a folder, and the windows should
    /// look again whether or not the list moved.
    @discardableResult
    func grant(_ url: URL) -> Bool {
        let folder = url.standardizedFileURL
        let reduced = Self.reduce(grants: folders, adding: folder)
        guard reduced != folders else {
            accessChanged.send()
            return true
        }

        // The bookmark comes first because without one there is no grant to
        // record. The panel's own access is live either way, so the windows
        // are still told to look again — the reader gets their images for
        // this run, just no row and nothing next launch. Taking the bookmark
        // before `startAccessing` also means a failure here leaves nothing
        // half-started to clean up.
        guard let bookmark = Self.makeBookmark(for: folder) else {
            NSLog("Mud: couldn't bookmark granted folder \(folder.path)")
            accessChanged.send()
            return false
        }
        // The panel's grant is live from the moment it returns, whether or not
        // this URL is one `startAccessing` reports on, so its answer isn't
        // worth guarding.
        _ = startAccessing(folder)

        for grant in grants where !reduced.contains(grant.folder) {
            stopAccessing(grant.folder)
        }
        grants = grants.filter { reduced.contains($0.folder) }
            + [Grant(path: folder.path, url: folder, bookmark: bookmark)]
        persist()
        accessChanged.send()
        return true
    }

    /// Takes a grant back: the bookmark is forgotten, so it is gone for good at
    /// the next launch.
    ///
    /// Whether the sandbox extension is torn down in *this* run isn't ours to
    /// promise — a folder the reader opened in a panel this session stays
    /// readable until quit, because that grant came from the panel rather than
    /// from us. Dropping the bookmark is the part that lasts.
    ///
    /// Takes the `Grant` rather than a URL because a grant Mud couldn't
    /// resolve has no URL, and that is exactly the grant a reader is most
    /// likely to want rid of.
    func revoke(_ grant: Grant) {
        if let url = grant.url { stopAccessing(url) }
        grants.removeAll { $0.id == grant.id }
        persist()
        accessChanged.send()
    }

    // MARK: Reduction

    /// The grant list that results from adding `folder`, keeping only what is
    /// worth keeping: nothing changes if a grant already covers `folder`, and
    /// any grant `folder` covers is replaced by it.
    ///
    /// Pure, and separate from the bookmark handling around it, so the rules
    /// can be read and tested without touching the file system.
    static func reduce(grants: [URL], adding folder: URL) -> [URL] {
        let folder = folder.standardizedFileURL
        if grants.contains(where: { covers($0, folder) }) { return grants }
        return grants.filter { !covers(folder, $0) } + [folder]
    }

    /// Whether `folder` is `other` or an ancestor of it.
    ///
    /// Compared by path component, not by string prefix: `/a/b` is not an
    /// ancestor of `/a/bc`, though one path does begin with the other.
    static func covers(_ folder: URL, _ other: URL) -> Bool {
        let ancestor = folder.standardizedFileURL.pathComponents
        let descendant = other.standardizedFileURL.pathComponents
        guard ancestor.count <= descendant.count else { return false }
        return Array(descendant.prefix(ancestor.count)) == ancestor
    }

    // MARK: Storage and access

    /// What `persist` would write, so `resolveSavedGrants` can tell whether
    /// its pass changed anything.
    private var storedBookmarks: [Data] { grants.map(\.bookmark) }

    private func persist() {
        defaults.set(storedBookmarks, forKey: Self.storageKey)
    }

    private static func makeBookmark(for url: URL) -> Data? {
        return try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil)
    }

    /// The path a bookmark records, read without resolving it. This is what
    /// can still be said about a grant whose volume isn't mounted; `nil` means
    /// the blob isn't a bookmark.
    private static func recordedPath(of bookmark: Data) -> String? {
        return URL.resourceValues(
            forKeys: [.pathKey], fromBookmarkData: bookmark)?.path
    }

    @discardableResult
    private func startAccessing(_ url: URL) -> Bool {
        guard url.startAccessingSecurityScopedResource() else { return false }
        accessing[url.standardizedFileURL] = url
        return true
    }

    private func stopAccessing(_ url: URL) {
        guard let started = accessing.removeValue(forKey: url.standardizedFileURL)
        else { return }
        started.stopAccessingSecurityScopedResource()
    }
}
