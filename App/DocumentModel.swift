import AppKit
import Combine
import MudCore
import MudPreferences

// MARK: - Document Model

/// The data layer for one document window: the loaded content, disk reads,
/// the file watcher with its hold/echo policy, and a cached render. Owned by
/// `DocumentWindowController` next to `DocumentState`; `DocumentContentView`
/// observes it and keeps layout, key handling, and callback plumbing.
///
/// The cache is what keeps the full markdown render out of SwiftUI `body`:
/// `display()` re-renders only when the content or the content-affecting
/// options change, so selection churn, zoom, and other view updates cost a
/// key comparison, not a render.
final class DocumentModel: ObservableObject {

    /// What the window shows: a parsed document, or the error page that took
    /// its place when the file couldn't be read.
    enum Content {
        case parsed(ParsedMarkdown)
        case error(String)  // pre-rendered error page HTML
    }

    /// The HTML to display plus the WebView reload identity, the footnote
    /// popover map (label → popover document HTML), and the parsed comments
    /// (for the Comments column). Up mode renders via the footnote API in
    /// `.popover` / `.interactive` modes so a single render yields the page,
    /// the popover bodies, and the comment model.
    struct RenderedDisplay {
        let html: String
        let contentID: String
        let footnoteHTML: [String: String]
        var comments: [Comment] = []
    }

    let fileURL: URL
    private let state: DocumentState
    private let changeTracker: ChangeTracker
    private let waypointProvider: any WaypointProvider
    /// What this window makes of a folder URL. Read at every load, so the
    /// setting takes effect on the next Cmd+R; a closure rather than a value
    /// so tests can pin it without writing the reader's preferences.
    private let folderBehavior: () -> FolderOpenBehavior

    /// The URL relative links in this document resolve against — the page's
    /// `<base href>` and the image resolver both take it.
    ///
    /// A folder's generated index links to files beneath the folder, so its
    /// base URL has to end in a slash: `<base href="file:///a/b/Doc">` would
    /// resolve `Guides/x.md` against `/a/b/`, one level too high, and every
    /// link in the index would miss.
    var baseURL: URL {
        MarkdownFolder.isFolder(fileURL)
            ? URL(fileURLWithPath: fileURL.path, isDirectory: true)
            : fileURL
    }

    @Published private(set) var content: Content = .parsed(ParsedMarkdown(""))
    /// True while a held change is specifically an *external* edit (not our
    /// own comment echo). Raises the window's info-bar notice, so you know the
    /// view is showing a stale version until you finish the comment. Cleared
    /// when composing ends.
    @Published var externalChangeHeld: Bool = false {
        didSet {
            guard externalChangeHeld != oldValue else { return }
            if externalChangeHeld {
                state.raise(.externalChangeHeld)
            } else {
                state.clear(.externalChangeHeld)
            }
        }
    }
    /// The document reloaded while its window was not key; drives the tab's
    /// brown-dot badge. Cleared by the window controller when the window
    /// becomes key.
    @Published var hasBackgroundReload: Bool = false

    /// DOM-derived locators for just-added comments, keyed by label, so the
    /// live `💬` marker lands byte-exactly without a reload. Pruned to live
    /// labels on each load; a stale entry is harmless (the JS skips insert
    /// when the marker already exists). Plain bookkeeping, read during the
    /// view's render.
    var pendingCommentLocators: [String: CommentLocator] = [:]

    /// Parsed comments, refreshed on load. Consulted for the
    /// reveal-on-first-comment rule and locator pruning; the Comments column
    /// itself is fed from the render (`RenderedDisplay.comments`).
    private var comments: [Comment] = []
    /// A change arrived while a compose box was open and was held rather than
    /// applied (applying would reload the page and destroy the box). Disk is
    /// re-read and the change applied when composing ends.
    private var pendingExternalReload = false
    /// Hashes of file contents Mud has just written itself (comment edits),
    /// each awaiting its file-watcher echo, oldest first. The watcher reload
    /// consumes a match and suppresses the background-reload badge — the
    /// change is ours, not external. Mutated only on the main thread, where
    /// both the comment write and the watcher fire.
    private var pendingSelfWrites: [Int] = []
    private var fileWatcher: FileWatcher?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Render cache

    private struct DisplayKey: Equatable {
        let contentVersion: Int
        let loadToken: Int
        let mode: Mode
        let identity: RenderOptions.ContentIdentity
    }
    /// Bumped on every content change so the cache key needs no content
    /// comparison of its own.
    private var contentVersion = 0
    /// Bumped by a forced load (Cmd+R) and appended to the contentID, so the
    /// WebView reloads the page even when the re-read produced identical
    /// text (the user expects a real reload — e.g. images changed on disk).
    private var loadToken = 0
    private var cachedKey: DisplayKey?
    private var cachedDisplay: RenderedDisplay?

    init(
        fileURL: URL, state: DocumentState, changeTracker: ChangeTracker,
        waypointProvider: any WaypointProvider = WaypointProviders.makeDefault(),
        folderBehavior: @escaping () -> FolderOpenBehavior = {
            AppState.shared.folderOpenBehavior
        }
    ) {
        self.fileURL = fileURL
        self.state = state
        self.changeTracker = changeTracker
        self.waypointProvider = waypointProvider
        self.folderBehavior = folderBehavior

        // When the compose box closes, apply any external change held while
        // it was open (re-reading disk so a successful comment write is
        // included). The info-bar notice goes with the box.
        // `$isColumnComposing` publishes in willSet, so act on the emitted
        // value.
        state.$isColumnComposing
            .dropFirst()
            .sink { [weak self] composing in
                if !composing { self?.composeDidEnd() }
            }
            .store(in: &cancellables)
    }

    // MARK: Render options

    /// The window's current render configuration, built from the app-wide
    /// preferences and this window's state. Read by the live view (which
    /// layers `displayOptions` on top) and by the export path
    /// (`DocumentWindowController` hands it to `DocumentExporter`, where
    /// `MudCore.exportDocument` drops the export-inapplicable parts).
    var renderOptions: RenderOptions {
        let appState = AppState.shared
        // Route through the one shared preferences → RenderOptions mapping, then
        // override the window-specific display fields it can't know about. With
        // AppState's live reads, this snapshot holds exactly the values AppState
        // would report, so both consumers produce identical output.
        let snapshot = MudPreferences.shared.snapshot(
            defaultEnabledExtensions: Set(RenderExtension.registry.keys))
        var opts = RenderOptions(snapshot: snapshot, baseURL: baseURL)
        // htmlClasses covers all view toggles (both modes) plus the per-window
        // comment classes, replacing the snapshot's Up-mode-only subset.
        opts.htmlClasses = Set(appState.viewToggles.map(\.className))
        // Column visibility is per-window state, not a persisted view toggle.
        if state.commentsColumnVisible { opts.htmlClasses.insert("is-comments-column") }
        // Read live by the compose box's keydown handler (mud-comments-edit.js).
        if appState.commentReturnSaves { opts.htmlClasses.insert("comment-return-saves") }
        // Shows the inline `💬` markers on screen; read by mud-comments.css/js.
        if appState.commentsShowMarkers { opts.htmlClasses.insert("show-comment-markers") }
        opts.zoomLevel = state.mode == .down
            ? state.downModeZoomLevel
            : state.upModeZoomLevel
        opts.showInlineDeletions = appState.changesShowInlineDeletions
        opts.wordDiffThreshold = appState.changesWordDiffThreshold
        if appState.changesEnabled && !changeTracker.changes.isEmpty {
            opts.waypoint = changeTracker.activeWaypoint
        }
        return opts
    }

    /// The options for the live view. Up mode renders via the footnote API in
    /// `.popover` / `.interactive` modes so a single render yields the page,
    /// the popover bodies, and the comment model.
    private var displayOptions: RenderOptions {
        var opts = renderOptions
        guard state.mode == .up else { return opts }
        opts.footnoteMode = .popover
        opts.commentMode = .interactive
        // The live view is editable, so embed the write-side comment styles.
        opts.commentsEditable = true
        return opts
    }

    // MARK: Rendering

    /// The rendered document for the window's current mode and display
    /// options, from the cache below.
    func display() -> RenderedDisplay {
        display(mode: state.mode, options: displayOptions)
    }

    /// The rendered document for `mode` under `options`, cached until the
    /// content or the content-affecting options change. Display-only options
    /// (htmlClasses, zoomLevel) are excluded from the key on purpose: they
    /// are applied to the live page via JS, so a cached page with a stale
    /// zoom baked in is exactly as correct as the freshly rendered page the
    /// WebView would have discarded (the contentID matches either way).
    private func display(mode: Mode, options: RenderOptions) -> RenderedDisplay {
        switch content {
        case .error(let html):
            return RenderedDisplay(
                html: html, contentID: "load-error", footnoteHTML: [:])
        case .parsed(let parsed):
            let key = DisplayKey(
                contentVersion: contentVersion, loadToken: loadToken,
                mode: mode, identity: options.contentIdentity)
            if let cached = cachedDisplay, cachedKey == key { return cached }
            let display = render(parsed, mode: mode, options: options)
            cachedKey = key
            cachedDisplay = display
            return display
        }
    }

    private func render(
        _ parsed: ParsedMarkdown, mode: Mode, options: RenderOptions
    ) -> RenderedDisplay {
        // Up mode is comment-invariant: a comment add/remove leaves the ID
        // unchanged, so the WebView doesn't reload — `mud-comments.js` syncs
        // the marker in place. Down mode keeps the full markdown so its raw
        // source reflects the comment (un-highlighted, via the diff fix).
        // The body stays exact; the options join as the identity struct's
        // hash (stable within the process, which is all the WebView's reload
        // dedup compares against).
        let body = mode == .up
            ? MudCore.removeComments(parsed.markdown)
            : parsed.markdown
        let contentID = "\(body)\(options.contentIdentity.hashValue)#\(loadToken)"
        if mode == .down {
            return RenderedDisplay(
                html: MudCore.renderDownModeDocument(parsed, options: options),
                contentID: contentID, footnoteHTML: [:])
        }
        let document = MudCore.renderUpModeDocumentWithFootnotes(
            parsed.markdown, options: options,
            resolveImageSource: Self.mudAssetResolver)
        var map: [String: String] = [:]
        for footnote in document.footnotes {
            map[footnote.label.lowercased()] = footnote.html
        }
        return RenderedDisplay(
            html: document.html, contentID: contentID,
            footnoteHTML: map, comments: document.comments)
    }

    /// Rewrites local image paths to `mud-asset:` URLs for WKWebView. Also
    /// used by the coordinator when rendering comment items for the column.
    nonisolated static func mudAssetResolver(
        source: String, baseURL: URL
    ) -> String? {
        guard !ImageDataURI.isExternal(source) else { return nil }
        let resolved = baseURL.deletingLastPathComponent()
            .appendingPathComponent(source)
            .standardized
        let ext = resolved.pathExtension.lowercased()
        guard ImageDataURI.mimeTypes[ext] != nil else { return nil }
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mud-asset"
        components.path = resolved.path
        return components.url?.absoluteString ?? nil
    }

    // MARK: Loading and watching

    /// Reads the file and (re-)establishes the watcher. Called on appear and
    /// for Cmd+R (`forced: true`), where the re-watch revives a watch lost to
    /// e.g. an exhausted atomic-save retry, and the bumped `loadToken` makes
    /// the page reload even when the file's text hasn't changed.
    func load(forced: Bool = false) {
        if forced { loadToken += 1 }
        loadFromDisk()
        setupFileWatcher()
    }

    /// Drops the watcher when the view goes away; `load()` restores it.
    func stopWatching() {
        fileWatcher = nil
    }

    /// Record that Mud just wrote `content` to disk, so the matching watcher
    /// event is recognized as a self-write rather than an external edit.
    func registerSelfWrite(_ content: String) {
        pendingSelfWrites.append(content.hashValue)
        // Bound the list: an echo that never lands (e.g. a failed re-watch)
        // mustn't accumulate. Comment writes are serial, so a few is plenty;
        // evict the oldest, whose echo is the least likely still to come.
        if pendingSelfWrites.count > 8 { pendingSelfWrites.removeFirst() }
    }

    /// Consume a pending self-write matching `content`. Returns true when
    /// this load is the echo of a write Mud made (the caller then skips the
    /// external-change badge); false for a genuine external edit, which also
    /// clears any stale pending entries (the file has moved past them).
    /// Internal (not private) so tests can exercise the dedup policy.
    func consumeSelfWrite(_ content: String) -> Bool {
        if let index = pendingSelfWrites.firstIndex(of: content.hashValue) {
            pendingSelfWrites.remove(at: index)
            return true
        }
        pendingSelfWrites.removeAll()
        return false
    }

    private func setupFileWatcher() {
        // Nothing to watch for a bundled guide, which can't change, or for the
        // empty-folder window, whose blank page re-reads to the same blank
        // page however the folder's contents move.
        guard !fileURL.isBundleResource, !MarkdownFolder.isFolder(fileURL) else {
            return
        }
        fileWatcher = FileWatcher(url: fileURL) { [weak self] in
            guard let self else { return }
            let read = self.readDisk()
            // While a compose box is open, hold the change instead of applying
            // it: applying would move the contentID, reload the page, and
            // destroy the box and its unsaved text. A read failure (e.g. a
            // transient gap mid atomic-save) is held the same way, so it can't
            // tear the box down either. The held change applies when composing
            // ends (`composeDidEnd`).
            guard case .text(let text, _) = read else {
                if self.state.isComposingComment {
                    self.pendingExternalReload = true
                } else if case .failure(let html, let notice) = read {
                    self.setLoadFailure(html, notice: notice)
                }
                return
            }
            // Consume a pending self-write (our own comment echo) so the set
            // stays bounded and a later genuine edit isn't misread.
            let isSelfWrite = self.consumeSelfWrite(text)
            // While composing, hold *every* change — external edits and our own
            // comment echo alike — so the page and the open box are never torn
            // down mid-edit. One `loadFromDisk` at compose-end applies whatever
            // is on disk by then (held prose, the new marker, or both). Holding
            // the self-write too matters: when a held external change and the
            // comment land in the same write, applying its echo now would change
            // the prose, reload the page, and strand the box.
            if self.state.isComposingComment {
                self.pendingExternalReload = true
                // Only a genuine external edit raises the notice; our own comment
                // echo is held too but isn't "the file changed under you".
                if !isSelfWrite { self.externalChangeHeld = true }
                return
            }
            self.applyLoaded(text)
            if !isSelfWrite,
               self.state.windowController?.window?.isKeyWindow != true {
                self.hasBackgroundReload = true
            }
        }
    }

    private func composeDidEnd() {
        externalChangeHeld = false  // the notice goes with the box
        if pendingExternalReload {
            pendingExternalReload = false
            loadFromDisk()
        }
    }

    /// The outcome of reading the document off disk: the decoded source, or
    /// the error-page HTML to show. Pure — it does not mutate `content` — so
    /// the file-watcher can classify a change (self-write? composing?) before
    /// deciding whether to apply or hold it.
    private enum DiskRead {
        /// The document's source, and a notice about it when the read has
        /// something to say — the folder index carries one when the tree was
        /// too big to list in full.
        case text(String, notice: DocumentNotice?)
        /// Pre-rendered page HTML to show in place of the document, and the
        /// notice raised over it. The notice travels with the page because the
        /// two are written to be read together — which failure it was decides
        /// both.
        case failure(html: String, notice: DocumentNotice)
    }

    private func readDisk() -> DiskRead {
        if MarkdownFolder.isFolder(fileURL) {
            return readFolder()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(
                    html: ErrorPage.fileEncodingError(), notice: openFailed)
            }
            return .text(text, notice: nil)
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return .failure(
                html: ErrorPage.fileNotFound(error: cocoaError),
                notice: openFailed)
        } catch {
            return .failure(
                html: ErrorPage.filePermissionDenied(
                    path: fileURL.path, error: error),
                notice: openFailed)
        }
    }

    /// The window `DocumentController` opens on a folder. Under the index
    /// behavior the tree below it becomes the document (`FolderIndex`); under
    /// the tab behavior this window exists only because the folder held no
    /// Markdown, and there is nothing to read at all.
    ///
    /// A folder with nothing in the tree answers the same way in both: a blank
    /// page where the notice in the bar is the whole message.
    private func readFolder() -> DiskRead {
        guard folderBehavior() == .index else {
            return .failure(
                html: ErrorPage.empty(), notice: .folderHasNoMarkdown)
        }
        let tree = FolderIndex.walk(fileURL)
        guard !tree.isEmpty else {
            return .failure(
                html: ErrorPage.empty(), notice: .folderHasNoMarkdown)
        }
        let notice: DocumentNotice? = tree.isTruncated
            ? .folderIndexTruncated(limit: FolderIndex.fileLimit)
            : nil
        return .text(FolderIndex.markdown(for: tree), notice: notice)
    }

    /// The headline over any of the three read failures.
    private var openFailed: DocumentNotice {
        .openFailed(fileName: fileURL.lastPathComponent)
    }

    private func loadFromDisk() {
        switch readDisk() {
        case .text(let text, let notice):
            applyLoaded(text)
            // `applyLoaded` has already cleared the notices a good read
            // settles, so a re-walk that now fits leaves the bar empty.
            if let notice { state.raise(notice) }
        case .failure(let html, let notice):
            setLoadFailure(html, notice: notice)
        }
    }

    /// Shows the page that took the document's place and raises its info-bar
    /// notice. The page carries the diagnosis and what to do about it; the bar
    /// is the headline, so the window says what went wrong without the reader
    /// having to read a rendered document to find out.
    private func setLoadFailure(_ html: String, notice: DocumentNotice) {
        setContent(.error(html))
        state.raise(notice)
    }

    /// Parses `text` and refreshes per-document state (the render, headings,
    /// comments, title, change tracking). The single place a successful disk
    /// read becomes the displayed document.
    private func applyLoaded(_ text: String) {
        // The file read this time, so whatever stopped it last time is over.
        state.clear(.openFailed)
        // Likewise for a folder index: this walk speaks for itself, and
        // `loadFromDisk` raises the notice again if it was cut short too.
        state.clear(.folderIndexTruncated)
        let parsed = ParsedMarkdown(text)
        setContent(.parsed(parsed))
        state.outlineHeadings = parsed.headings
        let hadComments = !comments.isEmpty
        comments = MudCore.parseComments(text)
        // Reveal the Comments Column when a document gains its first comment —
        // whether on first open or on a reload that adds one. A reload that
        // keeps existing comments (1+ → 1+) makes no change here, so a column
        // the user has hidden stays hidden.
        if !hadComments, !comments.isEmpty {
            state.commentsColumnVisible = true
        }
        // Drop locators for comments that no longer exist (e.g. deleted), so
        // a never-reused label can't misdirect a future live insert.
        let liveLabels = Set(comments.map(\.label))
        pendingCommentLocators = pendingCommentLocators
            .filter { liveLabels.contains($0.key) }
        state.contentTitle = parsed.title
        changeTracker.update(parsed)
        refreshExternalWaypoints(for: text)
    }

    private func setContent(_ newContent: Content) {
        contentVersion += 1
        content = newContent
    }

    // MARK: External waypoints

    /// Responds to the provider's setting changing: on enable, query for the
    /// current content; on disable, drop the external waypoints.
    func externalWaypointsSettingChanged(enabled: Bool) {
        if enabled {
            if case .parsed(let parsed) = content {
                refreshExternalWaypoints(for: parsed.markdown)
            }
        } else {
            changeTracker.setExternalWaypoints([])
        }
    }

    /// Queries the waypoint provider off the main thread and hands the
    /// result to the change tracker — or clears the external waypoints when
    /// the provider is off, or there is no file behind the document to ask
    /// about: a bundled guide, or a folder whose index Mud generated.
    private func refreshExternalWaypoints(for text: String) {
        guard waypointProvider.isEnabled, !fileURL.isBundleResource,
              !MarkdownFolder.isFolder(fileURL) else {
            changeTracker.setExternalWaypoints([])
            return
        }
        let url = fileURL
        let tracker = changeTracker
        let provider = waypointProvider
        Task {
            let waypoints = await Task.detached {
                provider.queryWaypoints(for: url, currentContent: text)
            }.value
            tracker.setExternalWaypoints(waypoints)
        }
    }
}
