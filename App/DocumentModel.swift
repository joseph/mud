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

    /// What the last Up render had to say about images it couldn't read.
    ///
    /// Kept so an unchanged answer can be left alone. `cachedDisplay` is a
    /// single slot, so a mode toggle or a theme change re-renders, and without
    /// this every one of those would raise the notice again — putting a
    /// dismissed bar back up, and taking the bar from whatever other condition
    /// had it.
    private enum BlockedReport: Equatable {
        /// Nothing reported yet, or a grant changed and the last answer is no
        /// longer worth trusting.
        case unknown
        /// The render read every image it met.
        case allRead
        /// The render met an image it wasn't allowed to read. A grant panel
        /// would open at `folder`.
        case blocked(folder: URL)
    }
    private var lastBlockedReport: BlockedReport = .unknown

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
        // The log rides along with the resolver for the length of this render,
        // collecting the images the sandbox wouldn't let us read.
        let blocked = BlockedAssetLog()
        let document = MudCore.renderUpModeDocumentWithFootnotes(
            parsed.markdown, options: options,
            resolveImageSource: blocked.resolver)
        reportBlockedAssets(blocked)
        var map: [String: String] = [:]
        for footnote in document.footnotes {
            map[footnote.label.lowercased()] = footnote.html
        }
        return RenderedDisplay(
            html: document.html, contentID: contentID,
            footnoteHTML: map, comments: document.comments)
    }

    /// Rewrites local image paths to `mud-asset:` URLs for WKWebView. Also
    /// used by the coordinator when rendering comment items for the column,
    /// which has no window to report a denial to and so takes this plain form.
    nonisolated static func mudAssetResolver(
        source: String, baseURL: URL
    ) -> String? {
        return resolve(source: source, baseURL: baseURL, onDenied: nil)
    }

    /// The resolution itself. `onDenied` is called with a file that is there
    /// and that Mud can't read — the sandbox case a folder grant fixes.
    ///
    /// A file that isn't there at all is passed over in silence. Both leave the
    /// reader with a broken image, but only one of them is Mud's to offer to
    /// do something about; a wrong path in the document is the author's.
    ///
    /// Kept apart from `mudAssetResolver` rather than made an overload of it,
    /// so that passing that function as a value stays unambiguous.
    nonisolated static func resolve(
        source: String, baseURL: URL, onDenied: ((URL) -> Void)?
    ) -> String? {
        guard !ImageDataURI.isExternal(source) else { return nil }
        let resolved = baseURL.deletingLastPathComponent()
            .appendingPathComponent(source)
            .standardized
        let ext = resolved.pathExtension.lowercased()
        guard ImageDataURI.mimeTypes[ext] != nil else { return nil }
        switch LocalAssetProbe.probe(resolved) {
        case .readable:
            break
        case .missing:
            return nil
        case .denied:
            onDenied?(resolved)
            return nil
        }
        var components = URLComponents()
        components.scheme = "mud-asset"
        components.path = resolved.path
        return components.url?.absoluteString ?? nil
    }

    /// The folder this document lives in — where a grant panel opens when the
    /// document's own images are the ones that were blocked.
    private var documentFolder: URL {
        MarkdownFolder.isFolder(fileURL)
            ? fileURL
            : fileURL.deletingLastPathComponent()
    }

    /// Whether the blocked-assets notice may take the info bar from whatever
    /// is showing there.
    ///
    /// It may not push another condition's message aside. Every other notice
    /// is raised by something that just happened and says so once
    /// (`externalChangeHeld` guards on its own `didSet`, and
    /// `commentWriteFailed` is carrying text the reader typed and hasn't got
    /// back yet); this one is re-derived on every render, so if it won the
    /// contest it would win it repeatedly and those messages would be gone for
    /// good.
    static func blockedAssetsMayRaise(over showing: DocumentNotice?) -> Bool {
        guard let showing else { return true }
        return showing.kind == .localAssetsBlocked
    }

    /// Raises or clears the info bar's notice from what the render just found.
    ///
    /// Deferred, because `render` runs inside `display()`, which SwiftUI calls
    /// from `DocumentContentView`'s body — setting an `@Published` property
    /// there is exactly what `deferMutation` is for.
    ///
    /// Sandboxed builds only. The probe is a better test than the file-exists
    /// check it replaced either way, but an unsandboxed Mud reads whatever the
    /// file system allows, so a denial there is an ordinary permissions
    /// problem and granting a folder would answer nothing.
    ///
    /// The panel opens at the document's own folder when that folder holds the
    /// blocked file, and at the blocked file's folder when it doesn't — a
    /// document that points at an image somewhere else entirely shouldn't send
    /// the reader to the wrong place to go looking for it.
    ///
    /// An answer that repeats the last one does nothing at all. That is what
    /// keeps a dismissed bar down through the re-renders a mode toggle and a
    /// theme change cause, and what keeps this from raising the notice over
    /// and over. `lastBlockedReport` is only moved on when the bar was
    /// actually changed, so a raise that stood down for another notice is
    /// tried again on the next render.
    ///
    /// Only Up mode renders images, so only Up mode calls this. A notice
    /// raised there stays up if the reader switches to Down — which is right:
    /// the document still has images Mud can't read, and taking the bar down
    /// on a mode toggle would only make it flicker back on the way returning.
    private func reportBlockedAssets(_ blocked: BlockedAssetLog) {
        guard isSandboxed else { return }
        var report = BlockedReport.allRead
        if let file = blocked.denied.first {
            let ownFolder = documentFolder
            report = .blocked(
                folder: AssetAccessStore.covers(ownFolder, file)
                    ? ownFolder
                    : file.deletingLastPathComponent())
        }
        guard report != lastBlockedReport else { return }

        deferMutation { [weak self] in
            guard let self else { return }
            switch report {
            case .blocked(let folder):
                guard Self.blockedAssetsMayRaise(over: state.notice)
                else { return }
                lastBlockedReport = report
                state.raise(.localAssetsBlocked(folder: folder))
            case .allRead:
                lastBlockedReport = report
                state.clear(.localAssetsBlocked)
            case .unknown:
                // A render always has an answer; `.unknown` is only ever the
                // starting value and what a grant change resets to.
                break
            }
        }
    }

    /// A folder grant changed, so images this document couldn't read may be
    /// readable now — or a revoked grant may have taken readable ones away.
    /// Re-reads, which re-renders and probes every image again.
    ///
    /// The load is forced: the file's text hasn't changed, and only the bumped
    /// load token makes the page reload and the images resolve a second time.
    ///
    /// The last report is dropped because the answer it held may no longer be
    /// the answer. In Down mode the notice is taken down outright: no Down
    /// render probes an image, so nothing else would ever take down a bar the
    /// grant may well have just made untrue. In Up mode it is left alone, and
    /// the render coming right behind this says whether it was fixed — which
    /// spares the bar a blink on its way to saying the same thing.
    func reloadForAssetAccessChange() {
        lastBlockedReport = .unknown
        if state.mode == .down { state.clear(.localAssetsBlocked) }
        load(forced: true)
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
                } else {
                    self.apply(read)
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
        /// The file couldn't be read. `html` is the page that takes the
        /// document's place when there is no document yet; a read that fails
        /// over one already on screen keeps it instead, so which of the two
        /// notices frames `reason` is `apply(_:)`'s to decide, not the read's.
        ///
        /// The page and the reason both travel because neither derives from
        /// the other here: the page is built from the underlying `Error` the
        /// read has in hand, and the reason is the three-way split the bar's
        /// wording turns on.
        case unreadable(html: String, reason: DocumentNotice.ReadFailure)
        /// There is nothing to show and nothing went wrong: the folder holds
        /// no Markdown. The blank page and its notice go up whether or not a
        /// document was there before, because a folder that has emptied really
        /// has nothing left to show.
        case blank(html: String, notice: DocumentNotice)
    }

    private func readDisk() -> DiskRead {
        if MarkdownFolder.isFolder(fileURL) {
            return readFolder()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                return .unreadable(
                    html: ErrorPage.fileEncodingError(), reason: .badEncoding)
            }
            return .text(text, notice: nil)
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return .unreadable(
                html: ErrorPage.fileNotFound(error: cocoaError),
                reason: .notFound)
        } catch {
            return .unreadable(
                html: ErrorPage.filePermissionDenied(
                    path: fileURL.path, error: error),
                reason: .noPermission)
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
            return .blank(
                html: ErrorPage.empty(), notice: .folderHasNoMarkdown)
        }
        let tree = FolderIndex.walk(fileURL)
        guard !tree.isEmpty else {
            return .blank(
                html: ErrorPage.empty(), notice: .folderHasNoMarkdown)
        }
        let notice: DocumentNotice? = tree.isTruncated
            ? .folderIndexTruncated(limit: FolderIndex.fileLimit)
            : nil
        return .text(FolderIndex.markdown(for: tree), notice: notice)
    }

    private func loadFromDisk() {
        apply(readDisk())
    }

    /// Shows what a read produced.
    ///
    /// A read that fails over a document already on screen is the one case
    /// that changes nothing but the info bar. The document is still the last
    /// version Mud read of that file, and it is worth more than the error page
    /// would be: an unreadable file is often unreadable only for a moment (a
    /// rename, an editor's atomic save, a volume that dropped out), and
    /// replacing the document would throw away the reader's place in it to say
    /// so. `reloadFailed` says it instead.
    ///
    /// With nothing to keep — the first read of the window, or a retry after
    /// one that already failed — the error page goes up as before. Either way
    /// the read's `ReadFailure` picks the sentence, so the bar names what went
    /// wrong even where the page it sits over is blank.
    private func apply(_ read: DiskRead) {
        switch read {
        case .text(let text, let notice):
            applyLoaded(text)
            // `applyLoaded` has already cleared the notices a good read
            // settles, so a re-walk that now fits leaves the bar empty.
            if let notice { state.raise(notice) }
        case .blank(let html, let notice):
            setContent(.error(html))
            state.raise(notice)
        case .unreadable(let html, let reason):
            let fileName = fileURL.lastPathComponent
            guard hasDocument else {
                setContent(.error(html))
                state.raise(.openFailed(fileName: fileName, reason: reason))
                return
            }
            state.raise(.reloadFailed(fileName: fileName, reason: reason))
        }
    }

    /// Whether a read has already put a document on screen — what a failed
    /// reload keeps there. False before the first read, and false when that
    /// read put up an error page: there is nothing behind it worth keeping, so
    /// a second failure leaves the page and its diagnosis where they are.
    private var hasDocument: Bool {
        guard case .parsed = content else { return false }
        return contentVersion > 0
    }

    /// Parses `text` and refreshes per-document state (the render, headings,
    /// comments, title, change tracking). The single place a successful disk
    /// read becomes the displayed document.
    private func applyLoaded(_ text: String) {
        // The file read this time, so whatever stopped it last time is over —
        // whichever of the two notices that raised.
        state.clear(.openFailed)
        state.clear(.reloadFailed)
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
