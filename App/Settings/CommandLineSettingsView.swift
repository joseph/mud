import SwiftUI

struct CommandLineSettingsView: View {
    @State private var selectedLocation = 0
    @State private var customDirectory: String?
    @State private var statusMessage: String?
    @State private var isError = false

    private let locations = CommandLineInstaller.defaultLocations

    var body: some View {
        Form {
            Section {
                Text("Create a \"mud\" symlink so you can easily open Markdown documents from the terminal.")
                    .foregroundStyle(.secondary)

                Picker("Location", selection: $selectedLocation) {
                    ForEach(locations.indices, id: \.self) { index in
                        Text(locations[index]).tag(index)
                    }
                    Text("Other…").tag(locations.count)
                }
                .onChange(of: selectedLocation) { _, newValue in
                    if newValue == locations.count {
                        if let chosen = CommandLineInstaller.chooseDirectory() {
                            customDirectory = chosen
                        } else {
                            // Cancelled — revert to first preset
                            selectedLocation = 0
                            customDirectory = nil
                        }
                    } else {
                        customDirectory = nil
                    }
                }

                if let custom = customDirectory {
                    Text(custom)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                HStack {
                    Spacer()
                    Button("Install") {
                        performInstall()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            if let message = statusMessage {
                Section {
                    Label(
                        message,
                        systemImage: isError ? "xmark.circle" : "checkmark.circle"
                    )
                    .foregroundStyle(isError ? .red : .secondary)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadCurrentStatus()
        }
    }

    private func resolvedDirectory() -> String {
        if let custom = customDirectory {
            return custom
        }
        let title = locations[min(selectedLocation, locations.count - 1)]
        return (title as NSString).expandingTildeInPath
    }

    private func performInstall() {
        let directory = resolvedDirectory()
        do {
            let path = try CommandLineInstaller.install(to: directory)
            statusMessage = "Installed at \(path)"
            isError = false
        } catch {
            statusMessage = error.localizedDescription
            isError = true
        }
    }

    private func loadCurrentStatus() {
        if let path = CommandLineInstaller.installedPath {
            statusMessage = "Installed at \(path)"
            isError = false

            // Pre-select the matching location
            let dir = ((path as NSString).expandingTildeInPath as NSString)
                .deletingLastPathComponent
            let abbreviated = CommandLineInstaller.abbreviate(dir)
            if let index = locations.firstIndex(of: abbreviated) {
                selectedLocation = index
            }
        }
    }
}
