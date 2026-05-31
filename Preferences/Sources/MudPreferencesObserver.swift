import Foundation

// MARK: - Startup mirror sync

extension MudPreferences {
    /// Copy every `defaults` value into `mirror`. Picks up any `defaults
    /// write` changes the user made while the app was not running, and
    /// removes mirror keys whose source value has since been cleared. No-op
    /// when the instance has no mirror.
    public func syncMirror() {
        guard let mirror else { return }
        for key in Keys.allCases {
            let value = defaults.object(forKey: key.rawValue)
            mirror.set(value, forKey: key.rawValue)
        }
    }
}

// MARK: - External change observation

extension MudPreferences {
    /// Start observing external changes to `defaults` (e.g. `defaults write
    /// org.josephpearson.Mud …` run while the app is live).
    ///
    /// For each externally-changed key, the observer:
    ///
    /// - Updates `mirror` so the Quick Look extension's next render sees the
    ///   new value.
    /// - Fires `onChange` on the main queue so AppState can refresh the
    ///   matching `@Published` property.
    ///
    /// Self-triggered notifications (the app's own writes) are filtered by
    /// a last-known snapshot that `write(_:forKey:)` keeps in sync. The
    /// subscription lives for the process lifetime; idempotent on repeat
    /// calls (later calls replace `onChange`).
    ///
    /// Not called by the Quick Look extension — it re-reads the snapshot on
    /// every preview request.
    public func startObservingExternalChanges(
        onChange: @escaping (Keys) -> Void
    ) {
        if state.isObserving {
            state.onChange = onChange
            return
        }

        for key in Keys.allCases {
            state.lastKnown[key] = defaults.object(forKey: key.rawValue) as? NSObject
        }
        state.onChange = onChange
        state.isObserving = true

        // cfprefsd does not post a public Darwin notification for app-specific
        // domain changes — it signals subscribers over private XPC, which
        // Foundation surfaces as per-key KVO on the same NSUserDefaults
        // instance. Hermetic test suites (defaults !== .standard) skip the
        // KVO registration and drive the diff pass directly via
        // `state.refresh()`.
        if defaults === UserDefaults.standard {
            state.registerKVOObservers()
        }
    }
}

// MARK: - Diff & coalescing (on State)

extension MudPreferences.State {
    /// Diff every Mud-owned key against `lastKnown`, fan deltas into
    /// `mirror`, and fire `onChange` once per actually-changed key. Called
    /// from `scheduleRefresh` (after cfprefsd invalidation) and from tests.
    func refresh() {
        guard isObserving else { return }

        var changes: [MudPreferences.Keys] = []
        for key in MudPreferences.Keys.allCases {
            let current = defaults.object(forKey: key.rawValue) as? NSObject
            let previous = lastKnown[key] ?? nil
            if !nsEqual(current, previous) {
                lastKnown[key] = current
                mirror?.set(current, forKey: key.rawValue)
                changes.append(key)
            }
        }

        guard let onChange else { return }
        for key in changes {
            onChange(key)
        }
    }

    /// Coalesce KVO bursts into a single main-queue refresh. cfprefsd
    /// invalidates the whole domain at once, so registering 25 observers
    /// means 25 callbacks per external write — of which only one needs to
    /// run the diff.
    func scheduleRefresh() {
        pendingLock.lock()
        if refreshPending {
            pendingLock.unlock()
            return
        }
        refreshPending = true
        pendingLock.unlock()

        DispatchQueue.main.async { [self] in
            // Clear before refresh so any KVO burst during the diff — e.g.
            // our own writes fanning out from `onChange` — can coalesce into
            // exactly one follow-up refresh pass.
            pendingLock.lock()
            refreshPending = false
            pendingLock.unlock()
            refresh()
        }
    }

    func registerKVOObservers() {
        let bridge = KVOBridge(state: self)
        self.kvoBridge = bridge
        for key in MudPreferences.Keys.allCases {
            defaults.addObserver(bridge, forKeyPath: key.rawValue, options: [.new], context: nil)
        }
    }
}

// MARK: - KVO bridge

/// NSObject subclass required to receive KVO callbacks. Retained by its
/// owning `MudPreferences.State` for the process lifetime; no explicit
/// `removeObserver` is needed.
final class KVOBridge: NSObject {
    let state: MudPreferences.State

    init(state: MudPreferences.State) {
        self.state = state
        super.init()
    }

    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        state.scheduleRefresh()
    }
}

// MARK: - Equality

/// NSObject-aware optional equality. UserDefaults values are always Foundation
/// class clusters — `NSNumber`, `NSString`, `NSArray`, `NSDictionary`, `NSData`,
/// `NSDate` — all of which implement `isEqual(_:)` with value semantics.
private func nsEqual(_ a: NSObject?, _ b: NSObject?) -> Bool {
    switch (a, b) {
    case (nil, nil):         return true
    case let (x?, y?):       return x.isEqual(y)
    default:                 return false
    }
}
