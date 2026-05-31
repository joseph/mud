import Combine
import MudPreferences
import MudCore
import SwiftUI
import UniformTypeIdentifiers

@main
struct MudApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var openIn = OpenInMenuModel.shared

    var body: some Scene {
        // No windows managed by SwiftUI — DocumentController handles them.
        // Settings lives in SettingsWindowController (AppKit) so we can
        // use .unified toolbar style; the Settings scene here is only the
        // required anchor for App.body.
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button {
                    SettingsWindowController.shared.openSettings()
                } label: {
                    Label("Settings...", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)

                #if SPARKLE
                CheckForUpdatesView()
                #endif
            }

            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    DocumentController.showOpenPanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    RecentDocumentsMenu()
                }

                Divider()

                Menu("Open In…") {
                    if let configured = openIn.configured {
                        Button {
                            openIn.launch(with: configured)
                        } label: {
                            Label {
                                Text("\(configured.displayName)  (default)")
                            } icon: {
                                Image(nsImage: configured.icon)
                            }
                        }
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                        Divider()
                    }
                    ForEach(openIn.others) { handler in
                        Button {
                            openIn.launch(with: handler)
                        } label: {
                            Label {
                                Text(handler.displayName)
                            } icon: {
                                Image(nsImage: handler.icon)
                            }
                        }
                    }
                    Divider()
                    Button("Choose…") {
                        openIn.chooseEditor()
                    }
                    .modify { view in
                        if openIn.configured == nil {
                            view.keyboardShortcut("e", modifiers: [.command, .shift])
                        } else {
                            view
                        }
                    }
                }

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
                Button(appState.sidebarEnabled ? "Hide Sidebar" : "Show Sidebar") {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Button(appState.changesEnabled ? "Hide Changes" : "Show Changes") {
                    appState.changesEnabled.toggle()
                }
                .keyboardShortcut("c", modifiers: [.command, .control])

                Divider()

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

                Toggle("Readable Column", isOn: Binding(
                    get: { appState.viewToggles.contains(.readableColumn) },
                    set: { _ in appState.toggle(.readableColumn) }
                ))
                .keyboardShortcut("r", modifiers: [.command, .control])

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

            CommandGroup(replacing: .help) {
                Button("HUMANS Guide to Mud") {
                    DocumentController.openBundledDocument("HUMANS", subdirectory: "Doc")
                }
                Button("Release Notes") {
                    DocumentController.openBundledDocument("RELEASES", subdirectory: "Doc")
                }
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

// MARK: - Sandbox

let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

// MARK: - Bundle Resources

extension URL {
    var isBundleResource: Bool {
        path.hasPrefix(Bundle.main.bundlePath)
    }
}

// MARK: - UTType

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}
