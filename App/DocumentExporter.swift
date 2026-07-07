import AppKit
import MudCore

/// The app side of the export path: writes a document's self-contained export
/// HTML to a temp file and hands it to another app via `NSWorkspace`. All
/// HTML shaping — standalone wrapping, comment stripping, the read-only
/// Comments column, image inlining — lives in `MudCore.exportDocument`.
/// Created on demand by `DocumentWindowController` for Open In Browser and
/// the Open In editor HTML handoff.
struct DocumentExporter {
    let fileURL: URL
    let markdown: String
    let mode: Mode
    let options: RenderOptions
    let includeComments: Bool

    /// Exports and opens the result in the default browser.
    func openInBrowser() {
        guard let tempURL = writeTempHTML(),
              let browserURL = NSWorkspace.shared.urlForApplication(
                  toOpen: URL(string: "https://example.com")!)
        else { return }
        NSWorkspace.shared.open(
            [tempURL],
            withApplicationAt: browserURL,
            configuration: NSWorkspace.OpenConfiguration())
    }

    /// Exports and opens the result with the app at `appURL` (the Open In
    /// editor HTML handoff).
    func open(withApplicationAt appURL: URL) {
        guard let tempURL = writeTempHTML() else { return }
        NSWorkspace.shared.open(
            [tempURL],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration())
    }

    /// Renders the export and writes it to `<basename>.html` (a readable
    /// browser-tab title) inside a fresh unique temp subdirectory, so two
    /// windows exporting same-named files (README.md in different folders)
    /// never race on one temp path. Nil when the directory or write failed.
    private func writeTempHTML() -> URL? {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MudExport-\(UUID().uuidString)",
                                    isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let tempURL = dir
            .appendingPathComponent(
                fileURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("html")
        let html = MudCore.exportDocument(
            markdown, mode: mode, options: options,
            includeComments: includeComments)
        guard let data = html.data(using: .utf8) else { return nil }
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
}
