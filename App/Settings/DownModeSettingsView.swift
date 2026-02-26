import SwiftUI

struct DownModeSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Toggle("Line Numbers", isOn: Binding(
                    get: { appState.viewToggles.contains(.lineNumbers) },
                    set: { _ in appState.toggle(.lineNumbers) }
                ))

                Toggle("Word Wrap", isOn: Binding(
                    get: { appState.viewToggles.contains(.wordWrap) },
                    set: { _ in appState.toggle(.wordWrap) }
                ))
            }
        }
        .formStyle(.grouped)
    }
}
