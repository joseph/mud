import Foundation
import MudCore

/// A pending comment draft: the Up-mode selection captured by the column write
/// JS and posted (inside a `.add` submission) over the `mudCommentSubmit` bridge.
struct CommentDraft {
    /// The selected text, whitespace-collapsed — the quotation.
    let quotation: String
    /// The rendered text of the block containing the selection end (used to
    /// locate the source block).
    let blockText: String
    /// Character offset of the selection end within `blockText`.
    let offsetInBlock: Int
    /// Which same-text block in document order the selection is in (disambiguates
    /// identical-text blocks).
    let occurrence: Int
}

/// A column edit posted from the page over the `mudCommentSubmit` bridge,
/// dispatched to `CommentController` by `CommentSubmissionHandler`. `.add`
/// carries the anchored `draft`; the others identify the comment by `label`.
struct CommentSubmission {
    enum Action: String { case add, reply, edit, delete }
    let action: Action
    let label: String?
    let body: String?
    let draft: CommentDraft?
}

/// Owns the document write path for comments: re-read from disk, byte-surgical
/// edit via `CommentEditor`, atomic write under security-scoped access. Reading
/// fresh from disk (never the possibly-stale in-memory render) keeps a
/// concurrent agent edit from being clobbered beyond the edited span; the
/// `FileWatcher` reload then re-renders with the new marker.
final class CommentController {
    let fileURL: URL

    /// Called with the exact content just written, on every successful write, so
    /// the caller can register a self-write and keep the file-watcher echo from
    /// being mistaken for an external edit.
    private let onWrite: ((String) -> Void)?

    init(fileURL: URL, onWrite: ((String) -> Void)? = nil) {
        self.fileURL = fileURL
        self.onWrite = onWrite
    }

    /// Whether the file should be treated as editable for comments. False when
    /// the user marked it read-only — either by clearing the POSIX write bit
    /// (`chmod`) or by locking it (Finder's Locked checkbox, i.e. the `uchg`
    /// user-immutable flag). Mud writes atomically (temp file + rename), which
    /// *can* replace a read-only file when its directory is writable — so without
    /// this check Mud would silently edit a file the user meant to protect. The
    /// caller refuses the edit when this is false.
    var isFileWritable: Bool {
        if let values = try? fileURL.resourceValues(forKeys: [.isUserImmutableKey]),
           values.isUserImmutable == true {
            return false
        }
        return FileManager.default.isWritableFile(atPath: fileURL.path)
    }

    /// Why a comment mutation failed. The two causes look identical to the user
    /// but have different fixes, so conflating them (as the old `Bool` returns
    /// did) shows a wrong diagnosis: `anchorFailed` means the comment no longer
    /// matches the source — an add's quoted text no longer maps to a source
    /// byte, or the label's definition is gone (changed or removed on disk
    /// while the box was open); `writeFailed` means the file itself couldn't be
    /// read or written (permission, lock, IO). Every mutation returns one of
    /// these, so the caller shows an accurate message for all four actions.
    enum CommentWriteError: Error, Equatable {
        case anchorFailed
        case writeFailed
    }

    /// Inserts a new comment anchored at the draft's selection end, carrying
    /// `body` as its first message. The marker lands at the quotation's end via
    /// `CommentAnchor`. Returns the new label on success — the caller uses it
    /// to place the live `💬` marker. v1 has no general-comment fallback for an
    /// anchor miss (a code block, or a structure the mapping doesn't handle).
    func addComment(
        _ draft: CommentDraft, author: String, avatar: String, body: String
    ) -> Result<String, CommentWriteError> {
        guard let source = readSource() else {
            NSLog("Mud: comment add failed; couldn't read the file.")
            return .failure(.writeFailed)
        }
        guard let byteOffset = CommentAnchor.insertionOffset(
            in: source, blockText: draft.blockText,
            offsetInBlock: draft.offsetInBlock,
            occurrenceIndex: draft.occurrence)
        else {
            // Log the locator the page sent so the next field report pinpoints
            // the block without a debugger (issue #5).
            NSLog("Mud: comment add failed; the quoted text no longer matches "
                + "the source, so the marker couldn't be anchored. "
                + "blockText=\(String(reflecting: draft.blockText)) "
                + "offsetInBlock=\(draft.offsetInBlock) "
                + "occurrence=\(draft.occurrence)")
            return .failure(.anchorFailed)
        }
        let message = CommentMessage(
            avatar: avatar, author: author, created: Date(), body: body)
        let result = CommentEditor.insert(
            into: source, markerByteOffset: byteOffset,
            quotation: draft.quotation, message: message)
        guard write(result.source) else { return .failure(.writeFailed) }
        return .success(result.comment.label)
    }

    /// Appends a reply message to the `label` comment's thread, preserving its
    /// quotation and existing messages. Re-reads the current thread from disk so
    /// a concurrent external edit isn't lost.
    @discardableResult
    func reply(
        toLabel label: String, author: String, avatar: String, body: String
    ) -> Result<Void, CommentWriteError> {
        guard let source = readSource() else { return .failure(.writeFailed) }
        guard let comment = MudCore.parseComments(source)
            .first(where: { $0.label == label })
        else { return .failure(.anchorFailed) }
        var messages = comment.messages
        messages.append(CommentMessage(
            avatar: avatar, author: author, created: Date(), body: body))
        return rewriteAndWrite(
            source, label: label, quotation: comment.quotation,
            messages: messages)
    }

    /// Replaces the body of the `label` comment's most recent message, keeping
    /// that message's avatar, author, and timestamp (it is the same message,
    /// edited).
    @discardableResult
    func editLastMessage(
        label: String, body: String
    ) -> Result<Void, CommentWriteError> {
        guard let source = readSource() else { return .failure(.writeFailed) }
        guard let comment = MudCore.parseComments(source)
            .first(where: { $0.label == label }),
            let last = comment.messages.last
        else { return .failure(.anchorFailed) }
        var messages = comment.messages
        messages[messages.count - 1] = CommentMessage(
            avatar: last.avatar, author: last.author, created: last.created,
            body: body)
        return rewriteAndWrite(
            source, label: label, quotation: comment.quotation,
            messages: messages)
    }

    /// Removes the `label` comment entirely — definition and every marker.
    @discardableResult
    func delete(label: String) -> Result<Void, CommentWriteError> {
        guard let source = readSource() else { return .failure(.writeFailed) }
        guard let deleted = CommentEditor.delete(source, label: label)
        else { return .failure(.anchorFailed) }
        guard write(deleted) else { return .failure(.writeFailed) }
        return .success(())
    }

    /// Removes the most recent message from the `label` comment's thread. When it
    /// was the only message, the whole comment goes (a comment can't be empty).
    @discardableResult
    func deleteLastMessage(label: String) -> Result<Void, CommentWriteError> {
        guard let source = readSource() else { return .failure(.writeFailed) }
        guard let comment = MudCore.parseComments(source)
            .first(where: { $0.label == label })
        else { return .failure(.anchorFailed) }
        guard comment.messages.count > 1 else {
            guard let deleted = CommentEditor.delete(source, label: label)
            else { return .failure(.anchorFailed) }
            guard write(deleted) else { return .failure(.writeFailed) }
            return .success(())
        }
        var messages = comment.messages
        messages.removeLast()
        return rewriteAndWrite(
            source, label: label, quotation: comment.quotation,
            messages: messages)
    }

    /// Rewrites the `label` definition and writes the result, telling a
    /// vanished label apart from a failed disk write.
    private func rewriteAndWrite(
        _ source: String, label: String,
        quotation: String?, messages: [CommentMessage]
    ) -> Result<Void, CommentWriteError> {
        guard let rewritten = CommentEditor.rewrite(
            source, label: label, quotation: quotation, messages: messages)
        else { return .failure(.anchorFailed) }
        guard write(rewritten) else { return .failure(.writeFailed) }
        return .success(())
    }

    // MARK: - IO

    private func readSource() -> String? {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            NSLog("Mud: comment read failed: \(diagnostics(error, scoped: scoped))")
            return nil
        }
    }

    /// Atomic write (temp file + rename) under security-scoped access — required
    /// for the sandboxed (MAS) build to write the user-opened file.
    private func write(_ contents: String) -> Bool {
        guard let data = contents.data(using: .utf8) else { return false }
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            try data.write(to: fileURL, options: .atomic)
            onWrite?(contents)
            return true
        } catch {
            NSLog("Mud: comment write failed: \(diagnostics(error, scoped: scoped))")
            return false
        }
    }

    /// One-line diagnostic for a read/write failure, enough to tell the causes
    /// apart without a debugger: a sandbox denial (`NSCocoaErrorDomain#513`,
    /// often `POSIX#13`/`#1`) vs a read-only volume (`#642`, `POSIX#30`) vs a
    /// non-UTF-8 file on read (`#261`). `scoped` is whether
    /// `startAccessingSecurityScopedResource` returned true — Mud holds no
    /// bookmark, so it's normally false and the write rides the live powerbox
    /// grant. The path shows where the file lives: an external, network, or
    /// iCloud location is itself a strong hint.
    private func diagnostics(_ error: Error, scoped: Bool) -> String {
        let ns = error as NSError
        var line = "sandboxed=\(isSandboxed) scoped=\(scoped) "
            + "error=\(ns.domain)#\(ns.code) (\(ns.localizedDescription))"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            line += " underlying=\(underlying.domain)#\(underlying.code)"
        }
        line += " path=\(fileURL.path)"
        return line
    }
}
