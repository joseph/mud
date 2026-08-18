import Foundation
import Testing
import MudCore
@testable import MudPreferences

@Suite("MudPreferences snapshot")
struct MudPreferencesSnapshotTests {
    @Test func emptySuiteReturnsDefaults() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        let snap = tc.config.snapshot()

        #expect(snap.theme == .earthy)
        #expect(snap.upModeZoomLevel == 1.0)
        #expect(snap.upModeAllowRemoteContent == true)
        #expect(snap.markdownDocCAlertMode == .extended)
        // lineNumbers, wordWrap, codeHeader, foldableHeadings default true;
        // readableColumn and autoExpandChanges default false.
        #expect(snap.viewToggles == [
            .lineNumbers, .wordWrap, .codeHeader, .foldableHeadings,
        ])
        #expect(snap.enabledExtensions == [])
        #expect(snap.diagramLook == .simplicity)
    }

    @Test func snapshotReflectsEachField() {
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.theme = .blues
        tc.config.upModeZoomLevel = 1.25
        tc.config.upModeAllowRemoteContent = false
        tc.config.markdownDocCAlertMode = .common
        tc.config.upModeDiagramLook = .handwritten
        tc.config.writeViewToggle(.readableColumn, enabled: false)
        tc.config.writeViewToggle(.lineNumbers, enabled: true)
        tc.config.writeViewToggle(.wordWrap, enabled: false)
        tc.config.writeViewToggle(.codeHeader, enabled: false)
        tc.config.writeViewToggle(.foldableHeadings, enabled: false)
        tc.config.writeEnabledExtensions(["alpha"])

        let all: Set<String> = ["alpha", "beta"]
        let snap = tc.config.snapshot(defaultEnabledExtensions: all)

        #expect(snap.theme == .blues)
        #expect(snap.upModeZoomLevel == 1.25)
        #expect(snap.upModeAllowRemoteContent == false)
        #expect(snap.markdownDocCAlertMode == .common)
        #expect(snap.viewToggles == [.lineNumbers])
        #expect(snap.enabledExtensions == ["alpha"])
        #expect(snap.diagramLook == .handwritten)
    }

    @Test func mirrorBackedSnapshotMatchesDefaults() {
        // The extension builds its own MudPreferences pointed at the
        // app-group suite. Its snapshot should match what the app wrote.
        let tc = TestPreferences()
        defer { tc.tearDown() }

        tc.config.theme = .blues
        tc.config.upModeZoomLevel = 1.25
        tc.config.upModeAllowRemoteContent = false
        tc.config.markdownDocCAlertMode = .common
        tc.config.writeViewToggle(.readableColumn, enabled: true)
        tc.config.writeViewToggle(.wordWrap, enabled: false)
        tc.config.writeEnabledExtensions(["alpha"])

        let all: Set<String> = ["alpha", "beta"]
        let defaultsSnap = tc.config.snapshot(defaultEnabledExtensions: all)
        let extensionConfig = MudPreferences(defaults: tc.config.mirror!)
        let mirrorSnap = extensionConfig.snapshot(defaultEnabledExtensions: all)

        #expect(mirrorSnap.theme == defaultsSnap.theme)
        #expect(mirrorSnap.upModeZoomLevel == defaultsSnap.upModeZoomLevel)
        #expect(mirrorSnap.upModeAllowRemoteContent == defaultsSnap.upModeAllowRemoteContent)
        #expect(mirrorSnap.markdownDocCAlertMode == defaultsSnap.markdownDocCAlertMode)
        #expect(mirrorSnap.viewToggles == defaultsSnap.viewToggles)
        #expect(mirrorSnap.enabledExtensions == defaultsSnap.enabledExtensions)
    }

    // MARK: - upModeHTMLClasses

    @Test func upModeHTMLClassesIncludesAllThree() {
        let snap = MudPreferencesSnapshot(
            theme: .earthy, upModeZoomLevel: 1.0,
            viewToggles: [.readableColumn, .wordWrap, .lineNumbers],
            upModeAllowRemoteContent: true, enabledExtensions: [],
            diagramLook: .simplicity, markdownDocCAlertMode: .extended
        )
        #expect(snap.upModeHTMLClasses == [
            "is-readable-column", "has-word-wrap", "has-line-numbers",
        ])
    }

    @Test func upModeHTMLClassesExcludesDownModeOnly() {
        let snap = MudPreferencesSnapshot(
            theme: .earthy, upModeZoomLevel: 1.0,
            viewToggles: [.readableColumn, .codeHeader, .autoExpandChanges],
            upModeAllowRemoteContent: true, enabledExtensions: [],
            diagramLook: .simplicity, markdownDocCAlertMode: .extended
        )
        #expect(snap.upModeHTMLClasses == ["is-readable-column"])
    }

    @Test func upModeHTMLClassesEmptyWhenNoUpToggles() {
        let snap = MudPreferencesSnapshot(
            theme: .earthy, upModeZoomLevel: 1.0,
            viewToggles: [.codeHeader, .autoExpandChanges],
            upModeAllowRemoteContent: true, enabledExtensions: [],
            diagramLook: .simplicity, markdownDocCAlertMode: .extended
        )
        #expect(snap.upModeHTMLClasses.isEmpty)
    }
}
