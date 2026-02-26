import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Picker("Lighting", selection: Binding(
                    get: { appState.lighting },
                    set: { newValue in
                        appState.lighting = newValue
                        appState.saveLighting(newValue)
                    }
                )) {
                    Text("System").tag(Lighting.auto)
                    Text("Bright").tag(Lighting.bright)
                    Text("Dark").tag(Lighting.dark)
                }
                .pickerStyle(.segmented)
            }

            Section {
                Toggle("Readable Column", isOn: Binding(
                    get: { appState.viewToggles.contains(.readableColumn) },
                    set: { _ in appState.toggle(.readableColumn) }
                ))
            }

            Section {
                Toggle("Quit when last window closes", isOn: Binding(
                    get: { appState.quitOnClose },
                    set: { newValue in
                        appState.quitOnClose = newValue
                        appState.saveQuitOnClose()
                    }
                ))
            }
        }
        .formStyle(.grouped)
    }
}
