import AppKit
import MudPreferences

/// Manages installation of the `mud` command-line symlink.
enum CommandLineInstaller {
    /// Standard locations offered in the picker.
    static let defaultLocations = ["/usr/local/bin", "~/.local/bin", "~/bin"]

    // MARK: - Status

    /// Whether the CLI symlink has been installed (per UserDefaults).
    static var isInstalled: Bool {
        MudPreferences.shared.cliInstalled
    }

    /// The abbreviated path to the current symlink, if recorded.
    static var installedPath: String? {
        guard let path = MudPreferences.shared.cliSymlinkPath
        else { return nil }
        return abbreviate(path)
    }

    /// When the `mud` symlink was last installed.
    ///
    /// The symlink's own timestamp is the truth: installing removes and
    /// recreates the link, so its creation date is the install date, and a
    /// link made by hand at the shell counts too. `attributesOfItem` reads the
    /// link rather than the file it points at, so even a dangling link
    /// answers. When it can't be read at all — no link recorded, the file
    /// gone, or a sandbox refusing the directory — fall back to the date
    /// `recordInstall` wrote, which is the only reason we write it.
    static var installedDate: Date? {
        if let path = MudPreferences.shared.cliSymlinkPath,
           let attributes = try? FileManager.default.attributesOfItem(
               atPath: (path as NSString).expandingTildeInPath
           ) {
            if let created = attributes[.creationDate] as? Date {
                return created
            }
            if let modified = attributes[.modificationDate] as? Date {
                return modified
            }
        }
        return MudPreferences.shared.cliInstalledAt
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
                return "Could not locate mud.sh in the application bundle."
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

        guard let resourcesURL = Bundle.main.resourceURL else {
            throw InstallError.noExecutablePath
        }
        let executablePath = resourcesURL.appendingPathComponent("mud.sh").path

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
        MudPreferences.shared.cliInstalled = true
        MudPreferences.shared.cliSymlinkPath = symlinkPath
        MudPreferences.shared.cliInstalledAt = Date()
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
