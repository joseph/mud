import Foundation

/// Emits word-level diff markers (`<ins>`/`<del>`) in step with the
/// rendering visitor's character stream.
///
/// `CMarkUpHTMLVisitor` owns document structure: it walks a changed block's
/// inline nodes and reports each character run it renders (a text node's
/// literal, an inline-code literal, a break's single character). The emitter owns the
/// cursor through the block's `[WordSpan]`: it splits spans that straddle
/// an inline-node boundary and returns the HTML for exactly the characters
/// consumed. Consecutive spans of the same type share a single tag,
/// producing cleaner HTML (e.g., `<del>quick brown</del>` instead of
/// `<del>quick</del><del> </del><del>brown</del>`).
///
/// Correctness depends on the visitor's character counts matching
/// `WordDiff.inlineText(of:)` exactly — every consuming span was cut from
/// that text, so a count mismatch shears every following marker.
/// `WordSpanEmitterTests` pins the alignment and the emission rules.
struct WordSpanEmitter {

    /// Role determines which spans consume characters and how the
    /// others are handled.
    enum Role {
        /// Blue block (paired insertion): unchanged and inserted spans
        /// consume; deleted spans are emitted eagerly in `<del>` when
        /// `showInlineDeletions` is set, otherwise silently skipped.
        case insertion
        /// Red block (paired deletion): unchanged and deleted spans
        /// consume; inserted spans are always skipped.
        case deletion
    }

    private var spans: [WordSpan]
    private var cursor = 0
    private let role: Role
    private let showInlineDeletions: Bool

    /// Currently open inline tag (`<del>` or `<ins>`).
    private var openTag: Tag?

    private enum Tag {
        case del, ins

        var open: String {
            switch self {
            case .del: return "<del>"
            case .ins: return "<ins>"
            }
        }

        var close: String {
            switch self {
            case .del: return "</del>"
            case .ins: return "</ins>"
            }
        }
    }

    init(spans: [WordSpan], role: Role, showInlineDeletions: Bool) {
        self.spans = spans
        self.role = role
        self.showInlineDeletions = showInlineDeletions
    }

    /// Advances the cursor by `charCount` characters and returns the
    /// HTML to append.
    ///
    /// When `emit` is true (used by `visitText` and `visitInlineCode`),
    /// consuming spans are rendered. When false (used by `visitSoftBreak`
    /// and `visitLineBreak`), characters are consumed silently — the
    /// break's own HTML handles the visual whitespace.
    ///
    /// Non-consuming spans (deleted in blue mode, inserted in red mode)
    /// are always handled eagerly: emitted or skipped.
    /// If a consuming span is larger than the remaining character count,
    /// it is split and the remainder stays at the cursor.
    mutating func advance(by charCount: Int, emit: Bool) -> String {
        var out = ""
        var remaining = charCount

        while cursor < spans.count {
            let span = spans[cursor]

            // Non-consuming: deleted in blue, inserted in red.
            switch (span, role) {
            case (.deleted(let text), .insertion):
                if showInlineDeletions {
                    setTag(.del, into: &out)
                    out += Self.escape(text)
                }
                cursor += 1
                continue
            case (.inserted, .deletion):
                cursor += 1
                continue
            default:
                break
            }

            guard remaining > 0 else { return out }

            let text = span.text
            if text.count <= remaining {
                if emit { emitSpan(span, into: &out) }
                cursor += 1
                remaining -= text.count
            } else {
                let consumed = String(text.prefix(remaining))
                let rest = String(text.dropFirst(remaining))
                if emit { emitSpan(span.withText(consumed), into: &out) }
                spans[cursor] = span.withText(rest)
                return out
            }
        }
        return out
    }

    /// Advances the cursor past `charCount` consuming characters
    /// without emitting anything. Non-consuming spans within the
    /// prefix are silently skipped. Used to skip the tag prefix in
    /// aside rendering so non-consuming spans (deleted/inserted
    /// words) don't appear before the alert title.
    mutating func skipPrefix(charCount: Int) {
        var remaining = charCount
        while cursor < spans.count && remaining > 0 {
            let span = spans[cursor]

            // Non-consuming spans in the prefix: skip silently.
            switch (span, role) {
            case (.deleted, .insertion), (.inserted, .deletion):
                cursor += 1
                continue
            default:
                break
            }

            let text = span.text
            if text.count <= remaining {
                cursor += 1
                remaining -= text.count
            } else {
                spans[cursor] = span.withText(
                    String(text.dropFirst(remaining)))
                remaining = 0
            }
        }
    }

    /// Closes the currently open inline tag, if any, and returns its
    /// closing HTML. The visitor calls this at every inline-node
    /// boundary so a `<del>`/`<ins>` never spans the visitor's own
    /// formatting tags.
    mutating func closeOpenTag() -> String {
        guard let tag = openTag else { return "" }
        openTag = nil
        return tag.close
    }

    /// Emits any remaining non-consuming spans after the last text
    /// node and closes the open tag. Called once when the block ends.
    mutating func finish() -> String {
        var out = ""
        flush: while cursor < spans.count {
            switch (spans[cursor], role) {
            case (.deleted(let text), .insertion):
                if showInlineDeletions {
                    setTag(.del, into: &out)
                    out += Self.escape(text)
                }
                cursor += 1
            case (.inserted, .deletion):
                cursor += 1
            default:
                break flush
            }
        }
        out += closeOpenTag()
        return out
    }

    /// Sets the currently open inline tag, closing the previous one
    /// if needed. Consecutive same-type spans share a single tag.
    private mutating func setTag(_ tag: Tag?, into out: inout String) {
        guard tag != openTag else { return }
        if let openTag { out += openTag.close }
        if let tag { out += tag.open }
        openTag = tag
    }

    private mutating func emitSpan(_ span: WordSpan, into out: inout String) {
        switch span {
        case .unchanged: setTag(nil, into: &out)
        case .inserted:  setTag(.ins, into: &out)
        case .deleted:   setTag(.del, into: &out)
        }
        out += Self.escape(span.text)
    }

    private static func escape(_ text: String) -> String {
        HTMLEscaping.escape(EmojiShortcodes.replaceShortcodes(in: text))
    }
}
