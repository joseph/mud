import Foundation
import Testing
import MudCore
@testable import Mud

/// The truth table behind making room for the Comments column. Below
/// `Layout.compactBreakpoint` the column stands down (`mud-narrow.css`), so
/// Add Comment and Show Comments both call `makeRoom` first.
///
/// Which remedy comes back decides what the user sees: `.widen` happens
/// silently, `.hideSidebar` puts up the one prompt, and `.unavailable` falls
/// back to scrolling the bottom Comments section into view. So a wrong answer
/// here is either a window that resizes for no reason or a prompt offering
/// something that wouldn't help.
@MainActor
@Suite struct CommentColumnFitTests {
    /// Points of window frame outside the content pane, sidebar excluded.
    private static let borders: CGFloat = 2

    @Test func widensWhenTheScreenHasRoom() {
        // A 640pt content pane on a 1680pt screen, sidebar collapsed.
        let remedy = CommentColumnFit.remedy(
            contentPaneWidth: 640,
            windowChromeWidth: Self.borders,
            visibleScreenWidth: 1680,
            expandedSidebarWidth: nil)
        #expect(remedy == .widen(contentWidth: 720))
    }

    /// The target is comfort, not the bare minimum, but a screen that can't
    /// reach it should still widen as far as it can rather than give up: 700 is
    /// the breakpoint, and anything over it opens the column.
    @Test func widensAsFarAsTheScreenAllows() {
        let remedy = CommentColumnFit.remedy(
            contentPaneWidth: 640,
            windowChromeWidth: Self.borders,
            visibleScreenWidth: 712,
            expandedSidebarWidth: nil)
        #expect(remedy == .widen(contentWidth: 710))
    }

    /// Widening wins even with the sidebar open — the user asked for comments,
    /// not for their sidebar to disappear. This is also what keeps the prompt
    /// rare: it only appears once widening is genuinely off the table.
    @Test func widensRatherThanHidingTheSidebarWhenBothWouldWork() {
        let remedy = CommentColumnFit.remedy(
            contentPaneWidth: 600,
            windowChromeWidth: 246 + Self.borders,
            visibleScreenWidth: 1680,
            expandedSidebarWidth: 246)
        #expect(remedy == .widen(contentWidth: 720))
    }

    /// The window already fills the screen and the sidebar is what's taking the
    /// room: collapsing it hands its full thickness to the content pane.
    @Test func hidesTheSidebarWhenThereIsNoRoomToWiden() {
        let remedy = CommentColumnFit.remedy(
            contentPaneWidth: 600,
            windowChromeWidth: 246 + Self.borders,
            visibleScreenWidth: 848,
            expandedSidebarWidth: 246)
        #expect(remedy == .hideSidebar)
    }

    /// Hiding a sidebar too thin to close the gap wouldn't help, so it isn't
    /// offered.
    @Test func offersNothingWhenHidingTheSidebarStillFallsShort() {
        let remedy = CommentColumnFit.remedy(
            contentPaneWidth: 400,
            windowChromeWidth: 246 + Self.borders,
            visibleScreenWidth: 648,
            expandedSidebarWidth: 246)
        #expect(remedy == .unavailable)
    }

    /// A display too narrow either way, with no sidebar to reclaim.
    @Test func offersNothingOnADisplayThatIsTooNarrow() {
        let remedy = CommentColumnFit.remedy(
            contentPaneWidth: 600,
            windowChromeWidth: Self.borders,
            visibleScreenWidth: 640,
            expandedSidebarWidth: nil)
        #expect(remedy == .unavailable)
    }

    /// Exactly at the breakpoint is still too narrow: the stylesheet's query is
    /// `max-width`, so 700 is inside the Compact tier and the column is hidden.
    /// Off by one here and the window would widen to a pane that still shows
    /// nothing.
    @Test func theBreakpointItselfCountsAsTooNarrow() {
        let remedy = CommentColumnFit.remedy(
            contentPaneWidth: 690,
            windowChromeWidth: Self.borders,
            visibleScreenWidth: CGFloat(Layout.compactBreakpoint) + Self.borders,
            expandedSidebarWidth: nil)
        #expect(remedy == .unavailable)
    }
}
