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
/// **Parse configuration is hard-coded.** The render parse sets
/// `CMARK_OPT_SMART | CMARK_OPT_SOURCEPOS | CMARK_OPT_FOOTNOTES` and attaches
/// the `table`, `strikethrough`, `tasklist`, and `autolink` extensions.
/// `CMARK_OPT_FOOTNOTES` is the reason this wrapper exists; `autolink` renders
/// a bare URL or email as a link. It is deliberately not configurable: four
/// subsystems (Up-mode text emission, word-span cursor counts, heading slugs,
/// `CommentAnchor.fold`) are calibrated to smart-typographed text-node
/// literals, and a caller-supplied option set could silently break all four.
///
/// `CMARK_OPT_TABLE_SPANS` is deliberately **not** set. It computes MultiMarkdown
/// colspan/rowspan metadata on table cells, but Up-mode rendering emits each
/// cell as a plain `<td>`/`<th>` with alignment only (`UpHTMLVisitor`) and
/// never reads that metadata, and Down mode renders the raw source. So the
/// option produced no spanning tables — its one visible effect was to blank a
/// body cell whose entire text is `^` (the rowspan marker), which made a lone
/// caret in a table silently vanish. Dropping it keeps that caret literal.
///
/// This is not the only cmark parse in Core. A second, narrower one runs for
/// footnote and comment scanning (`FootnoteProcessor.makeFootnoteParser`):
/// `CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS`, with the same four extensions.
/// It locates `[^…]` references and definitions by source position and renders
/// nothing, so it drops `SMART`. That one flag is the only difference between
/// the two configurations; the divergence is intended, and only this parse
/// drives rendering.
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
    let geometry: SourceGeometry

    private let rootPointer: UnsafeMutablePointer<cmark_node>

    /// Line span and indentation of one footnote definition.
    private struct DefinitionGeometry {
        let startLine: Int
        let endLine: Int
        /// Byte width of the opener line's `[^label]: ` prefix — the content
        /// offset cmark fixes for the whole definition.
        let openerDrop: Int
        /// Shared continuation-line indent, capped at 4.
        let contentIndent: Int
    }

    /// Every footnote definition in the tree, in document order. Precomputed
    /// at parse so `range(of:)` can correct an inline's position without
    /// walking ancestors or rescanning the definition once per node — and so
    /// the tree stays immutable after parsing, which `@unchecked Sendable`
    /// depends on.
    private let definitions: [DefinitionGeometry]

    /// The document node. Handles derived from it (children, siblings) all
    /// retain this document.
    var root: CMarkNode { CMarkNode(raw: rootPointer, document: self) }

    /// Parses `source`. Returns nil only when cmark fails to produce a tree
    /// (allocation failure — effectively never); callers supply their own
    /// fallback, as they do for `FootnoteProcessor.withFootnoteAST`.
    init?(parsing source: String) {
        _ = registerGFMExtensions
        let options = CMARK_OPT_SMART | CMARK_OPT_SOURCEPOS
            | CMARK_OPT_FOOTNOTES
        guard let parser = cmark_parser_new(options) else { return nil }
        defer { cmark_parser_free(parser) }
        for name in ["table", "strikethrough", "tasklist", "autolink"] {
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
        let geometry = SourceGeometry(bytes)
        self.source = source
        self.geometry = geometry
        self.rootPointer = root
        self.definitions = Self.collectDefinitions(
            root: root, geometry: geometry)
    }

    /// Measures every footnote definition's line span and indentation in one
    /// pass. Walks raw cmark pointers rather than `CMarkNode` because it runs
    /// during `init`, before `self` exists for a node to retain.
    ///
    /// Sorted by start line on the way out, because the walk does **not**
    /// yield source order: cmark-gfm moves footnote definitions to the end of
    /// the document ordered by first reference, so a definition referenced
    /// early but written late comes first.
    private static func collectDefinitions(
        root: UnsafeMutablePointer<cmark_node>, geometry: SourceGeometry
    ) -> [DefinitionGeometry] {
        var result: [DefinitionGeometry] = []
        let iter = cmark_iter_new(root)
        defer { cmark_iter_free(iter) }
        while true {
            let event = cmark_iter_next(iter)
            if event == CMARK_EVENT_DONE { break }
            guard event == CMARK_EVENT_ENTER,
                  let node = cmark_iter_get_node(iter),
                  cmark_node_get_type(node) == CMARK_NODE_FOOTNOTE_DEFINITION
            else { continue }
            let startLine = Int(cmark_node_get_start_line(node))
            let endLine = Int(cmark_node_get_end_line(node))
            guard startLine >= 1, endLine >= startLine,
                  endLine <= geometry.lastLine
            else { continue }
            // cmark keeps the label as the definition's literal.
            let label = cmark_node_get_literal(node)
                .map { String(cString: $0) } ?? ""
            // `[^` + label + `]:` → the label's bytes plus four.
            let markerEnd = geometry.firstNonSpaceColumn(line: startLine)
                + label.utf8.count + 4
            let contentStart = geometry.firstContentColumn(
                line: startLine, from: markerEnd)
            result.append(DefinitionGeometry(
                startLine: startLine,
                endLine: endLine,
                openerDrop: contentStart - 1,
                contentIndent: geometry.continuationIndent(
                    startLine: startLine, endLine: endLine)))
        }
        return result.sorted { $0.startLine < $1.startLine }
    }

    deinit {
        cmark_node_free(rootPointer)
    }

    // MARK: - Ranges

    /// The node's source range, in these conventions:
    ///
    /// - 1-based lines; 1-based UTF-8 **byte** columns within the line;
    /// - an **exclusive** upper bound (cmark's inclusive end column plus one).
    ///
    /// The conventions came from swift-markdown's converter, which the ported
    /// consumers' range math was written against. That dependency is gone, so
    /// they now stand on their own — matching it is no longer a reason to keep
    /// a behavior, and the normalizations below already diverge from it.
    ///
    /// Three normalizations turn cmark's raw spans into the bytes a reader
    /// would point at:
    ///
    /// - inline code widens by its backtick count on both sides, so the range
    ///   includes the ticks (cmark's raw span covers only the content);
    /// - an inline inside a footnote or comment definition is corrected for
    ///   the prefix cmark stripped from its block's first line
    ///   (`correctInline`);
    /// - a link's start is moved past leading whitespace
    ///   (`trimmingLeadingWhitespace`).
    ///
    /// Returns nil when cmark tracked no start position — which includes email
    /// autolinks, for which the GFM extension records none at all. The **end**
    /// is converted blindly — raw column plus one, no zero check — because a
    /// raw end column of 0 can be meaningful rather than untracked: a setext
    /// heading ends at (line after the underline, 0), which converts to an
    /// exclusive bound at that line's first byte. An inverted position pair
    /// (end before start — a fully untracked end, or garbage sourcepos)
    /// returns nil instead of trapping in `Range.init`.
    func range(of node: CMarkNode) -> Range<CMarkSourceLocation>? {
        guard node.startLine > 0, node.startColumn > 0 else { return nil }
        let endColumn = node.endColumn + 1
        let backticks = node.backtickCount
        var lower = CMarkSourceLocation(
            line: node.startLine, column: node.startColumn - backticks)
        var upper = CMarkSourceLocation(
            line: node.endLine, column: endColumn + backticks)
        if node.kind.isInline, let body = definitionBody(of: node) {
            lower = correctInline(lower, in: body)
            upper = correctInline(upper, in: body)
        }
        // After `correctInline`, so the bytes it inspects are the ones the
        // location actually points at.
        if node.kind == .link {
            lower = trimmingLeadingWhitespace(lower, notPast: upper)
        }
        guard lower <= upper else { return nil }
        return lower..<upper
    }

    /// Moves a link's start past any leading space or tab.
    ///
    /// The GFM autolink extension begins its match at the boundary character
    /// before a bare URL, so `Visit https://example.org` reports a range that
    /// starts on the space. No link range legitimately begins with whitespace
    /// — a bracketed link starts at `[`, an angled autolink at `<`, and a bare
    /// autolink at its scheme — so trimming is safe for every link form.
    ///
    /// This fixes the shape we can observe. Whether the extension is also off
    /// by one after a non-space boundary (an opening paren, say) is pinned by
    /// `ParityCorpus.autolinkPositions` rather than assumed here.
    private func trimmingLeadingWhitespace(
        _ location: CMarkSourceLocation, notPast limit: CMarkSourceLocation
    ) -> CMarkSourceLocation {
        guard location.line >= 1, location.line <= geometry.lastLine
        else { return location }
        let end = geometry.contentEnd(location.line)
        var column = location.column
        while location.line < limit.line || column < limit.column {
            let offset = geometry.offset(line: location.line, column: column)
            guard offset >= 0, offset < end,
                  geometry.bytes[offset] == 0x20
                    || geometry.bytes[offset] == 0x09
            else { break }
            column += 1
        }
        return CMarkSourceLocation(line: location.line, column: column)
    }

    /// The footnote definition whose lines cover `line`, if any. Definitions
    /// are block-level and never overlap, and `definitions` is sorted by start
    /// line, so the scan can stop at the first one starting past `line`.
    private func definition(containing line: Int) -> DefinitionGeometry? {
        for definition in definitions {
            if line < definition.startLine { return nil }
            if line <= definition.endLine { return definition }
        }
        return nil
    }

    /// Where an inline sits for the purpose of correcting its column: the
    /// enclosing definition's geometry, and the first line of the leaf block
    /// holding the inline.
    private struct DefinitionBody {
        let definition: DefinitionGeometry
        let blockStartLine: Int
    }

    /// The definition body an inline belongs to, or nil if it isn't in one.
    ///
    /// Requires the inline's block to be a *direct* child of the definition. A
    /// block nested in a blockquote or list inside the definition carries that
    /// container's marker on every line too, a prefix this correction doesn't
    /// model, so those are left exactly as cmark reported them.
    private func definitionBody(of node: CMarkNode) -> DefinitionBody? {
        var block = node
        while block.kind.isInline {
            guard let parent = block.parent else { return nil }
            block = parent
        }
        guard block.parent?.kind == .footnoteDefinition, block.startLine >= 1,
              let definition = definition(containing: block.startLine)
        else { return nil }
        return DefinitionBody(
            definition: definition, blockStartLine: block.startLine)
    }

    /// Moves an inline position inside a definition body onto the raw source
    /// column it actually occupies.
    ///
    /// cmark derives an inline's position from its offset within the enclosing
    /// block's content, then adds back the prefix it stripped from that
    /// block's **first** line — on every line of the block. So the column is
    /// right on the block's first line and wrong on the rest by the difference
    /// between the two lines' prefixes.
    ///
    /// The anchor is the block's first line, not the definition's opener: a
    /// definition's later blocks (a comment thread's message paragraphs, say)
    /// begin on a continuation line, where the stripped prefix is already the
    /// plain indent and the correct adjustment is zero.
    ///
    /// Block positions come from the source line directly and are right on
    /// every line, which is why only `isInline` nodes are corrected.
    private func correctInline(
        _ location: CMarkSourceLocation, in body: DefinitionBody
    ) -> CMarkSourceLocation {
        let definition = body.definition
        guard location.line != body.blockStartLine,
              location.line >= definition.startLine,
              location.line <= definition.endLine
        else { return location }
        let correction = drop(line: location.line, in: definition)
            - drop(line: body.blockStartLine, in: definition)
        return CMarkSourceLocation(
            line: location.line,
            column: max(1, location.column + correction))
    }

    /// Bytes cmark strips from the front of `line` inside `definition`: the
    /// `[^label]: ` prefix on the opener line, the shared indent on the rest.
    private func drop(line: Int, in definition: DefinitionGeometry) -> Int {
        line == definition.startLine
            ? definition.openerDrop
            : geometry.leadingWhitespace(
                line: line, max: definition.contentIndent)
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
