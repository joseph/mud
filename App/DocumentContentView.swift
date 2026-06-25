import SwiftUI
import Combine
import MudPreferences
import MudCore

// MARK: - Document Content View

private enum DocumentContent {
    case parsed(ParsedMarkdown)
    case error(String)  // pre-rendered error page HTML
}

struct DocumentContentView: View {
    let fileURL: URL
    @ObservedObject var state: DocumentState
    @ObservedObject var findState: FindState
    @ObservedObject var changeTracker: ChangeTracker
    @ObservedObject private var appState = AppState.shared

    @State private var content: DocumentContent = .parsed(ParsedMarkdown(""))
    @State private var fileWatcher: FileWatcher?
    @FocusState private var contentFocused: Bool
    @Environment(\.colorScheme) private var environmentColorScheme

    /// The HTML to display plus the footnote popover map (label → popover
    /// document HTML) and the parsed comments (for the Comments column). Up mode
    /// renders via the footnote API in `.popover` / `.interactive` modes so a
    /// single render yields the page, the popover bodies, and the comment model.
    private struct RenderedDisplay {
        let html: String
        let footnoteHTML: [String: String]
        var comments: [Comment] = []
    }

    private var renderedDisplay: RenderedDisplay {
        switch content {
        case .error(let html):
            return RenderedDisplay(html: html, footnoteHTML: [:])
        case .parsed(let parsed):
            if state.mode == .down {
                return RenderedDisplay(
                    html: MudCore.renderDownModeDocument(parsed, options: renderOptions),
                    footnoteHTML: [:])
            }
            var opts = renderOptions
            opts.footnoteMode = .popover
            opts.commentMode = .interactive
            // The live view is editable, so embed the write-side comment styles.
            opts.commentsEditable = true
            let document = MudCore.renderUpModeDocumentWithFootnotes(
                parsed.markdown, options: opts,
                resolveImageSource: Self.mudAssetResolver)
            var map: [String: String] = [:]
            for footnote in document.footnotes {
                map[footnote.label.lowercased()] = footnote.html
            }
            return RenderedDisplay(
                html: document.html, footnoteHTML: map,
                comments: document.comments)
        }
    }

    private var displayTheme: Theme {
        if case .error = content { return .system }
        return appState.theme
    }

    private var renderOptions: RenderOptions {
        var opts = RenderOptions()
        opts.baseURL = fileURL
        opts.theme = appState.theme.rawValue
        opts.blockRemoteContent = !appState.upModeAllowRemoteContent
        opts.docCAlertMode = appState.markdownDocCAlertMode
        opts.extensions = appState.enabledExtensions
        opts.htmlClasses = Set(appState.viewToggles.map(\.className))
        // Column visibility is per-window state, not a persisted view toggle.
        if state.commentsColumnVisible { opts.htmlClasses.insert("is-comments-column") }
        // Read live by the compose box's keydown handler (mud-comments-edit.js).
        if appState.commentReturnSaves { opts.htmlClasses.insert("comment-return-saves") }
        opts.zoomLevel = modeZoomLevel
        opts.showInlineDeletions = appState.changesShowInlineDeletions
        opts.wordDiffThreshold = appState.changesWordDiffThreshold
        if appState.changesEnabled && !changeTracker.changes.isEmpty {
            opts.waypoint = changeTracker.activeWaypoint
        }
        return opts
    }

    private var displayContentID: String {
        switch content {
        case .parsed(let parsed):
            // Up mode is comment-invariant: a comment add/remove leaves the ID
            // unchanged, so the WebView doesn't reload — `mud-comments.js` syncs
            // the marker in place. Down mode keeps the full markdown so its raw
            // source reflects the comment (un-highlighted, via the diff fix).
            let body = state.mode == .up
                ? MudCore.removeComments(parsed.markdown)
                : parsed.markdown
            return "\(body)\(renderOptions.contentIdentity)"
        case .error:              return "load-error"
        }
    }

    /// Rewrites local image paths to `mud-asset:` URLs for WKWebView. Also used
    /// by the coordinator when rendering comment items for the column.
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

    private var modeZoomLevel: Double {
        state.mode == .down
            ? appState.downModeZoomLevel
            : appState.upModeZoomLevel
    }

    var body: some View {
        let display = renderedDisplay
        return WebView(
            html: display.html,
            baseURL: fileURL,
            contentID: displayContentID,
            mode: state.mode,
            theme: displayTheme,
            bodyClasses: renderOptions.htmlClasses,
            zoomLevel: renderOptions.zoomLevel,
            commentColumnWidth: appState.commentColumnWidth,
            searchQuery: findState.currentQuery,
            scrollTarget: state.scrollTarget,
            changeScrollTarget: state.changeScrollTarget,
            reloadID: state.reloadID,
            printID: state.printID,
            actualSizeID: state.actualSizeID,
            addCommentID: state.addCommentID,
            composeResolution: state.composeResolution,
            externalChangeHeld: state.externalChangeHeld,
            extensions: appState.enabledExtensions,
            footnoteHTML: display.footnoteHTML,
            comments: display.comments,
            commentLocators: state.pendingCommentLocators,
            onCommentSubmit: { submission in
                handleCommentSubmit(submission)
            },
            onComposing: { composing in
                state.isColumnComposing = composing
            },
            onCommentableSelection: { has in
                state.commentableSelection.send(has)
            },
            onColumnWidthChange: { width in
                appState.commentColumnWidth = width
            },
            onSearchResult: { info in
                findState.matchInfo = info
            }
        )
        .focusable()
        .focusEffectDisabled()
        .focused($contentFocused)
        .floatingBarsOverlay(
            findState: findState,
            changeTracker: changeTracker,
            commentsColumnVisible: state.commentsColumnVisible,
            onSelectChange: { changeIDs in
                state.changeScrollTarget = ChangeScrollTarget(
                    id: UUID(), changeIDs: changeIDs)
            }
        )
        .frame(minWidth: 500, minHeight: 400)

        .onKeyPress(.space) {
            // Let the keystroke reach an in-webview compose textarea.
            guard !findState.isVisible, !state.isComposingComment else { return .ignored }
            deferMutation { state.toggleMode() }
            return .handled
        }
        .onKeyPress(.escape) {
            guard findState.isVisible else { return .ignored }
            findState.close()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "/")) { _ in
            guard !findState.isVisible, !state.isComposingComment else { return .ignored }
            NSApp.sendAction(#selector(DocumentWindowController.performFindAction(_:)), to: nil, from: nil)
            return .handled
        }
        .onChange(of: findState.isVisible) { _, isVisible in
            if !isVisible { contentFocused = true }
        }
        .onChange(of: state.mode) { _, _ in
            if findState.isVisible { findState.close() }
        }
        .onChange(of: state.isComposingComment) { _, composing in
            // When the compose box closes, take keyboard focus back so document
            // shortcuts resume, and apply any external change held while it was
            // open (re-reading disk so a successful comment write is included).
            if !composing {
                contentFocused = true
                state.externalChangeHeld = false  // banner goes with the box
                if state.pendingExternalReload {
                    state.pendingExternalReload = false
                    loadFromDisk()
                }
            }
        }
        .onChange(of: contentFocused) { _, focused in
            // Reclaim focus so document keyboard shortcuts (space, `/`) keep
            // working — but not while Find or the Comments compose box legitimately
            // owns first responder, or it could never be typed into.
            if !focused && !findState.isVisible && !state.isComposingComment {
                contentFocused = true
            }
        }
        .onAppear {
            contentFocused = true
            loadFromDisk()
            setupFileWatcher()
        }
        .onDisappear {
            fileWatcher = nil
        }
        .onChange(of: state.reloadID) { _, id in
            if id != nil {
                loadFromDisk()
                setupFileWatcher()
            }
        }
        .onChange(of: state.openInBrowserID) { _, id in
            if id != nil { openInBrowser() }
        }
        .onChange(of: state.openInEditorRequest?.id) { _, id in
            if id != nil, let request = state.openInEditorRequest {
                openInEditor(request)
            }
        }
        #if GIT_PROVIDER
        .onChange(of: appState.changesShowGitWaypoints) { _, enabled in
            if enabled {
                if case .parsed(let parsed) = content {
                    refreshGitWaypoints(for: parsed.markdown)
                }
            } else {
                changeTracker.setExternalWaypoints([])
            }
        }
        #endif
    }

    /// Dispatches a column edit to `CommentController`, then acknowledges the
    /// outcome back to the page (`resolveCompose`). On success the write echoes
    /// through the `FileWatcher`, refreshing `state.comments`, which re-pushes the
    /// comment data so the column reprojects in place (no reload). On failure the
    /// box stays open with its text and we explain why (the most likely cause is
    /// the quoted text changing on disk while the box was held open).
    private func handleCommentSubmit(_ submission: CommentSubmission) {
        let controller = CommentController(fileURL: fileURL) { state.registerSelfWrite($0) }
        let author = appState.commentAuthor
        let body = submission.body ?? ""
        switch submission.action {
        case .add:
            guard let draft = submission.draft else { resolveCompose(false); return }
            if let label = controller.addComment(draft, author: author, body: body) {
                state.pendingCommentLocators[label] = CommentLocator(
                    blockText: draft.blockText, offset: draft.offsetInBlock,
                    occurrence: draft.occurrence)
                resolveCompose(true)
            } else {
                resolveCompose(false)
                presentCommentFailure(
                    message: "The text you commented on has changed, "
                        + "so the comment couldn't be placed. "
                        + "Your note is still in the compose box.",
                    note: body)
            }
        case .reply:
            guard let label = submission.label else { resolveCompose(false); return }
            let ok = controller.reply(toLabel: label, author: author, body: body)
            resolveCompose(ok)
            if !ok { presentCommentFailure(message: replyFailureMessage, note: body) }
        case .edit:
            guard let label = submission.label else { resolveCompose(false); return }
            let ok = controller.editLastMessage(label: label, body: body)
            resolveCompose(ok)
            if !ok { presentCommentFailure(message: replyFailureMessage, note: body) }
        case .delete:
            guard let label = submission.label else { return }
            _ = controller.deleteLastMessage(label: label)
        }
    }

    private var replyFailureMessage: String {
        "The comment has changed or been removed, "
            + "so your text couldn't be saved. It is still in the compose box."
    }

    /// Pushes the submit outcome to the page. A fresh `id` makes `WebView` fire it
    /// once, so the compose box closes (success) or re-enables (failure).
    private func resolveCompose(_ success: Bool) {
        state.composeResolution = ComposeResolution(id: UUID(), success: success)
    }

    /// Explains a comment write that couldn't be completed, keeping the user's
    /// text recoverable: the box stays open (the page re-enables it on the false
    /// resolve) and "Copy Note" puts the body on the clipboard. Deferred past the
    /// current run loop so the `resolveCompose` render lands — and re-enables the
    /// box — before this modal blocks the main thread.
    private func presentCommentFailure(message: String, note: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Couldn't save your comment"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            if !note.isEmpty { alert.addButton(withTitle: "Copy Note") }
            let response = alert.runModal()
            if !note.isEmpty, response == .alertSecondButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note, forType: .string)
            }
        }
    }

    private func setupFileWatcher() {
        guard !fileURL.isBundleResource else { return }
        fileWatcher = FileWatcher(url: fileURL) {
            let read = readDisk()
            // While a compose box is open, hold the change instead of applying
            // it: applying would move `displayContentID`, reload the page, and
            // destroy the box and its unsaved text. A read failure (e.g. a
            // transient gap mid atomic-save) is held the same way, so it can't
            // tear the box down either. The held change applies when composing
            // ends (`onChange(of: state.isComposingComment)`).
            guard case .text(let text) = read else {
                if state.isComposingComment {
                    state.pendingExternalReload = true
                } else if case .failure(let html) = read {
                    content = .error(html)
                }
                return
            }
            // Consume a pending self-write (our own comment echo) so the set
            // stays bounded and a later genuine edit isn't misread.
            let isSelfWrite = state.consumeSelfWrite(text)
            // While composing, hold *every* change — external edits and our own
            // comment echo alike — so the page and the open box are never torn
            // down mid-edit. One `loadFromDisk` at compose-end applies whatever
            // is on disk by then (held prose, the new marker, or both). Holding
            // the self-write too matters: when a held external change and the
            // comment land in the same write, applying its echo now would change
            // the prose, reload the page, and strand the box.
            if state.isComposingComment {
                state.pendingExternalReload = true
                // Only a genuine external edit raises the banner; our own comment
                // echo is held too but isn't "the file changed under you".
                if !isSelfWrite { state.externalChangeHeld = true }
                return
            }
            applyLoaded(text)
            if !isSelfWrite, state.windowController?.window?.isKeyWindow != true {
                state.hasBackgroundReload = true
            }
        }
    }

    /// The outcome of reading the document off disk: the decoded source, or the
    /// error-page HTML to show. Pure — it does not mutate `content` — so the
    /// file-watcher can classify a change (self-write? composing?) before
    /// deciding whether to apply or hold it.
    private enum DiskRead {
        case text(String)
        case failure(String)  // pre-rendered error page HTML
    }

    private func readDisk() -> DiskRead {
        do {
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                return .failure(ErrorPage.fileEncodingError())
            }
            return .text(text)
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            return .failure(ErrorPage.fileNotFound(error: cocoaError))
        } catch {
            return .failure(
                ErrorPage.filePermissionDenied(path: fileURL.path, error: error))
        }
    }

    /// Reads the file and applies it. Returns the loaded source text (nil on a
    /// read/decoding failure), used by callers that need it; others discard it.
    @discardableResult
    private func loadFromDisk() -> String? {
        switch readDisk() {
        case .text(let text):
            applyLoaded(text)
            return text
        case .failure(let html):
            content = .error(html)
            return nil
        }
    }

    /// Parses `text` and refreshes per-document state (the render, headings,
    /// comments, title, change tracking). The single place a successful disk
    /// read becomes the displayed document.
    private func applyLoaded(_ text: String) {
        let parsed = ParsedMarkdown(text)
        content = .parsed(parsed)
        state.outlineHeadings = parsed.headings
        let hadComments = !state.comments.isEmpty
        state.comments = MudCore.parseComments(text)
        // Reveal the Comments Column when a document gains its first comment —
        // whether on first open or on a reload that adds one. A reload that
        // keeps existing comments (1+ → 1+) makes no change here, so a column
        // the user has hidden stays hidden.
        if !hadComments, !state.comments.isEmpty {
            state.commentsColumnVisible = true
        }
        // Drop locators for comments that no longer exist (e.g. deleted), so
        // a never-reused label can't misdirect a future live insert.
        let liveLabels = Set(state.comments.map(\.label))
        state.pendingCommentLocators = state.pendingCommentLocators
            .filter { liveLabels.contains($0.key) }
        state.contentTitle = parsed.title
        changeTracker.update(parsed)
        #if GIT_PROVIDER
        refreshGitWaypoints(for: text)
        #endif
    }

    #if GIT_PROVIDER
    private func refreshGitWaypoints(for text: String) {
        guard appState.changesShowGitWaypoints,
              !fileURL.isBundleResource else {
            changeTracker.setExternalWaypoints([])
            return
        }
        let url = fileURL
        let tracker = changeTracker
        Task {
            let waypoints = await Task.detached {
                GitProvider(fileURL: url).queryWaypoints(currentContent: text)
            }.value
            tracker.setExternalWaypoints(waypoints)
        }
    }
    #endif

    private func openInEditor(_ request: EditorLaunchRequest) {
        let target: URL
        switch request.format {
        case .markdown, .auto:
            // `.auto` should be resolved to `.markdown` or `.html` upstream;
            // treat as markdown as a safe fallback.
            target = fileURL
        case .html:
            guard case .parsed(let parsed) = content,
                  let url = renderToTempHTML(parsed: parsed)
            else { return }
            target = url
        }
        NSWorkspace.shared.open(
            [target],
            withApplicationAt: request.handler.appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private func renderToTempHTML(parsed: ParsedMarkdown) -> URL? {
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(baseName)
            .appendingPathExtension("html")
        var exportOptions = renderOptions
        exportOptions.standalone = true
        exportOptions.waypoint = nil
        // Unless comments are included, drop every comment from the source so
        // the exported file holds none at all (like the CLI's --exclude-comments).
        let markdown = appState.commentsIncludeInExport
            ? parsed.markdown : MudCore.removeComments(parsed.markdown)
        let html: String
        if state.mode == .down {
            html = MudCore.renderDownModeDocument(markdown,
                options: exportOptions)
        } else {
            // A commented document exports the read-only Comments column.
            exportOptions = MudCore.showingReadOnlyComments(
                exportOptions, ifPresentIn: markdown)
            html = MudCore.renderUpModeDocument(markdown,
                options: exportOptions,
                resolveImageSource: { source, baseURL in
                    ImageDataURI.encode(source: source, baseURL: baseURL)
                })
        }
        guard let data = html.data(using: .utf8) else { return nil }
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }

    private func openInBrowser() {
        guard case .parsed(let parsed) = content else { return }
        // Unless comments are included, drop every comment from the source so
        // the exported file holds none at all (like the CLI's --exclude-comments).
        let text = appState.commentsIncludeInExport
            ? parsed.markdown : MudCore.removeComments(parsed.markdown)
        let tempDir = NSTemporaryDirectory()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let tempURL = URL(fileURLWithPath: tempDir)
            .appendingPathComponent(baseName)
            .appendingPathExtension("html")
        var exportOptions = renderOptions
        exportOptions.standalone = true
        exportOptions.waypoint = nil
        let exportHTML: String
        if state.mode == .down {
            exportHTML = MudCore.renderDownModeDocument(text,
                options: exportOptions)
        } else {
            // A commented document exports the read-only Comments column.
            exportOptions = MudCore.showingReadOnlyComments(
                exportOptions, ifPresentIn: text)
            exportHTML = MudCore.renderUpModeDocument(text,
                options: exportOptions,
                resolveImageSource: { source, baseURL in
                    ImageDataURI.encode(source: source, baseURL: baseURL)
                })
        }
        guard let data = exportHTML.data(using: .utf8) else { return }
        try? data.write(to: tempURL)
        guard let browserURL = NSWorkspace.shared.urlForApplication(
            toOpen: URL(string: "https://example.com")!
        ) else { return }
        NSWorkspace.shared.open(
            [tempURL],
            withApplicationAt: browserURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

// MARK: - Comparable Clamping

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
