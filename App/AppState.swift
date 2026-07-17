import Foundation
import Combine
import MudPreferences
import MudCore

class AppState: ObservableObject {
    static let shared = AppState()

    // `lighting`, `viewToggles`, `changesEnabled`, and `uiUseHeadingAsTitle`
    // keep `@Published`: an AppKit Combine sink in DocumentWindowController
    // subscribes to each one's `$` publisher (toolbar buttons, window title),
    // which `@Pref` can't vend. Every other preference is a live-read `@Pref`.
    @Published var lighting: Lighting {
        didSet { MudPreferences.shared.lighting = lighting }
    }
    @Pref(\.theme) var theme: Theme
    @Published var viewToggles: Set<ViewToggle> {
        didSet { MudPreferences.shared.viewToggles = viewToggles }
    }
    @Pref(\.commentColumnWidth) var commentColumnWidth: Double
    @Pref(\.sidebarEnabled) var sidebarEnabled: Bool
    @Published var changesEnabled: Bool {
        didSet { MudPreferences.shared.changesEnabled = changesEnabled }
    }
    @Pref(\.changesShowInlineDeletions) var changesShowInlineDeletions: Bool
    @Pref(\.quitOnClose) var quitOnClose: Bool
    @Pref(\.upModeAllowRemoteContent) var upModeAllowRemoteContent: Bool
    @Pref(\.markdownDocCAlertMode) var markdownDocCAlertMode: DocCAlertMode
    @Published var uiUseHeadingAsTitle: Bool {
        didSet { MudPreferences.shared.uiUseHeadingAsTitle = uiUseHeadingAsTitle }
    }
    @Pref(\.changesWordDiffThreshold) var changesWordDiffThreshold: Double
    @Pref(\.uiFloatingControlsPosition) var uiFloatingControlsPosition: FloatingControlsPosition
    @Pref(\.changesShowGitWaypoints) var changesShowGitWaypoints: Bool
    @Published var enabledExtensions: Set<String> {
        didSet { MudPreferences.shared.writeEnabledExtensions(enabledExtensions) }
    }
    @Pref(\.commentAuthor) var commentAuthor: String
    @Pref(\.commentReturnSaves) var commentReturnSaves: Bool
    @Pref(\.commentsIncludeInExport) var commentsIncludeInExport: Bool
    @Pref(\.commentsShowMarkers) var commentsShowMarkers: Bool

    private init() {
        // Move any preference still stored under its old dotted name to the
        // hyphenated name before anything reads or mirrors it. Dotted names
        // broke external-change (KVO) detection; see `migrateLegacyKeys`.
        MudPreferences.shared.migrateLegacyKeys()

        // Fan the current `defaults` values out to the app-group mirror so the
        // Quick Look extension sees a fresh snapshot of any `defaults write`
        // changes made while the app was not running.
        MudPreferences.shared.syncMirror()

        // Seed only the properties that keep a cached copy — the four
        // `@Published` exceptions and `enabledExtensions`. Every `@Pref`
        // reads the store live, so there is nothing to seed.
        let config = MudPreferences.shared
        self.lighting = config.lighting
        self.viewToggles = config.viewToggles
        self.changesEnabled = config.changesEnabled
        self.uiUseHeadingAsTitle = config.uiUseHeadingAsTitle
        self.enabledExtensions = config.readEnabledExtensions(
            defaultValue: Set(RenderExtension.registry.keys)
        )

        // Pick up `defaults write org.josephpearson.Mud …` made while the app
        // is running. The callback's `didSet` writes idempotently update the
        // last-known snapshot, so there's no feedback loop with the app's own
        // writes.
        MudPreferences.shared.startObservingExternalChanges { [weak self] key in
            self?.reloadPreference(key)
        }
    }

    /// React to an external change to a single preference. The four
    /// `@Published` properties re-read into their cached copy so their `$`
    /// publisher fires the AppKit sink; every `@Pref` property falls into
    /// `default`, where one `objectWillChange.send()` makes the views re-read
    /// the live value. Ignores per-window and `internal.*` keys.
    private func reloadPreference(_ key: MudPreferences.Keys) {
        let c = MudPreferences.shared
        switch key {
        // The four `@Published` props: assign so their `$` publisher fires.
        case .lighting:            self.lighting = c.lighting
        case .changesEnabled:      self.changesEnabled = c.changesEnabled
        case .uiUseHeadingAsTitle: self.uiUseHeadingAsTitle = c.uiUseHeadingAsTitle
        // Every ViewToggle-backed key reloads the whole `@Published` Set —
        // cheaper than duplicating the Key → ViewToggle lookup.
        case .changesAutoExpandGroups,
             .upModeShowCodeHeader,
             .downModeShowLineNumbers,
             .downModeWrapLines,
             .uiShowReadableColumn:
            self.viewToggles = c.viewToggles
        // enabledExtensions is still `@Published` until its own commit.
        case .enabledExtensions:
            self.enabledExtensions = c.readEnabledExtensions(
                defaultValue: Set(RenderExtension.registry.keys)
            )
        case .openInDefaultBundleID, .openInDefaultFormat:
            OpenInMenuModel.shared.refresh()
        // Zoom and the sidebar-pane selection are per-window (DocumentState),
        // not mirrored here; `internal.*` keys have no AppState representative.
        case .upModeZoomLevel, .downModeZoomLevel, .sidebarPane,
             .hasLaunched, .cliInstalled, .cliSymlinkPath:
            break
        // Every `@Pref` preference: one blanket invalidation; views re-read.
        default:
            objectWillChange.send()
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
