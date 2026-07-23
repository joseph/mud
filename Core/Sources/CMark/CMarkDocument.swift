import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Registers the GFM core syntax extensions exactly once for the whole module.
/// `ensure_registered` is idempotent but not guaranteed thread-safe on its
/// first call, so we gate it behind a lazily-initialized `let` (run-once,
/// thread-safe in Swift). Render can be driven from multiple threads (app,
/// Quick Look, CLI). Both parse sites — this wrapper and
/// `FootnoteProcessor.makeFootnoteParser` — reference this one token.
let registerGFMExtensions: Void = {
    cmark_gfm_core_extensions_ensure_registered()
}()

/// A position in a Markdown source: 1-based line, 1-based column counted in
/// **UTF-8 bytes** within the line — the same model as swift-markdown's
/// `SourceLocation`, which copies these fields from cmark unchanged.
struct CMarkSourceLocation: Equatable, Comparable, Sendable,
    CustomStringConvertible
{
    let line: Int
    let column: Int

    init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    static func < (lhs: CMarkSourceLocation, rhs: CMarkSourceLocation) -> Bool {
        lhs.line != rhs.line ? lhs.line < rhs.line : lhs.column < rhs.column
    }

    var description: String { "\(line):\(column)" }
}

/// An owning wrapper around one `cmark-gfm` parse — the parse every render
/// runs on (see Doc/Plans/Archive/2026-07-single-parser-rendering.md).
///
/// **Parse configuration is hard-coded** to the exact setup swift-markdown
/// 0.8.0 uses (its `Parser/CommonMarkConverter.swift`): options
/// `CMARK_OPT_SMART | CMARK_OPT_SOURCEPOS | CMARK_OPT_TABLE_SPANS` with the
/// `table`, `strikethrough`, and `tasklist` extensions attached — plus
/// `CMARK_OPT_FOOTNOTES`, the reason this wrapper exists. It is deliberately
/// not configurable: four subsystems (Up-mode text emission, word-span cursor
/// counts, heading slugs, `CommentAnchor.fold`) are calibrated to
/// smart-typographed text-node literals, and a caller-supplied option set
/// could silently break all four. `autolink` is deliberately **not** attached:
/// swift-markdown never attaches it, and turning it on is a separate,
/// user-visible decision to make after the port (see the plan's "Extension
/// parity" section).
///
/// The tree is a manually-freed C structure. The document owns the root
/// (freed in `deinit`) and every `CMarkNode` handle retains its document, so
/// a live handle can never outlive its tree — this is the safety-by-
/// construction the plan's "Node lifetime" section calls for.
final class CMarkDocument {
    /// The source exactly as parsed. No normalization happens here: byte
    /// ranges index into this string's UTF-8 view, so callers doing byte
    /// surgery must parse the same bytes they edit. (`ParsedMarkdown`
    /// normalizes CRLF *before* parsing; this class stays faithful to its
    /// input.)
    let source: String

    /// Byte/line geometry of `source`, shared with the range APIs below.
    let geometry: FootnoteProcessor.SourceGeometry

    private let rootPointer: UnsafeMutablePointer<cmark_node>

    /// The document node. Handles derived from it (children, siblings) all
    /// retain this document.
    var root: CMarkNode { CMarkNode(raw: rootPointer, document: self) }

    /// Parses `source`. Returns nil only when cmark fails to produce a tree
    /// (allocation failure — effectively never); callers supply their own
    /// fallback, as they do for `FootnoteProcessor.withFootnoteAST`.
    init?(parsing source: String) {
        _ = registerGFMExtensions
        let options = CMARK_OPT_SMART | CMARK_OPT_SOURCEPOS
            | CMARK_OPT_TABLE_SPANS | CMARK_OPT_FOOTNOTES
        guard let parser = cmark_parser_new(options) else { return nil }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "tasklist"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        let bytes = Array(source.utf8)
        if !bytes.isEmpty {
            bytes.withUnsafeBytes { raw in
                cmark_parser_feed(
                    parser, raw.bindMemory(to: CChar.self).baseAddress,
                    bytes.count)
            }
        }
        guard let root = cmark_parser_finish(parser) else { return nil }
        self.source = source
        self.geometry = FootnoteProcessor.SourceGeometry(bytes)
        self.rootPointer = root
    }

    deinit {
        cmark_node_free(rootPointer)
    }

    // MARK: - Ranges

    /// The node's source range in swift-markdown's conventions, reproducing
    /// its converter's `range(_:)` exactly so ported consumers keep their
    /// range math:
    ///
    /// - 1-based lines; 1-based UTF-8 **byte** columns within the line;
    /// - an **exclusive** upper bound (cmark's inclusive end column plus one);
    /// - inline code spans widened by their backtick count on both sides, so
    ///   the range includes the ticks (cmark's raw span covers only the
    ///   content between them).
    ///
    /// Returns nil when cmark tracked no start position for the node. The
    /// **end** is converted blindly — raw column plus one, no zero check —
    /// exactly as swift-markdown does, because a raw end column of 0 can be
    /// meaningful rather than untracked: a setext heading ends at (line after
    /// the underline, 0), which converts to an exclusive bound at that line's
    /// first byte. One deliberate divergence: an inverted position pair (end
    /// before start — a fully untracked end, or garbage sourcepos) returns
    /// nil instead of trapping in `Range.init`.
    func range(of node: CMarkNode) -> Range<CMarkSourceLocation>? {
        guard node.startLine > 0, node.startColumn > 0 else { return nil }
        let endColumn = node.endColumn + 1
        let backticks = node.backtickCount
        let lower = CMarkSourceLocation(
            line: node.startLine, column: node.startColumn - backticks)
        let upper = CMarkSourceLocation(
            line: node.endLine, column: endColumn + backticks)
        guard lower <= upper else { return nil }
        return lower..<upper
    }

    /// The node's range as a half-open byte range into `source`'s UTF-8
    /// bytes, bounds-checked against the real line/byte geometry. Returns nil
    /// when the node has no position or the position falls outside the
    /// source, so a caller can never index out of bounds off a bad sourcepos.
    func byteRange(of node: CMarkNode) -> Range<Int>? {
        guard let range = range(of: node) else { return nil }
        let lower = range.lowerBound
        let upper = range.upperBound
        guard lower.column >= 1, upper.column >= 1,
              lower.line <= geometry.lastLine, upper.line <= geometry.lastLine
        else { return nil }
        let start = geometry.offset(line: lower.line, column: lower.column)
        // `upper` is exclusive, so its offset is already one past the node's
        // last byte.
        let end = geometry.offset(line: upper.line, column: upper.column)
        guard start >= 0, end <= geometry.bytes.count, start <= end
        else { return nil }
        return start..<end
    }

    /// ``byteRange(of:)``, additionally verified against the raw source bytes
    /// before it can drive any byte surgery — the generalization of
    /// `FootnoteProcessor`'s `delimitsFootnoteRef` defense. cmark's position
    /// math has known inaccuracies (lazy continuation lines, entity
    /// references), so for node kinds with a fixed delimiter the sliced bytes
    /// must actually start and end with it; a mismatch returns nil and the
    /// caller falls back gracefully. Kinds without a checkable delimiter get
    /// the bounds check only.
    func verifiedRange(of node: CMarkNode) -> Range<Int>? {
        guard let range = byteRange(of: node) else { return nil }
        guard delimitersHold(node.kind, in: range) else { return nil }
        return range
    }

    /// True when the bytes in `range` carry the delimiters `kind` requires.
    private func delimitersHold(
        _ kind: CMarkNodeKind, in range: Range<Int>
    ) -> Bool {
        let bytes = geometry.bytes
        guard !range.isEmpty else {
            // Only kinds with no delimiter requirement may be empty.
            switch kind {
            case .footnoteReference, .inlineCode, .emphasis, .strong,
                 .strikethrough, .image, .link, .blockQuote:
                return false
            default:
                return true
            }
        }
        let first = bytes[range.lowerBound]
        let last = bytes[range.upperBound - 1]
        switch kind {
        case .footnoteReference:
            return geometry.delimitsFootnoteRef(
                start: range.lowerBound, end: range.upperBound)
        case .inlineCode:
            // The range includes the backticks (see `range(of:)`).
            return range.count >= 3 && first == 0x60 && last == 0x60
        case .emphasis:
            return range.count >= 3 && (first == 0x2A || first == 0x5F)
                && last == first
        case .strong:
            return range.count >= 5 && (first == 0x2A || first == 0x5F)
                && bytes[range.lowerBound + 1] == first
                && bytes[range.upperBound - 2] == first && last == first
        case .strikethrough:
            return range.count >= 3 && first == 0x7E && last == 0x7E
        case .image:
            return range.count >= 2 && first == 0x21
                && bytes[range.lowerBound + 1] == 0x5B
        case .link:
            // `[text](url)`, `[text][ref]` / `[shortcut]`, or `<autolink>`.
            return (first == 0x5B || first == 0x3C)
                && (last == 0x29 || last == 0x5D || last == 0x3E)
        case .blockQuote:
            return first == 0x3E
        default:
            return true
        }
    }
}

// @unchecked because of the raw tree pointer. Safe because the tree is never
// mutated after `init` and every cmark accessor the wrapper calls is a pure
// read — the same immutability argument as `ParsedMarkdown`. Renders can be
// driven from multiple threads (app, Quick Look, CLI).
extension CMarkDocument: @unchecked Sendable {}
