import SwiftUI
import MudPreferences

struct GeneralSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                LabeledContent("Lighting") {
                    HStack(spacing: 12) {
                        ForEach(Lighting.allCases, id: \.self) { lighting in
                            LightingPreviewCard(
                                lighting: lighting,
                                isSelected: appState.lighting == lighting
                            ) {
                                appState.lighting = lighting
                            }
                            .frame(width: 72)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Picker("Floating controls", selection: $appState.uiFloatingControlsPosition) {
                    ForEach(FloatingControlsPosition.allCases, id: \.self) { position in
                        Text(position.label).tag(position)
                    }
                }
                Text("Window location where the Find bar and Changes bar appear.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $appState.uiUseHeadingAsTitle) {
                    Text("First heading as window title")
                    Text("Take the text of the first heading in the document as the title in the toolbar. When off, use the filename.")
                }
            }

            Section {
                Toggle(isOn: Binding(
                    get: { appState.viewToggles.contains(.readableColumn) },
                    set: { _ in appState.toggle(.readableColumn) }
                )) {
                    Text("Readable column")
                    Text("Constrain content to a comfortable reading width — no more than about 80 characters per line.")
                }
            }

            Section {
                Toggle("Quit when last window closes", isOn: $appState.quitOnClose)
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
