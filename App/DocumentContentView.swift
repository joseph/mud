import SwiftUI
import Combine
import MudPreferences
import MudCore

// MARK: - Document Content View

/// The SwiftUI layer of a document window: layout, key handling, and the
/// plumbing between `DocumentModel` / `DocumentState` and `WebView`. The
/// document's data — disk reads, the file watcher, the cached render — lives
/// on `DocumentModel`.
struct DocumentContentView: View {
    @ObservedObject var model: DocumentModel
    @ObservedObject var state: DocumentState
    @ObservedObject var findState: FindState
    @ObservedObject var changeTracker: ChangeTracker
    @ObservedObject private var appState = AppState.shared

    @FocusState private var contentFocused: Bool
    @Environment(\.colorScheme) private var environmentColorScheme

    private var fileURL: URL { model.fileURL }

    private var displayTheme: Theme {
        if case .error = model.content { return .system }
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
        // Shows the inline `💬` markers on screen; read by mud-comments.css/js.
        if appState.commentsShowMarkers { opts.htmlClasses.insert("show-comment-markers") }
        opts.zoomLevel = modeZoomLevel
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

    private var modeZoomLevel: Double {
        state.mode == .down
            ? appState.downModeZoomLevel
            : appState.upModeZoomLevel
    }

    var body: some View {
        let display = model.display(mode: state.mode, options: displayOptions)
        return WebView(
            html: display.html,
            baseURL: fileURL,
            contentID: display.contentID,
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
            externalChangeHeld: model.externalChangeHeld,
            extensions: appState.enabledExtensions,
            footnoteHTML: display.footnoteHTML,
            comments: display.comments,
            commentLocators: model.pendingCommentLocators,
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
            onRevealColumn: {
                // A marker click opened the column in JS; persist the per-window
                // toggle so the next class sync keeps it up.
                state.commentsColumnVisible = true
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
            // shortcuts resume. Applying a change held while it was open is the
            // model's job — it watches the same flag.
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
            model.load()
        }
        .onDisappear {
            model.stopWatching()
        }
        .onChange(of: state.reloadID) { _, id in
            if id != nil { model.load() }
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
            model.gitWaypointsSettingChanged(enabled: enabled)
        }
        #endif
    }

    /// Dispatches a column edit to `CommentController`, then acknowledges the
    /// outcome back to the page (`resolveCompose`). On success the write echoes
    /// through the `FileWatcher`, refreshing the comment data so the column
    /// reprojects in place (no reload). On failure the box stays open with its
    /// text and we explain why (the most likely cause is the quoted text
    /// changing on disk while the box was held open).
    private func handleCommentSubmit(_ submission: CommentSubmission) {
        let controller = CommentController(fileURL: fileURL) { model.registerSelfWrite($0) }
        let author = appState.commentAuthor
        let body = submission.body ?? ""
        // Respect a read-only or locked file: refuse every comment edit with a
        // clear message rather than atomically replacing a file the user marked
        // protected (an atomic write can replace a read-only file whose directory
        // is writable, so without this guard Mud would silently edit it).
        guard controller.isFileWritable else {
            if submission.action != .delete {
                resolveCompose(false, reason: "Cannot save: this file is read-only.")
            }
            presentCommentFailure(message: readOnlyFailureMessage, note: body)
            return
        }
        switch submission.action {
        case .add:
            guard let draft = submission.draft else { resolveCompose(false); return }
            switch controller.addComment(draft, author: author, body: body) {
            case .success(let label):
                model.pendingCommentLocators[label] = CommentLocator(
                    blockText: draft.blockText, offset: draft.offsetInBlock,
                    occurrence: draft.occurrence)
                resolveCompose(true)
            case .failure(.anchorFailed):
                resolveCompose(false, reason: "Cannot save: the highlighted text has changed.")
                presentCommentFailure(message: anchorFailureMessage, note: body)
            case .failure(.writeFailed):
                resolveCompose(false, reason: "Cannot save: Mud couldn't write to the file.")
                presentCommentFailure(message: writeFailureMessage, note: body)
            }
        case .reply:
            guard let label = submission.label else { resolveCompose(false); return }
            resolveThreadEdit(
                controller.reply(toLabel: label, author: author, body: body),
                note: body)
        case .edit:
            guard let label = submission.label else { resolveCompose(false); return }
            resolveThreadEdit(
                controller.editLastMessage(label: label, body: body),
                note: body)
        case .delete:
            guard let label = submission.label else { return }
            // No compose box to resolve. A vanished label means the comment is
            // already gone — the watcher reload catches the column up, so only
            // a failed disk write is worth an alert.
            if case .failure(.writeFailed) =
                controller.deleteLastMessage(label: label) {
                presentCommentFailure(message: deleteFailureMessage, note: "")
            }
        }
    }

    /// Acknowledges a reply/edit outcome to the page and, on failure, explains
    /// the actual cause: the comment vanishing from disk and the file refusing
    /// the write need different fixes, so they get different messages.
    private func resolveThreadEdit(
        _ result: Result<Void, CommentController.CommentWriteError>,
        note: String
    ) {
        switch result {
        case .success:
            resolveCompose(true)
        case .failure(.anchorFailed):
            resolveCompose(false, reason: "Cannot save: the comment has changed.")
            presentCommentFailure(message: replyFailureMessage, note: note)
        case .failure(.writeFailed):
            resolveCompose(false, reason: "Cannot save: Mud couldn't write to the file.")
            presentCommentFailure(message: writeFailureMessage, note: note)
        }
    }

    private var replyFailureMessage: String {
        "The comment has changed or been removed, "
            + "so your text couldn't be saved. It is still in the compose box."
    }

    /// The file is read-only or locked: Mud leaves it untouched and says so,
    /// rather than atomically replacing a file the user meant to protect.
    private var readOnlyFailureMessage: String {
        "This file is read-only, so Mud didn't change it. "
            + "Make it writable to add comments."
    }

    /// The marker couldn't be anchored: the quoted text no longer maps to a spot
    /// in the source (it changed on disk, or hit a mapping gap).
    private var anchorFailureMessage: String {
        "The text you commented on has changed, so the comment couldn't be "
            + "placed. Your note is still in the compose box."
    }

    /// The file itself couldn't be written (permission, lock, or another IO
    /// problem) — distinct from the text moving.
    private var writeFailureMessage: String {
        "Mud couldn't write to this file, so the comment couldn't be saved. "
            + "Check that the file is writable and not locked. "
            + "Your note is still in the compose box."
    }

    /// A delete that failed at the disk: there is no compose box to keep the
    /// text in, so this is the only signal the user gets.
    private var deleteFailureMessage: String {
        "Mud couldn't write to this file, so the comment couldn't be deleted. "
            + "Check that the file is writable and not locked."
    }

    /// Pushes the submit outcome to the page. A fresh `id` makes `WebView` fire it
    /// once, so the compose box closes (success) or re-enables (failure). On
    /// failure, `reason` is the short note shown inside the box.
    private func resolveCompose(_ success: Bool, reason: String? = nil) {
        state.composeResolution = ComposeResolution(
            id: UUID(), success: success, reason: reason)
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

    private func openInEditor(_ request: EditorLaunchRequest) {
        let target: URL
        switch request.format {
        case .markdown, .auto:
            // `.auto` should be resolved to `.markdown` or `.html` upstream;
            // treat as markdown as a safe fallback.
            target = fileURL
        case .html:
            guard case .parsed(let parsed) = model.content,
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

    /// A destination for an exported HTML file: `<basename>.html` (a readable
    /// browser-tab title) inside a fresh unique subdirectory, so two windows
    /// exporting same-named files (README.md in different folders) never race
    /// on one temp path.
    private func exportTempURL() -> URL? {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MudExport-\(UUID().uuidString)",
                                    isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return dir
            .appendingPathComponent(
                fileURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("html")
    }

    private func renderToTempHTML(parsed: ParsedMarkdown) -> URL? {
        guard let tempURL = exportTempURL() else { return nil }
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
        guard case .parsed(let parsed) = model.content else { return }
        // Unless comments are included, drop every comment from the source so
        // the exported file holds none at all (like the CLI's --exclude-comments).
        let text = appState.commentsIncludeInExport
            ? parsed.markdown : MudCore.removeComments(parsed.markdown)
        guard let tempURL = exportTempURL() else { return }
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
