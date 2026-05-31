import AppKit
import Combine
import MudPreferences
import UniformTypeIdentifiers

struct RegisteredMarkdownHandler: Identifiable {
    var id: String { bundleID }
    let displayName: String
    let appURL: URL
    let bundleID: String
    let icon: NSImage

    init?(appURL: URL) {
        guard
            let bundle = Bundle(url: appURL),
            let bundleID = bundle.bundleIdentifier
        else { return nil }
        let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 16, height: 16)
        self.displayName = name
        self.appURL = appURL
        self.bundleID = bundleID
        self.icon = icon
    }
}

struct EditorLaunchRequest {
    let id = UUID()
    let handler: RegisteredMarkdownHandler
    let format: EditorFormat
}

final class OpenInMenuModel: ObservableObject {
    static let shared = OpenInMenuModel()

    @Published private(set) var configured: RegisteredMarkdownHandler?
    @Published private(set) var others: [RegisteredMarkdownHandler] = []

    init() { refresh() }

    func refresh() {
        let mudBundleID = Bundle.main.bundleIdentifier
        let all = NSWorkspace.shared.urlsForApplications(toOpen: UTType.markdown)
            .compactMap(RegisteredMarkdownHandler.init(appURL:))
            .filter { $0.bundleID != mudBundleID }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        let resolved = MudPreferences.shared.openInDefaultBundleID
            .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .flatMap(RegisteredMarkdownHandler.init(appURL:))

        // Clear stale preference if the configured app is no longer installed.
        if MudPreferences.shared.openInDefaultBundleID != nil && resolved == nil {
            MudPreferences.shared.openInDefaultBundleID = nil
        }

        configured = resolved
        others = all.filter { $0.bundleID != resolved?.bundleID }
    }

    /// Submenu and context-menu click path. The format is the stored one when
    /// the picked handler is already the default; otherwise `.auto`.
    func launch(with handler: RegisteredMarkdownHandler) {
        guard let controller = keyDocumentController else { return }
        let isDefault = handler.bundleID == MudPreferences.shared.openInDefaultBundleID
        let format: EditorFormat = isDefault
            ? MudPreferences.shared.openInDefaultFormat
            : .auto
        launch(controller: controller, handler: handler, format: format)
    }

    func chooseEditor() {
        guard let controller = keyDocumentController, let window = controller.window
        else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Choose an editor for Markdown files."
        panel.prompt = "Choose"

        // Sandboxed builds can't hand a rendered HTML temp file to another app
        // (the temp dir lives in our container), so HTML is markdown-only there
        // — no accessory at all.
        let popup: NSPopUpButton?
        if !isSandboxed {
            let accessory = makeFormatAccessoryView()
            panel.accessoryView = accessory.view
            panel.isAccessoryViewDisclosed = true
            popup = accessory.control
        } else {
            popup = nil
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            guard
                response == .OK,
                let self,
                let url = panel.url,
                let handler = RegisteredMarkdownHandler(appURL: url)
            else { return }
            // Sandboxed builds have no popup; force `.markdown` because the
            // HTML handoff doesn't work under sandboxing (temp file lives in
            // our container, other apps can't read it).
            let format: EditorFormat
            if let popup, popup.indexOfSelectedItem >= 0 {
                format = EditorFormat.allCases[popup.indexOfSelectedItem]
            } else {
                format = .markdown
            }
            self.launch(controller: controller, handler: handler, format: format)
        }
    }

    /// Persists the choice and routes the launch through `DocumentState`.
    /// `.auto` is resolved to a concrete format here based on the chosen
    /// app's UTI claims; the view layer only ever sees `.markdown` or
    /// `.html`.
    private func launch(
        controller: DocumentWindowController,
        handler: RegisteredMarkdownHandler,
        format: EditorFormat
    ) {
        MudPreferences.shared.openInDefaultBundleID = handler.bundleID
        MudPreferences.shared.openInDefaultFormat = format
        refresh()
        let concrete = resolveFormat(format, for: handler)
        controller.state.openInEditorRequest = EditorLaunchRequest(
            handler: handler,
            format: concrete
        )
    }

    private func resolveFormat(
        _ format: EditorFormat,
        for handler: RegisteredMarkdownHandler
    ) -> EditorFormat {
        switch format {
        case .auto:
            // Only send HTML when the app accepts it and doesn't claim
            // markdown — that's the niche (e.g. a browser) where markdown
            // wouldn't reach the editor in a useful state. Markdown is the
            // safer default for anything that handles markdown directly or
            // claims neither type.
            let claimsMarkdown = appClaims(bundleID: handler.bundleID, type: .markdown)
            let claimsHTML = appClaims(bundleID: handler.bundleID, type: .html)
            return (claimsHTML && !claimsMarkdown) ? .html : .markdown
        case .markdown, .html:
            return format
        }
    }

    private func appClaims(bundleID: String, type: UTType) -> Bool {
        let urls = NSWorkspace.shared.urlsForApplications(toOpen: type)
        return urls.contains { Bundle(url: $0)?.bundleIdentifier == bundleID }
    }

    private func makeFormatAccessoryView() -> (view: NSView, control: NSPopUpButton) {
        let label = NSTextField(labelWithString: "Export:")
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: EditorFormat.allCases.map(displayTitle))
        let current = MudPreferences.shared.openInDefaultFormat
        popup.selectItem(at: EditorFormat.allCases.firstIndex(of: current) ?? 0)
        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        return (stack, popup)
    }

    private func displayTitle(_ format: EditorFormat) -> String {
        switch format {
        case .auto:     return "Auto"
        case .markdown: return "Markdown"
        case .html:     return "HTML"
        }
    }

    private var keyDocumentController: DocumentWindowController? {
        NSApp.keyWindow?.windowController as? DocumentWindowController
    }
}
