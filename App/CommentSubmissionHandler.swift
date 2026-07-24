import AppKit
import Combine

/// Routes a column edit posted from the page (`CommentSubmission`, over the
/// `mudCommentSubmit` bridge) to `CommentController`, then acknowledges the
/// outcome back to the page (`resolveCompose`). On success the write echoes
/// through the `FileWatcher`, refreshing the comment data so the column
/// reprojects in place (no reload). On failure the box stays open with its
/// text and an alert explains why (the most likely cause is the quoted text
/// changing on disk while the box was held open).
struct CommentSubmissionHandler {
    let model: DocumentModel
    let state: DocumentState

    func handle(_ submission: CommentSubmission) {
        let controller = CommentController(fileURL: model.fileURL) {
            model.registerSelfWrite($0)
        }
        let author = AppState.shared.commentAuthor
        let body = submission.body ?? ""
        // Respect a read-only or locked file: refuse every comment edit with a
        // clear message rather than atomically replacing a file the user marked
        // protected (an atomic write can replace a read-only file whose directory
        // is writable, so without this guard Mud would silently edit it).
        guard controller.isFileWritable else {
            if submission.action != .delete {
                resolveCompose(false, reason: "Cannot save: this file is read-only.")
            }
            presentCommentFailure(message: readOnlyFailureMessage, note: body)
            return
        }
        switch submission.action {
        case .add:
            guard let draft = submission.draft else { resolveCompose(false); return }
            switch controller.addComment(draft, author: author, body: body) {
            case .success(let label):
                model.pendingCommentLocators[label] = CommentLocator(
                    blockText: draft.blockText, offset: draft.offsetInBlock,
                    occurrence: draft.occurrence)
                resolveCompose(true)
            case .failure(.anchorFailed):
                resolveCompose(false, reason: "Cannot save: the highlighted text couldn't be matched.")
                presentCommentFailure(message: anchorFailureMessage, note: body)
            case .failure(.writeFailed):
                resolveCompose(false, reason: "Cannot save: Mud couldn't write to the file.")
                presentCommentFailure(message: writeFailureMessage, note: body)
            }
        case .reply:
            guard let label = submission.label else { resolveCompose(false); return }
            resolveThreadEdit(
                controller.reply(toLabel: label, author: author, body: body),
                note: body)
        case .edit:
            guard let label = submission.label else { resolveCompose(false); return }
            resolveThreadEdit(
                controller.editLastMessage(label: label, body: body),
                note: body)
        case .delete:
            guard let label = submission.label else { return }
            // No compose box to resolve. A vanished label means the comment is
            // already gone — the watcher reload catches the column up, so only
            // a failed disk write is worth an alert.
            if case .failure(.writeFailed) =
                controller.deleteLastMessage(label: label) {
                presentCommentFailure(message: deleteFailureMessage, note: "")
            }
        }
    }

    /// Acknowledges a reply/edit outcome to the page and, on failure, explains
    /// the actual cause: the comment vanishing from disk and the file refusing
    /// the write need different fixes, so they get different messages.
    private func resolveThreadEdit(
        _ result: Result<Void, CommentController.CommentWriteError>,
        note: String
    ) {
        switch result {
        case .success:
            resolveCompose(true)
        case .failure(.anchorFailed):
            resolveCompose(false, reason: "Cannot save: the comment has changed.")
            presentCommentFailure(message: replyFailureMessage, note: note)
        case .failure(.writeFailed):
            resolveCompose(false, reason: "Cannot save: Mud couldn't write to the file.")
            presentCommentFailure(message: writeFailureMessage, note: note)
        }
    }

    private var replyFailureMessage: String {
        "The comment has changed or been removed, "
            + "so your text couldn't be saved. It is still in the compose box."
    }

    /// The file is read-only or locked: Mud leaves it untouched and says so,
    /// rather than atomically replacing a file the user meant to protect.
    private var readOnlyFailureMessage: String {
        "This file is read-only, so Mud didn't change it. "
            + "Make it writable to add comments."
    }

    /// The marker couldn't be anchored: Mud couldn't match the quoted text to a
    /// spot in the source. Two honest possibilities — the file changed on disk,
    /// or the text is somewhere Mud can't yet anchor a comment — rather than
    /// asserting the file changed (issue #5: nothing had changed, and the old
    /// copy sent both reporter and maintainer chasing file permissions).
    private var anchorFailureMessage: String {
        "Mud couldn't match the highlighted text to the file on disk. The file "
            + "may have changed since it was loaded, or this text may be in a "
            + "spot Mud can't anchor a comment to yet. Your note is still in the "
            + "compose box."
    }

    /// The file itself couldn't be written (permission, lock, or another IO
    /// problem) — distinct from the text moving.
    private var writeFailureMessage: String {
        "Mud couldn't write to this file, so the comment couldn't be saved. "
            + "Check that the file is writable and not locked. "
            + "Your note is still in the compose box."
    }

    /// A delete that failed at the disk: there is no compose box to keep the
    /// text in, so this is the only signal the user gets.
    private var deleteFailureMessage: String {
        "Mud couldn't write to this file, so the comment couldn't be deleted. "
            + "Check that the file is writable and not locked."
    }

    /// Pushes the submit outcome to the page, so the compose box closes
    /// (success) or re-enables (failure). On failure, `reason` is the short
    /// note shown inside the box.
    private func resolveCompose(_ success: Bool, reason: String? = nil) {
        state.webCommands.send(.resolveCompose(success: success, reason: reason))
    }

    /// Explains a comment write that couldn't be completed, keeping the user's
    /// text recoverable: the box stays open (the page re-enables it on the false
    /// resolve) and "Copy Note" puts the body on the clipboard. Deferred past the
    /// current run loop so the `resolveCompose` JS reaches the page — and
    /// re-enables the box — before this modal blocks the main thread.
    private func presentCommentFailure(message: String, note: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Couldn't save your comment"
            alert.informativeText = message
            alert.addButton(withTitle: "OK")
            if !note.isEmpty { alert.addButton(withTitle: "Copy Note") }
            let response = alert.runModal()
            if !note.isEmpty, response == .alertSecondButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(note, forType: .string)
            }
        }
    }
}
