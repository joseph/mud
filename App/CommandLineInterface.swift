import Foundation
import MudCore

/// Handles CLI invocation of the Mud executable.
///
/// When the binary is invoked with `--html-up` or `--html-down`, it renders
/// Markdown to HTML on stdout and exits — no GUI, no dock icon.
/// Bare filenames (without a mode flag) open in the GUI instead.
enum CommandLineInterface {
    // MARK: - Detection

    /// Flags that trigger the command line interface.
    private static let cliFlags: Set<String> = [
        "--html-up", "-u",
        "--html-down", "-d",
        "--browser", "-b",
        "--fragment", "-f",
        "--help", "-h",
        "--version", "-v",
    ]

    /// Returns `true` when arguments contain a recognized CLI flag.
    /// Positional filenames alone do not trigger the command line interface —
    /// they open in the GUI.  System flags (`-NS*`, `-Apple*`) are skipped.
    static func looksLikeCLI(_ args: [String]) -> Bool {
        var i = 0
        while i < args.count {
            let arg = args[i]
            if isSystemFlag(arg) { i += 2; continue }
            if cliFlags.contains(arg) { return true }
            i += 1
        }
        return false
    }

    /// Returns positional (non-flag, non-system) arguments — the file paths
    /// passed on the command line that should open in the GUI.
    static func fileArguments(_ args: [String]) -> [String] {
        var files: [String] = []
        var i = 0
        while i < args.count {
            let arg = args[i]
            if isSystemFlag(arg) { i += 2; continue }
            if !arg.hasPrefix("-") { files.append(arg) }
            i += 1
        }
        return files
    }

    /// Returns `true` when the process was launched via a symlink (i.e. the
    /// CLI tool) rather than directly from the app bundle.
    static var launchedViaSymlink: Bool {
        guard let exec = Bundle.main.executableURL else { return false }
        let resolved = exec.resolvingSymlinksInPath()
        return exec.path != resolved.path
    }

    private static func isSystemFlag(_ arg: String) -> Bool {
        arg.hasPrefix("-NS") || arg.hasPrefix("-Apple")
    }

    // MARK: - Execution

    /// Parses arguments, renders, writes to stdout, and returns an exit code.
    static func run(_ args: [String]) -> Int32 {
        var files: [String] = []
        var mode: OutputMode?
        var theme = "earthy"
        var htmlClasses: [String] = []
        var browser = false
        var fragment = false
        var i = 0

        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--help", "-h":
                printUsage()
                return 0
            case "--version", "-v":
                printToStdout("mud \(MudCore.version)")
                return 0
            case "--html-up", "-u":
                mode = .up
            case "--html-down", "-d":
                mode = .down
            case "--browser", "-b":
                browser = true
            case "--fragment", "-f":
                fragment = true
            case "--line-numbers":
                htmlClasses.append("has-line-numbers")
            case "--word-wrap":
                htmlClasses.append("has-word-wrap")
            case "--readable-column":
                htmlClasses.append("is-readable-column")
            case "--theme":
                i += 1
                guard i < args.count else {
                    printError("--theme requires a value")
                    return 1
                }
                theme = args[i]
            default:
                if arg.hasPrefix("--theme=") {
                    theme = String(arg.dropFirst("--theme=".count))
                } else if isSystemFlag(arg) {
                    i += 1  // skip the value that follows
                } else if arg.hasPrefix("-") {
                    printError("unknown option: \(arg)")
                    return 1
                } else {
                    files.append(arg)
                }
            }
            i += 1
        }

        let validThemes = ["austere", "blues", "earthy", "riot"]
        if !validThemes.contains(theme) {
            printError(
                "unknown theme '\(theme)' "
                + "(available: \(validThemes.joined(separator: ", ")))"
            )
            return 1
        }

        if fragment {
            if theme != "earthy" {
                printError("--theme ignored with --fragment")
            }
            if htmlClasses.contains("has-line-numbers") {
                printError("--line-numbers ignored with --fragment")
            }
            if htmlClasses.contains("has-word-wrap") {
                printError("--word-wrap ignored with --fragment")
            }
            if htmlClasses.contains("is-readable-column") {
                printError("--readable-column ignored with --fragment")
            }
        }

        guard let mode else {
            printError("specify --html-up (-u) or --html-down (-d)")
            return 1
        }

        // Read from stdin when no files given
        if files.isEmpty {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else {
                printError("failed to read from stdin")
                return 2
            }
            let html = render(text, title: "", baseURL: nil,
                              mode: mode, theme: theme,
                              htmlClasses: htmlClasses,
                              forBrowser: browser,
                              forFragment: fragment)
            if browser {
                guard let url = writeTempFile(html: html, name: "stdin") else {
                    printError("failed to write temp file")
                    return 2
                }
                openInBrowser([url])
            } else {
                printToStdout(html)
            }
            return 0
        }

        // Render each file
        var tempURLs: [URL] = []
        for path in files {
            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                printError("no such file: \(path)")
                return 2
            }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                printError("cannot read file: \(path)")
                return 2
            }
            let html = render(text, title: url.lastPathComponent,
                              baseURL: url, mode: mode, theme: theme,
                              htmlClasses: htmlClasses,
                              forBrowser: browser,
                              forFragment: fragment)
            if browser {
                let baseName = url.deletingPathExtension().lastPathComponent
                guard let tempURL = writeTempFile(html: html,
                                                  name: baseName) else {
                    printError("failed to write temp file for \(path)")
                    return 2
                }
                tempURLs.append(tempURL)
            } else {
                printToStdout(html)
            }
        }

        if browser { openInBrowser(tempURLs) }

        return 0
    }

    /// Returns `true` when stdin is piped (not a terminal).
    static var hasStdin: Bool {
        isatty(STDIN_FILENO) == 0
    }

    /// Reads stdin into a temporary `.md` file and returns its URL,
    /// or `nil` on failure.
    static func stdinToTempFile() -> URL? {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("mud-stdin.md")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Open in GUI

    /// Launches (or reuses) Mud.app via `open -a` so the system handles
    /// activation, and the calling terminal process can exit immediately.
    static func openInApp(_ urls: [URL]) {
        // Resolve the .app bundle: executable lives at
        // Mud.app/Contents/MacOS/Mud — resolve symlinks first since
        // the CLI symlink path itself is not inside the bundle.
        let execURL = Bundle.main.executableURL!
            .resolvingSymlinksInPath()
        let appBundle = execURL
            .deletingLastPathComponent()  // MacOS/
            .deletingLastPathComponent()  // Contents/
            .deletingLastPathComponent()  // Mud.app
        var arguments = ["-a", appBundle.path]
        for url in urls { arguments.append(url.path) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Rendering

    private enum OutputMode { case up, down }

    private static func render(
        _ markdown: String,
        title: String,
        baseURL: URL?,
        mode: OutputMode,
        theme: String,
        htmlClasses: [String],
        forBrowser: Bool = false,
        forFragment: Bool = false
    ) -> String {
        if forFragment {
            var body: String
            switch mode {
            case .up:
                body = MudCore.renderUpToHTML(markdown)
            case .down:
                body = MudCore.renderDownToHTML(markdown)
            }
            if forBrowser {
                body = "<meta charset=\"utf-8\">\n" + body
            }
            return body
        }
        var html: String
        switch mode {
        case .up:
            if forBrowser {
                html = MudCore.renderUpModeDocument(
                    markdown, title: title, baseURL: baseURL, theme: theme,
                    includeBaseTag: false,
                    resolveImageSource: { source, base in
                        ImageDataURI.encode(source: source, baseURL: base)
                    }
                )
            } else {
                html = MudCore.renderUpModeDocument(
                    markdown, title: title, baseURL: baseURL, theme: theme
                )
            }
        case .down:
            html = MudCore.renderDownModeDocument(
                markdown, title: title, theme: theme
            )
        }
        if !htmlClasses.isEmpty {
            let attr = "class=\"\(htmlClasses.joined(separator: " "))\""
            html = html.replacingOccurrences(
                of: "<html>", with: "<html \(attr)>"
            )
        }
        return html
    }

    // MARK: - Browser helpers

    private static func writeTempFile(html: String, name: String) -> URL? {
        let tempDir = NSTemporaryDirectory()
        let url = URL(fileURLWithPath: tempDir)
            .appendingPathComponent("mud-\(name)")
            .appendingPathExtension("html")
        guard let data = html.data(using: .utf8) else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    private static func openInBrowser(_ urls: [URL]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = urls.map(\.path)
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Output helpers

    private static func printToStdout(_ string: String) {
        if let data = string.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
            if !string.hasSuffix("\n") {
                FileHandle.standardOutput.write(Data([0x0A]))
            }
        }
    }

    private static func printError(_ message: String) {
        let line = "mud: \(message)\n"
        if let data = line.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private static func printUsage() {
        printToStdout("""
        mud — Markdown preview and HTML renderer

        Usage:
          mud                           Launch the Mud app
          mud [file ...]                Open files in the Mud app
          command | mud                 Preview stdin in the Mud app
          mud -u [options] [file ...]   Render to HTML (mark-up view)
          mud -d [options] [file ...]   Render to HTML (mark-down view)
          command | mud -u [options]    Render stdin to HTML

        Modes:
          -u, --html-up      HTML document (rendered Markdown)
          -d, --html-down    HTML document (syntax-highlighted source)

        Options:
          -f, --fragment     Output HTML body only, no document wrapper
          -b, --browser      Open in default browser instead of stdout
          --line-numbers     Show line numbers (with -d)
          --word-wrap        Enable word wrapping (with -d)
          --readable-column  Limit content width (with -d or -u)
          --theme NAME       Theme: austere, blues, earthy (default), riot
          -v, --version      Print version and exit
          -h, --help         Print this help and exit

        Without -u or -d, files open in the GUI. With -u or -d, a full
        HTML document is written to stdout; add -f for just the HTML body.
        If no file is given, reads from stdin. Add -b to open the result
        in your default browser instead.
        """)
    }
}
