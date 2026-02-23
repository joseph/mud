import SwiftUI
import MudCore

// MARK: - Document Content View

struct DocumentContentView: View {
    let fileURL: URL
    @ObservedObject var state: DocumentState
    @ObservedObject var findState: FindState
    @ObservedObject private var appState = AppState.shared

    @State private var displayText = ""
    @State private var fileWatcher: FileWatcher?
    @FocusState private var contentFocused: Bool
    @Environment(\.colorScheme) private var environmentColorScheme
    @Environment(\.openSettings) private var openSettings

    private var modeHTML: String {
        let themeName = appState.theme.rawValue
        if state.mode == .down {
            return MudCore.renderDownModeDocument(displayText,
                title: fileURL.lastPathComponent,
                theme: themeName)
        }
        return MudCore.renderUpModeDocument(displayText,
            baseURL: fileURL,
            theme: themeName,
            blockRemoteContent: !appState.allowRemoteContent,
            resolveImageSource: Self.mudAssetResolver)
    }

    /// Rewrites local image paths to `mud-asset:` URLs for WKWebView.
    private nonisolated static func mudAssetResolver(
        source: String, baseURL: URL
    ) -> String? {
        guard !ImageDataURI.isExternal(source) else { return nil }
        let resolved = baseURL.deletingLastPathComponent()
            .appendingPathComponent(source)
            .standardized
        let ext = resolved.pathExtension.lowercased()
        guard ImageDataURI.mimeTypes[ext] != nil else { return nil }
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = "mud-asset"
        components.path = resolved.path
        return components.url?.absoluteString ?? nil
    }

    private var modeZoomLevel: Double {
        state.mode == .down
            ? appState.downModeZoomLevel
            : appState.upModeZoomLevel
    }

    var body: some View {
        WebView(
            html: modeHTML,
            baseURL: fileURL,
            contentID: "\(displayText)\(appState.allowRemoteContent)",
            mode: state.mode,
            theme: appState.theme,
            bodyClasses: Set(appState.viewToggles.map(\.className)),
            zoomLevel: modeZoomLevel,
            searchQuery: findState.currentQuery,
            scrollTarget: state.scrollTarget,
            printID: state.printID,
            onSearchResult: { info in
                findState.matchInfo = info
            }
        )
        .focusable()
        .focusEffectDisabled()
        .focused($contentFocused)
        .findOverlay(state: findState)
        .frame(minWidth: 500, minHeight: 400)

        .onKeyPress(.space) {
            guard !findState.isVisible else { return .ignored }
            deferMutation { state.toggleMode() }
            return .handled
        }
        .onKeyPress(.escape) {
            guard findState.isVisible else { return .ignored }
            findState.close()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "/")) { _ in
            guard !findState.isVisible else { return .ignored }
            NSApp.sendAction(#selector(DocumentWindowController.performFindAction(_:)), to: nil, from: nil)
            return .handled
        }
        .onChange(of: findState.isVisible) { _, isVisible in
            if !isVisible { contentFocused = true }
        }
        .onChange(of: state.mode) { _, _ in
            if findState.isVisible { findState.close() }
        }
        .onChange(of: contentFocused) { _, focused in
            if !focused && !findState.isVisible {
                contentFocused = true
            }
        }
        .onAppear {
            contentFocused = true
            loadFromDisk()
            setupFileWatcher()
            appState.openSettingsAction = { openSettings() }
        }
        .onDisappear {
            fileWatcher = nil
        }
        .onChange(of: state.reloadID) { _, id in
            if id != nil { loadFromDisk() }
        }
        .onChange(of: state.openInBrowserID) { _, id in
            if id != nil { openInBrowser() }
        }
    }

    private func setupFileWatcher() {
        guard !fileURL.isBundleResource else { return }
        fileWatcher = FileWatcher(url: fileURL) { loadFromDisk() }
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return }
        displayText = text
        state.outlineHeadings = MudCore.extractHeadings(text)
    }

    private func openInBrowser() {
        let tempDir = NSTemporaryDirectory()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let tempURL = URL(fileURLWithPath: tempDir)
            .appendingPathComponent(baseName)
            .appendingPathExtension("html")
        let themeName = appState.theme.rawValue
        let exportDocument: String
        if state.mode == .down {
            exportDocument = MudCore.renderDownModeDocument(displayText,
                title: fileURL.lastPathComponent,
                theme: themeName)
        } else {
            exportDocument = MudCore.renderUpModeDocument(displayText,
                baseURL: fileURL,
                theme: themeName,
                includeBaseTag: false,
                resolveImageSource: { source, baseURL in
                    ImageDataURI.encode(source: source, baseURL: baseURL)
                })
        }
        let exportHTML = WebView.injectState(
            into: exportDocument,
            bodyClasses: Set(appState.viewToggles.map(\.className)),
            zoomLevel: modeZoomLevel
        )
        guard let data = exportHTML.data(using: .utf8) else { return }
        try? data.write(to: tempURL)
        guard let browserURL = NSWorkspace.shared.urlForApplication(
            toOpen: URL(string: "https://example.com")!
        ) else { return }
        NSWorkspace.shared.open(
            [tempURL],
            withApplicationAt: browserURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

// MARK: - Comparable Clamping

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
