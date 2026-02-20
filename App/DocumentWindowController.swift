import SwiftUI
import Combine

// MARK: - Document Window Controller

class DocumentWindowController: NSWindowController {
    let fileURL: URL
    let state = DocumentState()
    var onClose: ((DocumentWindowController) -> Void)?

    private var lightingButton: NSButton?
    private var modeButton: NSButton?
    private var readableColumnButton: NSButton?
    // private var lineNumbersButton: NSButton?
    // private var wordWrapButton: NSButton?
    private var zoomControl: NSSegmentedControl?

    private var splitVC: NSSplitViewController?
    private var cancellables = Set<AnyCancellable>()

    private static let frameKey = "Mud-WindowFrame"

    init(url: URL) {
        self.fileURL = url

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = url.lastPathComponent
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: 500, height: 400)

        super.init(window: window)
        shouldCascadeWindows = false

        // Apply lighting BEFORE content setup to prevent flash
        applyLighting(AppState.shared.lighting)
        setupContent()
        setupToolbar()
        observeState()

        // Restore saved window frame AFTER content and toolbar setup,
        // so that layout changes don't override the saved frame.
        if let frameString = UserDefaults.standard.string(forKey: Self.frameKey) {
            window.setFrame(NSRectFromString(frameString), display: false)
        } else {
            window.center()
        }

        window.delegate = self
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupContent() {
        let sidebarView = OutlineSidebarView(state: state) { [weak self] heading in
            self?.state.scrollTarget = ScrollTarget(id: UUID(), heading: heading)
        }
        let sidebarHost = NSHostingController(rootView: sidebarView)

        let contentView = DocumentContentView(fileURL: fileURL, state: state, findState: state.find)
        let contentHost = NSHostingController(rootView: contentView)

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHost)
        sidebarItem.canCollapse = true
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 320

        let contentItem = NSSplitViewItem(viewController: contentHost)

        let split = NSSplitViewController()
        split.addSplitViewItem(sidebarItem)
        split.addSplitViewItem(contentItem)
        splitVC = split

        window?.contentViewController = split

        // Collapse sidebar if persisted state says hidden
        if !AppState.shared.sidebarVisible {
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
                AppState.shared.saveLighting(lighting)
            }
            .store(in: &cancellables)

        AppState.shared.$theme
            .dropFirst()
            .sink { theme in
                AppState.shared.saveTheme(theme)
            }
            .store(in: &cancellables)

        state.$mode
            .dropFirst()
            .sink { [weak self] mode in
                self?.updateModeButton(mode)
                self?.updateZoomLabel(for: mode)
                if self?.window?.isKeyWindow == true {
                    deferMutation {
                        AppState.shared.modeInActiveTab = mode
                    }
                }
            }
            .store(in: &cancellables)

        AppState.shared.$viewToggles
            .sink { [weak self] toggles in
                self?.updateReadableColumnButton(toggles.contains(.readableColumn))
                // self?.updateToggleButton(self?.lineNumbersButton, on: toggles.contains(.lineNumbers))
                // self?.updateToggleButton(self?.wordWrapButton, on: toggles.contains(.wordWrap))
            }
            .store(in: &cancellables)

        // Track sidebar collapse state for persistence
        if let sidebarItem = splitVC?.splitViewItems.first {
            sidebarItem.publisher(for: \.isCollapsed)
                .dropFirst()
                .sink { collapsed in
                    AppState.shared.sidebarVisible = !collapsed
                    AppState.shared.saveSidebarVisible()
                }
                .store(in: &cancellables)
        }
    }

    private func applyLighting(_ lighting: Lighting) {
        window?.appearance = lighting.appearance
    }

    private func updateLightingButton(_ lighting: Lighting) {
        lightingButton?.image = NSImage(systemSymbolName: lighting.isDark() ? "moon" : "sun.max", accessibilityDescription: nil)
    }

    private func updateModeButton(_ mode: Mode) {
        let symbol = mode == .down ? "arrowshape.down.circle" : "arrowshape.up.circle"
        modeButton?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    private func updateReadableColumnButton(_ on: Bool) {
        let symbol = on ? "rectangle.compress.vertical" : "rectangle.expand.vertical"
        readableColumnButton?.image = rotatedSymbol(symbol)
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

    @objc func toggleLineNumbers(_ sender: Any?) {
        AppState.shared.toggle(.lineNumbers)
    }

    @objc func toggleWordWrap(_ sender: Any?) {
        AppState.shared.toggle(.wordWrap)
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

    private func adjustZoom(by delta: Double) {
        let app = AppState.shared
        if state.mode == .down {
            app.downModeZoomLevel = (app.downModeZoomLevel + delta)
                .clamped(to: 0.5...3.0)
        } else {
            app.upModeZoomLevel = (app.upModeZoomLevel + delta)
                .clamped(to: 0.5...3.0)
        }
        app.saveZoomLevels()
        updateZoomLabel()
    }

    private func resetZoom() {
        let app = AppState.shared
        if state.mode == .down {
            app.downModeZoomLevel = 1.0
        } else {
            app.upModeZoomLevel = 1.0
        }
        app.saveZoomLevels()
        updateZoomLabel()
    }

    @objc func reloadDocument(_ sender: Any?) {
        state.reloadID = UUID()
    }

    @objc func performFindAction(_ sender: Any?) {
        state.find.show()
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

    private func rotatedSymbol(_ name: String) -> NSImage? {
        guard let original = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let s = original.size
        let rotated = NSImage(size: NSSize(width: s.height, height: s.width), flipped: false) { rect in
            let t = NSAffineTransform()
            t.translateX(by: rect.width / 2, yBy: rect.height / 2)
            t.rotate(byDegrees: 90)
            t.translateX(by: -s.width / 2, yBy: -s.height / 2)
            t.concat()
            original.draw(in: NSRect(origin: .zero, size: s))
            return true
        }
        rotated.isTemplate = true
        return rotated
    }
}

// MARK: - NSWindowDelegate

extension DocumentWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_ notification: Notification) {
        AppState.shared.modeInActiveTab = state.mode
    }

    func windowDidResignMain(_ notification: Notification) {
        state.find.close()
    }

    func windowWillClose(_ notification: Notification) {
        // Save window frame for next launch
        if let frame = window?.frame {
            UserDefaults.standard.set(NSStringFromRect(frame), forKey: Self.frameKey)
        }
        onClose?(self)
    }
}

// MARK: - NSToolbarDelegate

extension DocumentWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .toggleMode]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .space, .toggleLighting, .toggleMode,
         .toggleReadableColumn, /* .toggleLineNumbers, .toggleWordWrap, */ .zoom]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .toggleLighting:
            let button = makeToolbarButton(symbolName: AppState.shared.lighting.isDark() ? "moon" : "sun.max", action: #selector(toggleLighting(_:)))
            lightingButton = button
            item.view = button
            item.label = "Lighting"
            return item

        case .toggleMode:
            let button = makeToolbarButton(symbolName: "arrowshape.up.circle", action: #selector(toggleMode(_:)))
            modeButton = button
            item.view = button
            item.label = "Mode"
            return item

        case .toggleReadableColumn:
            let button = makeToolbarButton(symbolName: "rectangle.compress.vertical", action: #selector(toggleReadableColumn(_:)))
            readableColumnButton = button
            updateReadableColumnButton(AppState.shared.viewToggles.contains(.readableColumn))
            item.view = button
            item.label = "Column"
            return item

        // case .toggleLineNumbers:
        //     let button = makeToolbarButton(symbolName: "list.number", action: #selector(toggleLineNumbers(_:)), toggle: true)
        //     lineNumbersButton = button
        //     updateToggleButton(button, on: AppState.shared.viewToggles.contains(.lineNumbers))
        //     item.view = button
        //     item.label = "Numbers"
        //     return item

        // case .toggleWordWrap:
        //     let button = makeToolbarButton(symbolName: "text.word.spacing", action: #selector(toggleWordWrap(_:)), toggle: true)
        //     wordWrapButton = button
        //     updateToggleButton(button, on: AppState.shared.viewToggles.contains(.wordWrap))
        //     item.view = button
        //     item.label = "Wrap"
        //     return item

        case .zoom:
            let control = NSSegmentedControl()
            control.segmentCount = 3
            control.trackingMode = .momentary
            control.setImage(NSImage(systemSymbolName: "minus.magnifyingglass", accessibilityDescription: "Zoom Out"), forSegment: 0)
            control.setImage(NSImage(systemSymbolName: "plus.magnifyingglass", accessibilityDescription: "Zoom In"), forSegment: 2)
            control.setWidth(30, forSegment: 0)
            control.setWidth(30, forSegment: 2)
            let level = state.mode == .down ? AppState.shared.downModeZoomLevel : AppState.shared.upModeZoomLevel
            control.setLabel("\(Int(round(level * 100)))%", forSegment: 1)
            control.setWidth(0, forSegment: 1)
            control.target = self
            control.action = #selector(zoomAction(_:))
            zoomControl = control
            item.view = control
            item.label = "Zoom"
            return item

        default:
            return nil
        }
    }
}

extension NSToolbarItem.Identifier {
    static let toggleLighting = NSToolbarItem.Identifier("toggleLighting")
    static let toggleMode = NSToolbarItem.Identifier("toggleMode")
    static let toggleReadableColumn = NSToolbarItem.Identifier("toggleReadableColumn")
    static let toggleLineNumbers = NSToolbarItem.Identifier("toggleLineNumbers")
    static let toggleWordWrap = NSToolbarItem.Identifier("toggleWordWrap")
    static let zoom = NSToolbarItem.Identifier("zoom")
}
