import Foundation
import Testing
import MudCore
@testable import MudPreferences

@Suite("MudPreferences")
struct MudPreferencesTests {
    // MARK: - Round-trips

    @Test func themeRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.theme = .blues
        #expect(tc.config.theme == .blues)
    }

    @Test func lightingRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.lighting = .dark
        #expect(tc.config.lighting == .dark)
    }

    @Test func markdownDocCAlertModeRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.markdownDocCAlertMode = .off
        #expect(tc.config.markdownDocCAlertMode == .off)
    }

    @Test func doubleRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.upModeZoomLevel = 1.5
        #expect(tc.config.upModeZoomLevel == 1.5)
    }

    @Test func boolRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.changesEnabled = false
        #expect(tc.config.changesEnabled == false)
    }

    @Test func stringArrayRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        let all: Set<String> = ["alpha", "beta", "gamma"]
        tc.config.writeEnabledExtensions(["alpha", "gamma"])
        let read = tc.config.readEnabledExtensions(defaultValue: all)
        #expect(read == ["alpha", "gamma"])
    }

    @Test func sidebarPaneRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.sidebarPane = .changes
        #expect(tc.config.sidebarPane == .changes)
    }

    @Test func uiFloatingControlsPositionRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.uiFloatingControlsPosition = .topRight
        #expect(tc.config.uiFloatingControlsPosition == .topRight)
    }

    @Test func viewToggleSingularRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.writeViewToggle(.readableColumn, enabled: false)
        #expect(tc.config.readViewToggle(.readableColumn) == false)
    }

    @Test func hasLaunchedRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.hasLaunched == false)
        tc.config.hasLaunched = true
        #expect(tc.config.hasLaunched == true)
    }

    @Test func cliInstalledRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.cliInstalled == false)
        tc.config.cliInstalled = true
        #expect(tc.config.cliInstalled == true)
    }

    @Test func cliSymlinkPathRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.cliSymlinkPath == nil)
        tc.config.cliSymlinkPath = "/usr/local/bin/mud"
        #expect(tc.config.cliSymlinkPath == "/usr/local/bin/mud")
        tc.config.cliSymlinkPath = nil
        #expect(tc.config.cliSymlinkPath == nil)
    }

    @Test func openInDefaultBundleIDRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.openInDefaultBundleID == nil)
        tc.config.openInDefaultBundleID = "com.barebones.bbedit"
        #expect(tc.config.openInDefaultBundleID == "com.barebones.bbedit")
        tc.config.openInDefaultBundleID = nil
        #expect(tc.config.openInDefaultBundleID == nil)
    }

    @Test func openInDefaultFormatRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.openInDefaultFormat == .auto)
        tc.config.openInDefaultFormat = .html
        #expect(tc.config.openInDefaultFormat == .html)
        tc.config.openInDefaultFormat = .markdown
        #expect(tc.config.openInDefaultFormat == .markdown)
        tc.config.openInDefaultFormat = .auto
        #expect(tc.config.openInDefaultFormat == .auto)
    }

    @Test func internalKeysFanOutToMirror() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.hasLaunched = true
        tc.config.cliInstalled = true
        tc.config.cliSymlinkPath = "/usr/local/bin/mud"

        let mirror = tc.config.mirror!
        #expect(mirror.bool(forKey: MudPreferences.Keys.hasLaunched.rawValue) == true)
        #expect(mirror.bool(forKey: MudPreferences.Keys.cliInstalled.rawValue) == true)
        #expect(
            mirror.string(forKey: MudPreferences.Keys.cliSymlinkPath.rawValue)
                == "/usr/local/bin/mud"
        )
    }

    @Test func viewTogglePluralRoundTrip() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.writeViewToggle(.readableColumn, enabled: true)
        tc.config.writeViewToggle(.lineNumbers, enabled: false)
        tc.config.writeViewToggle(.wordWrap, enabled: true)
        tc.config.writeViewToggle(.codeHeader, enabled: false)
        tc.config.writeViewToggle(.autoExpandChanges, enabled: true)
        let set = tc.config.viewToggles
        #expect(set == [.readableColumn, .wordWrap, .autoExpandChanges])
    }

    // MARK: - Defaults on empty suite

    @Test func emptySuiteLightingDefault() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.lighting == .auto)
    }

    @Test func emptySuiteThemeDefault() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.theme == .earthy)
    }

    @Test func emptySuiteMarkdownDocCAlertDefault() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.markdownDocCAlertMode == .extended)
    }

    @Test func emptySuiteZoomDefaults() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.upModeZoomLevel == 1.0)
        #expect(tc.config.downModeZoomLevel == 1.0)
    }

    @Test func emptySuiteBoolDefaults() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        // Bool prefs must not fall back to `false` on an empty suite —
        // the object(forKey:) as? Bool ?? default pattern matters here.
        #expect(tc.config.changesEnabled == true)
        #expect(tc.config.changesShowInlineDeletions == false)
        #expect(tc.config.quitOnClose == true)
        #expect(tc.config.upModeAllowRemoteContent == true)
        #expect(tc.config.uiUseHeadingAsTitle == true)
        #expect(tc.config.changesShowGitWaypoints == false)
        #expect(tc.config.sidebarEnabled == false)
    }

    @Test func emptySuiteChangesWordDiffThresholdDefault() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.changesWordDiffThreshold == 0.25)
    }

    @Test func emptySuiteUIFloatingControlsDefault() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.uiFloatingControlsPosition == .bottomCenter)
    }

    @Test func emptySuiteSidebarPaneDefault() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.sidebarPane == .outline)
    }

    @Test func emptySuiteEnabledExtensionsReturnsDefault() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        let all: Set<String> = ["alpha", "beta"]
        #expect(tc.config.readEnabledExtensions(defaultValue: all) == all)
    }

    @Test func emptySuiteViewToggleDefaults() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        #expect(tc.config.readViewToggle(.readableColumn) == false)
        #expect(tc.config.readViewToggle(.lineNumbers) == true)
        #expect(tc.config.readViewToggle(.wordWrap) == true)
        #expect(tc.config.readViewToggle(.codeHeader) == true)
        #expect(tc.config.readViewToggle(.autoExpandChanges) == false)
    }

    // MARK: - Unknown enum raw values fall back to the default

    @Test func unknownThemeRawFallsBackToDefault() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.defaults.set("not-a-theme", forKey: MudPreferences.Keys.theme.rawValue)
        #expect(tc.config.theme == .earthy)
    }

    @Test func unknownLightingRawFallsBackToDefault() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.defaults.set("nope", forKey: MudPreferences.Keys.lighting.rawValue)
        #expect(tc.config.lighting == .auto)
    }

    @Test func unknownMarkdownDocCAlertRawFallsBackToDefault() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.defaults.set("xyz", forKey: MudPreferences.Keys.markdownDocCAlertMode.rawValue)
        #expect(tc.config.markdownDocCAlertMode == .extended)
    }

    // MARK: - Reset

    @Test func resetClearsEveryKey() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.theme = .blues
        tc.config.lighting = .dark
        tc.config.upModeZoomLevel = 2.0
        tc.config.changesEnabled = false
        tc.config.writeViewToggle(.readableColumn, enabled: true)
        tc.config.reset()
        #expect(tc.config.theme == .earthy)
        #expect(tc.config.lighting == .auto)
        #expect(tc.config.upModeZoomLevel == 1.0)
        #expect(tc.config.changesEnabled == true)
        #expect(tc.config.readViewToggle(.readableColumn) == false)
    }

    @Test func resetClearsMirror() {
        let tc = TestPreferences()
        defer { tc.tearDown() }
        tc.config.theme = .blues
        tc.config.upModeZoomLevel = 2.0
        tc.config.writeViewToggle(.readableColumn, enabled: true)

        tc.config.reset()

        let mirror = tc.config.mirror!
        for key in MudPreferences.Keys.allCases {
            #expect(mirror.object(forKey: key.rawValue) == nil)
        }
    }

    // MARK: - Mirror fan-out

    @Test func writesLandInBothDefaultsAndMirror() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.theme = .blues
        tc.config.upModeZoomLevel = 1.5
        tc.config.changesEnabled = false
        tc.config.writeEnabledExtensions(["alpha", "beta"])
        tc.config.writeViewToggle(.readableColumn, enabled: true)

        #expect(
            tc.config.defaults.string(forKey: MudPreferences.Keys.theme.rawValue)
                == "blues"
        )
        #expect(
            tc.config.mirror!.string(forKey: MudPreferences.Keys.theme.rawValue)
                == "blues"
        )
        #expect(
            tc.config.mirror!.object(forKey: MudPreferences.Keys.upModeZoomLevel.rawValue)
                as? Double == 1.5
        )
        #expect(
            tc.config.mirror!.object(forKey: MudPreferences.Keys.changesEnabled.rawValue)
                as? Bool == false
        )
        #expect(
            (tc.config.mirror!.array(forKey: MudPreferences.Keys.enabledExtensions.rawValue)
                as? [String]).map(Set.init) == ["alpha", "beta"]
        )
        #expect(
            tc.config.mirror!.object(forKey: MudPreferences.Keys.uiShowReadableColumn.rawValue)
                as? Bool == true
        )
    }

    @Test func mirrorBackedReadMatchesDefaults() {
        // Simulate the Quick Look extension: a second MudPreferences whose
        // `defaults` points at the main instance's mirror suite. It should
        // read back whatever the app just wrote.
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.theme = .riot
        tc.config.upModeZoomLevel = 1.25
        tc.config.upModeAllowRemoteContent = false
        tc.config.writeViewToggle(.readableColumn, enabled: true)
        tc.config.writeViewToggle(.lineNumbers, enabled: false)

        let readerAsExtension = MudPreferences(defaults: tc.config.mirror!)

        #expect(readerAsExtension.theme == .riot)
        #expect(readerAsExtension.upModeZoomLevel == 1.25)
        #expect(readerAsExtension.upModeAllowRemoteContent == false)
        #expect(readerAsExtension.readViewToggle(.readableColumn) == true)
        #expect(readerAsExtension.readViewToggle(.lineNumbers) == false)
    }

    @Test func writesWithoutMirrorDoNotFanOut() {
        // The extension's own MudPreferences has no mirror. Writes should
        // still work; they just don't fan out anywhere.
        let suiteName = "test.mud.nomirror.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let config = MudPreferences(defaults: defaults)
        config.theme = .blues

        #expect(config.theme == .blues)
        #expect(config.mirror == nil)
    }

    // MARK: - Key-catalog invariants

    @Test func keyCatalogCount() {
        #expect(MudPreferences.Keys.allCases.count == 31)
    }

    @Test func keyRawValuesAreDistinct() {
        let raws = MudPreferences.Keys.allCases.map(\.rawValue)
        #expect(Set(raws).count == raws.count)
    }
}
