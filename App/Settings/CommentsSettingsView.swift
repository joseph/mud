import SwiftUI
import MudPreferences

struct CommentsSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    /// What a new comment is actually attributed to, mirroring
    /// `MudPreferences.commentAuthor`'s blank-falls-back-to-full-name rule, so
    /// the preview below stays truthful while the field is empty.
    private var effectiveAuthor: String {
        let trimmed = appState.commentAuthor.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? NSFullUserName() : trimmed
    }

    var body: some View {
        Form {
            Section {
                TextField("Author", text: $appState.commentAuthor,
                          prompt: Text(NSFullUserName()))
                Text("The name associated with your comments. "
                     + "Leave blank to use your system full name.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
