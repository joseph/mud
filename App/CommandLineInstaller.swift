import AppKit

/// Manages installation of the `mud` command-line symlink.
enum CommandLineInstaller {
    private static let installedKey = "Mud-CLIInstalled"
    private static let symlinkPathKey = "Mud-CLISymlinkPath"

    // MARK: - Install dialog

    /// Presents an alert letting the user choose where to install the `mud`
    /// symlink.  Called from the menu item and from first-launch.
    static func showInstallDialog() {
        let alert = NSAlert()
        alert.messageText = "Install Command Line Tool"
        alert.informativeText =
            "Create a \"mud\" symlink so you can render Markdown "
            + "from the terminal.\n\nChoose a directory on your PATH:"

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 280, height: 26))
        let locations = ["/usr/local/bin", "~/.local/bin", "~/bin"]
        popup.addItems(withTitles: locations)
        popup.addItem(withTitle: "Other…")

        // Pre-select previously installed location
        if let previous = UserDefaults.standard.string(forKey: symlinkPathKey) {
            let previousDir = (previous as NSString).deletingLastPathComponent
            let abbreviated = abbreviate(previousDir)
            if let index = locations.firstIndex(of: abbreviated) {
                popup.selectItem(at: index)
            }
        }

        alert.accessoryView = popup
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let selectedTitle = popup.titleOfSelectedItem ?? locations[0]
        let directory: String

        if selectedTitle == "Other…" {
            guard let chosen = chooseDirectory() else { return }
            directory = chosen
        } else {
            directory = (selectedTitle as NSString)
                .expandingTildeInPath
        }

        install(to: directory)
    }

    // MARK: - Directory picker

    private static func chooseDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select a directory on your PATH for the mud symlink."

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    // MARK: - Symlink creation

    private static func install(to directory: String) {
        let symlinkPath = (directory as NSString)
            .appendingPathComponent("mud")
        let executablePath = Bundle.main.executablePath ?? ""

        guard !executablePath.isEmpty else {
            showError("Could not determine the application executable path.")
            return
        }

        // Ensure target directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory) {
            do {
                try fm.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                // Try elevated
                if !elevatedCreateDirectory(directory) {
                    showError(
                        "Could not create directory: \(directory)\n\n\(error.localizedDescription)"
                    )
                    return
                }
            }
        }

        // Remove existing symlink or file at target
        if fm.fileExists(atPath: symlinkPath) {
            do {
                try fm.removeItem(atPath: symlinkPath)
            } catch {
                if !elevatedRemoveAndLink(
                    symlinkPath: symlinkPath, target: executablePath
                ) {
                    showError(
                        "Could not remove existing file at \(symlinkPath)\n\n\(error.localizedDescription)"
                    )
                    return
                }
                // Elevated path handled both remove and link
                recordSuccess(symlinkPath)
                return
            }
        }

        // Create symlink
        do {
            try fm.createSymbolicLink(
                atPath: symlinkPath,
                withDestinationPath: executablePath
            )
        } catch {
            if !elevatedRemoveAndLink(
                symlinkPath: symlinkPath, target: executablePath
            ) {
                showError(
                    "Could not create symlink at \(symlinkPath)\n\n\(error.localizedDescription)"
                )
                return
            }
        }

        recordSuccess(symlinkPath)
    }

    private static func recordSuccess(_ symlinkPath: String) {
        UserDefaults.standard.set(true, forKey: installedKey)
        UserDefaults.standard.set(symlinkPath, forKey: symlinkPathKey)

        let alert = NSAlert()
        alert.messageText = "Command Line Tool Installed"
        alert.informativeText =
            "Symlink created at \(abbreviate(symlinkPath)).\n\n"
            + "You can now use \"mud\" from the terminal."
        alert.alertStyle = .informational
        alert.runModal()
    }

    // MARK: - Elevated permissions

    private static func elevatedCreateDirectory(_ path: String) -> Bool {
        let script = "do shell script \"mkdir -p '\(escaped(path))'\" "
            + "with administrator privileges"
        return runOsascript(script)
    }

    private static func elevatedRemoveAndLink(
        symlinkPath: String, target: String
    ) -> Bool {
        let script = "do shell script "
            + "\"rm -f '\(escaped(symlinkPath))' "
            + "&& ln -s '\(escaped(target))' '\(escaped(symlinkPath))'\" "
            + "with administrator privileges"
        return runOsascript(script)
    }

    private static func runOsascript(_ script: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Escapes single quotes for use inside AppleScript shell strings.
    private static func escaped(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }

    // MARK: - Helpers

    private static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private static func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Installation Failed"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
    }
}
