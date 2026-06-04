import Foundation

/// Pure source rewriting for comments — no IO. Every edit is **byte-surgical**:
/// untouched bytes (line endings, trailing-newline state, indentation) are
/// preserved exactly, so diffs stay minimal and a concurrent agent edit outside
/// the edited span is never clobbered.
///
/// Locating existing definitions/references by label goes through
/// ``FootnoteProcessor/locateComments(_:)`` (a fresh `cmark-gfm` parse), so a
/// `[^comment-x]:` inside a code block is never mistaken for a real definition.
public enum CommentEditor {
    /// Inserts a new comment: splices the `[^label]` marker at `markerByteOffset`
    /// (the selection end, mapped to a source byte by the caller) and appends a
    /// canonical definition at the end of the document. Returns the rewritten
    /// source and the new `Comment` (its `ordinal` is assigned at render time).
    ///
    /// The DOM-point → source-byte mapping (walking the anchor block's inline
    /// nodes for the selection end) is the caller's responsibility; end-anchoring
    /// confines that mapping to this single point.
    public static func insert(
        into source: String, markerByteOffset: Int,
        quotation: String?, message: CommentMessage
    ) -> (source: String, comment: Comment) {
        let label = nextLabel(in: source)

        var bytes = Array(source.utf8)
        let clampedOffset = min(max(markerByteOffset, 0), bytes.count)
        bytes.insert(
            contentsOf: Array("[^\(label)]".utf8), at: clampedOffset)
        let withMarker = String(decoding: bytes, as: UTF8.self)

        let body = CommentSerialization.serialize(quotation: quotation, [message])
        let definition = "[^\(label)]:\n" + indentBody(body)
        let withDefinition = appendDefinition(definition, to: withMarker)

        let comment = Comment(
            label: label, ordinal: 0, quotation: quotation, messages: [message])
        return (withDefinition, comment)
    }

    /// Replaces the body of the `label` definition with a freshly serialized
    /// quotation + messages. Covers edit, reply (caller passes `existing +
    /// [newMessage]`), and removing one message of a thread. The marker and the
    /// quotation's anchor are untouched. A missing label leaves `source` as-is.
    public static func rewrite(
        _ source: String, label: String,
        quotation: String?, messages: [CommentMessage]
    ) -> String {
        guard let loc = FootnoteProcessor.locateComments(source)
            .first(where: { $0.label == label })
        else { return source }

        let body = CommentSerialization.serialize(quotation: quotation, messages)
        let rebuilt = "[^\(label)]:\n" + indentBody(body)

        var bytes = Array(source.utf8)
        bytes.replaceSubrange(
            loc.defStart..<loc.defContentEnd, with: Array(rebuilt.utf8))
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Removes a comment entirely — its definition (and trailing blank lines)
    /// plus every `[^label]` marker — leaving the label gap rather than
    /// renumbering later labels. A missing label leaves `source` as-is.
    public static func delete(_ source: String, label: String) -> String {
        guard let loc = FootnoteProcessor.locateComments(source)
            .first(where: { $0.label == label })
        else { return source }

        var ranges = loc.refRanges.map { ($0.lowerBound, $0.upperBound) }
        ranges.append((loc.defStart, loc.defDeleteEnd))

        var bytes = Array(source.utf8)
        for (start, end) in ranges.sorted(by: { $0.0 > $1.0 }) {
            bytes.removeSubrange(start..<end)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// The next label: `comment-` plus the lexicographically greatest existing
    /// *scheme-valid* suffix, incremented (last letter `z` ⇒ append `a`,
    /// otherwise bump it). Anomalous suffixes (`az`, `aa`, `comment-1`,
    /// `comment-foo`) are ignored as the basis, so they can neither lengthen nor
    /// misdirect the next label; the result exceeds every scheme-valid label and
    /// differs from every anomaly, so it can never collide.
    static func nextLabel(in source: String) -> String {
        guard let greatest = schemeValidSuffixes(in: source).max() else {
            return "comment-a"
        }
        return "comment-" + increment(greatest)
    }

    // MARK: - Labelling internals

    /// Scans `source` for `[^comment-<suffix>]` labels (references and
    /// definitions alike) and returns the suffixes that match the allocation
    /// scheme `^(z*[a-y]|z+)$`.
    static func schemeValidSuffixes(in source: String) -> [String] {
        let bytes = Array(source.utf8)
        let prefix = Array("[^comment-".utf8)
        var suffixes: [String] = []
        var i = 0
        while i + prefix.count <= bytes.count {
            guard Array(bytes[i..<i + prefix.count]) == prefix else { i += 1; continue }
            var j = i + prefix.count
            var suffix: [UInt8] = []
            while j < bytes.count, isLabelByte(bytes[j]) {
                suffix.append(bytes[j])
                j += 1
            }
            if j < bytes.count, bytes[j] == 0x5D, !suffix.isEmpty {  // ']'
                let s = String(decoding: suffix, as: UTF8.self)
                if isSchemeValid(s) { suffixes.append(s) }
            }
            i = max(j, i + 1)
        }
        return suffixes
    }

    /// A label-suffix byte: `[A-Za-z0-9_-]`.
    private static func isLabelByte(_ b: UInt8) -> Bool {
        (0x30...0x39).contains(b) || (0x41...0x5A).contains(b)
            || (0x61...0x7A).contains(b) || b == 0x5F || b == 0x2D
    }

    /// True when `s` is a suffix the scheme itself produces: `z*[a-y]` (zero or
    /// more `z` then one `a`–`y`) or `z+`.
    static func isSchemeValid(_ s: String) -> Bool {
        let chars = Array(s)
        guard !chars.isEmpty, chars.allSatisfy({ $0 >= "a" && $0 <= "z" })
        else { return false }
        if chars.allSatisfy({ $0 == "z" }) { return true }  // z+
        guard let last = chars.last, last >= "a", last <= "y" else { return false }
        return chars.dropLast().allSatisfy { $0 == "z" }  // z*[a-y]
    }

    /// Increments a scheme-valid suffix: a trailing `z` rolls over by appending
    /// `a` (`z` → `za`, `zz` → `zza`); otherwise the last letter bumps up
    /// (`a` → `b`, `zy` → `zz`).
    static func increment(_ s: String) -> String {
        var chars = Array(s)
        guard chars.last != "z" else { return s + "a" }
        let last = chars.removeLast()
        let bumped = UnicodeScalar(last.unicodeScalars.first!.value + 1)!
        chars.append(Character(bumped))
        return String(chars)
    }

    // MARK: - Layout internals

    /// Indents every line of a serialized body by four spaces (the GFM footnote
    /// continuation indent); blank lines stay empty.
    private static func indentBody(_ body: String) -> String {
        body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "    " + $0 }
            .joined(separator: "\n")
    }

    /// Appends a definition to `source` after exactly one blank line, normalizing
    /// any trailing newlines so the diff is a clean append.
    private static func appendDefinition(_ definition: String, to source: String)
        -> String
    {
        var trimmed = source
        while trimmed.hasSuffix("\n") { trimmed.removeLast() }
        guard !trimmed.isEmpty else { return definition + "\n" }
        return trimmed + "\n\n" + definition + "\n"
    }
}
