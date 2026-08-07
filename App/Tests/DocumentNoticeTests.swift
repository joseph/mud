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
        state.raise(.openFailed(fileName: "Notes.md", reason: .notFound))

        #expect(state.notice?.kind == .openFailed)
        #expect(state.notice?.level == .warning)
    }

    /// Clearing names a kind, so a condition ending can only take down its own
    /// notice. Without the guard, a successful re-read would wipe a comment
    /// write failure the reader hasn't seen yet.
    @Test func clearingADifferentKindLeavesTheNoticeAlone() {
        let state = DocumentState()
        state.raise(.commentWriteFailed(
            message: "Couldn't write.", note: "", composeIsOpen: false))

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

    /// "Copy Comment" is offered only when there is a body to copy. A failed
    /// delete has no compose box and no body, so the bar would otherwise show a
    /// button that put an empty string on the pasteboard. With no box to close,
    /// the × is the only way out — so this is the variant that has one.
    @Test func copyCommentIsNotOfferedWithoutANote() {
        let notice = DocumentNotice.commentWriteFailed(
            message: "Couldn't write.", note: "", composeIsOpen: false)

        #expect(notice.action == nil)
        #expect(notice.level == .error)
        #expect(notice.isDismissible)
    }

    /// The button carries the body the reader wrote, not the message explaining
    /// the failure. Assertable because the action is a value: with a closure
    /// the test could only see that *some* button existed.
    @Test func copyCommentCarriesTheNote() {
        let notice = DocumentNotice.commentWriteFailed(
            message: "Couldn't write.", note: "Some note", composeIsOpen: true)

        #expect(notice.action?.title == "Copy Comment")
        #expect(notice.action?.effect == .copyToPasteboard("Some note"))
    }

    /// With a compose box still open, closing it is what takes this notice
    /// down, so the bar offers no × of its own — two controls for one thing,
    /// where only one of them also settles the comment.
    @Test func aFailureWithAnOpenComposeBoxCarriesNoDismissButton() {
        let notice = DocumentNotice.commentWriteFailed(
            message: "Couldn't write.", note: "Some note", composeIsOpen: true)

        #expect(!notice.isDismissible)
    }

    /// Cancel, Escape, and hiding the column all end composing, and the reader
    /// abandoning the text answers the message about it.
    @Test func endingComposeClearsTheWriteFailure() {
        let state = DocumentState()
        state.isColumnComposing = true
        state.raise(.commentWriteFailed(
            message: "Couldn't write.", note: "Some note", composeIsOpen: true))

        state.isColumnComposing = false
        #expect(state.notice == nil)
    }

    /// A failed delete is raised with no box open. Composing ending later —
    /// somewhere else in the window — must not take it down, since the reader
    /// has only the × to answer it with.
    @Test func endingComposeSparesANoticeRaisedWithoutABox() {
        let state = DocumentState()
        state.raise(.commentWriteFailed(
            message: "Couldn't delete.", note: "", composeIsOpen: false))

        state.isColumnComposing = false
        #expect(state.notice?.kind == .commentWriteFailed)
    }

    /// Ending compose clears by kind, so a notice some other condition raised
    /// while the box was open is left where it is.
    @Test func endingComposeLeavesAnotherKindAlone() {
        let state = DocumentState()
        state.isColumnComposing = true
        state.raise(.externalChangeHeld)

        state.isColumnComposing = false
        #expect(state.notice == DocumentNotice.externalChangeHeld)
    }

    /// The empty-folder window's page is blank, so the bar carries the whole
    /// message — and there is nothing to do about it and nothing that would
    /// clear it, so it has neither a button nor an ×.
    @Test func theEmptyFolderNoticeIsAPlainWarning() {
        let notice = DocumentNotice.folderHasNoMarkdown

        #expect(notice.level == .warning)
        #expect(notice.action == nil)
        #expect(!notice.isDismissible)
    }

    /// A truncated index isn't a failure — the document is a real one, just
    /// not the whole tree — so it reads as information, and the walk that
    /// fits is what takes it down rather than the reader.
    @Test func theTruncatedIndexNoticeGivesTheLimit() {
        let notice = DocumentNotice.folderIndexTruncated(limit: 1000)

        #expect(notice.message.contains("1,000"))
        #expect(notice.level == .info)
        #expect(notice.action == nil)
        #expect(!notice.isDismissible)
    }

    /// The reload failure is the one read failure with an ×: the reader can go
    /// on using the document under it, and a file that stays unreadable would
    /// otherwise never clear the notice.
    @Test func reloadFailureNamesTheFileAndCarriesADismissButton() {
        let notice = DocumentNotice.reloadFailed(
            fileName: "Notes.md", reason: .notFound)

        #expect(notice.message.contains("Notes.md"))
        #expect(notice.level == .warning)
        #expect(notice.action == nil)
        #expect(notice.isDismissible)
    }

    @Test func openFailureNamesTheFile() {
        let notice = DocumentNotice.openFailed(
            fileName: "Notes.md", reason: .notFound)

        #expect(notice.message.contains("Notes.md"))
        // A document that can't be read is a warning; the held-reload notice,
        // where nothing is wrong and the view catches up on its own, is the
        // `.info` one.
        #expect(notice.level == .warning)
        #expect(DocumentNotice.externalChangeHeld.level == .info)
        // Nothing to do about it from the bar — so no button, and no way to
        // hide the headline while the page it belongs to is still showing.
        #expect(notice.action == nil)
        #expect(!notice.isDismissible)
    }

    /// Six sentences, all different. Two of the three error pages are blank,
    /// and a failed reload has no page at all, so the bar is where the reader
    /// learns which failure this was — a message that read the same for a
    /// missing file and an unreadable one would tell them nothing.
    @Test func everyReadFailureReadsDifferently() {
        let reasons: [DocumentNotice.ReadFailure] =
            [.notFound, .noPermission, .badEncoding]
        let messages = reasons.flatMap {
            [$0.openMessage(fileName: "Notes.md"),
             $0.reloadMessage(fileName: "Notes.md")]
        }

        #expect(Set(messages).count == messages.count)
        #expect(messages.allSatisfy { $0.contains("Notes.md") })
    }

    /// The button opens a file panel with nothing in between, so the folder it
    /// starts at is part of what the notice promises. Assertable because the
    /// effect is a value rather than a closure.
    @Test func theBlockedAssetsNoticeCarriesTheFolderToGrant() {
        let folder = URL(fileURLWithPath: "/Users/jp/Notes", isDirectory: true)

        let notice = DocumentNotice.localAssetsBlocked(folder: folder)

        #expect(notice.action?.title == "Grant Access…")
        #expect(notice.action?.effect == .grantFolderAccess(startingAt: folder))
    }

    /// Nothing is broken — the document is fine and its images aren't showing —
    /// so it is a warning rather than an error. It carries an × because a
    /// reader who doesn't care about the images shouldn't have to grant a
    /// folder to put the bar away.
    @Test func theBlockedAssetsNoticeIsADismissibleWarning() {
        let notice = DocumentNotice.localAssetsBlocked(
            folder: URL(fileURLWithPath: "/Users/jp/Notes", isDirectory: true))

        #expect(notice.kind == .localAssetsBlocked)
        #expect(notice.level == .warning)
        #expect(notice.isDismissible)
    }

    /// A render that reads every image clears it, and clearing is by kind, so
    /// a grant that fixes one window can't take down another window's unread
    /// message about something else.
    @Test func theBlockedAssetsNoticeClearsByKind() {
        let state = DocumentState()
        state.raise(.localAssetsBlocked(
            folder: URL(fileURLWithPath: "/Users/jp", isDirectory: true)))

        state.clear(.openFailed)
        #expect(state.notice?.kind == .localAssetsBlocked)

        state.clear(.localAssetsBlocked)
        #expect(state.notice == nil)
    }

    /// Unlike every other notice, this one is re-derived on every Up render —
    /// a mode toggle or a theme change is enough. So it is the one notice that
    /// isn't allowed to take the bar from another: `externalChangeHeld` says
    /// its piece once and guards on its own `didSet`, so a message pushed
    /// aside here would never come back.
    @Test func blockedAssetsWaitsForTheBarRatherThanTakingIt() {
        let folder = URL(fileURLWithPath: "/Users/jp/Notes", isDirectory: true)

        #expect(DocumentModel.blockedAssetsMayRaise(over: nil))
        #expect(
            DocumentModel.blockedAssetsMayRaise(
                over: .localAssetsBlocked(folder: folder)))
        #expect(!DocumentModel.blockedAssetsMayRaise(over: .externalChangeHeld))
        #expect(
            !DocumentModel.blockedAssetsMayRaise(
                over: .openFailed(fileName: "Notes.md", reason: .notFound)))
    }
}
