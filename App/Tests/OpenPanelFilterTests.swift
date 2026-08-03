import Testing
import UniformTypeIdentifiers
@testable import Mud

/// The open panel's "Enable:" filter. Thin, but it records the non-obvious
/// contract that an empty `allowedContentTypes` means *unfiltered* rather than
/// *nothing allowed* — the one thing that would silently break the All Files
/// case if someone "fixed" it later.
@MainActor
@Suite struct OpenPanelFilterTests {
    @Test func markdownAndTextAllowsMarkdownAndPlainText() {
        #expect(OpenPanelFilter.markdownAndText.contentTypes == [.markdown, .plainText])
    }

    @Test func allFilesIsUnfilteredRatherThanEmpty() {
        #expect(OpenPanelFilter.allFiles.contentTypes.isEmpty)
    }

    @Test func panelsOpenOnTheMarkdownFilter() {
        #expect(OpenPanelFilter.default == .markdownAndText)
    }

    /// The raw values are the popup's item indices, so the two have to agree
    /// for `openPanelFilterChanged` to map a selection back to a case.
    @Test func rawValuesMatchMenuOrder() {
        for (index, filter) in OpenPanelFilter.allCases.enumerated() {
            #expect(filter.rawValue == index)
            #expect(OpenPanelFilter(rawValue: index) == filter)
        }
    }

    @Test func everyCaseHasADistinctTitle() {
        let titles = OpenPanelFilter.allCases.map(\.title)
        #expect(Set(titles).count == titles.count)
        #expect(!titles.contains { $0.isEmpty })
    }
}
