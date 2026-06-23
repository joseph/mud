import SwiftUI
import WebKit
import MudPreferences
import MudCore

/// The Comments sidebar pane: a small master/detail. A **list** of the
/// document's comments (document order) swaps to a **thread view** for the
/// selected comment (or a *create* compose when a selection is pending). The
/// existing messages render read-only in a `WKWebView`; the compose box is a
/// native SwiftUI `TextEditor` — and because the sidebar lives in the document
/// window (the key window), it takes keystrokes with no popover/key-window
/// workaround. Writes go through `CommentController`; the `FileWatcher` reload
/// refreshes `state.comments` and the document render.
struct CommentsSidebarView: View {
    let fileURL: URL
    @ObservedObject var state: DocumentState

    var body: some View {
        if let draft = state.pendingDraft {
            CommentThreadView(
                fileURL: fileURL, state: state, mode: .create(draft))
        } else if let label = state.activeCommentLabel,
                  let comment = state.comments.first(where: { $0.label == label }) {
            CommentThreadView(
                fileURL: fileURL, state: state, mode: .edit(comment))
        } else {
            CommentListView(state: state)
        }
    }
}

// MARK: - List

private struct CommentListView: View {
    @ObservedObject var state: DocumentState

    var body: some View {
        if state.comments.isEmpty {
            emptyState
        } else {
            List(state.comments, selection: selectionBinding) { comment in
                CommentRow(comment: comment)
            }
            .listStyle(.sidebar)
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { state.activeCommentLabel },
            set: { state.activeCommentLabel = $0 })
    }

    private var emptyState: some View {
        VStack {
            ContentUnavailableView(
                "No Comments",
                systemImage: "text.bubble",
                description: Text("Select text and choose\nAdd Comment to start.")
            )
            Spacer()
        }
        .padding(.top, 16)
    }
}

private struct CommentRow: View {
    let comment: Comment

    private var snippet: String {
        if let quotation = comment.quotation, !quotation.isEmpty {
            return quotation
        }
        return comment.messages.first?.body ?? "—"
    }

    private var attribution: String? {
        guard let message = comment.messages.first else { return nil }
        var parts: [String] = []
        if let author = message.author, !author.isEmpty { parts.append(author) }
        if let created = message.created { parts.append(created.shortTimestamp) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if comment.quotation != nil {
                Text(snippet)
                    .font(.callout)
                    .italic()
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
            } else {
                Text(snippet)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            HStack(spacing: 6) {
                if let attribution {
                    Text(attribution)
                }
                if comment.messages.count > 1 {
                    Text("· \(comment.messages.count) messages")
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Thread + compose

private struct CommentThreadView: View {
    enum Mode {
        case create(CommentDraft)
        case edit(Comment)
    }

    let fileURL: URL
    @ObservedObject var state: DocumentState
    let mode: Mode
    @ObservedObject private var appState = AppState.shared

    @State private var text = ""
    @State private var editingLast = false
    @State private var errorMessage: String?
    @FocusState private var composeFocused: Bool

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The author written into new messages — the `comment-author` preference,
    /// which resolves to the system full name when unset.
    private var author: String { appState.commentAuthor }

    private var controller: CommentController {
        CommentController(fileURL: fileURL) { state.registerSelfWrite($0) }
    }

    private var threadComment: Comment {
        switch mode {
        case .create(let draft):
            return Comment(
                label: "", ordinal: 0,
                quotation: draft.quotation.isEmpty ? nil : draft.quotation,
                messages: [])
        case .edit(let comment):
            return comment
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            CommentThreadWebView(html: threadHTML, baseURL: fileURL)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            composer
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: close) {
                Label("Comments", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
                    .font(.callout)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(height: 64)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color(nsColor: .separatorColor)))
                .focused($composeFocused)
            actions
        }
        .padding(8)
        .onAppear {
            if isCreate { composeFocused = true }
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack {
            switch mode {
            case .create:
                Button("Cancel", action: close)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            case .edit(let comment):
                if editingLast {
                    Button("Cancel") { editingLast = false; text = "" }
                    Spacer()
                    Button("Save") { saveEdit(comment) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmed.isEmpty)
                } else {
                    Button("Delete", role: .destructive) { delete() }
                    Spacer()
                    if !comment.messages.isEmpty {
                        Button("Edit last") {
                            text = comment.messages.last?.body ?? ""
                            editingLast = true
                            composeFocused = true
                        }
                    }
                    Button("Reply") { reply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(trimmed.isEmpty)
                }
            }
        }
    }

    // MARK: Actions

    private func close() {
        state.pendingDraft = nil
        state.activeCommentLabel = nil
    }

    private func add() {
        guard case .create(let draft) = mode else { return }
        if controller.addComment(draft, author: author, body: trimmed) {
            close()
        } else {
            errorMessage = "Couldn't anchor this selection. Try selecting plain "
                + "body text (not a code block)."
        }
    }

    private func reply() {
        guard case .edit(let comment) = mode else { return }
        if controller.reply(toLabel: comment.label, author: author, body: trimmed) {
            text = ""
        }
    }

    private func saveEdit(_ comment: Comment) {
        if controller.editLastMessage(label: comment.label, body: trimmed) {
            editingLast = false
            text = ""
        }
    }

    private func delete() {
        guard case .edit(let comment) = mode else { return }
        _ = controller.delete(label: comment.label)
        state.activeCommentLabel = nil
    }

    // MARK: Rendering

    private var threadHTML: String {
        var opts = RenderOptions()
        opts.baseURL = fileURL
        opts.theme = appState.theme.rawValue
        opts.commentMode = .interactive
        return MudCore.renderCommentThreadDocument(
            threadComment, options: opts,
            resolveImageSource: DocumentContentView.mudAssetResolver)
    }
}

// MARK: - Read-only thread web view

/// Renders a comment thread document read-only. Declines first responder so it
/// never steals focus from the sibling compose `TextEditor`.
private struct CommentThreadWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(),
                                   forURLScheme: "mud-asset")
        let webView = NonFocusingWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHTML: String?

        // Read-only: allow the initial load only, cancel link navigations.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            decisionHandler(
                navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}

private final class NonFocusingWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}
