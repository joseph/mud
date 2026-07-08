import Foundation
import Testing
@testable import Mud

/// The find state machine: how typing, Enter, and the arrows classify each
/// query (`SearchOrigin`), and what shows/clears the bar. Typing flows
/// through a Combine sink received on `RunLoop.main`, and `close()` defers
/// its mutations to the next run-loop turn, so these tests `await pump()`
/// after each such step.
@MainActor
@Suite struct FindStateTests {
    private func visibleState() -> FindState {
        let state = FindState()
        state.isVisible = true
        return state
    }

    @Test func newTermSearchesFromTheTop() async {
        let state = visibleState()
        state.searchText = "he"
        await pump()
        #expect(state.searchOrigin == .top)
        #expect(state.searchDirection == .forward)
        #expect(state.currentQuery?.text == "he")
    }

    @Test func prefixContinuationRefines() async {
        let state = visibleState()
        state.searchText = "he"
        await pump()
        state.searchText = "hel"
        await pump()
        #expect(state.searchOrigin == .refine)
    }

    @Test func nonPrefixEditRestartsFromTheTop() async {
        let state = visibleState()
        state.searchText = "hel"
        await pump()
        state.searchText = "world"
        await pump()
        #expect(state.searchOrigin == .top)
    }

    @Test func retypingTheSameTermFiresNoNewQuery() async {
        let state = visibleState()
        state.searchText = "he"
        await pump()
        let id = state.searchID
        state.searchText = "he"
        await pump()
        #expect(state.searchID == id)
    }

    @Test func findNextAndPreviousAdvanceFromTheSelection() async {
        let state = visibleState()
        state.searchText = "he"
        await pump()
        state.findNext()
        #expect(state.searchOrigin == .advance)
        #expect(state.searchDirection == .forward)

        state.findPrevious()
        #expect(state.searchOrigin == .advance)
        #expect(state.searchDirection == .backward)
    }

    @Test func navigationWithoutATermIsIgnored() {
        let state = visibleState()
        let id = state.searchID
        state.findNext()
        state.findPrevious()
        #expect(state.searchID == id)
    }

    @Test func currentQueryRequiresVisibilityAndText() async {
        let state = FindState()
        #expect(state.currentQuery == nil)

        state.isVisible = true
        #expect(state.currentQuery == nil)  // no text yet

        state.searchText = "he"
        await pump()
        #expect(state.currentQuery != nil)

        state.isVisible = false
        #expect(state.currentQuery == nil)
    }

    @Test func closeClearsTheSearch() async {
        let state = visibleState()
        state.searchText = "he"
        await pump()
        state.matchInfo = MatchInfo(current: 1, total: 3)

        state.close()
        await pump()  // close() defers its mutations to the next turn
        #expect(!state.isVisible)
        #expect(state.searchText.isEmpty)
        #expect(state.matchInfo == nil)
        #expect(state.currentQuery == nil)
    }

    @Test func clearingTextDropsTheMatchCounter() async {
        let state = visibleState()
        state.searchText = "he"
        await pump()
        state.matchInfo = MatchInfo(current: 1, total: 3)

        state.clear()
        await pump()
        #expect(state.matchInfo == nil)
        // The next identical term is a fresh search, not a refinement.
        state.searchText = "he"
        await pump()
        #expect(state.searchOrigin == .top)
    }
}
