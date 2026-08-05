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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fileURL: URL { model.fileURL }

    private var displayTheme: Theme {
        if case .error = model.content { return .system }
        return appState.theme
    }

    var body: some View {
        let display = model.display()
        let renderOptions = model.renderOptions
        return WebView(
            html: display.html,
            baseURL: model.baseURL,
            contentID: display.contentID,
            mode: state.mode,
            theme: displayTheme,
            bodyClasses: renderOptions.htmlClasses,
            zoomLevel: renderOptions.zoomLevel,
            commentColumnWidth: appState.commentColumnWidth,
            searchQuery: findState.currentQuery,
            commands: state.webCommands,
            extensions: appState.enabledExtensions,
            footnoteHTML: display.footnoteHTML,
            comments: display.comments,
            commentLocators: model.pendingCommentLocators,
            onCommentSubmit: { submission in
                CommentSubmissionHandler(model: model, state: state)
                    .handle(submission)
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
            onRevealColumn: { label in
                // A marker click wants the column. The window controller owns
                // that: it makes room first (widening the window if need be),
                // persists the per-window toggle, and tells the page which
                // comment to open — or falls back to the bottom section.
                state.windowController?.revealComment(label)
            },
            onSearchResult: { info in
                findState.matchInfo = info
            }
        )
        .safeAreaInset(edge: .top, spacing: 0) {
            // The info bar, between the tab bar and the page. As a safe-area
            // inset it takes space from the WebView rather than covering it,
            // and SwiftUI measures it — a message that wraps to two lines just
            // makes the bar taller.
            ZStack {
                if let notice = state.notice {
                    DocumentNoticeBar(
                        notice: notice,
                        onDismiss: { state.dismissNotice() })
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.2), value: state.notice)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($contentFocused)
        .floatingBarsOverlay(
            findState: findState,
            changeTracker: changeTracker,
            commentsColumnVisible: state.commentsColumnVisible,
            onSelectChange: { changeIDs in
                state.webCommands.send(.scrollToChanges(changeIDs))
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
        .onChange(of: appState.changesShowGitWaypoints) { _, enabled in
            model.externalWaypointsSettingChanged(enabled: enabled)
        }
    }
}

// MARK: - Comparable Clamping

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
