import Markdown

/// A span in a word-level diff result.
enum WordSpan: Equatable {
    case unchanged(String)
    case inserted(String)
    case deleted(String)

    var text: String {
        switch self {
        case .unchanged(let t), .inserted(let t), .deleted(let t): return t
        }
    }

    var isUnchanged: Bool {
        if case .unchanged = self { return true } else { return false }
    }

    var isInserted: Bool {
        if case .inserted = self { return true } else { return false }
    }

    var isDeleted: Bool {
        if case .deleted = self { return true } else { return false }
    }

    /// Returns a new span of the same kind with different text.
    func withText(_ newText: String) -> WordSpan {
        switch self {
        case .unchanged: return .unchanged(newText)
        case .inserted:  return .inserted(newText)
        case .deleted:   return .deleted(newText)
        }
    }
}

/// Word-level diffing and inline structure comparison.
enum WordDiff {
    /// Fraction of the longer side (old or new) that is unchanged text.
    /// Returns 1.0 when both sides are empty.
    static func similarity(_ spans: [WordSpan]) -> Double {
        var unchangedLen = 0, deletedLen = 0, insertedLen = 0
        for span in spans {
            switch span {
            case .unchanged(let t): unchangedLen += t.count
            case .deleted(let t):   deletedLen += t.count
            case .inserted(let t):  insertedLen += t.count
            }
        }
        let total = max(unchangedLen + deletedLen,
                        unchangedLen + insertedLen)
        guard total > 0 else { return 1.0 }
        return Double(unchangedLen) / Double(total)
    }

    /// True when spans contain word-level changes worth highlighting.
    ///
    /// Returns `false` when all spans are unchanged (nothing to mark)
    /// or when similarity is below the threshold (too noisy to be
    /// useful).
    static func hasSignificantChanges(
        _ spans: [WordSpan], threshold: Double
    ) -> Bool {
        let hasChanges = spans.contains { !$0.isUnchanged }
        guard hasChanges else { return false }
        return similarity(spans) >= threshold
    }

    /// Computes a word-level diff between two plain-text strings.
    ///
    /// The diff operates on words only — whitespace is tracked as
    /// separators between words and emitted with the same type as
    /// its surrounding word. Within each gap between unchanged
    /// anchors, all deletions are emitted before all insertions
    /// (grouped style).
    ///
    /// Concatenating all non-deleted spans reproduces the new text;
    /// concatenating all non-inserted spans reproduces the old text.
    static func diff(old: String, new: String) -> [WordSpan] {
        // Preserve leading spaces/tabs as explicit spans so that
        // callers tracking position through the result (e.g. Down
        // mode's word-marker injection) stay aligned with the source
        // text. `extractWords` discards leading whitespace, which
        // otherwise causes every marker to shift left by the indent
        // width on indented list-item continuation lines and similar.
        let (oldLead, oldRest) = splitLeadingIndent(old)
        let (newLead, newRest) = splitLeadingIndent(new)

        var leadSpans: [WordSpan] = []
        if oldLead == newLead {
            if !oldLead.isEmpty {
                leadSpans.append(.unchanged(oldLead))
            }
        } else {
            if !oldLead.isEmpty { leadSpans.append(.deleted(oldLead)) }
            if !newLead.isEmpty { leadSpans.append(.inserted(newLead)) }
        }

        let oldParts = extractWords(tokenize(oldRest))
        let newParts = extractWords(tokenize(newRest))

        guard !oldParts.isEmpty || !newParts.isEmpty else {
            return leadSpans
        }
        if oldParts.isEmpty {
            return leadSpans
                + newParts.flatMap { emitWord($0, as: .inserted) }
        }
        if newParts.isEmpty {
            return leadSpans
                + oldParts.flatMap { emitWord($0, as: .deleted) }
        }

        // Diff on word content only (whitespace is not diffed).
        let cdiff = newParts.map(\.word)
            .difference(from: oldParts.map(\.word))

        var removedOld = Set<Int>()
        var insertedNew = Set<Int>()

        for change in cdiff {
            switch change {
            case .remove(let offset, _, _): removedOld.insert(offset)
            case .insert(let offset, _, _): insertedNew.insert(offset)
            }
        }

        // Find unchanged pairs (anchors).
        var anchors: [(old: Int, new: Int)] = []
        var oi = 0, ni = 0
        while oi < oldParts.count && ni < newParts.count {
            if removedOld.contains(oi) { oi += 1; continue }
            if insertedNew.contains(ni) { ni += 1; continue }
            anchors.append((old: oi, new: ni))
            oi += 1; ni += 1
        }

        // Build result: deletions before insertions within each gap.
        var result: [WordSpan] = leadSpans

        let boundaries =
            [(-1, -1)]
            + anchors.map { ($0.old, $0.new) }
            + [(oldParts.count, newParts.count)]

        for i in 0..<(boundaries.count - 1) {
            let (prevOld, prevNew) = boundaries[i]
            let (nextOld, nextNew) = boundaries[i + 1]

            let delIndices = ((prevOld + 1)..<nextOld)
                .filter { removedOld.contains($0) }
            let insIndices = ((prevNew + 1)..<nextNew)
                .filter { insertedNew.contains($0) }
            let hasAnchor = i + 1 < boundaries.count - 1

            // For substitution gaps (both del and ins), strip the
            // last separator from each group — it represents the
            // space before the anchor, emitted once as unchanged.
            // For pure del or pure ins, keep separators on the words
            // — the previous anchor's separator already provides the
            // space before this gap.
            let isSubstitution = !delIndices.isEmpty && !insIndices.isEmpty

            for (j, oi) in delIndices.enumerated() {
                let isLast = j == delIndices.count - 1
                if isLast && hasAnchor && isSubstitution {
                    result.append(.deleted(oldParts[oi].word))
                } else {
                    result += emitWord(oldParts[oi], as: .deleted)
                }
            }

            for (j, ni) in insIndices.enumerated() {
                let isLast = j == insIndices.count - 1
                if isLast && hasAnchor && isSubstitution {
                    result.append(.inserted(newParts[ni].word))
                } else {
                    result += emitWord(newParts[ni], as: .inserted)
                }
            }

            if hasAnchor {
                // Emit the transition separator as unchanged only
                // for substitution gaps. For pure del/ins the
                // preceding anchor separator covers it.
                if isSubstitution, let ni = insIndices.last {
                    let sep = newParts[ni].separator
                    if !sep.isEmpty {
                        result.append(.unchanged(sep))
                    }
                }

                result += emitWord(newParts[nextNew], as: .unchanged)

                // If the old anchor has more trailing whitespace
                // than the new (word moved from middle to end of
                // text), emit the excess as deleted.
                let oldSep = oldParts[nextOld].separator
                let newSep = newParts[nextNew].separator
                if oldSep.count > newSep.count {
                    result.append(.deleted(
                        String(oldSep.suffix(oldSep.count - newSep.count))
                    ))
                }
            }
        }

        return result
    }

    /// A word with its trailing whitespace separator.
    private struct WordPart {
        let word: String
        let separator: String
    }

    /// Extracts word+separator pairs from a token list.
    private static func extractWords(
        _ tokens: [String]
    ) -> [WordPart] {
        var parts: [WordPart] = []
        var i = 0
        while i < tokens.count {
            // Skip leading whitespace (rare in paragraph text).
            if tokens[i].allSatisfy(\.isWhitespace) { i += 1; continue }
            let word = tokens[i]
            i += 1
            let sep: String
            if i < tokens.count
                && tokens[i].allSatisfy(\.isWhitespace) {
                sep = tokens[i]
                i += 1
            } else {
                sep = ""
            }
            parts.append(WordPart(word: word, separator: sep))
        }
        return parts
    }

    /// Emits a word and its separator as spans of the given kind.
    private static func emitWord(
        _ part: WordPart, as kind: SpanKind
    ) -> [WordSpan] {
        var spans = [kind.span(part.word)]
        if !part.separator.isEmpty {
            spans.append(kind.span(part.separator))
        }
        return spans
    }

    private enum SpanKind {
        case unchanged, inserted, deleted

        func span(_ text: String) -> WordSpan {
            switch self {
            case .unchanged: return .unchanged(text)
            case .inserted:  return .inserted(text)
            case .deleted:   return .deleted(text)
            }
        }
    }

    // MARK: - Inline text extraction

    /// Extracts the inline text content of a markup node, matching
    /// the character sources the rendering visitor consumes:
    /// `Text.string`, `InlineCode.code`, SoftBreak → `" "`,
    /// LineBreak → `"\n"`, and recursion into formatting containers.
    ///
    /// This must be used instead of `plainText`, which includes
    /// backticks around InlineCode — causing a character count
    /// mismatch with the visitor.
    static func inlineText(of node: Markup) -> String {
        var result = ""
        for child in node.children {
            if let t = child as? Text {
                result += t.string
            } else if let c = child as? InlineCode {
                result += c.code
            } else if child is SoftBreak {
                result += " "
            } else if child is LineBreak {
                result += "\n"
            } else {
                result += inlineText(of: child)
            }
        }
        return result
    }

    /// `CMarkNode` counterpart of `inlineText(of:)` above — Stage 2 of
    /// Doc/Plans/2026-07-single-parser-rendering.md. Not wired to any
    /// caller yet: `ChangePlan` and `UpHTMLVisitor` still hand this function
    /// swift-markdown nodes until Stage 4 ports the diff layer onto cmark.
    static func inlineText(of node: CMarkNode) -> String {
        var result = ""
        for child in node.children {
            switch child.kind {
            case .text:
                result += child.literal ?? ""
            case .inlineCode:
                result += child.literal ?? ""
            case .softBreak:
                result += " "
            case .lineBreak:
                result += "\n"
            default:
                result += inlineText(of: child)
            }
        }
        return result
    }

    // MARK: - Tokenization

    /// Returns the run of leading spaces/tabs from `text` and the
    /// remainder. Newlines are not considered indent.
    private static func splitLeadingIndent(
        _ text: String
    ) -> (leading: String, rest: String) {
        var idx = text.startIndex
        while idx < text.endIndex,
              text[idx] == " " || text[idx] == "\t" {
            idx = text.index(after: idx)
        }
        if idx == text.startIndex { return ("", text) }
        return (String(text[..<idx]), String(text[idx...]))
    }

    /// Splits text into alternating word and whitespace tokens.
    /// For example, `"the quick fox"` becomes `["the", " ", "quick", " ", "fox"]`.
    ///
    /// Each token is either all non-whitespace (a word) or all
    /// whitespace (a separator). Concatenating all tokens reproduces
    /// the original text.
    static func tokenize(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        var tokens: [String] = []
        var current = ""
        var currentIsWhitespace = text.first!.isWhitespace

        for char in text {
            if char.isWhitespace == currentIsWhitespace {
                current.append(char)
            } else {
                tokens.append(current)
                current = String(char)
                currentIsWhitespace = char.isWhitespace
            }
        }

        if !current.isEmpty {
            tokens.append(current)
        }

        return tokens
    }
}
