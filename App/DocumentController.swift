import SwiftUI
import MudPreferences

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
        // A folder isn't a document, so it takes a route of its own — and
        // which route is the reader's choice. Either it stands for the
        // Markdown files directly inside it, one tab each, or for one window
        // holding an index of the whole tree below it.
        if MarkdownFolder.isFolder(url) {
            switch AppState.shared.folderOpenBehavior {
            case .tabs:
                openFolderAsTabs(
                    url, files: MarkdownFolder.markdownFiles(in: url) ?? [])
            case .index:
                // Noted as recent even when the folder currently holds no
                // Markdown: in this mode the folder itself is the document,
                // and what is in it can change between opens.
                presentWindow(for: url, noteRecent: true)
            }
            completionHandler(nil, false, nil)
            return
        }

        presentWindow(for: url, noteRecent: !url.isBundleResource)
        completionHandler(nil, false, nil)
    }

    /// Opens one window per Markdown file in `folder`, tabbed into one group.
    /// A folder with none still gets a window: the request is answered with a
    /// blank page and the info bar's warning, rather than with nothing at all.
    /// (`FolderOpenBehavior.tabs`; the index behavior opens one window on the
    /// folder itself and lets `DocumentModel` make a document of it.)
    ///
    /// The tab group is why this doesn't just loop over `openDocument`. Mud's
    /// windows don't cascade (`shouldCascadeWindows = false`) and each one
    /// opens centered, so a folder of a dozen documents would otherwise put a
    /// dozen windows on the same rect and look like one. Tabbing here is
    /// explicit rather than a `tabbingMode` on every window, because
    /// `tabbingMode` is answered by the reader's system-wide "Prefer tabs"
    /// setting: it would either group *every* Mud window or none. One command
    /// asking for many documents is the case that needs them together.
    private func openFolderAsTabs(_ folder: URL, files: [URL]) {
        guard !files.isEmpty else {
            presentWindow(for: folder, noteRecent: false)
            return
        }
        // Only the windows this open creates join the group. A document
        // already on screen is surfaced where it is — it belongs to whatever
        // window the reader put it in, and moving it would be a surprise.
        var host: NSWindow?
        var previous: NSWindow?
        for file in files {
            guard let window = presentWindow(
                for: file, noteRecent: !file.isBundleResource) else { continue }
            previous?.addTabbedWindow(window, ordered: .above)
            if host == nil { host = window }
            previous = window
        }
        // Each added tab becomes the selected one, so without this the last
        // file in the folder would be the one on screen.
        host?.makeKeyAndOrderFront(nil)
    }

    /// Surfaces the window for `url`: the one already showing this document,
    /// else a new one. `noteRecent` is false for anything File > Open Recent
    /// shouldn't list — a bundled guide, or the folder that held no Markdown
    /// (there is nothing in it to reopen).
    ///
    /// Returns the window only when this call created it, which is what
    /// `openFolder` needs to know: an already-open document keeps its place
    /// instead of being pulled into the folder's tab group.
    @discardableResult
    private func presentWindow(for url: URL, noteRecent: Bool) -> NSWindow? {
        if let existingWindow = findWindow(for: url) {
            existingWindow.makeKeyAndOrderFront(nil)
            didOpenDocument()
            return nil
        }

        let windowController = DocumentWindowController(url: url)
        windowController.onClose = { [weak self] controller in
            self?.windowControllers.removeAll { $0 === controller }
        }
        windowControllers.append(windowController)
        windowController.showWindow(nil)
        if noteRecent {
            noteNewRecentDocumentURL(url)
        }
        didOpenDocument()
        return windowController.window
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
        panel.allowedContentTypes = OpenPanelFilter.default.contentTypes
        panel.allowsMultipleSelection = true
        // A folder is an answer to "open what?" too — Mud opens the Markdown
        // files directly inside it. Double-clicking a folder still navigates
        // into it; selecting one and clicking Open is what opens it.
        panel.canChooseDirectories = true
        panel.accessoryView = makeFilterAccessoryView()
        panel.isAccessoryViewDisclosed = true
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

    /// The panel's "Enable:" row — a label and a popup of the
    /// `OpenPanelFilter` cases, centered in a container the panel sizes.
    ///
    /// Built fresh per panel, and never seeded from anything but
    /// `OpenPanelFilter.default`: the choice is deliberately not persisted, so
    /// a panel opened weeks later doesn't silently come up unfiltered.
    private func makeFilterAccessoryView() -> NSView {
        let label = NSTextField(labelWithString: "Enable:")

        let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
        popUp.addItems(withTitles: OpenPanelFilter.allCases.map(\.title))
        popUp.selectItem(at: OpenPanelFilter.default.rawValue)
        popUp.target = self
        popUp.action = #selector(openPanelFilterChanged(_:))

        let row = NSStackView(views: [label, popUp])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 35))
        container.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    /// Applies the popup's selection to the panel that's already on screen.
    /// The panel re-evaluates its browser on the change, so files un-grey
    /// without the user reopening it.
    @objc private func openPanelFilterChanged(_ sender: NSPopUpButton) {
        guard let filter = OpenPanelFilter(rawValue: sender.indexOfSelectedItem) else { return }
        openPanel?.allowedContentTypes = filter.contentTypes
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
