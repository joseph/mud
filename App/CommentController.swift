import Foundation
import MudCore

/// A pending comment draft captured from a Up-mode selection by
/// `mud-comments.js` and posted over the `mudCommentDraft` bridge.
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

    /// Inserts a new comment anchored at the draft's selection end, carrying
    /// `body` as its first message. The marker lands at the quotation's end via
    /// `CommentAnchor`. Returns the new comment's label on success — the caller
    /// uses it to place the live `[⋯]` marker — or nil when the selection can't
    /// be anchored (e.g. a code block, or a structure the mapping doesn't yet
    /// handle) or the write fails. v1 has no general-comment fallback.
    @discardableResult
    func addComment(_ draft: CommentDraft, author: String, body: String) -> String? {
        guard let source = readSource() else { return nil }
        guard let byteOffset = CommentAnchor.insertionOffset(
            in: source, blockText: draft.blockText,
            offsetInBlock: draft.offsetInBlock,
            occurrenceIndex: draft.occurrence)
        else {
            NSLog("Mud: could not anchor comment; skipping.")
            return nil
        }
        let message = CommentMessage(author: author, created: Date(), body: body)
        let result = CommentEditor.insert(
            into: source, markerByteOffset: byteOffset,
            quotation: draft.quotation, message: message)
        return write(result.source) ? result.comment.label : nil
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

    // MARK: - IO

    private func readSource() -> String? {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        return try? String(contentsOf: fileURL, encoding: .utf8)
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
            NSLog("Mud: comment write failed: \(error.localizedDescription)")
            return false
        }
    }
}
