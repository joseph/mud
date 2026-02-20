import SwiftUI
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate {
    private var hasOpenedDocument = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        let args = Array(CommandLine.arguments.dropFirst())

        // CLI: render to stdout and exit without launching the GUI
        if CommandLineInterface.looksLikeCLI(args) {
            NSApp.setActivationPolicy(.prohibited)
            exit(CommandLineInterface.run(args))
        }

        // Invoked via symlink (CLI tool) without render flags: hand off
        // to `open -a` so the real app instance handles it, then exit.
        // This covers `mud file.md`, piped stdin, and bare `mud`.
        if CommandLineInterface.launchedViaSymlink {
            var urls = CommandLineInterface.fileArguments(args).map {
                URL(fileURLWithPath: $0).standardizedFileURL
            }
            if urls.isEmpty, CommandLineInterface.hasStdin,
               let tempURL = CommandLineInterface.stdinToTempFile() {
                urls.append(tempURL)
            }
            NSApp.setActivationPolicy(.prohibited)
            CommandLineInterface.openInApp(urls)
            exit(0)
        }

        // Suppress system Edit menu items irrelevant for a read-only app
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")

        // Install our custom document controller before anything else
        _ = DocumentController()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // F6 as secondary shortcut for Toggle Lighting (Cmd-L is primary)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 97 {  // F6
                NSApp.sendAction(
                    #selector(DocumentWindowController.toggleLighting(_:)),
                    to: nil, from: nil
                )
                return nil
            }
            return event
        }

        // Strip AutoFill whenever the system adds it to the Edit menu
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(menuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )

        // If no documents were opened, show file picker
        DispatchQueue.main.async {
            if NSApp.windows.filter({ $0.isVisible }).isEmpty {
                self.openOrQuit()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        hasOpenedDocument && AppState.shared.quitOnClose
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        hasOpenedDocument = true
        for url in urls {
            NSDocumentController.shared.openDocument(
                withContentsOf: url,
                display: true
            ) { _, _, _ in }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openOrQuit()
        }
        return true
    }

    @objc private func menuDidAddItem(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              menu == NSApp.mainMenu?.item(withTitle: "Edit")?.submenu else { return }
        // Hide rather than remove — SwiftUI tracks item indices internally
        // and removing items causes index-out-of-bounds crashes on update.
        for item in menu.items {
            if item.title.localizedCaseInsensitiveContains("autofill") {
                item.isHidden = true
            }
        }
    }

    private func openOrQuit() {
        DocumentController.showOpenPanel()

        // If user cancelled and no windows are open, quit
        if NSApp.windows.filter({ $0.isVisible }).isEmpty {
            NSApp.terminate(nil)
        } else {
            hasOpenedDocument = true
        }
    }
}
