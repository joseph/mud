import SwiftUI
import UniformTypeIdentifiers

// MARK: - Document Controller

class DocumentController: NSDocumentController {
    private var windowControllers: [DocumentWindowController] = []

    override func openDocument(
        withContentsOf url: URL,
        display displayDocument: Bool,
        completionHandler: @escaping (NSDocument?, Bool, (any Error)?) -> Void
    ) {
        if let existingWindow = findWindow(for: url) {
            existingWindow.makeKeyAndOrderFront(nil)
            completionHandler(nil, false, nil)
            return
        }

        let windowController = DocumentWindowController(url: url)
        windowController.onClose = { [weak self] controller in
            self?.windowControllers.removeAll { $0 === controller }
        }
        windowControllers.append(windowController)
        windowController.showWindow(nil)
        noteNewRecentDocumentURL(url)
        completionHandler(nil, false, nil)
    }

    override var documentClassNames: [String] { [] }
    override var defaultType: String? { nil }
    override func documentClass(forType typeName: String) -> AnyClass? { nil }

    private func findWindow(for url: URL) -> NSWindow? {
        NSApp.windows.first { ($0.windowController as? DocumentWindowController)?.fileURL == url }
    }

    /// Shows the standard open panel and opens selected documents
    static func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.markdown, .plainText]
        panel.allowsMultipleSelection = true

        if panel.runModal() == .OK {
            for url in panel.urls {
                NSDocumentController.shared.openDocument(
                    withContentsOf: url,
                    display: true
                ) { _, _, _ in }
            }
        }
    }
}
