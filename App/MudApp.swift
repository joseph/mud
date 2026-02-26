import Combine
import SwiftUI
import UniformTypeIdentifiers

@main
struct MudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appState = AppState.shared

    var body: some Scene {
        // No windows managed by SwiftUI — DocumentController handles them
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    DocumentController.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    RecentDocumentsMenu()
                }

                Divider()

                if !isSandboxed {
                    Button("Open in Browser") {
                        NSApp.sendAction(#selector(DocumentWindowController.openInBrowser(_:)), to: nil, from: nil)
                    }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                }

                Button("Print...") {
                    NSApp.sendAction(#selector(DocumentWindowController.printCurrentDocument(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("p", modifiers: .command)

                Divider()

                Button("Reload") {
                    NSApp.sendAction(#selector(DocumentWindowController.reloadDocument(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Close") {
                    NSApp.keyWindow?.close()
                }
                .keyboardShortcut("w", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .undoRedo) { }

            CommandGroup(before: .toolbar) {
                Toggle("Mark Up", isOn: Binding(
                    get: { appState.modeInActiveTab == .up },
                    set: { newValue in
                        if newValue {
                            NSApp.sendAction(
                                #selector(DocumentWindowController.toggleMode(_:)),
                                to: nil, from: nil
                            )
                        }
                    }
                ))

                Toggle("Mark Down", isOn: Binding(
                    get: { appState.modeInActiveTab == .down },
                    set: { newValue in
                        if newValue {
                            NSApp.sendAction(
                                #selector(DocumentWindowController.toggleMode(_:)),
                                to: nil, from: nil
                            )
                        }
                    }
                ))

                Divider()

                Toggle("Sidebar", isOn: Binding(
                    get: { appState.sidebarVisible },
                    set: { _ in
                        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                    }
                ))
                .keyboardShortcut("s", modifiers: [.command, .control])

                Toggle("Readable Column", isOn: Binding(
                    get: { appState.viewToggles.contains(.readableColumn) },
                    set: { _ in appState.toggle(.readableColumn) }
                ))

                Toggle("Line Numbers", isOn: Binding(
                    get: { appState.viewToggles.contains(.lineNumbers) },
                    set: { _ in appState.toggle(.lineNumbers) }
                ))
                .disabled(appState.modeInActiveTab == .up)

                Toggle("Word Wrap", isOn: Binding(
                    get: { appState.viewToggles.contains(.wordWrap) },
                    set: { _ in appState.toggle(.wordWrap) }
                ))
                .disabled(appState.modeInActiveTab == .up)

                Divider()

                Button("Actual Size") {
                    NSApp.sendAction(#selector(DocumentWindowController.actualSize(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Button("Zoom In") {
                    NSApp.sendAction(#selector(DocumentWindowController.zoomIn(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NSApp.sendAction(#selector(DocumentWindowController.zoomOut(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("-", modifiers: .command)
            }

            CommandMenu("Theme") {
                ForEach(Theme.allCases, id: \.self) { theme in
                    Toggle(theme.rawValue.capitalized, isOn: Binding(
                        get: { appState.theme == theme },
                        set: { _ in appState.theme = theme }
                    ))
                }

                Divider()

                Toggle(
                    Lighting.systemIsDark ? "Bright Lighting" : "Dark Lighting",
                    isOn: Binding(
                        get: { appState.lighting != .auto },
                        set: { _ in
                            NSApp.sendAction(
                                #selector(DocumentWindowController.toggleLighting(_:)),
                                to: nil, from: nil
                            )
                        }
                    )
                )
                .keyboardShortcut("l", modifiers: .command)
            }

            CommandGroup(replacing: .textEditing) {
                Button("Find...") {
                    NSApp.sendAction(#selector(DocumentWindowController.performFindAction(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    NSApp.sendAction(#selector(DocumentWindowController.findNext(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") {
                    NSApp.sendAction(#selector(DocumentWindowController.findPrevious(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Recent Documents Menu

struct RecentDocumentsMenu: View {
    @State private var recentURLs: [URL] = []

    var body: some View {
        ForEach(recentURLs, id: \.absoluteString) { url in
            Button(url.lastPathComponent) {
                NSDocumentController.shared.openDocument(
                    withContentsOf: url,
                    display: true
                ) { _, _, _ in }
            }
        }

        if !recentURLs.isEmpty {
            Divider()
        }

        Button("Clear Menu") {
            NSDocumentController.shared.clearRecentDocuments(nil)
            recentURLs = []
        }
        .disabled(recentURLs.isEmpty)
        .onAppear {
            recentURLs = NSDocumentController.shared.recentDocumentURLs
        }
    }
}

// MARK: - App State

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var modeInActiveTab: Mode = .up
    @Published var lighting: Lighting
    @Published var theme: Theme
    @Published var viewToggles: Set<ViewToggle>
    @Published var upModeZoomLevel: Double
    @Published var downModeZoomLevel: Double
    @Published var sidebarVisible: Bool
    @Published var quitOnClose: Bool

    private static let lightingKey = "Mud-Lighting"
    private static let themeKey = "Mud-Theme"
    private static let upModeZoomKey = "Mud-UpModeZoomLevel"
    private static let downModeZoomKey = "Mud-DownModeZoomLevel"
    private static let sidebarVisibleKey = "Mud-SidebarVisible"
    private static let quitOnCloseKey = "Mud-QuitOnClose"

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.lightingKey) ?? ""
        self.lighting = Lighting(rawValue: raw) ?? .auto
        let themeRaw = UserDefaults.standard.string(forKey: Self.themeKey) ?? ""
        self.theme = Theme(rawValue: themeRaw) ?? .earthy
        self.viewToggles = Set(ViewToggle.allCases.filter { $0.isEnabled })
        let defaults = UserDefaults.standard
        self.upModeZoomLevel = defaults.object(forKey: Self.upModeZoomKey) as? Double ?? 1.0
        self.downModeZoomLevel = defaults.object(forKey: Self.downModeZoomKey) as? Double ?? 1.0
        self.sidebarVisible = defaults.bool(forKey: Self.sidebarVisibleKey)
        self.quitOnClose = defaults.object(forKey: Self.quitOnCloseKey) as? Bool ?? true
    }

    func saveLighting(_ lighting: Lighting) {
        UserDefaults.standard.set(lighting.rawValue, forKey: Self.lightingKey)
    }

    func saveTheme(_ theme: Theme) {
        UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
    }

    func saveZoomLevels() {
        UserDefaults.standard.set(upModeZoomLevel, forKey: Self.upModeZoomKey)
        UserDefaults.standard.set(downModeZoomLevel, forKey: Self.downModeZoomKey)
    }

    func saveSidebarVisible() {
        UserDefaults.standard.set(sidebarVisible, forKey: Self.sidebarVisibleKey)
    }

    func saveQuitOnClose() {
        UserDefaults.standard.set(quitOnClose, forKey: Self.quitOnCloseKey)
    }

    func toggle(_ option: ViewToggle) {
        if viewToggles.contains(option) {
            viewToggles.remove(option)
        } else {
            viewToggles.insert(option)
        }
        option.save(viewToggles.contains(option))
    }
}

// MARK: - Sandbox

let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

// MARK: - UTType

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}
