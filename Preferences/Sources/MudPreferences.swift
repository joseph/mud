import Foundation
import Security
import MudCore

/// Centralized read/write layer for every persisted user preference.
///
/// Production code uses `MudPreferences.shared`. `defaults` is the source of
/// truth — `UserDefaults.standard` for the app so that `defaults write
/// org.josephpearson.Mud …` from the command line Just Works — and `mirror` is
/// the app-group suite, which receives a fan-out copy of every write so the
/// Quick Look extension can read a stable snapshot. Tests construct their own
/// instance with hermetic per-test suites.
public struct MudPreferences: @unchecked Sendable {
    /// App-group suite name, resolved from the calling process's
    /// `com.apple.security.application-groups` entitlement. Xcode expands
    /// `$(TeamIdentifierPrefix)` in the entitlements file at signing time,
    /// so the runtime value is already Team-ID-prefixed — which macOS
    /// Sequoia+ requires for silent container access without a TCC prompt.
    /// The hardcoded fallback guards against `SecTask` failure (e.g. running
    /// unsigned in a test harness) and must match the entitlements file.
    public static let appGroupSuiteName: String = {
        guard
            let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.security.application-groups" as CFString,
                nil
            ),
            let groups = value as? [String],
            let first = groups.first
        else {
            return "XVL2AFNXH5.org.josephpearson.Mud"
        }
        return first
    }()

    let state: State

    var defaults: UserDefaults { state.defaults }
    var mirror: UserDefaults? { state.mirror }

    public init(defaults: UserDefaults, mirror: UserDefaults? = nil) {
        self.state = State(defaults: defaults, mirror: mirror)
    }

    /// Reference-typed storage so that the struct's `nonmutating` setters
    /// can update the last-known snapshot used for external-change detection.
    /// Single-threaded invariant: every mutation happens on the main queue
    /// (AppState setters, Darwin notification dispatched to `.main`). Tests
    /// use their own instance on the testing thread, no sharing.
    final class State: @unchecked Sendable {
        let defaults: UserDefaults
        let mirror: UserDefaults?

        /// Snapshot of every Mud-owned key as seen by `defaults` at the
        /// most recent checkpoint (observation start, in-app write, or
        /// external-change diff pass). Populated only while `isObserving`.
        var lastKnown: [Keys: NSObject?] = [:]
        var isObserving = false
        var onChange: ((Keys) -> Void)?

        /// Holds the NSObject subclass that receives KVO callbacks. Retained
        /// here for the process lifetime; see `registerKVOObservers`.
        var kvoBridge: KVOBridge?

        /// Coalesces KVO bursts: a single external write fires KVO for every
        /// registered key. `scheduleRefresh` guards the enqueue with this
        /// flag so only one main-queue block is in flight at a time.
        let pendingLock = NSLock()
        var refreshPending = false

        init(defaults: UserDefaults, mirror: UserDefaults?) {
            self.defaults = defaults
            self.mirror = mirror
        }
    }

    /// Production instance — reads and writes `.standard`, mirrors writes into
    /// the app-group suite for the Quick Look extension.
    public static let shared = MudPreferences(
        defaults: .standard,
        mirror: UserDefaults(suiteName: appGroupSuiteName)!
    )
}

extension MudPreferences {
    public enum Keys: String, CaseIterable {
        // Top-level — app-global selections
        case lighting                   = "lighting"
        case theme                      = "theme"
        case quitOnClose                = "quit-on-close"
        case enabledExtensions          = "enabled-extensions"

        // changes.* — diff display and change-tracking
        case changesEnabled             = "changes.enabled"
        case changesShowInlineDeletions = "changes.show-inline-deletions"
        case changesShowGitWaypoints    = "changes.show-git-waypoints"
        case changesAutoExpandGroups    = "changes.auto-expand-groups"
        case changesWordDiffThreshold   = "changes.word-diff-threshold"

        // up-mode.* — rendered-HTML view options
        case upModeZoomLevel            = "up-mode.zoom-level"
        case upModeAllowRemoteContent   = "up-mode.allow-remote-content"
        case upModeShowCodeHeader       = "up-mode.show-code-header"

        // down-mode.* — source view options
        case downModeZoomLevel          = "down-mode.zoom-level"
        case downModeShowLineNumbers    = "down-mode.show-line-numbers"
        case downModeWrapLines          = "down-mode.wrap-lines"

        // sidebar.* — sidebar state
        case sidebarEnabled             = "sidebar.enabled"
        case sidebarPane                = "sidebar.pane"

        // markdown.* — parser options
        case markdownDocCAlertMode      = "markdown.docc-alert-mode"

        // ui.* — UI chrome and cross-mode layout
        case uiUseHeadingAsTitle        = "ui.use-heading-as-title"
        case uiFloatingControlsPosition = "ui.floating-controls-position"
        case uiShowReadableColumn       = "ui.show-readable-column"

        // internal.* — app-owned bookkeeping
        case hasLaunched                = "internal.has-launched"
        case windowFrame                = "internal.window-frame"
        case cliInstalled               = "internal.cli-installed"
        case cliSymlinkPath             = "internal.cli-symlink-path"

        // open-in.* — external-editor handoff
        case openInDefaultBundleID         = "open-in.default-bundle-id"
        case openInDefaultFormat           = "open-in.default-format"

        // comment.* — comment authoring
        case commentAuthor                 = "comment-author"
        case commentReturnSaves            = "comment-return-saves"
    }
}

// MARK: - Generic read/write helpers

extension MudPreferences {
    /// Fan a write out to `defaults` (source of truth) and `mirror` (when
    /// present). Passing `nil` removes the key from both stores.
    ///
    /// Updating `lastKnown` before the fan-out means any self-triggered
    /// Darwin notification sees no diff for this key; see
    /// `startObservingExternalChanges`.
    func write(_ value: Any?, forKey key: Keys) {
        if state.isObserving {
            state.lastKnown[key] = value as? NSObject
        }
        defaults.set(value, forKey: key.rawValue)
        mirror?.set(value, forKey: key.rawValue)
    }

    /// Overload for string-backed enums — persists the rawValue.
    func write<T: RawRepresentable>(_ value: T, forKey key: Keys) where T.RawValue == String {
        write(value.rawValue, forKey: key)
    }

    /// Read a `UserDefaults`-compatible value (Bool, Double, Int, String, …),
    /// falling back to `d` when the key is absent or of the wrong type.
    func read<T>(_ key: Keys, default d: T) -> T {
        defaults.object(forKey: key.rawValue) as? T ?? d
    }

    /// Read a string-backed enum, falling back to `d`.
    func read<T: RawRepresentable>(_ key: Keys, default d: T) -> T where T.RawValue == String {
        defaults.string(forKey: key.rawValue).flatMap(T.init(rawValue:)) ?? d
    }
}

// MARK: - Preferences

extension MudPreferences {
    public var lighting: Lighting {
        get { read(.lighting, default: .auto) }
        nonmutating set { write(newValue, forKey: .lighting) }
    }

    public var theme: Theme {
        get { read(.theme, default: .earthy) }
        nonmutating set { write(newValue, forKey: .theme) }
    }

    public var upModeZoomLevel: Double {
        get { read(.upModeZoomLevel, default: 1.0) }
        nonmutating set { write(newValue, forKey: .upModeZoomLevel) }
    }

    public var downModeZoomLevel: Double {
        get { read(.downModeZoomLevel, default: 1.0) }
        nonmutating set { write(newValue, forKey: .downModeZoomLevel) }
    }

    public var sidebarEnabled: Bool {
        get { read(.sidebarEnabled, default: false) }
        nonmutating set { write(newValue, forKey: .sidebarEnabled) }
    }

    public var sidebarPane: SidebarPane {
        get { read(.sidebarPane, default: .outline) }
        nonmutating set { write(newValue, forKey: .sidebarPane) }
    }

    public var changesEnabled: Bool {
        get { read(.changesEnabled, default: false) }
        nonmutating set { write(newValue, forKey: .changesEnabled) }
    }

    public var changesShowInlineDeletions: Bool {
        get { read(.changesShowInlineDeletions, default: false) }
        nonmutating set { write(newValue, forKey: .changesShowInlineDeletions) }
    }

    public var quitOnClose: Bool {
        get { read(.quitOnClose, default: true) }
        nonmutating set { write(newValue, forKey: .quitOnClose) }
    }

    public var upModeAllowRemoteContent: Bool {
        get { read(.upModeAllowRemoteContent, default: true) }
        nonmutating set { write(newValue, forKey: .upModeAllowRemoteContent) }
    }

    public var markdownDocCAlertMode: DocCAlertMode {
        get { read(.markdownDocCAlertMode, default: .extended) }
        nonmutating set { write(newValue, forKey: .markdownDocCAlertMode) }
    }

    public var uiUseHeadingAsTitle: Bool {
        get { read(.uiUseHeadingAsTitle, default: true) }
        nonmutating set { write(newValue, forKey: .uiUseHeadingAsTitle) }
    }

    public var changesWordDiffThreshold: Double {
        get { read(.changesWordDiffThreshold, default: 0.25) }
        nonmutating set { write(newValue, forKey: .changesWordDiffThreshold) }
    }

    public var uiFloatingControlsPosition: FloatingControlsPosition {
        get { read(.uiFloatingControlsPosition, default: .bottomCenter) }
        nonmutating set { write(newValue, forKey: .uiFloatingControlsPosition) }
    }

    public var changesShowGitWaypoints: Bool {
        get { read(.changesShowGitWaypoints, default: false) }
        nonmutating set { write(newValue, forKey: .changesShowGitWaypoints) }
    }

    public var hasLaunched: Bool {
        get { read(.hasLaunched, default: false) }
        nonmutating set { write(newValue, forKey: .hasLaunched) }
    }

    public var windowFrame: String? {
        get { defaults.string(forKey: Keys.windowFrame.rawValue) }
        nonmutating set { write(newValue, forKey: .windowFrame) }
    }

    public var cliInstalled: Bool {
        get { read(.cliInstalled, default: false) }
        nonmutating set { write(newValue, forKey: .cliInstalled) }
    }

    public var cliSymlinkPath: String? {
        get { defaults.string(forKey: Keys.cliSymlinkPath.rawValue) }
        nonmutating set { write(newValue, forKey: .cliSymlinkPath) }
    }

    public var openInDefaultBundleID: String? {
        get { defaults.string(forKey: Keys.openInDefaultBundleID.rawValue) }
        nonmutating set { write(newValue, forKey: .openInDefaultBundleID) }
    }

    public var openInDefaultFormat: EditorFormat {
        get { read(.openInDefaultFormat, default: .auto) }
        nonmutating set { write(newValue, forKey: .openInDefaultFormat) }
    }

    /// Author name written into new comment messages' `💬 <author> (…)` header.
    /// An empty or unset value resolves to the system full name, so a fresh
    /// install attributes comments without any configuration.
    public var commentAuthor: String {
        get {
            let stored = defaults.string(forKey: Keys.commentAuthor.rawValue)
            if let stored, !stored.isEmpty { return stored }
            return NSFullUserName()
        }
        nonmutating set { write(newValue, forKey: .commentAuthor) }
    }

    /// When on, pressing Return in a comment compose box saves the message (as
    /// if Done were clicked) and Shift-Return inserts a line break. When off,
    /// Return inserts a line break and ⌘Return saves. Read live by
    /// `mud-comments-edit.js` via the `comment-return-saves` html class.
    public var commentReturnSaves: Bool {
        get { read(.commentReturnSaves, default: false) }
        nonmutating set { write(newValue, forKey: .commentReturnSaves) }
    }
}

// MARK: - Parameterized accessors
//
// These stay as methods because their shape doesn't fit a bare property:
// `enabledExtensions` takes a caller-supplied default, and `ViewToggle`
// accessors are parameterized by the toggle itself.

extension MudPreferences {
    /// Extensions. The default is supplied by the caller because
    /// MudPreferences does not own the registry of available extensions.
    public func readEnabledExtensions(defaultValue: Set<String>) -> Set<String> {
        guard let stored = defaults.array(forKey: Keys.enabledExtensions.rawValue)
                as? [String] else {
            return defaultValue
        }
        return Set(stored).intersection(defaultValue)
    }
    public func writeEnabledExtensions(_ value: Set<String>) {
        write(Array(value), forKey: .enabledExtensions)
    }

    public func readViewToggle(_ toggle: ViewToggle) -> Bool {
        read(toggle.key, default: toggle.defaultValue)
    }
    public func writeViewToggle(_ toggle: ViewToggle, enabled: Bool) {
        write(enabled, forKey: toggle.key)
    }

    public var viewToggles: Set<ViewToggle> {
        get { Set(ViewToggle.allCases.filter { readViewToggle($0) }) }
        nonmutating set {
            for toggle in ViewToggle.allCases {
                writeViewToggle(toggle, enabled: newValue.contains(toggle))
            }
        }
    }
}

// MARK: - Reset

extension MudPreferences {
    /// Remove every Mud preference from this instance's `defaults` and, when
    /// present, from `mirror`. Used by the Debugging settings pane in debug
    /// builds. Clearing the mirror synchronously matters because the Quick
    /// Look extension reads it on the next preview request.
    public func reset() {
        for key in Keys.allCases {
            write(nil, forKey: key)
        }
    }
}
