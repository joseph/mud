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
            searchQuery: findState.currentQuery,
            scrollTarget: state.scrollTarget,
            changeScrollTarget: state.changeScrollTarget,
            reloadID: state.reloadID,
            printID: state.printID,
            addCommentID: state.addCommentID,
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
            // shortcuts resume.
            if !composing { contentFocused = true }
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
            // Reveal the column when a document that already has comments opens.
            // First-open only (not in loadFromDisk), so a later reload won't
            // re-show a column the user has since hidden.
            if !state.comments.isEmpty { state.commentsColumnVisible = true }
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

    /// Dispatches a column edit to `CommentController`. The write echoes back
    /// through the `FileWatcher`, refreshing `state.comments`, which re-pushes the
    /// comment data so the column reprojects in place (no reload).
    private func handleCommentSubmit(_ submission: CommentSubmission) {
        let controller = CommentController(fileURL: fileURL) { state.registerSelfWrite($0) }
        let author = appState.commentAuthor
        let body = submission.body ?? ""
        switch submission.action {
        case .add:
            guard let draft = submission.draft else { return }
            if let label = controller.addComment(draft, author: author, body: body) {
                state.pendingCommentLocators[label] = CommentLocator(
                    blockText: draft.blockText, offset: draft.offsetInBlock,
                    occurrence: draft.occurrence)
            }
        case .reply:
            guard let label = submission.label else { return }
            _ = controller.reply(toLabel: label, author: author, body: body)
        case .edit:
            guard let label = submission.label else { return }
            _ = controller.editLastMessage(label: label, body: body)
        case .delete:
            guard let label = submission.label else { return }
            _ = controller.deleteLastMessage(label: label)
        }
    }

    private func setupFileWatcher() {
        guard !fileURL.isBundleResource else { return }
        fileWatcher = FileWatcher(url: fileURL) {
            let text = loadFromDisk()
            // A reload echoing one of our own comment writes isn't an external
            // change: refresh the render (the new marker appears) but don't raise
            // the background-reload badge. A genuine external edit still does.
            let isSelfWrite = text.map { state.consumeSelfWrite($0) } ?? false
            if !isSelfWrite, state.windowController?.window?.isKeyWindow != true {
                state.hasBackgroundReload = true
            }
        }
    }

    /// Reads the file, parses, and refreshes per-document state. Returns the
    /// loaded source text (nil on a read/decoding failure) so the file-watcher
    /// echo can match it against a pending self-write; other callers discard it.
    @discardableResult
    private func loadFromDisk() -> String? {
        do {
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                content = .error(ErrorPage.fileEncodingError())
                return nil
            }
            let parsed = ParsedMarkdown(text)
            content = .parsed(parsed)
            state.outlineHeadings = parsed.headings
            state.comments = MudCore.parseComments(text)
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
            return text
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            content = .error(ErrorPage.fileNotFound(error: cocoaError))
            return nil
        } catch {
            content = .error(ErrorPage.filePermissionDenied(path: fileURL.path, error: error))
            return nil
        }
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
