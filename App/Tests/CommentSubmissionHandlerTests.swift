import Combine
import Foundation
import MudCore
import Testing
@testable import Mud

/// The page-facing half of a comment submission: what the handler tells the
/// column over `resolveCompose`.
///
/// Every action is answered, including the ones with no compose box. The page
/// acts before the file has agreed — a delete puffs the message away as soon as
/// it is clicked — so a submission left unanswered strands the column showing
/// something the file doesn't say.
@MainActor
@Suite struct CommentSubmissionHandlerTests {
    private let directory: URL
    private let fileURL: URL
    private let state: DocumentState
    private let model: DocumentModel
    private let label: String

    private static let source = """
    Hello brave new world.

    Another paragraph of prose.
    """

    /// The selection end after "world" in the first paragraph.
    private static let draft = CommentDraft(
        quotation: "brave new world",
        blockText: "Hello brave new world.",
        offsetInBlock: 21,
        occurrence: 0)

    init() throws {
        directory = try makeTempDirectory()
        fileURL = directory.appendingPathComponent("notes.md")
        try Self.source.write(to: fileURL, atomically: true, encoding: .utf8)
        // Seed one real comment while the file is still writable, so the delete
        // cases below have something to remove.
        label = try CommentController(fileURL: fileURL)
            .addComment(Self.draft, author: "Tester", body: "A note.").get()
        state = DocumentState()
        model = DocumentModel(
            fileURL: fileURL, state: state, changeTracker: state.changeTracker)
    }

    // MARK: - Helpers

    /// The outcomes the handler pushed to the page while `body` ran.
    /// `webCommands` is a `PassthroughSubject`, so its sink runs synchronously
    /// and the array is complete by the time this returns.
    private func resolveOutcomes(
        _ body: (CommentSubmissionHandler) -> Void
    ) -> [Bool] {
        var outcomes: [Bool] = []
        let token = state.webCommands.sink { command in
            if case .resolveCompose(let success) = command {
                outcomes.append(success)
            }
        }
        defer { token.cancel() }
        body(CommentSubmissionHandler(model: model, state: state))
        return outcomes
    }

    private func makeReadOnly() throws {
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444], ofItemAtPath: fileURL.path)
    }

    private func submission(_ action: CommentSubmission.Action) -> CommentSubmission {
        // A delete carries no body — the page posts just the label, there being
        // no compose box behind it. That is what leaves its notice with no
        // "Copy Comment" button.
        CommentSubmission(
            action: action,
            label: label,
            body: action == .delete ? nil : "Some text",
            draft: Self.draft)
    }

    // MARK: - Tests

    /// A delete the file refuses has to be reported. The page has already
    /// played the puff, and this false is what rebuilds the capsule from the
    /// bottom section — without it the comment stays off screen until a
    /// hide/reveal of the column or a reload of the document.
    @Test func aRefusedDeleteIsAnswered() throws {
        try makeReadOnly()

        #expect(resolveOutcomes { $0.handle(submission(.delete)) } == [false])
    }

    @Test func aSuccessfulDeleteIsAnswered() {
        #expect(resolveOutcomes { $0.handle(submission(.delete)) } == [true])
    }

    /// A label that isn't in the file is not a refusal: the comment is gone
    /// whichever way, so the puff was right and the page keeps it.
    @Test func aDeleteOfAVanishedCommentStands() {
        let gone = CommentSubmission(
            action: .delete, label: "comment-zz", body: nil, draft: nil)

        #expect(resolveOutcomes { $0.handle(gone) } == [true])
    }

    /// The read-only guard refuses before attempting any write. Whichever
    /// action it turned away, the page hears about it.
    @Test func everyActionOnAReadOnlyFileIsAnswered() throws {
        try makeReadOnly()

        for action in [CommentSubmission.Action.add, .reply, .edit, .delete] {
            #expect(
                resolveOutcomes { $0.handle(submission(action)) } == [false],
                "\(action.rawValue) went unanswered")
        }
    }

    /// One read-only message covers all four actions, so a refused delete isn't
    /// told to make the file writable "to add comments".
    @Test func theReadOnlyMessageDoesNotNameOneAction() throws {
        try makeReadOnly()
        _ = resolveOutcomes { $0.handle(submission(.delete)) }

        #expect(state.notice?.kind == .commentWriteFailed)
        #expect(state.notice?.message.contains("read-only") == true)
        #expect(state.notice?.message.contains("add comments") == false)
    }

    /// A failed delete has no compose box to close, so nothing but the reader
    /// can take its notice down — and no text to offer the pasteboard.
    @Test func aRefusedDeleteRaisesADismissibleNotice() throws {
        try makeReadOnly()
        _ = resolveOutcomes { $0.handle(submission(.delete)) }

        #expect(state.notice?.isDismissible == true)
        #expect(state.notice?.action == nil)
    }
}
