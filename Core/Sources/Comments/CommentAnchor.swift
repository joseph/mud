import Foundation
import cmark_gfm

/// Maps a rendered-DOM selection end to a source UTF-8 byte offset, so a comment
/// marker can be written **exactly where the quoted text ends** — the single
/// DOM→source mapping the design needs (end-anchoring confines it to one point).
///
/// Parsing goes through cmark with footnotes enabled (the same AST
/// `FootnoteProcessor` uses), so a `[^label]` reference is a **zero-width** node
/// with a raw source position. That makes the rendered (marker-free) text align
/// with the source — the rendered marker glyph (`💬` / footnote number) has no
/// counterpart in the source — while the byte offsets stay in **raw** source
/// coordinates, ready for `CommentEditor.insert`. The JS side computes the block
/// text and offset with marker glyphs skipped, to match.
///
/// The selection's block is located by matching its whitespace-collapsed
/// rendered text; the offset is walked through the block's inline nodes by
/// rendered length. Emoji shortcodes are substituted on the way (the DOM shows
/// 🎉 where the source has `:tada:`), so a paragraph with shortcodes still
/// matches and the marker byte still maps back to the raw source without
/// splitting a shortcode. Inline code and breaks resolve to their start. Inside
/// a block quote the rendered text may be a **suffix** of the source paragraph
/// (a GFM alert / DocC aside title is split off and rewritten), so a suffix
/// match is accepted and the stripped title is skipped.
///
/// Returns nil only when **no block matches**. When the block matches but the
/// exact offset within it can't be resolved, it falls back to the block's end
/// rather than refusing — the marker still lands in the right paragraph.
public enum CommentAnchor {
    public static func insertionOffset(
        in source: String, blockText: String, offsetInBlock: Int,
        occurrenceIndex: Int = 0
    ) -> Int? {
        guard offsetInBlock >= 0, occurrenceIndex >= 0 else { return nil }
        let target = fold(collapse(blockText))
        guard !target.isEmpty else { return nil }

        let geo = FootnoteProcessor.SourceGeometry(Array(source.utf8))
        let result: Int?? = FootnoteProcessor.withFootnoteAST(geo.bytes) { root in
            // Match the innermost *leaf* block (paragraph, heading, table cell) —
            // not the top-level container — so a selection inside a list item,
            // blockquote, or table cell resolves against the block whose text it
            // actually shares. `occurrenceIndex` disambiguates identical-text
            // blocks (the JS side counts the same way over the rendered body).
            // Blocks inside footnote/comment definitions are skipped: those are
            // the hidden bottom section, never the selection's source.
            let iter = cmark_iter_new(root)
            defer { cmark_iter_free(iter) }
            var inDefinition = 0
            var inBlockQuote = 0
            var matchIndex = 0
            while true {
                let event = cmark_iter_next(iter)
                if event == CMARK_EVENT_DONE { break }
                guard let node = cmark_iter_get_node(iter) else { continue }
                let type = cmark_node_get_type(node)
                if type == CMARK_NODE_FOOTNOTE_DEFINITION {
                    if event == CMARK_EVENT_ENTER { inDefinition += 1 }
                    else if event == CMARK_EVENT_EXIT { inDefinition -= 1 }
                    continue
                }
                if type == CMARK_NODE_BLOCK_QUOTE {
                    if event == CMARK_EVENT_ENTER { inBlockQuote += 1 }
                    else if event == CMARK_EVENT_EXIT { inBlockQuote -= 1 }
                    continue
                }
                guard event == CMARK_EVENT_ENTER, inDefinition == 0,
                      isLeafBlock(node) else { continue }
                // A GFM alert / DocC aside renders its title (`[!NOTE]`, `Note:`)
                // as a *separate* leading paragraph that the renderer rewrites, so
                // the rendered body is only a **suffix** of cmark's paragraph. In a
                // block quote, accept that suffix and skip the stripped title when
                // resolving the offset; elsewhere require an exact match.
                let full = fold(collapse(inlineText(of: node)))
                var prefixLen = 0
                if full != target {
                    guard inBlockQuote > 0, full.count > target.count,
                          full.hasSuffix(target) else { continue }
                    prefixLen = full.count - target.count
                }
                if matchIndex == occurrenceIndex {
                    var remaining = offsetInBlock + prefixLen
                    if let byte = resolveByte(
                        in: node, remaining: &remaining, geo: geo) {
                        return byte
                    }
                    // The block matched but the offset couldn't be pinned down
                    // (an offset past the block's text, or a rendered/source
                    // length gap). Degrade rather than refuse: anchor at the
                    // block's end so the marker still lands in this paragraph.
                    return endByte(of: node, geo: geo)
                        ?? startByte(of: node, geo: geo)
                }
                matchIndex += 1
            }
            return nil
        }
        return result ?? nil
    }

    // MARK: - cmark walk

    /// A block whose children are inline content (so its text can be matched and
    /// walked): a paragraph, a heading, or a GFM table cell. Code blocks are
    /// excluded — a `[^label]` written into one would not render as a marker.
    private static func isLeafBlock(_ node: UnsafeMutablePointer<cmark_node>) -> Bool {
        switch cmark_node_get_type(node) {
        case CMARK_NODE_PARAGRAPH, CMARK_NODE_HEADING:
            return true
        default:
            return String(cString: cmark_node_get_type_string(node)) == "table_cell"
        }
    }

    /// The rendered text of a node's inline content: `Text`/`Code` literals
    /// (emoji shortcodes substituted in `Text`), breaks → a space, footnote/
    /// comment references and images skipped (a footnote renders as a marker, an
    /// image as `<img>` — neither adds to the DOM's `textContent`). Mirrors the
    /// DOM's marker-free `textContent`.
    private static func inlineText(of node: UnsafeMutablePointer<cmark_node>) -> String {
        var text = ""
        var child = cmark_node_first_child(node)
        while let current = child {
            switch cmark_node_get_type(current) {
            case CMARK_NODE_TEXT:
                // Mirror the DOM: emoji shortcodes are substituted in rendered
                // text, so the match (and the offset walk below) count 🎉, not
                // `:tada:`. Inline code is left literal (it isn't substituted).
                if let literal = cmark_node_get_literal(current) {
                    text += EmojiShortcodes.replaceShortcodes(
                        in: String(cString: literal))
                }
            case CMARK_NODE_CODE:
                if let literal = cmark_node_get_literal(current) {
                    text += String(cString: literal)
                }
            case CMARK_NODE_SOFTBREAK, CMARK_NODE_LINEBREAK:
                text += " "
            case CMARK_NODE_FOOTNOTE_REFERENCE:
                break  // zero-width: rendered as a marker
            case CMARK_NODE_IMAGE:
                break  // cmark holds the alt as child text, but the DOM's <img>
                       // adds nothing to textContent — skip it to match.
            default:
                text += inlineText(of: current)  // emphasis, strong, link, …
            }
            child = cmark_node_next(current)
        }
        return text
    }

    /// Walks `node`'s inline content in the same order as ``inlineText(of:)``,
    /// decrementing `remaining` by each node's rendered length until the offset
    /// falls inside one — then resolves to a source byte.
    private static func resolveByte(
        in node: UnsafeMutablePointer<cmark_node>, remaining: inout Int,
        geo: FootnoteProcessor.SourceGeometry
    ) -> Int? {
        var child = cmark_node_first_child(node)
        while let current = child {
            let type = cmark_node_get_type(current)
            switch type {
            case CMARK_NODE_TEXT:
                let literal = cmark_node_get_literal(current)
                    .map { String(cString: $0) } ?? ""
                // `remaining` counts rendered characters (emoji substituted), so
                // measure and step by the rendered length, then map the offset
                // back to a raw byte without splitting a shortcode.
                let renderedCount = EmojiShortcodes
                    .replaceShortcodes(in: literal).count
                if remaining <= renderedCount {
                    guard let base = startByte(of: current, geo: geo)
                    else { return nil }
                    let rawChars = EmojiShortcodes.rawOffset(
                        forRendered: remaining, in: literal)
                    return base + String(literal.prefix(rawChars)).utf8.count
                }
                remaining -= renderedCount
            case CMARK_NODE_CODE:
                let literal = cmark_node_get_literal(current)
                    .map { String(cString: $0) } ?? ""
                if remaining <= literal.count {
                    // Inline code: cmark's span covers the content *between* the
                    // backtick runs, so walk past the trailing backticks to land
                    // after the whole span (inserting inside would break it).
                    guard var byte = endByte(of: current, geo: geo) else { return nil }
                    while byte < geo.bytes.count, geo.bytes[byte] == 0x60 { byte += 1 }
                    return byte
                }
                remaining -= literal.count
            case CMARK_NODE_SOFTBREAK, CMARK_NODE_LINEBREAK:
                if remaining <= 1 { return startByte(of: current, geo: geo) }
                remaining -= 1
            case CMARK_NODE_FOOTNOTE_REFERENCE:
                break  // zero-width
            case CMARK_NODE_IMAGE:
                break  // no rendered text (see inlineText): don't walk its alt
            default:
                if let found = resolveByte(
                    in: current, remaining: &remaining, geo: geo) {
                    return found
                }
            }
            child = cmark_node_next(current)
        }
        return nil
    }

    /// The source byte of a node's start position (1-based line/column → byte).
    private static func startByte(
        of node: UnsafeMutablePointer<cmark_node>,
        geo: FootnoteProcessor.SourceGeometry
    ) -> Int? {
        let line = Int(cmark_node_get_start_line(node))
        let column = Int(cmark_node_get_start_column(node))
        guard line >= 1, line <= geo.lastLine, column >= 1 else { return nil }
        return geo.offset(line: line, column: column)
    }

    /// The source byte just past a node's end (1-based end line/column → byte).
    private static func endByte(
        of node: UnsafeMutablePointer<cmark_node>,
        geo: FootnoteProcessor.SourceGeometry
    ) -> Int? {
        let line = Int(cmark_node_get_end_line(node))
        let column = Int(cmark_node_get_end_column(node))
        guard line >= 1, line <= geo.lastLine, column >= 1 else { return nil }
        return geo.offset(line: line, column: column) + 1
    }

    private static func collapse(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Folds smart typography back to its ASCII source form so the rendered,
    /// smart-quoted block text matches cmark's raw-source text.
    /// Quotes and apostrophes are length-preserving, so the byte walk over the
    /// raw literals stays aligned; dashes and ellipses change length, so an
    /// offset *past* one of those characters can drift by a char or two (rare;
    /// the block still matches and anchors).
    private static func fold(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text {
            switch ch {
            case "\u{201C}", "\u{201D}", "\u{201E}", "\u{201F}": out += "\""
            case "\u{2018}", "\u{2019}", "\u{201A}", "\u{201B}": out += "'"
            case "\u{2013}": out += "--"   // en dash (from `--`)
            case "\u{2014}": out += "---"  // em dash (from `---`)
            case "\u{2026}": out += "..."  // ellipsis (from `...`)
            default: out.append(ch)
            }
        }
        return out
    }
}
