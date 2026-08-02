import AppKit
import SwiftUI

class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()
    private var hasBeenShown = false

    private convenience init() {
        let window = NSWindow(
            contentRect: NSRect(
                x: 0, y: 0,
                width: SettingsView.width, height: SettingsView.minHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false

        // `.resizable` enables the zoom button; a settings window has no use
        // for it, so it stays greyed out as it was before.
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        // An empty toolbar is needed for NavigationSplitView to populate
        // its title and items into the unified titlebar.
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        let hosting = NSHostingController(rootView: SettingsView())
        // Turn the root frame's limits into constraints on the hosting view,
        // which is what the window resizes against. `.preferredContentSize` is
        // left out on purpose: it would push the content's fitting size back
        // onto the window on every SwiftUI layout, snapping a window the user
        // had dragged taller back to its opening height on the next pane
        // switch.
        hosting.sizingOptions = [.minSize, .maxSize]
        window.contentViewController = hosting

        // Installing the content view controller recomputes the window's size
        // limits from the new content, so state them afterwards. Equal min and
        // max widths are what make the window vertically resizable only.
        window.contentMinSize = NSSize(
            width: SettingsView.width, height: SettingsView.minHeight)
        window.contentMaxSize = NSSize(
            width: SettingsView.width, height: SettingsView.maxHeight)

        self.init(window: window)
    }

    func openSettings() {
        showWindow(nil)
        if !hasBeenShown {
            window?.center()
            hasBeenShown = true
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
