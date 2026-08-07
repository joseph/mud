import SwiftUI
import UniformTypeIdentifiers
import MudPreferences

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Suppress system Edit menu items irrelevant for a read-only app
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")

        // Install our custom document controller before anything else
        _ = DocumentController()

        // Take back the folder grants the reader has made, before any document
        // opens, so a document's local images are readable the first time it
        // renders rather than after a reload.
        AssetAccessStore.shared.resolveSavedGrants()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // F3 / F4 / F6 as secondary shortcuts for Sidebar / Find / Lighting
        // (Cmd-Ctrl-S / Cmd-F / Cmd-L are primary)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 99 {  // F3
                NSApp.sendAction(
                    #selector(NSSplitViewController.toggleSidebar(_:)),
                    to: nil, from: nil
                )
                return nil
            }
            if event.keyCode == 118 {  // F4
                NSApp.sendAction(
                    #selector(DocumentWindowController.performFindAction(_:)),
                    to: nil, from: nil
                )
                return nil
            }
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

        // If no documents were opened, show the bundled HUMANS.md on first
        // launch, or the file picker on subsequent launches.
        DispatchQueue.main.async {
            guard !isRunningTests else { return }
            if NSApp.windows.filter({ $0.isVisible }).isEmpty {
                if Self.isFirstLaunch() {
                    self.openBundledReadme()
                } else {
                    self.openOrQuit()
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        (NSDocumentController.shared as? DocumentController)?.hasOpenedDocument == true
            && AppState.shared.quitOnClose
    }

    func application(_ application: NSApplication, open urls: [URL]) {
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

    // String matching on system menu titles is English-only.
    // TODO: revisit when adding localization support.
    @objc private func menuDidAddItem(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu,
              let title = menu.supermenu?.items.first(where: { $0.submenu == menu })?.title,
              title == "Edit" || title == "View" else { return }
        // Hide rather than remove — SwiftUI tracks item indices internally
        // and removing items causes index-out-of-bounds crashes on update.
        for item in menu.items {
            if item.title.localizedCaseInsensitiveContains("autofill") ||
               item.title.localizedCaseInsensitiveContains("full screen") {
                item.isHidden = true
            }
        }
    }

    private static func isFirstLaunch() -> Bool {
        if MudPreferences.shared.hasLaunched { return false }
        MudPreferences.shared.hasLaunched = true
        return true
    }

    private func openBundledReadme() {
        DocumentController.openBundledDocument("HUMANS", subdirectory: "Doc")
    }

    private func openOrQuit() {
        guard let controller = NSDocumentController.shared as? DocumentController else { return }
        controller.presentOpenPanel {
            // The panel is modeless, so this runs after it closes. If no
            // document window is up, the user cancelled an empty launch — quit,
            // since there's nothing to show. Opening a document (via the panel
            // or Open Recent) leaves its window on screen, so we stay.
            let hasDocumentWindow = NSApp.windows.contains {
                $0.isVisible && $0.windowController is DocumentWindowController
            }
            if !hasDocumentWindow {
                NSApp.terminate(nil)
            }
        }
    }
}

// MARK: - Test Host

// The Mud Tests target hosts inside Mud.app (@testable import Mud), so the
// app's launch path still runs under Cmd+U. Without this guard it would show
// the open panel modally, blocking the run loop that pump/pumpUntil depend on,
// and mark UserDefaults.standard.hasLaunched true — the same domain the real
// app uses on this machine.
private let isRunningTests = ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] != nil
