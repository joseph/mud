import AppKit

/// Manages installation of the `mud` command-line symlink.
enum CommandLineInstaller {
    static let installedKey = "Mud-CLIInstalled"
    static let symlinkPathKey = "Mud-CLISymlinkPath"

    /// Standard locations offered in the picker.
    static let defaultLocations = ["/usr/local/bin", "~/.local/bin", "~/bin"]

    // MARK: - Status

    /// Whether the CLI symlink has been installed (per UserDefaults).
    static var isInstalled: Bool {
        UserDefaults.standard.bool(forKey: installedKey)
    }

    /// The abbreviated path to the current symlink, if recorded.
    static var installedPath: String? {
        guard let path = UserDefaults.standard.string(forKey: symlinkPathKey)
        else { return nil }
        return abbreviate(path)
    }

    // MARK: - Directory picker

    /// Opens an NSOpenPanel for choosing a custom directory.
    /// Returns the selected path, or nil if cancelled.
    static func chooseDirectory() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select a directory on your PATH for the mud symlink."

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url.path
    }

    // MARK: - Install

    enum InstallError: LocalizedError {
        case noExecutablePath
        case createDirectoryFailed(String)
        case removeExistingFailed(String)
        case symlinkFailed(String)

        var errorDescription: String? {
            switch self {
            case .noExecutablePath:
                return "Could not determine the application executable path."
            case .createDirectoryFailed(let detail):
                return "Could not create directory.\n\n\(detail)"
            case .removeExistingFailed(let detail):
                return "Could not remove existing file.\n\n\(detail)"
            case .symlinkFailed(let detail):
                return "Could not create symlink.\n\n\(detail)"
            }
        }
    }

    /// Installs the `mud` symlink into `directory`.
    /// Returns the abbreviated symlink path on success.
    @discardableResult
    static func install(to directory: String) throws -> String {
        let symlinkPath = (directory as NSString)
            .appendingPathComponent("mud")
        let executablePath = Bundle.main.executablePath ?? ""

        guard !executablePath.isEmpty else {
            throw InstallError.noExecutablePath
        }

        let fm = FileManager.default

        // Ensure target directory exists
        if !fm.fileExists(atPath: directory) {
            do {
                try fm.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                if !elevatedCreateDirectory(directory) {
                    throw InstallError.createDirectoryFailed(
                        error.localizedDescription
                    )
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
                    throw InstallError.removeExistingFailed(
                        error.localizedDescription
                    )
                }
                // Elevated path handled both remove and link
                recordInstall(symlinkPath)
                return abbreviate(symlinkPath)
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
                throw InstallError.symlinkFailed(error.localizedDescription)
            }
        }

        recordInstall(symlinkPath)
        return abbreviate(symlinkPath)
    }

    private static func recordInstall(_ symlinkPath: String) {
        UserDefaults.standard.set(true, forKey: installedKey)
        UserDefaults.standard.set(symlinkPath, forKey: symlinkPathKey)
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

    static func abbreviate(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
