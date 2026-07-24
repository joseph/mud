import SwiftUI
import UniformTypeIdentifiers

// MARK: - Document Controller

class DocumentController: NSDocumentController {
    private var windowControllers: [DocumentWindowController] = []

    /// True once any document window has been shown. Every open route — the
    /// launch panel, Open Recent, Finder, in-page links — funnels through
    /// `openDocument`, so this is the one place that learns a document is up.
    /// `applicationShouldTerminateAfterLastWindowClosed` reads it to gate
    /// quit-on-close.
    private(set) var hasOpenedDocument = false

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        if let existingWindow = findWindow(for: url) {
            existingWindow.makeKeyAndOrderFront(nil)
            didOpenDocument()
            completionHandler(nil, false, nil)
            return
        }

        let windowController = DocumentWindowController(url: url)
        windowController.onClose = { [weak self] controller in
            self?.windowControllers.removeAll { $0 === controller }
        }
        windowControllers.append(windowController)
        windowController.showWindow(nil)
        if !url.isBundleResource {
            noteNewRecentDocumentURL(url)
        }
        didOpenDocument()
        completionHandler(nil, false, nil)
    }

    /// Records that a document window is up and clears any launch/Cmd+O open
    /// panel still floating. Called after the window is surfaced, so the panel
    /// closes with a document already on screen — the launch quit check then
    /// sees it and keeps the app running.
    private func didOpenDocument() {
        hasOpenedDocument = true
        dismissOpenPanel()
    }

    override var documentClassNames: [String] { [] }
    override var defaultType: String? { nil }
    override func documentClass(forType typeName: String) -> AnyClass? { nil }

    private func findWindow(for url: URL) -> NSWindow? {
        NSApp.windows.first { ($0.windowController as? DocumentWindowController)?.fileURL == url }
    }

    /// Opens a markdown file bundled in the app's resources
    static func openBundledDocument(_ name: String, subdirectory: String? = nil) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: subdirectory) else { return }
        NSDocumentController.shared.openDocument(
            withContentsOf: url,
            display: true
        ) { _, _, _ in }
    }

    /// The modeless open panel shown at launch or via Cmd+O, held so a
    /// document opened another way (e.g. File > Open Recent) can dismiss it.
    private var openPanel: NSOpenPanel?

    /// Shows the standard open panel and opens the selected documents.
    ///
    /// Presented with `begin`, not `runModal`, so it doesn't block the run
    /// loop: the main menu — File > Open Recent included — stays live while the
    /// panel is up. `onFinish` runs after the panel closes; the launch path
    /// uses it to quit when the user cancelled without opening anything.
    func presentOpenPanel(onFinish: (() -> Void)? = nil) {
        if let openPanel {
            openPanel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.markdown, .plainText]
        panel.allowsMultipleSelection = true
        openPanel = panel

        panel.begin { [weak self] response in
            self?.openPanel = nil
            if response == .OK {
                for url in panel.urls {
                    self?.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                }
            }
            onFinish?()
        }
    }

    /// Bridges the Cmd+O menu command, which has no controller in hand.
    static func showOpenPanel() {
        (NSDocumentController.shared as? DocumentController)?.presentOpenPanel()
    }

    /// Closes the open panel because a document is being surfaced.
    /// `openDocument` calls this after the new window is up, so the panel's
    /// completion (the launch quit check) sees the document and keeps running.
    private func dismissOpenPanel() {
        guard let panel = openPanel else { return }
        openPanel = nil
        panel.cancel(nil)
    }
}
