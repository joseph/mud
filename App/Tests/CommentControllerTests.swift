import Foundation
import MudCore
import Testing
@testable import Mud

/// The comment write path against real files: each mutation's success
/// shape, and the failure matrix (Phase 1 fix 4) — `anchorFailed` when the
/// comment no longer matches the source, `writeFailed` when the file can't
/// be read or written.
@MainActor
@Suite struct CommentControllerTests {
    private let directory: URL
    private let fileURL: URL

    /// One paragraph to anchor to, one bystander paragraph.
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
    }

    private func controller(
        onWrite: ((String) -> Void)? = nil
    ) -> CommentController {
        CommentController(fileURL: fileURL, onWrite: onWrite)
    }

    // `MudComment` (see TestSupport.swift): Swift Testing exports a
    // `Comment` type too, making the bare name ambiguous.
    private func diskComments() throws -> [MudComment] {
        MudCore.parseComments(
            try String(contentsOf: fileURL, encoding: .utf8))
    }

    private func addComment(
        _ controller: CommentController, body: String = "First note."
    ) throws -> String {
        try controller.addComment(
            Self.draft, author: "Tester", avatar: "👤", body: body).get()
    }

    // MARK: Success paths

    @Test func addWritesAnAnchoredComment() throws {
        let label = try addComment(controller())
        let comments = try diskComments()
        #expect(comments.count == 1)
        #expect(comments.first?.label == label)
        #expect(comments.first?.quotation == "brave new world")
        #expect(comments.first?.messages.first?.avatar == "👤")
        #expect(comments.first?.messages.first?.author == "Tester")
        #expect(comments.first?.messages.first?.body == "First note.")
        // The marker sits in the paragraph, right after the quotation.
        let written = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(written.contains("Hello brave new world[^\(label)]."))
    }

    @Test func replyAppendsAMessage() throws {
        let ctrl = controller()
        let label = try addComment(ctrl)
        try ctrl.reply(
            toLabel: label, author: "Someone", avatar: "🤖", body: "A reply."
        ).get()
        let messages = try #require(try diskComments().first?.messages)
        #expect(messages.count == 2)
        #expect(messages.last?.avatar == "🤖")
        #expect(messages.last?.author == "Someone")
        #expect(messages.last?.body == "A reply.")
    }

    @Test func editReplacesTheLastBodyKeepingItsAuthor() throws {
        let ctrl = controller()
        let label = try addComment(ctrl)
        try ctrl.editLastMessage(label: label, body: "Edited note.").get()
        let messages = try #require(try diskComments().first?.messages)
        #expect(messages.count == 1)
        #expect(messages.last?.avatar == "👤")
        #expect(messages.last?.author == "Tester")
        #expect(messages.last?.body == "Edited note.")
    }

    @Test func deleteLastMessageRemovesAnEmptiedComment() throws {
        let ctrl = controller()
        let label = try addComment(ctrl)
        try ctrl.reply(
            toLabel: label, author: "Someone", avatar: "🤖", body: "A reply."
        ).get()

        try ctrl.deleteLastMessage(label: label).get()
        #expect(try diskComments().first?.messages.count == 1)

        // Deleting the only remaining message removes the whole comment,
        // marker included.
        try ctrl.deleteLastMessage(label: label).get()
        #expect(try diskComments().isEmpty)
        let remaining = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!remaining.contains("[^\(label)]"))
    }

    @Test func deleteRemovesDefinitionAndMarker() throws {
        let ctrl = controller()
        let label = try addComment(ctrl)
        try ctrl.delete(label: label).get()
        #expect(try diskComments().isEmpty)
        let remaining = try String(contentsOf: fileURL, encoding: .utf8)
        #expect(!remaining.contains("[^\(label)]"))
        #expect(remaining.trimmingCharacters(in: .whitespacesAndNewlines)
            == Self.source)
    }

    @Test func successfulWritesReportTheirContent() throws {
        var reported: [String] = []
        let ctrl = controller(onWrite: { reported.append($0) })
        _ = try addComment(ctrl)
        #expect(reported.count == 1)
        #expect(reported.last
            == (try String(contentsOf: fileURL, encoding: .utf8)))
    }

    // MARK: Failure matrix

    @Test func mutationsOnAMissingLabelAreAnchorFailures() throws {
        let ctrl = controller()
        _ = try addComment(ctrl)
        for result in [
            ctrl.reply(
                toLabel: "comment-zz", author: "X", avatar: "👤", body: "b"),
            ctrl.editLastMessage(label: "comment-zz", body: "b"),
            ctrl.delete(label: "comment-zz"),
            ctrl.deleteLastMessage(label: "comment-zz"),
        ] {
            guard case .failure(let error) = result else {
                Issue.record("expected a failure for the missing label")
                continue
            }
            #expect(error == .anchorFailed)
        }
    }

    @Test func addOnAVanishedSelectionIsAnAnchorFailure() throws {
        // The paragraph the draft anchors to no longer exists on disk.
        try "Entirely different text.".write(
            to: fileURL, atomically: true, encoding: .utf8)
        let result = controller().addComment(
            Self.draft, author: "Tester", avatar: "👤", body: "A note.")
        guard case .failure(let error) = result else {
            Issue.record("expected a failure for the vanished selection")
            return
        }
        #expect(error == .anchorFailed)
    }

    @Test func mutationsOnAMissingFileAreWriteFailures() throws {
        let ctrl = controller()
        let label = try addComment(ctrl)
        try FileManager.default.removeItem(at: fileURL)
        let results: [Result<Void, CommentController.CommentWriteError>] = [
            ctrl.addComment(Self.draft, author: "T", avatar: "👤", body: "b")
                .map { _ in () },
            ctrl.reply(
                toLabel: label, author: "T", avatar: "👤", body: "b"),
            ctrl.editLastMessage(label: label, body: "b"),
            ctrl.delete(label: label),
            ctrl.deleteLastMessage(label: label),
        ]
        for result in results {
            guard case .failure(let error) = result else {
                Issue.record("expected a failure for the missing file")
                continue
            }
            #expect(error == .writeFailed)
        }
    }

    @Test func lockedFilesAreNotWritable() throws {
        let ctrl = controller()
        #expect(ctrl.isFileWritable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o444], ofItemAtPath: fileURL.path)
        #expect(!ctrl.isFileWritable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: fileURL.path)
    }
}
