import Foundation
import Combine
import MudPreferences
import MudCore

class AppState: ObservableObject {
    static let shared = AppState()
    @Published var modeInActiveTab: Mode = .up
    /// Transient (not persisted) mirror of the key window's state, for app-level
    /// menu gating — updated on key-window change like `modeInActiveTab`.
    @Published var activeDocumentEditable: Bool = false
    /// Transient mirror of whether the key window can add a comment right now
    /// (Up mode, writable document, commentable selection), gating the "Add
    /// Comment" menu item. Updated on key-window change and on selection change.
    @Published var canAddComment: Bool = false
    /// Transient mirror of the key window's Comments column visibility, for the
    /// "Show/Hide Comments" menu item's label. Column visibility itself is
    /// per-window (`DocumentState.commentsColumnVisible`) and not persisted.
    @Published var activeCommentsColumnVisible: Bool = false
    @Published var lighting: Lighting {
        didSet { MudPreferences.shared.lighting = lighting }
    }
    @Published var theme: Theme {
        didSet { MudPreferences.shared.theme = theme }
    }
    @Published var viewToggles: Set<ViewToggle> {
        didSet { MudPreferences.shared.viewToggles = viewToggles }
    }
    @Published var upModeZoomLevel: Double {
        didSet { MudPreferences.shared.upModeZoomLevel = upModeZoomLevel }
    }
    @Published var downModeZoomLevel: Double {
        didSet { MudPreferences.shared.downModeZoomLevel = downModeZoomLevel }
    }
    @Published var sidebarEnabled: Bool {
        didSet { MudPreferences.shared.sidebarEnabled = sidebarEnabled }
    }
    @Published var sidebarPane: SidebarPane {
        didSet { MudPreferences.shared.sidebarPane = sidebarPane }
    }
    @Published var changesEnabled: Bool {
        didSet { MudPreferences.shared.changesEnabled = changesEnabled }
    }
    @Published var changesShowInlineDeletions: Bool {
        didSet { MudPreferences.shared.changesShowInlineDeletions = changesShowInlineDeletions }
    }
    @Published var quitOnClose: Bool {
        didSet { MudPreferences.shared.quitOnClose = quitOnClose }
    }
    @Published var upModeAllowRemoteContent: Bool {
        didSet { MudPreferences.shared.upModeAllowRemoteContent = upModeAllowRemoteContent }
    }
    @Published var markdownDocCAlertMode: DocCAlertMode {
        didSet { MudPreferences.shared.markdownDocCAlertMode = markdownDocCAlertMode }
    }
    @Published var uiUseHeadingAsTitle: Bool {
        didSet { MudPreferences.shared.uiUseHeadingAsTitle = uiUseHeadingAsTitle }
    }
    @Published var changesWordDiffThreshold: Double {
        didSet { MudPreferences.shared.changesWordDiffThreshold = changesWordDiffThreshold }
    }
    @Published var uiFloatingControlsPosition: FloatingControlsPosition {
        didSet { MudPreferences.shared.uiFloatingControlsPosition = uiFloatingControlsPosition }
    }
    @Published var changesShowGitWaypoints: Bool {
        didSet { MudPreferences.shared.changesShowGitWaypoints = changesShowGitWaypoints }
    }
    @Published var enabledExtensions: Set<String> {
        didSet { MudPreferences.shared.writeEnabledExtensions(enabledExtensions) }
    }
    @Published var commentAuthor: String {
        didSet { MudPreferences.shared.commentAuthor = commentAuthor }
    }

    private init() {
        // Fan the current `defaults` values out to the app-group mirror so the
        // Quick Look extension sees a fresh snapshot of any `defaults write`
        // changes made while the app was not running.
        MudPreferences.shared.syncMirror()

        let config = MudPreferences.shared
        self.lighting = config.lighting
        self.theme = config.theme
        self.viewToggles = config.viewToggles
        self.upModeZoomLevel = config.upModeZoomLevel
        self.downModeZoomLevel = config.downModeZoomLevel
        self.sidebarEnabled = config.sidebarEnabled
        self.sidebarPane = config.sidebarPane
        self.changesEnabled = config.changesEnabled
        self.changesShowInlineDeletions = config.changesShowInlineDeletions
        self.quitOnClose = config.quitOnClose
        self.upModeAllowRemoteContent = config.upModeAllowRemoteContent
        self.markdownDocCAlertMode = config.markdownDocCAlertMode
        self.uiUseHeadingAsTitle = config.uiUseHeadingAsTitle
        self.changesWordDiffThreshold = config.changesWordDiffThreshold
        self.uiFloatingControlsPosition = config.uiFloatingControlsPosition
        self.changesShowGitWaypoints = config.changesShowGitWaypoints
        self.enabledExtensions = config.readEnabledExtensions(
            defaultValue: Set(RenderExtension.registry.keys)
        )
        self.commentAuthor = config.commentAuthor

        // Pick up `defaults write org.josephpearson.Mud …` made while the app
        // is running. The callback's `didSet` writes idempotently update the
        // last-known snapshot, so there's no feedback loop with the app's own
        // writes.
        MudPreferences.shared.startObservingExternalChanges { [weak self] key in
            self?.reloadPreference(key)
        }
    }

    /// Re-read a single preference from `MudPreferences.shared` into the
    /// matching `@Published` property. Called from the external-change
    /// observer; ignores internal.* keys that have no AppState representative.
    private func reloadPreference(_ key: MudPreferences.Keys) {
        let c = MudPreferences.shared
        switch key {
        case .lighting:                   self.lighting = c.lighting
        case .theme:                      self.theme = c.theme
        case .quitOnClose:                self.quitOnClose = c.quitOnClose
        case .enabledExtensions:
            self.enabledExtensions = c.readEnabledExtensions(
                defaultValue: Set(RenderExtension.registry.keys)
            )
        case .changesEnabled:             self.changesEnabled = c.changesEnabled
        case .changesShowInlineDeletions: self.changesShowInlineDeletions = c.changesShowInlineDeletions
        case .changesShowGitWaypoints:    self.changesShowGitWaypoints = c.changesShowGitWaypoints
        case .changesWordDiffThreshold:   self.changesWordDiffThreshold = c.changesWordDiffThreshold
        case .upModeZoomLevel:            self.upModeZoomLevel = c.upModeZoomLevel
        case .upModeAllowRemoteContent:   self.upModeAllowRemoteContent = c.upModeAllowRemoteContent
        case .downModeZoomLevel:          self.downModeZoomLevel = c.downModeZoomLevel
        case .sidebarEnabled:             self.sidebarEnabled = c.sidebarEnabled
        case .sidebarPane:                self.sidebarPane = c.sidebarPane
        case .markdownDocCAlertMode:      self.markdownDocCAlertMode = c.markdownDocCAlertMode
        case .uiUseHeadingAsTitle:        self.uiUseHeadingAsTitle = c.uiUseHeadingAsTitle
        case .uiFloatingControlsPosition: self.uiFloatingControlsPosition = c.uiFloatingControlsPosition
        case .commentAuthor:              self.commentAuthor = c.commentAuthor
        case .openInDefaultBundleID, .openInDefaultFormat:
            OpenInMenuModel.shared.refresh()
        // Every ViewToggle-backed key reloads the whole set — cheaper than
        // duplicating the Key → ViewToggle lookup, and `viewToggles` is a
        // small Set<ViewToggle>.
        case .changesAutoExpandGroups,
             .upModeShowCodeHeader,
             .downModeShowLineNumbers,
             .downModeWrapLines,
             .uiShowReadableColumn:
            self.viewToggles = c.viewToggles
        // internal.* — not exposed on AppState; mirror already updated.
        case .hasLaunched, .windowFrame, .cliInstalled, .cliSymlinkPath:
            break
        }
    }

    func toggle(_ option: ViewToggle) {
        if viewToggles.contains(option) {
            viewToggles.remove(option)
        } else {
            viewToggles.insert(option)
        }
    }
}
