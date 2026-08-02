import Foundation
import Combine
import MudPreferences
import MudCore

class AppState: ObservableObject {
    static let shared = AppState()

    // Every preference is a live-read `@Pref`: one declaration each, no cached
    // copy on AppState. DocumentWindowController's window chrome (lighting,
    // toolbar buttons, window title) refreshes from `objectWillChange` rather
    // than a per-property `$` publisher, so nothing here needs `@Published`.
    @Pref(\.lighting) var lighting: Lighting
    @Pref(\.theme) var theme: Theme
    @Pref(\.viewToggles) var viewToggles: Set<ViewToggle>
    @Pref(\.commentColumnWidth) var commentColumnWidth: Double
    @Pref(\.sidebarEnabled) var sidebarEnabled: Bool
    @Pref(\.changesEnabled) var changesEnabled: Bool
    @Pref(\.changesShowInlineDeletions) var changesShowInlineDeletions: Bool
    @Pref(\.quitOnClose) var quitOnClose: Bool
    @Pref(\.upModeAllowRemoteContent) var upModeAllowRemoteContent: Bool
    @Pref(\.markdownDocCAlertMode) var markdownDocCAlertMode: DocCAlertMode
    @Pref(\.uiUseHeadingAsTitle) var uiUseHeadingAsTitle: Bool
    @Pref(\.changesWordDiffThreshold) var changesWordDiffThreshold: Double
    @Pref(\.uiFloatingControlsPosition) var uiFloatingControlsPosition: FloatingControlsPosition
    @Pref(\.changesShowGitWaypoints) var changesShowGitWaypoints: Bool
    // `enabledExtensions` is the one real special case: its default is a runtime
    // value the store doesn't own (the RenderExtension registry), so it uses the
    // closure escape hatch rather than a plain key path.
    @Pref(
        get: {
            MudPreferences.shared.readEnabledExtensions(
                defaultValue: Set(RenderExtension.registry.keys)
            )
        },
        set: { MudPreferences.shared.writeEnabledExtensions($0) }
    ) var enabledExtensions: Set<String>
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

        // Nothing to seed: every preference is a live-read `@Pref`, so each read
        // goes straight to the store.

        // Pick up `defaults write org.josephpearson.Mud …` made while the app
        // is running. The observer's last-known-value guard blocks the echo of
        // the app's own writes, so there's no feedback loop.
        MudPreferences.shared.startObservingExternalChanges { [weak self] key in
            self?.reloadPreference(key)
        }
    }

    /// React to an external change to a single preference. Every `@Pref`
    /// property falls into `default`, where one `objectWillChange.send()` makes
    /// the views re-read the live value. The Open In keys drive a different
    /// `ObservableObject`; per-window and `internal.*` keys have no AppState
    /// representative and are ignored.
    private func reloadPreference(_ key: MudPreferences.Keys) {
        switch key {
        case .openInDefaultBundleID, .openInDefaultFormat:
            OpenInMenuModel.shared.refresh()
        // Zoom and the sidebar-pane selection are per-window (DocumentState),
        // not mirrored here; `internal.*` keys have no AppState representative.
        case .upModeZoomLevel, .downModeZoomLevel, .sidebarPane,
             .hasLaunched, .cliInstalled, .cliSymlinkPath, .cliInstalledAt:
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
