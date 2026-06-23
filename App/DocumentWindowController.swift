import SwiftUI
import Combine
import MudPreferences

// MARK: - Document Window Controller

class DocumentWindowController: NSWindowController {
    let fileURL: URL
    let state = DocumentState()
    var onClose: ((DocumentWindowController) -> Void)?

    private var lightingButton: NSButton?
    private var modeButton: NSButton?
    private var findButton: NSButton?
    private var changesButton: NSButton?
    private var readableColumnButton: NSButton?
    private var commentButton: NSButton?
    private var commentsColumnButton: NSButton?
    private var zoomControl: NSSegmentedControl?

    private var splitVC: NSSplitViewController?
    private var cancellables = Set<AnyCancellable>()

    init(url: URL) {
        self.fileURL = url

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = url.lastPathComponent
        window.representedURL = url
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 500, height: 400)

        super.init(window: window)
        shouldCascadeWindows = false
        state.windowController = self

        // Apply lighting BEFORE content setup to prevent flash
        applyLighting(AppState.shared.lighting)
        setupContent()
        setupToolbar()
        observeState()

        // Restore saved window frame AFTER content and toolbar setup,
        // so that layout changes don't override the saved frame.
        if let frameString = MudPreferences.shared.windowFrame {
            window.setFrame(NSRectFromString(frameString), display: false)
        } else {
            window.setContentSize(NSSize(width: 860, height: 740))
            window.center()
        }

        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        let sidebarView = SidebarView(
            state: state,
            changeTracker: state.changeTracker,
            onSelectHeading: { [weak self] heading in
                self?.state.scrollTarget = ScrollTarget(id: UUID(), heading: heading)
            },
            onSelectChange: { [weak self] changeIDs in
                self?.state.changeScrollTarget = ChangeScrollTarget(
                    id: UUID(), changeIDs: changeIDs)
            }
        )
        let sidebarHost = NSHostingController(rootView: sidebarView)

        let contentView = DocumentContentView(fileURL: fileURL, state: state, findState: state.find, changeTracker: state.changeTracker)
        let contentHost = NSHostingController(rootView: contentView)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 246
        sidebarItem.maximumThickness = 400

        let contentItem = NSSplitViewItem(viewController: contentHost)

        let split = NSSplitViewController()
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(contentItem)
        splitVC = split

        window?.contentViewController = split

        // Collapse sidebar if persisted state says hidden
        if !AppState.shared.sidebarEnabled {
            sidebarItem.isCollapsed = true
        }
    }

    private func setupToolbar() {
        let toolbar = NSToolbar(identifier: "DocumentToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        window?.toolbar = toolbar
    }



    private func observeState() {
        AppState.shared.$lighting
            .dropFirst()
            .sink { [weak self] lighting in
                self?.applyLighting(lighting)
                self?.updateLightingButton(lighting)
            }
            .store(in: &cancellables)

        state.$mode
            .dropFirst()
            .sink { [weak self] mode in
                self?.updateModeButton(mode)
                self?.updateZoomLabel(for: mode)
                self?.updateCommentButton()
                if self?.window?.isKeyWindow == true {
                    deferMutation {
                        AppState.shared.modeInActiveTab = mode
                    }
                }
            }
            .store(in: &cancellables)

        // Enable the "Comment" toolbar button only while the rendered view holds
        // a commentable selection.
        state.commentableSelection
            .sink { [weak self] _ in self?.updateCommentButton() }
            .store(in: &cancellables)

        // Keep this window's Comments-column toolbar button in step with its own
        // visibility, and mirror that visibility into AppState for the View-menu
        // label, but only while it is the key window.
        state.$commentsColumnVisible
            .sink { [weak self] visible in
                self?.updateCommentsColumnButton(visible)
                guard self?.window?.isKeyWindow == true else { return }
                AppState.shared.activeCommentsColumnVisible = visible
            }
            .store(in: &cancellables)

        AppState.shared.$viewToggles
            .sink { [weak self] toggles in
                self?.updateReadableColumnButton(toggles.contains(.readableColumn))
            }
            .store(in: &cancellables)

        AppState.shared.$changesEnabled
            .sink { [weak self] enabled in
                self?.updateChangesButton(enabled)
            }
            .store(in: &cancellables)

        state.find.$isVisible
            .sink { [weak self] visible in
                self?.updateFindButton(visible)
            }
            .store(in: &cancellables)

        state.$contentTitle
            .combineLatest(AppState.shared.$uiUseHeadingAsTitle)
            .sink { [weak self] title, useHeading in
                guard let self, let window = self.window else { return }
                if useHeading, let title {
                    window.title = title
                } else {
                    window.title = self.fileURL.lastPathComponent
                }
            }
            .store(in: &cancellables)

        state.$hasBackgroundReload
            .sink { [weak self] hasReload in
                self?.updateTabReloadBadge(hasReload)
            }
            .store(in: &cancellables)

        // Track sidebar collapse state for persistence
        if let sidebarItem = splitVC?.splitViewItems.first {
            sidebarItem.publisher(for: \.isCollapsed)
                .dropFirst()
                .sink { collapsed in
                    AppState.shared.sidebarEnabled = !collapsed
                }
                .store(in: &cancellables)
        }
    }

    private func applyLighting(_ lighting: Lighting) {
        window?.appearance = lighting.appearance
    }

    private func updateTabReloadBadge(_ showBadge: Bool) {
        guard let window else { return }
        if showBadge {
            if !(window.tab.accessoryView is TabReloadBadgeView) {
                window.tab.accessoryView = TabReloadBadgeView()
            }
        } else {
            window.tab.accessoryView = nil
        }
    }

    private func updateLightingButton(_ lighting: Lighting) {
        let isDark = lighting.isDark()
        lightingButton?.image = NSImage(systemSymbolName: isDark ? "moon" : "sun.max", accessibilityDescription: nil)
        lightingButton?.toolTip = isDark ? "Switch to Bright Lighting" : "Switch to Dark Lighting"
    }

    private func updateModeButton(_ mode: Mode) {
        let symbol = mode == .down ? "arrow.uturn.down.circle.fill" : "arrow.uturn.up.circle"
        modeButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        modeButton?.toolTip = mode == .down ? "Switch to Mark Up" : "Switch to Mark Down"
    }

    private func updateReadableColumnButton(_ on: Bool) {
        let symbol = on
            ? "rectangle.portrait.arrowtriangle.2.inward"
            : "rectangle.portrait.arrowtriangle.2.outward"
        readableColumnButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        readableColumnButton?.toolTip = on ? "Show document full-width" : "Show document in a readable-width column"
    }

    /// The "Comment" button adds a comment to the selection, so it is live only
    /// for a commentable selection in a writable Up-mode document. Mirrors the
    /// same condition into `AppState` for the key window so the "Add Comment"
    /// menu item (and its shortcut) gates in step with the button.
    private func updateCommentButton() {
        let canAdd = state.mode == .up
            && state.commentableSelection.value
            && !fileURL.isBundleResource
        commentButton?.isEnabled = canAdd
        if window?.isKeyWindow == true {
            AppState.shared.canAddComment = canAdd
        }
    }

    private func updateChangesButton(_ enabled: Bool) {
        let symbol = enabled ? "clock.fill" : "clock"
        changesButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        changesButton?.toolTip = enabled ? "Hide Changes" : "Show Changes"
    }

    private func updateFindButton(_ visible: Bool) {
        let symbol = visible ? "magnifyingglass.circle.fill" : "magnifyingglass.circle"
        findButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    private func updateCommentsColumnButton(_ visible: Bool) {
        let symbol = visible ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.and.text.bubble.right"
        commentsColumnButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        commentsColumnButton?.toolTip = visible ? "Hide Comments" : "Show Comments"
    }

    private func updateToggleButton(_ button: NSButton?, on: Bool) {
        button?.state = on ? .on : .off
    }

    private func updateZoomLabel(for mode: Mode? = nil) {
        let app = AppState.shared
        let level = (mode ?? state.mode) == .down ? app.downModeZoomLevel : app.upModeZoomLevel
        let percent = Int(round(level * 100))
        zoomControl?.setLabel("\(percent)%", forSegment: 1)
        zoomControl?.setWidth(0, forSegment: 1) // auto-size
    }

    @objc func toggleReadableColumn(_ sender: Any?) {
        AppState.shared.toggle(.readableColumn)
    }

    /// Reveals the Comments column (per-window state, so a later class-sync keeps
    /// it shown) and opens a compose box on the current selection.
    @objc func addComment(_ sender: Any?) {
        state.commentsColumnVisible = true
        state.addCommentID = UUID()
    }

    /// Shows or hides the Comments column for this window only.
    @objc func toggleCommentsColumn(_ sender: Any?) {
        state.commentsColumnVisible.toggle()
    }

    @objc func zoomAction(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: adjustZoom(by: -0.1)
        case 1: resetZoom()
        case 2: adjustZoom(by: 0.1)
        default: break
        }
    }

    @objc func toggleLighting(_ sender: Any?) {
        AppState.shared.lighting = AppState.shared.lighting.toggled()
    }

    @objc func toggleMode(_ sender: Any?) {
        state.toggleMode()
    }

    @objc func printCurrentDocument(_ sender: Any?) {
        state.printID = UUID()
    }

    @objc func openInBrowser(_ sender: Any?) {
        state.openInBrowserID = UUID()
    }

    @objc func zoomIn(_ sender: Any?) {
        adjustZoom(by: 0.1)
    }

    @objc func zoomOut(_ sender: Any?) {
        adjustZoom(by: -0.1)
    }

    @objc func actualSize(_ sender: Any?) {
        resetZoom()
    }

    @objc func openSettings(_ sender: Any?) {
        SettingsWindowController.shared.openSettings()
    }

    private func adjustZoom(by delta: Double) {
        let app = AppState.shared
        if state.mode == .down {
            app.downModeZoomLevel = (app.downModeZoomLevel + delta)
                .clamped(to: 0.5...3.0)
        } else {
            app.upModeZoomLevel = (app.upModeZoomLevel + delta)
                .clamped(to: 0.5...3.0)
        }
        updateZoomLabel()
    }

    private func resetZoom() {
        let app = AppState.shared
        if state.mode == .down {
            app.downModeZoomLevel = 1.0
        } else {
            app.upModeZoomLevel = 1.0
        }
        updateZoomLabel()
    }

    @objc func reloadDocument(_ sender: Any?) {
        state.reloadID = UUID()
    }

    @objc func performFindAction(_ sender: Any?) {
        if state.find.isVisible {
            state.find.close()
        } else {
            state.find.show()
        }
    }

    @objc func toggleChangesBar(_ sender: Any?) {
        AppState.shared.changesEnabled.toggle()
    }

    @objc func findNext(_ sender: Any?) {
        state.find.findNext()
    }

    @objc func findPrevious(_ sender: Any?) {
        state.find.findPrevious()
    }

    private func makeToolbarButton(symbolName: String, action: Selector, toggle: Bool = false) -> NSButton {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 38, height: 24))
        button.bezelStyle = .texturedRounded
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        if toggle { button.setButtonType(.toggle) }
        return button
    }

}

// MARK: - NSWindowDelegate

extension DocumentWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        AppState.shared.modeInActiveTab = state.mode
        AppState.shared.activeDocumentEditable = !fileURL.isBundleResource
        AppState.shared.activeCommentsColumnVisible = state.commentsColumnVisible
        updateCommentButton()
        state.hasBackgroundReload = false
    }

    func windowWillClose(_ notification: Notification) {
        // Save window frame for next launch
        if let frame = window?.frame {
            MudPreferences.shared.windowFrame = NSStringFromRect(frame)
        }
        onClose?(self)
    }
}

// MARK: - NSToolbarDelegate

extension DocumentWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .addComment,
            .toggleCommentsColumn,
            .space,
            .toggleFind,
            .toggleChanges,
            .space,
            .toggleMode
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .flexibleSpace,
            .space,
            .zoom,
            .toggleReadableColumn,
            .addComment,
            .toggleCommentsColumn,
            .toggleLighting,
            .toggleFind,
            .toggleChanges,
            .toggleMode,
            .settings
        ]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .toggleLighting:
            let button = makeToolbarButton(symbolName: "sun.max", action: #selector(toggleLighting(_:)))
            if flag { lightingButton = button }
            updateLightingButton(AppState.shared.lighting)
            item.view = button
            item.label = "Lighting"
            return item

        case .toggleMode:
            let button = makeToolbarButton(symbolName: "arrow.uturn.up.circle", action: #selector(toggleMode(_:)))
            if flag { modeButton = button }
            updateModeButton(state.mode)
            item.view = button
            item.label = "Mode"
            return item

        case .toggleChanges:
            let button = makeToolbarButton(symbolName: "clock", action: #selector(toggleChangesBar(_:)))
            if flag { changesButton = button }
            updateChangesButton(AppState.shared.changesEnabled)
            item.view = button
            item.label = "Changes"
            return item

        case .toggleFind:
            let button = makeToolbarButton(symbolName: "magnifyingglass.circle", action: #selector(performFindAction(_:)))
            if flag { findButton = button }
            button.toolTip = "Find…"
            item.view = button
            item.label = "Find"
            return item

        case .toggleReadableColumn:
            let button = makeToolbarButton(symbolName: "rectangle.portrait.arrowtriangle.2.inward", action: #selector(toggleReadableColumn(_:)))
            if flag { readableColumnButton = button }
            updateReadableColumnButton(AppState.shared.viewToggles.contains(.readableColumn))
            item.view = button
            item.label = "Column"
            return item

        case .addComment:
            let button = makeToolbarButton(symbolName: "plus.message", action: #selector(addComment(_:)))
            button.toolTip = "Add Comment…"
            if flag { commentButton = button }
            updateCommentButton()
            item.view = button
            item.label = "Comment"
            return item

        case .toggleCommentsColumn:
            let button = makeToolbarButton(symbolName: "bubble.left.and.text.bubble.right", action: #selector(toggleCommentsColumn(_:)))
            if flag { commentsColumnButton = button }
            updateCommentsColumnButton(state.commentsColumnVisible)
            item.view = button
            item.label = "Comments"
            return item

        case .zoom:
            let control = NSSegmentedControl()
            control.segmentCount = 3
            control.trackingMode = .momentary
            control.setImage(NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "Zoom Out"), forSegment: 0)
            control.setImage(NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoom In"), forSegment: 2)
            control.setWidth(30, forSegment: 0)
            control.setWidth(30, forSegment: 2)
            control.setToolTip("Zoom Out", forSegment: 0)
            control.setToolTip("Zoom In", forSegment: 2)
            let level = state.mode == .down ? AppState.shared.downModeZoomLevel : AppState.shared.upModeZoomLevel
            control.setLabel("\(Int(round(level * 100)))%", forSegment: 1)
            control.setWidth(0, forSegment: 1)
            control.target = self
            control.action = #selector(zoomAction(_:))
            if flag { zoomControl = control }
            item.view = control
            item.label = "Zoom"
            return item

        case .settings:
            let button = makeToolbarButton(symbolName: "gearshape", action: #selector(openSettings(_:)))
            button.toolTip = "Settings…"
            item.view = button
            item.label = "Settings"
            return item

        default:
            return nil
        }
    }
}

extension NSToolbarItem.Identifier {
    static let zoom = NSToolbarItem.Identifier("zoom")
    static let settings = NSToolbarItem.Identifier("settings")
    static let toggleReadableColumn = NSToolbarItem.Identifier("toggleReadableColumn")
    static let addComment = NSToolbarItem.Identifier("addComment")
    static let toggleCommentsColumn = NSToolbarItem.Identifier("toggleCommentsColumn")
    static let toggleLighting = NSToolbarItem.Identifier("toggleLighting")
    static let toggleMode = NSToolbarItem.Identifier("toggleMode")
    static let toggleChanges = NSToolbarItem.Identifier("toggleChanges")
    static let toggleFind = NSToolbarItem.Identifier("find")
}
