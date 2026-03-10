import SwiftUI
import MudCore

// MARK: - Document Content View

private enum DocumentContent {
    case text(String)
    case error(String)  // pre-rendered error page HTML
}

struct DocumentContentView: View {
    let fileURL: URL
    @ObservedObject var state: DocumentState
    @ObservedObject var findState: FindState
    @ObservedObject private var appState = AppState.shared

    @State private var content: DocumentContent = .text("")
    @State private var fileWatcher: FileWatcher?
    @FocusState private var contentFocused: Bool
    @Environment(\.colorScheme) private var environmentColorScheme
    @Environment(\.openSettings) private var openSettings

    private var displayHTML: String {
        switch content {
        case .text:            return modeHTML
        case .error(let html): return html
        }
    }

    private var displayTheme: Theme {
        if case .error = content { return .system }
        return appState.theme
    }

    private var renderOptions: RenderOptions {
        var opts = RenderOptions()
        opts.title = fileURL.lastPathComponent
        opts.baseURL = fileURL
        opts.theme = appState.theme.rawValue
        opts.blockRemoteContent = !appState.allowRemoteContent
        opts.doccAlertMode = appState.doccAlertMode
        return opts
    }

    private var displayContentID: String {
        switch content {
        case .text(let text): return "\(text)\(renderOptions)"
        case .error:          return "load-error"
        }
    }

    private var modeHTML: String {
        guard case .text(let text) = content else { return "" }
        if state.mode == .down {
            return MudCore.renderDownModeDocument(text, options: renderOptions)
        }
        return MudCore.renderUpModeDocument(text, options: renderOptions,
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
            html: displayHTML,
            baseURL: fileURL,
            contentID: displayContentID,
            mode: state.mode,
            theme: displayTheme,
            bodyClasses: Set(appState.viewToggles.map(\.className)),
            zoomLevel: modeZoomLevel,
            searchQuery: findState.currentQuery,
            scrollTarget: state.scrollTarget,
            reloadID: state.reloadID,
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
        do {
            let data = try Data(contentsOf: fileURL)
            guard let text = String(data: data, encoding: .utf8) else {
                content = .error(ErrorPage.fileEncodingError())
                return
            }
            content = .text(text)
            state.outlineHeadings = MudCore.extractHeadings(text)
        } catch let cocoaError as CocoaError where cocoaError.code == .fileReadNoSuchFile {
            content = .error(ErrorPage.fileNotFound(error: cocoaError))
        } catch {
            content = .error(ErrorPage.filePermissionDenied(path: fileURL.path, error: error))
        }
    }

    private func openInBrowser() {
        guard case .text(let text) = content else { return }
        let tempDir = NSTemporaryDirectory()
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let tempURL = URL(fileURLWithPath: tempDir)
            .appendingPathComponent(baseName)
            .appendingPathExtension("html")
        var exportOptions = renderOptions
        exportOptions.includeBaseTag = false
        exportOptions.embedMermaid = true
        let exportDocument: String
        if state.mode == .down {
            exportDocument = MudCore.renderDownModeDocument(text,
                options: exportOptions)
        } else {
            exportDocument = MudCore.renderUpModeDocument(text,
                options: exportOptions,
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
