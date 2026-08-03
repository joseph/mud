import SwiftUI
import Combine
import MudCore
import MudPreferences

// MARK: - Document Window Controller

class DocumentWindowController: NSWindowController {
    let fileURL: URL
    let state: DocumentState
    let model: DocumentModel
    var onClose: ((DocumentWindowController) -> Void)?

    private var lightingButton: NSButton?
    private var modeButton: NSButton?
    private var findButton: NSButton?
    private var changesButton: NSButton?
    private var readableColumnButton: NSButton?
    private var commentButton: NSButton?
    private var commentsColumnButton: NSButton?
    private var openInItem: NSMenuToolbarItem?
    private var zoomControl: NSSegmentedControl?

    private var splitVC: NSSplitViewController?
    private var cancellables = Set<AnyCancellable>()

    init(url: URL) {
        self.fileURL = url
        let state = DocumentState()
        self.state = state
        self.model = DocumentModel(
            fileURL: url, state: state, changeTracker: state.changeTracker)

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

        // Default size/position for a file with no saved frame yet. Applied
        // BEFORE the frame-autosave name below, so a first-time open still
        // gets a sensible starting frame instead of Cocoa's zero-size
        // default; `setFrameAutosaveName` overwrites it immediately if a
        // saved frame already exists for this file.
        window.setContentSize(NSSize(width: 860, height: 740))
        window.center()

        // Per-file frame autosave (AFTER content/toolbar setup, so their
        // layout doesn't override the restored frame): each file's window
        // remembers its own size and position, so closing one window can no
        // longer overwrite another's, which the single global `windowFrame`
        // preference used to do. Cocoa saves and restores this automatically
        // from here on — no explicit save/restore code needed.
        window.setFrameAutosaveName(Self.frameAutosaveName(for: url))

        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// A stable, per-file key for `NSWindow.setFrameAutosaveName`, so each
    /// file's window frame is independent of every other open window's.
    private static func frameAutosaveName(for url: URL) -> String {
        "document-window:\(url.path)"
    }

    private func setupContent() {
        let sidebarView = SidebarView(
            state: state,
            changeTracker: state.changeTracker,
            onSelectHeading: { [weak self] heading in
                self?.state.webCommands.send(.scrollToHeading(heading))
            },
            onSelectChange: { [weak self] changeIDs in
                self?.state.webCommands.send(.scrollToChanges(changeIDs))
            }
        )
        let sidebarHost = NSHostingController(rootView: sidebarView)

        let contentView = DocumentContentView(model: model, state: state, findState: state.find, changeTracker: state.changeTracker)
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
        // Every window-chrome bit that reflects an AppState preference —
        // appearance, the lighting/readable-column/changes toolbar buttons, and
        // the window title — refreshes from one sink. `objectWillChange` fires
        // before the value settles (willSet timing), so hop to the next run-loop
        // pass and re-read the live values in `refreshAppStateChrome`. Initial
        // appearance is applied synchronously in `init` (before content setup,
        // to avoid a flash); this sink only catches later changes.
        AppState.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAppStateChrome() }
            .store(in: &cancellables)

        state.$mode
            .dropFirst()
            .sink { [weak self] mode in
                guard let self else { return }
                self.updateModeButton(mode)
                self.updateZoomLabel(for: mode)
                self.updateCommentButton(for: mode)
                self.updateCommentsColumnButton(self.state.commentsColumnVisible,
                                                for: mode)
            }
            .store(in: &cancellables)

        // Enable the "Comment" toolbar button only while the rendered view holds
        // a commentable selection.
        state.commentableSelection
            .sink { [weak self] _ in self?.updateCommentButton() }
            .store(in: &cancellables)

        // Keep this window's Comments-column toolbar button in step with its
        // own visibility. (The View-menu label reads the key window's
        // visibility off `ActiveDocumentObserver`.)
        state.$commentsColumnVisible
            .sink { [weak self] visible in
                self?.updateCommentsColumnButton(visible)
            }
            .store(in: &cancellables)

        // Keep the Open In toolbar button's icon and click behavior in step with
        // the chosen default editor (which any window can change). `$configured`
        // publishes in willSet, so use the emitted value, not the still-stale
        // property.
        OpenInMenuModel.shared.$configured
            .sink { [weak self] configured in self?.updateOpenInItem(configured: configured) }
            .store(in: &cancellables)

        state.find.$isVisible
            .sink { [weak self] visible in
                self?.updateFindButton(visible)
            }
            .store(in: &cancellables)

        // The window title has two inputs: this window's `contentTitle` and the
        // `uiUseHeadingAsTitle` preference. The preference side rides the
        // `objectWillChange` sink above; this covers the per-window side (and,
        // via its replay through the hop, sets the initial title).
        state.$contentTitle
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshAppStateChrome() }
            .store(in: &cancellables)

        model.$hasBackgroundReload
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

    /// Apply the window chrome that reflects AppState preferences. Reads live
    /// values and every update is idempotent, so any change signal — the shared
    /// `objectWillChange`, or a `contentTitle` change for the title — can drive
    /// it. Must be called after the change has settled (see `observeState`).
    private func refreshAppStateChrome() {
        let appState = AppState.shared
        applyLighting(appState.lighting)
        updateLightingButton(appState.lighting)
        updateReadableColumnButton(appState.viewToggles.contains(.readableColumn))
        updateChangesButton(appState.changesEnabled)

        if appState.uiUseHeadingAsTitle, let title = state.contentTitle {
            window?.title = title
        } else {
            window?.title = fileURL.lastPathComponent
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

    /// Whether "Add Comment" applies to this window right now. Read by the
    /// toolbar button below and by the WebView context menu, which — unlike the
    /// Edit menu item — can't go through `ActiveDocumentObserver`: a
    /// control-click opens the menu without making the window key, so the
    /// active-document snapshot can belong to another window.
    ///
    /// `mode` defaults to this window's current one; the `$mode` sink passes
    /// the value it emitted, which `state.mode` doesn't hold yet (willSet).
    func canAddComment(for mode: Mode? = nil) -> Bool {
        ActiveDocumentSnapshot.canAddComment(
            mode: mode ?? state.mode,
            commentable: state.commentableSelection.value,
            editable: !fileURL.isBundleResource)
    }

    /// The "Comment" button adds a comment to the selection, so it is live only
    /// for a commentable selection in a writable Up-mode document.
    private func updateCommentButton(for mode: Mode? = nil) {
        commentButton?.isEnabled = canAddComment(for: mode)
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

    /// The Comments column is an Up-mode layout, so its button — like the View
    /// menu item — is live only in Up mode. See `updateCommentButton` on the
    /// `mode` parameter.
    private func updateCommentsColumnButton(_ visible: Bool, for mode: Mode? = nil) {
        let symbol = visible ? "bubble.left.and.text.bubble.right.fill" : "bubble.left.and.text.bubble.right"
        commentsColumnButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        commentsColumnButton?.toolTip = visible ? "Hide Comments" : "Show Comments"
        commentsColumnButton?.isEnabled = (mode ?? state.mode) == .up
    }

    private func updateToggleButton(_ button: NSButton?, on: Bool) {
        button?.state = on ? .on : .off
    }

    /// Reflects the chosen default editor on the Open In toolbar item. With a
    /// default set, the body shows that app's icon and launches it directly;
    /// with none, it shows a grid icon and a click opens the menu (no action).
    /// The chevron opens the menu in both states.
    private func updateOpenInItem(
        _ explicitItem: NSMenuToolbarItem? = nil,
        configured: RegisteredMarkdownHandler?
    ) {
        guard let item = explicitItem ?? openInItem else { return }
        if let configured {
            let icon = configured.icon
            icon.size = NSSize(width: 18, height: 18)
            item.image = icon
            item.target = self
            item.action = #selector(openInDefault(_:))
            item.toolTip = "Open in \(configured.displayName)"
        } else {
            item.image = NSImage(systemSymbolName: "square.grid.3x3.square.badge.ellipsis", accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: nil)
            item.target = nil
            item.action = nil
            item.toolTip = "Open In…"
        }
    }

    @objc func openInDefault(_ sender: Any?) {
        guard let configured = OpenInMenuModel.shared.configured else { return }
        OpenInMenuModel.shared.launch(with: configured)
    }

    private func updateZoomLabel(for mode: Mode? = nil) {
        let level = (mode ?? state.mode) == .down ? state.downModeZoomLevel : state.upModeZoomLevel
        let percent = Int(round(level * 100))
        zoomControl?.setLabel("\(percent)%", forSegment: 1)
        zoomControl?.setWidth(0, forSegment: 1) // auto-size
    }

    @objc func toggleReadableColumn(_ sender: Any?) {
        AppState.shared.toggle(.readableColumn)
    }

    /// Folds every foldable heading in the page, or unfolds them all. The
    /// page holds the folded set and reports the new one back over `mudFolds`,
    /// so these send and forget like any other page command.
    @objc func foldHeadings(_ sender: Any?) {
        state.webCommands.send(.foldAllHeadings)
    }

    @objc func unfoldHeadings(_ sender: Any?) {
        state.webCommands.send(.unfoldAllHeadings)
    }

    /// Reveals the Comments column (per-window state, so a later class-sync
    /// keeps it shown) and opens a compose box on the current selection.
    ///
    /// The one funnel for every entry point — the toolbar button, the Edit menu
    /// item, the keyboard shortcut, and the WebView context menu all send this
    /// selector.
    @objc func addComment(_ sender: Any?) {
        withRoomForComments { [weak self] in self?.beginComment() }
    }

    private func beginComment() {
        state.commentsColumnVisible = true
        state.webCommands.send(.addCommentFromSelection)
    }

    /// Opens the Comments column to one comment (a marker click in the page),
    /// making room the same way Show Comments does. The fallback names the
    /// comment too: the click asked for that one, so a window too narrow for
    /// the column lands on it in the bottom section rather than on the
    /// section's top.
    func revealComment(_ label: String) {
        withRoomForComments(fallingBackTo: label) { [weak self] in
            self?.state.commentsColumnVisible = true
            self?.state.webCommands.send(.revealComment(label: label))
        }
    }

    /// Runs `show` with the Comments column able to fit, widening the window
    /// first if it's too narrow (see `CommentColumnFit`). When the window can't
    /// be made wide enough, falls back to scrolling the bottom Comments section
    /// into view — below the column's breakpoint that section is what the page
    /// shows in the column's place, so the reader still lands on the comments.
    /// `label`, when given, scrolls to that comment within the section.
    ///
    /// Either way the per-window toggle ends up on: the section answers to it
    /// just as the column does (`mud-narrow.css`), so a fallback that only
    /// scrolled would scroll to something still hidden — and Hide Comments
    /// would then have nothing to turn off. The page reveals the section
    /// itself, the same way `openToComment` opens the column, so this doesn't
    /// depend on the class sync landing first.
    private func withRoomForComments(fallingBackTo label: String? = nil,
                                     _ show: @escaping () -> Void) {
        guard let fit = CommentColumnFit(window: window, splitVC: splitVC) else {
            show()
            return
        }
        fit.makeRoom(then: show) { [weak self] in
            guard let self else { return }
            self.state.commentsColumnVisible = true
            self.state.webCommands.send(.scrollToComments(label: label))
        }
    }

    /// Shows or hides the Comments column for this window only. Showing it
    /// makes room the same way Add Comment does; hiding it never resizes
    /// anything, and never puts the width back — the window is the user's once
    /// it has been widened.
    @objc func toggleCommentsColumn(_ sender: Any?) {
        guard !state.commentsColumnVisible else {
            state.commentsColumnVisible = false
            return
        }
        // The column is an Up-mode layout, and both entry points — the View
        // menu item and the toolbar button — disable themselves in Down mode.
        // Belt and braces, so nothing can widen a window for a column that
        // wouldn't be drawn.
        guard state.mode == .up else { return }
        withRoomForComments { [weak self] in
            self?.state.commentsColumnVisible = true
        }
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
        state.webCommands.send(.print)
    }

    @objc func openInBrowser(_ sender: Any?) {
        exporter()?.openInBrowser()
    }

    /// The Open In editor handoff (from `OpenInMenuModel`): markdown hands the
    /// file itself to the app; HTML exports first. `.auto` should be resolved
    /// to `.markdown` or `.html` upstream; treat it as markdown as a safe
    /// fallback.
    func openInEditor(with handler: RegisteredMarkdownHandler, format: EditorFormat) {
        switch format {
        case .markdown, .auto:
            NSWorkspace.shared.open(
                [fileURL],
                withApplicationAt: handler.appURL,
                configuration: NSWorkspace.OpenConfiguration())
        case .html:
            exporter()?.open(withApplicationAt: handler.appURL)
        }
    }

    /// The exporter for the current content under this window's current render
    /// configuration — nil while the error page is showing.
    private func exporter() -> DocumentExporter? {
        guard case .parsed(let parsed) = model.content else { return nil }
        return DocumentExporter(
            fileURL: fileURL, markdown: parsed.markdown, mode: state.mode,
            options: model.renderOptions,
            includeComments: AppState.shared.commentsIncludeInExport)
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
        if state.mode == .down {
            state.downModeZoomLevel = (state.downModeZoomLevel + delta)
                .clamped(to: 0.5...3.0)
        } else {
            state.upModeZoomLevel = (state.upModeZoomLevel + delta)
                .clamped(to: 0.5...3.0)
        }
        updateZoomLabel()
    }

    private func resetZoom() {
        if state.mode == .down {
            state.downModeZoomLevel = 1.0
        } else {
            state.upModeZoomLevel = 1.0
        }
        // Also clear any native pinch magnification stacked on top of CSS zoom.
        state.webCommands.send(.resetMagnification)
        updateZoomLabel()
    }

    @objc func reloadDocument(_ sender: Any?) {
        model.load(forced: true)
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
        // Menu state follows automatically: `ActiveDocumentObserver` watches
        // the same notification and re-attaches to this window's state.
        model.hasBackgroundReload = false
    }

    func windowWillClose(_ notification: Notification) {
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
            .openIn,
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
            let level = state.mode == .down ? state.downModeZoomLevel : state.upModeZoomLevel
            control.setLabel("\(Int(round(level * 100)))%", forSegment: 1)
            control.setWidth(0, forSegment: 1)
            control.target = self
            control.action = #selector(zoomAction(_:))
            if flag { zoomControl = control }
            item.view = control
            item.label = "Zoom"
            return item

        case .openIn:
            let menuItem = NSMenuToolbarItem(itemIdentifier: itemIdentifier)
            let menu = NSMenu()
            menu.delegate = OpenInMenuModel.shared
            menuItem.menu = menu
            menuItem.showsIndicator = true
            menuItem.label = "Open In…"
            if flag { openInItem = menuItem }
            updateOpenInItem(menuItem, configured: OpenInMenuModel.shared.configured)
            return menuItem

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
    static let openIn = NSToolbarItem.Identifier("openIn")
    static let settings = NSToolbarItem.Identifier("settings")
    static let toggleReadableColumn = NSToolbarItem.Identifier("toggleReadableColumn")
    static let addComment = NSToolbarItem.Identifier("addComment")
    static let toggleCommentsColumn = NSToolbarItem.Identifier("toggleCommentsColumn")
    static let toggleLighting = NSToolbarItem.Identifier("toggleLighting")
    static let toggleMode = NSToolbarItem.Identifier("toggleMode")
    static let toggleChanges = NSToolbarItem.Identifier("toggleChanges")
    static let toggleFind = NSToolbarItem.Identifier("find")
}
