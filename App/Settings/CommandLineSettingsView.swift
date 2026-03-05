import SwiftUI

struct CommandLineSettingsView: View {
    var body: some View {
        if isSandboxed {
            appStoreView
        } else {
            automaticInstallView
        }
    }

    // MARK: - App Store release (sandboxed)

    private var aliasCommand: String {
        let path = Bundle.main.bundlePath
        return "alias mud='open -a \"\(path)\"'"
    }

    private var appStoreView: some View {
        Form {
            Section {
                Text("Add a shell alias to open Markdown files in Mud from the terminal.")
                    .foregroundStyle(.secondary)

                Text(aliasCommand)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)

                Text("Add this to your ~/.zshrc or ~/.bashrc.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section {
                HStack(spacing: 0) {
                    Text("Learn more about ")
                        .foregroundStyle(.secondary)
                    Button("command-line usage") {
                        SettingsWindowController.shared.window?.close()
                        DocumentController.openBundledDocument("command-line", subdirectory: "Doc/Guides")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.link)
                    Text(" of Mud.")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }

    // MARK: - Automatic install (non-sandboxed)

    @State private var selectedLocation = 0
    @State private var customDirectory: String?
    @State private var statusMessage: String?
    @State private var isError = false

    private let locations = CommandLineInstaller.defaultLocations

    private var automaticInstallView: some View {
        Form {
            Section {
                Text("Create a \"mud\" symlink so you can easily open Markdown documents from the command line.")
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
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
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
