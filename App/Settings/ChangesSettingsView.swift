import SwiftUI
import MudPreferences

struct ChangesSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $appState.changesShowInlineDeletions) {
                    Text("Inline deletions")
                    Text("Show replaced words with strikethrough alongside new words in changed blocks.")
                }
                Toggle(isOn: Binding(
                    get: { appState.viewToggles.contains(.autoExpandChanges) },
                    set: { _ in appState.toggle(.autoExpandChanges) }
                )) {
                    Text("Auto-expand changes")
                    Text("Expand deletion and mixed change groups by default, rather than collapsing them.")
                }
                if WaypointProviders.isAvailable {
                    Toggle(isOn: $appState.changesShowGitWaypoints) {
                        Text("Git commits")
                        Text("Show comparisons against git history in the Changes menu.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
