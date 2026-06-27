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
/// dispatched to `CommentController` by `DocumentContentView`. `.add` carries the
/// anchored `draft`; the others identify the comment by `label`.
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

    /// The outcome of `addComment`, distinguishing the two ways an add can fail.
    /// They look identical to the user but have different causes and fixes, and
    /// the old `nil` return conflated them: `anchorFailed` means the quoted text
    /// no longer maps to a source byte (it changed, or hit a mapping gap the
    /// anchor doesn't yet handle); `writeFailed` means the file itself couldn't
    /// be read or written (permission, lock, IO). Telling them apart lets the
    /// caller show an accurate message and lets us log distinctly.
    enum AddResult: Equatable {
        case added(label: String)
        case anchorFailed
        case writeFailed
    }

    /// Inserts a new comment anchored at the draft's selection end, carrying
    /// `body` as its first message. The marker lands at the quotation's end via
    /// `CommentAnchor`. Returns `.added(label:)` on success — the caller uses the
    /// label to place the live `💬` marker — or the reason it couldn't. v1 has no
    /// general-comment fallback for an anchor miss (a code block, or a structure
    /// the mapping doesn't handle).
    func addComment(_ draft: CommentDraft, author: String, body: String) -> AddResult {
        guard let source = readSource() else {
            NSLog("Mud: comment add failed; couldn't read the file.")
            return .writeFailed
        }
        guard let byteOffset = CommentAnchor.insertionOffset(
            in: source, blockText: draft.blockText,
            offsetInBlock: draft.offsetInBlock,
            occurrenceIndex: draft.occurrence)
        else {
            NSLog("Mud: comment add failed; the quoted text no longer matches "
                + "the source, so the marker couldn't be anchored.")
            return .anchorFailed
        }
        let message = CommentMessage(author: author, created: Date(), body: body)
        let result = CommentEditor.insert(
            into: source, markerByteOffset: byteOffset,
            quotation: draft.quotation, message: message)
        guard write(result.source) else { return .writeFailed }
        return .added(label: result.comment.label)
    }

    /// Appends a reply message to the `label` comment's thread, preserving its
    /// quotation and existing messages. Re-reads the current thread from disk so
    /// a concurrent external edit isn't lost.
    @discardableResult
    func reply(toLabel label: String, author: String, body: String) -> Bool {
        guard let source = readSource(),
              let comment = MudCore.parseComments(source)
                .first(where: { $0.label == label })
        else { return false }
        var messages = comment.messages
        messages.append(CommentMessage(author: author, created: Date(), body: body))
        return write(CommentEditor.rewrite(
            source, label: label, quotation: comment.quotation,
            messages: messages))
    }

    /// Replaces the body of the `label` comment's most recent message, keeping
    /// that message's author and timestamp (it is the same message, edited).
    @discardableResult
    func editLastMessage(label: String, body: String) -> Bool {
        guard let source = readSource(),
              let comment = MudCore.parseComments(source)
                .first(where: { $0.label == label }),
              let last = comment.messages.last
        else { return false }
        var messages = comment.messages
        messages[messages.count - 1] = CommentMessage(
            author: last.author, created: last.created, body: body)
        return write(CommentEditor.rewrite(
            source, label: label, quotation: comment.quotation,
            messages: messages))
    }

    /// Removes the `label` comment entirely — definition and every marker.
    @discardableResult
    func delete(label: String) -> Bool {
        guard let source = readSource() else { return false }
        return write(CommentEditor.delete(source, label: label))
    }

    /// Removes the most recent message from the `label` comment's thread. When it
    /// was the only message, the whole comment goes (a comment can't be empty).
    @discardableResult
    func deleteLastMessage(label: String) -> Bool {
        guard let source = readSource(),
              let comment = MudCore.parseComments(source)
                .first(where: { $0.label == label })
        else { return false }
        guard comment.messages.count > 1 else {
            return write(CommentEditor.delete(source, label: label))
        }
        var messages = comment.messages
        messages.removeLast()
        return write(CommentEditor.rewrite(
            source, label: label, quotation: comment.quotation,
            messages: messages))
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
