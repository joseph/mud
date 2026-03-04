import Foundation
import MudCore

// MARK: - Types

enum OutputMode { case up, down }

// MARK: - Argument parsing

var files: [String] = []
var mode: OutputMode?
var theme = "earthy"
var htmlClasses: [String] = []
var browser = false
var fragment = false
var i = 1  // skip argv[0]

while i < CommandLine.arguments.count {
    let arg = CommandLine.arguments[i]
    switch arg {
    case "--help", "-h":
        printUsage()
        exit(0)
    case "--version", "-v":
        printToStdout("mud \(MudCore.version)")
        exit(0)
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
        guard i < CommandLine.arguments.count else {
            printError("--theme requires a value")
            exit(1)
        }
        theme = CommandLine.arguments[i]
    default:
        if arg.hasPrefix("--theme=") {
            theme = String(arg.dropFirst("--theme=".count))
        } else if arg.hasPrefix("-") {
            printError("unknown option: \(arg)")
            exit(1)
        } else {
            files.append(arg)
        }
    }
    i += 1
}

// MARK: - Validation

let validThemes = ["austere", "blues", "earthy", "riot"]
if !validThemes.contains(theme) {
    printError(
        "unknown theme '\(theme)' "
        + "(available: \(validThemes.joined(separator: ", ")))"
    )
    exit(1)
}

if fragment {
    if theme != "earthy" { printError("--theme ignored with --fragment") }
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
    exit(1)
}

// MARK: - Render

if files.isEmpty {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let text = String(data: data, encoding: .utf8) else {
        printError("failed to read from stdin")
        exit(2)
    }
    let html = render(text, title: "", baseURL: nil)
    if browser {
        guard let url = writeTempFile(html: html, name: "stdin") else {
            printError("failed to write temp file")
            exit(2)
        }
        openInBrowser([url])
    } else {
        printToStdout(html)
    }
} else {
    var tempURLs: [URL] = []
    for path in files {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            printError("no such file: \(path)")
            exit(2)
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            printError("cannot read file: \(path)")
            exit(2)
        }
        let html = render(text, title: url.lastPathComponent, baseURL: url)
        if browser {
            let baseName = url.deletingPathExtension().lastPathComponent
            guard let tempURL = writeTempFile(html: html, name: baseName) else {
                printError("failed to write temp file for \(path)")
                exit(2)
            }
            tempURLs.append(tempURL)
        } else {
            printToStdout(html)
        }
    }
    if browser { openInBrowser(tempURLs) }
}

exit(0)

// MARK: - Rendering

func render(_ markdown: String, title: String, baseURL: URL?) -> String {
    if fragment {
        var body: String
        switch mode {
        case .up:  body = MudCore.renderUpToHTML(markdown)
        case .down: body = MudCore.renderDownToHTML(markdown)
        }
        if browser { body = "<meta charset=\"utf-8\">\n" + body }
        return body
    }
    var html: String
    switch mode {
    case .up:
        if browser {
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
        html = MudCore.renderDownModeDocument(markdown, title: title, theme: theme)
    }
    if !htmlClasses.isEmpty {
        let attr = "class=\"\(htmlClasses.joined(separator: " "))\""
        html = html.replacingOccurrences(of: "<html>", with: "<html \(attr)>")
    }
    return html
}

// MARK: - Browser helpers

func writeTempFile(html: String, name: String) -> URL? {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
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

func openInBrowser(_ urls: [URL]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = urls.map(\.path)
    try? process.run()
    process.waitUntilExit()
}

// MARK: - Output helpers

func printToStdout(_ string: String) {
    if let data = string.data(using: .utf8) {
        FileHandle.standardOutput.write(data)
        if !string.hasSuffix("\n") {
            FileHandle.standardOutput.write(Data([0x0A]))
        }
    }
}

func printError(_ message: String) {
    let line = "mud: \(message)\n"
    if let data = line.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func printUsage() {
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
