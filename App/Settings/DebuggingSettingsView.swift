import SwiftUI
import MudPreferences

struct DebuggingSettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var openIn = OpenInMenuModel.shared
    @State private var showingConfirmation = false
    @State private var didReset = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Sandbox") {
                    Image(systemName: "circle.fill")
                        .foregroundStyle(isSandboxed ? .green : .red)
                        .font(.system(size: 8))
                }
            }

            Section("Change Tracking") {
                Slider(
                    value: $appState.changesWordDiffThreshold,
                    in: 0.0...1.0,
                    step: 0.05
                ) {
                    Text("Word diff threshold")
                    Text("How much can a block change before word highlights are hidden?")
                } minimumValueLabel: {
                    Text("0%")
                } maximumValueLabel: {
                    Text("100%")
                }
            }

            Section("Open In") {
                Text("Forget the default editor chosen for “Open In…”, so the toolbar button reverts to offering the full list.")
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Clear Choice for “Open In…”") {
                        clearOpenInChoice()
                    }
                    .disabled(openIn.configured == nil)
                }
            }

            Section("Application Data") {
                Text("Remove all saved preferences and restore factory defaults. The app will quit so changes take full effect.")
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Reset All Preferences…") {
                        showingConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18)
        .confirmationDialog(
            "Reset all preferences?",
            isPresented: $showingConfirmation
        ) {
            Button("Reset and Quit", role: .destructive) {
                resetAllPreferences()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will clear all saved settings and quit the app. Your documents will not be affected.")
        }
    }

    /// Clears the remembered "Open In…" default so the toolbar button drops back
    /// to the grid icon and the full chooser. `refresh()` republishes
    /// `configured`, updating every window's button and this pane in step.
    private func clearOpenInChoice() {
        MudPreferences.shared.openInDefaultBundleID = nil
        MudPreferences.shared.openInDefaultFormat = .auto
        OpenInMenuModel.shared.refresh()
    }

    private func resetAllPreferences() {
        MudPreferences.shared.reset()
        if let bundleID = Bundle.main.bundleIdentifier {
            removeSavedApplicationState(bundleID: bundleID)
        }
        exit(0)
    }

    private func removeSavedApplicationState(bundleID: String) {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
        guard let savedStateDir = library?
            .appendingPathComponent("Saved Application State")
            .appendingPathComponent("\(bundleID).savedState")
        else { return }
        try? FileManager.default.removeItem(at: savedStateDir)
    }
}
