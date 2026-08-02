import Foundation
import Testing
@testable import Mud

/// The info bar is driven entirely by `DocumentState.notice`, so these cover
/// what decides whether the bar is on screen and what it says.
@MainActor
@Suite struct DocumentNoticeTests {

    @Test func noNoticeMeansNoBar() {
        let state = DocumentState()
        #expect(state.notice == nil)
    }

    @Test func raisingAndClearingTheSameKind() {
        let state = DocumentState()
        state.raise(.externalChangeHeld)
        #expect(state.notice == DocumentNotice.externalChangeHeld)

        state.clear(.externalChangeHeld)
        #expect(state.notice == nil)
    }

    /// Raising twice replaces the message rather than stacking: the bar shows
    /// one notice, so the newer text has to win.
    @Test func raisingAgainReplacesTheMessage() {
        let state = DocumentState()
        state.raise(.externalChangeHeld)
        state.raise(.openFailed(fileName: "Notes.md"))

        #expect(state.notice?.kind == .openFailed)
        #expect(state.notice?.level == .warning)
    }

    /// Clearing names a kind, so a condition ending can only take down its own
    /// notice. Without the guard, a successful re-read would wipe a comment
    /// write failure the reader hasn't seen yet.
    @Test func clearingADifferentKindLeavesTheNoticeAlone() {
        let state = DocumentState()
        state.raise(.commentWriteFailed(message: "Couldn't write.", note: ""))

        state.clear(.openFailed)
        #expect(state.notice?.kind == .commentWriteFailed)

        state.clear(.commentWriteFailed)
        #expect(state.notice == nil)
    }

    /// The × takes down whatever is in front of the reader, whatever raised it.
    @Test func dismissingTakesDownAnyNotice() {
        let state = DocumentState()
        state.raise(.externalChangeHeld)

        state.dismissNotice()
        #expect(state.notice == nil)
    }

    /// "Copy Comment" is offered only when there is a body to copy. A delete
    /// that fails has no compose box and no body, so the bar would otherwise
    /// show a button that put an empty string on the pasteboard.
    @Test func copyCommentIsNotOfferedWithoutANote() {
        let notice = DocumentNotice.commentWriteFailed(
            message: "Couldn't write.", note: "")

        #expect(notice.action == nil)
        #expect(notice.level == .error)
        #expect(notice.isDismissible)
    }

    /// The button carries the body the reader wrote, not the message explaining
    /// the failure. Assertable because the action is a value: with a closure
    /// the test could only see that *some* button existed.
    @Test func copyCommentCarriesTheNote() {
        let notice = DocumentNotice.commentWriteFailed(
            message: "Couldn't write.", note: "Some note")

        #expect(notice.action?.title == "Copy Comment")
        #expect(notice.action?.effect == .copyToPasteboard("Some note"))
    }

    @Test func openFailureNamesTheFile() {
        let notice = DocumentNotice.openFailed(fileName: "Notes.md")

        #expect(notice.message.contains("Notes.md"))
        // A document that can't be read is a warning; the held-reload notice,
        // where nothing is wrong and the view catches up on its own, is the
        // `.info` one.
        #expect(notice.level == .warning)
        #expect(DocumentNotice.externalChangeHeld.level == .info)
        // Nothing to do about it from the bar, and the error page underneath
        // is the explanation — so no button, and no way to hide the headline
        // while the page it belongs to is still showing.
        #expect(notice.action == nil)
        #expect(!notice.isDismissible)
    }
}
