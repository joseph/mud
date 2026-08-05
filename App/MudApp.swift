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
    /// The key document window's snapshot; `nil` disables document menu items.
    @ObservedObject private var activeDocument = ActiveDocumentObserver.shared

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
                    let apps = openIn.menuApps
                    ForEach(apps) { entry in
                        Button {
                            openIn.launch(with: entry.handler)
                        } label: {
                            Label {
                                Text(entry.title)
                            } icon: {
                                Image(nsImage: entry.handler.icon)
                            }
                        }
                        .modify { view in
                            if entry.isDefault {
                                view.keyboardShortcut("e", modifiers: [.command, .shift])
                            } else {
                                view
                            }
                        }
                        if entry.isDefault {
                            Divider()
                        }
                    }
                    if let last = apps.last, !last.isDefault {
                        Divider()
                    }
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
                    Button("Open In Browser") {
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

            CommandGroup(before: .toolbar) {
                Button(appState.sidebarEnabled ? "Hide Sidebar" : "Show Sidebar") {
                    NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Button(appState.changesEnabled ? "Hide Changes" : "Show Changes") {
                    appState.changesEnabled.toggle()
                }
                .keyboardShortcut("c", modifiers: [.command, .control])

                Button(activeDocument.snapshot?.commentsColumnVisible == true
                       ? "Hide Comments" : "Show Comments") {
                    NSApp.sendAction(#selector(DocumentWindowController.toggleCommentsColumn(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("k", modifiers: [.command, .control])
                .disabled(activeDocument.snapshot?.mode != .up)

                Divider()

                Toggle("Mark Up", isOn: Binding(
                    get: { activeDocument.snapshot?.mode == .up },
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
                    get: { activeDocument.snapshot?.mode == .down },
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

                // Only while the setting is on: with it off there are no
                // arrows and nothing to fold, so the pair would be two dead
                // items pointing at a preference the reader can't see from
                // here. Ctrl-Cmd-H rather than Cmd-H, which is Hide Mud.
                if appState.viewToggles.contains(.foldableHeadings) {
                    Button("Fold Headings") {
                        NSApp.sendAction(
                            #selector(DocumentWindowController.foldHeadings(_:)),
                            to: nil, from: nil
                        )
                    }
                    .keyboardShortcut("h", modifiers: [.command, .control])
                    .disabled(activeDocument.snapshot?.mode != .up)

                    Button("Unfold Headings") {
                        NSApp.sendAction(
                            #selector(DocumentWindowController.unfoldHeadings(_:)),
                            to: nil, from: nil
                        )
                    }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                    .disabled(activeDocument.snapshot?.mode != .up)
                }

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
                Button {
                    NSApp.sendAction(#selector(DocumentWindowController.addComment(_:)), to: nil, from: nil)
                } label: {
                    Label("Add Comment…", systemImage: "plus.message")
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!(activeDocument.snapshot?.canAddComment ?? false))

                Divider()

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

    /// Whether Mud can write a comment back to the document this URL stands
    /// for. False for a bundled guide, which lives inside the app, and for a
    /// folder, whose index Mud generates rather than reads — there is no file
    /// under it to edit.
    var isEditableDocument: Bool {
        !isBundleResource && !MarkdownFolder.isFolder(self)
    }
}

// MARK: - UTType

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}
