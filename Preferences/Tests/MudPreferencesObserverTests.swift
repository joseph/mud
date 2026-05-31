import Foundation
import Testing
@testable import MudPreferences

@Suite("MudPreferences observer")
struct MudPreferencesObserverTests {
    // MARK: - Diff surfaces external writes

    @Test func externalWriteSurfacesAsCallback() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        let log = tc.startObserving()

        tc.config.defaults.set("blues", forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.state.refresh()

        #expect(log.keys == [.theme])
    }

    @Test func externalWriteUpdatesMirror() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        _ = tc.startObserving()

        tc.config.defaults.set("riot", forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.state.refresh()

        #expect(
            tc.config.mirror!.string(forKey: MudPreferences.Keys.theme.rawValue)
                == "riot"
        )
    }

    @Test func externalKeyRemovalSurfacesAsCallback() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        // Seed a value so its absence is observable.
        tc.config.theme = .blues

        let log = tc.startObserving()

        tc.config.defaults.removeObject(forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.state.refresh()

        #expect(log.keys == [.theme])
    }

    @Test func externalKeyRemovalClearsMirror() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.theme = .blues
        _ = tc.startObserving()

        tc.config.defaults.removeObject(forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.state.refresh()

        #expect(
            tc.config.mirror!.object(forKey: MudPreferences.Keys.theme.rawValue) == nil
        )
    }

    // MARK: - Self-filter

    @Test func inAppWriteDoesNotFireCallback() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        let log = tc.startObserving()

        tc.config.theme = .blues
        tc.config.state.refresh()

        #expect(log.keys.isEmpty)
    }

    @Test func inAppWriteOfEnabledExtensionsDoesNotFireCallback() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        let log = tc.startObserving()

        tc.config.writeEnabledExtensions(["alpha", "beta"])
        tc.config.state.refresh()

        #expect(log.keys.isEmpty)
    }

    @Test func inAppWriteOfViewToggleDoesNotFireCallback() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        let log = tc.startObserving()

        tc.config.writeViewToggle(.readableColumn, enabled: true)
        tc.config.state.refresh()

        #expect(log.keys.isEmpty)
    }

    @Test func resetDoesNotFireCallback() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.theme = .blues
        tc.config.changesEnabled = false

        let log = tc.startObserving()

        tc.config.reset()
        tc.config.state.refresh()

        #expect(log.keys.isEmpty)
    }

    // MARK: - Diff across multiple keys and types

    @Test func externalWriteOfMultipleKeysFiresOnceEach() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        let log = tc.startObserving()

        tc.config.defaults.set("blues", forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.defaults.set("dark", forKey: MudPreferences.Keys.lighting.rawValue)
        tc.config.defaults.set(1.5, forKey: MudPreferences.Keys.upModeZoomLevel.rawValue)
        tc.config.defaults.set(false, forKey: MudPreferences.Keys.changesEnabled.rawValue)
        tc.config.state.refresh()

        #expect(Set(log.keys) == [.theme, .lighting, .upModeZoomLevel, .changesEnabled])
    }

    @Test func externalWriteOfViewToggleKeySurfaces() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        let log = tc.startObserving()

        tc.config.defaults.set(
            true,
            forKey: MudPreferences.Keys.uiShowReadableColumn.rawValue
        )
        tc.config.state.refresh()

        #expect(log.keys == [.uiShowReadableColumn])
    }

    @Test func secondDiffPassWithoutChangesFiresNothing() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        let log = tc.startObserving()

        tc.config.defaults.set("blues", forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.state.refresh()
        log.keys.removeAll()

        // Same value — no diff.
        tc.config.state.refresh()
        #expect(log.keys.isEmpty)

        // Overwrite with the same value — still no diff.
        tc.config.defaults.set("blues", forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.state.refresh()
        #expect(log.keys.isEmpty)
    }

    @Test func preExistingValuesDoNotFireOnFirstRefresh() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        // Values already in the store before observation starts should seed
        // `lastKnown` — they must not surface as a spurious first-refresh diff.
        tc.config.defaults.set("blues", forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.defaults.set(1.5, forKey: MudPreferences.Keys.upModeZoomLevel.rawValue)

        let log = tc.startObserving()
        tc.config.state.refresh()

        #expect(log.keys.isEmpty)
    }

    // MARK: - Observation lifecycle

    @Test func refreshBeforeStartObservingIsNoop() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        // Should not trap or interact with defaults.
        tc.config.state.refresh()
    }

    @Test func startObservingReplacesCallbackWhenCalledAgain() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        var firstCount = 0
        var secondCount = 0

        tc.config.startObservingExternalChanges { _ in firstCount += 1 }
        tc.config.startObservingExternalChanges { _ in secondCount += 1 }

        tc.config.defaults.set("blues", forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.state.refresh()

        #expect(firstCount == 0)
        #expect(secondCount == 1)
    }

    // MARK: - syncMirror — startup fan-out copy from `defaults` into `mirror`

    @Test func syncMirrorCopiesEveryPresentKey() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        // Set values directly on `defaults` to simulate external
        // `defaults write` changes made while the app was not running.
        tc.config.defaults.set("blues", forKey: MudPreferences.Keys.theme.rawValue)
        tc.config.defaults.set(1.5, forKey: MudPreferences.Keys.upModeZoomLevel.rawValue)
        tc.config.defaults.set(false, forKey: MudPreferences.Keys.changesEnabled.rawValue)

        tc.config.syncMirror()

        let mirror = tc.config.mirror!
        #expect(
            mirror.string(forKey: MudPreferences.Keys.theme.rawValue) == "blues"
        )
        #expect(
            mirror.object(forKey: MudPreferences.Keys.upModeZoomLevel.rawValue)
                as? Double == 1.5
        )
        #expect(
            mirror.object(forKey: MudPreferences.Keys.changesEnabled.rawValue)
                as? Bool == false
        )
    }

    @Test func syncMirrorClearsStaleValueWhenSourceIsAbsent() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.mirror!.set("riot", forKey: MudPreferences.Keys.theme.rawValue)
        // `defaults` does not have a `theme` key.

        tc.config.syncMirror()

        #expect(
            tc.config.mirror!.object(forKey: MudPreferences.Keys.theme.rawValue) == nil
        )
    }

    @Test func syncMirrorWithoutMirrorIsNoop() {
        let suiteName = "test.mud.nomirror.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let config = MudPreferences(defaults: defaults)
        config.syncMirror() // must not crash
    }

    @Test func syncMirrorIsIdempotent() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.theme = .blues
        tc.config.syncMirror()
        let first = tc.config.mirror!.string(
            forKey: MudPreferences.Keys.theme.rawValue
        )
        tc.config.syncMirror()
        let second = tc.config.mirror!.string(
            forKey: MudPreferences.Keys.theme.rawValue
        )
        #expect(first == second)
    }
}
