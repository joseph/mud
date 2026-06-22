import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Registers the GFM core syntax extensions exactly once. `ensure_registered`
/// is idempotent but not guaranteed thread-safe on its first call, so we gate
/// it behind a lazily-initialized `let` (run-once, thread-safe in Swift).
/// Render can be driven from multiple threads (app, Quick Look, CLI).
private let registerGFMExtensions: Void = {
    cmark_gfm_core_extensions_ensure_registered()
}()

/// Where footnotes go in the rendered output.
///
/// - `.section`: emit only the bottom `<section class="footnotes">` (the
///   export / browser / CLI / Quick Look default; native anchor jumps work).
/// - `.popover`: also emit the section but mark it `is-print-only` so it is
///   hidden on screen and reappears under `@media print`; the live app shows
///   footnote bodies in an `NSPopover` instead.
public enum FootnoteMode: String, Sendable, Equatable {
    case popover
    case section
}

/// A resolved footnote: its label, its 1-based number (first-reference order),
/// and its body as clean Markdown ready to render.
public struct FootnoteEntry: Sendable, Equatable {
    public let label: String         // "1", "named", "long-name", …
    public let number: Int           // 1-based, first-reference order
    public let bodyMarkdown: String  // clean, de-indented CommonMark

    public init(label: String, number: Int, bodyMarkdown: String) {
        self.label = label
        self.number = number
        self.bodyMarkdown = bodyMarkdown
    }
}

/// The product of preprocessing a Markdown source for footnotes: the source
/// with references rewritten to inline-HTML markers and definitions removed,
/// plus the collected footnote entries.
struct FootnoteProcessingResult {
    let transformedMarkdown: String
    let footnotes: [FootnoteEntry]
    let comments: [Comment]
}

/// Detects GFM footnotes by parsing the raw source with `cmark-gfm`
/// (`CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS`), then **rewrites the source**
/// for the `swift-markdown` pipeline rather than teaching that pipeline about
/// footnotes:
///
/// - each `[^label]` reference to a *defined* label is replaced, by source
///   byte range, with an inline-HTML `<sup class="footnote-ref">…</sup>` marker
///   (swift-markdown passes inline HTML straight through);
/// - each definition block is deleted from the source;
/// - footnote bodies are returned as clean Markdown (rendered per child block
///   so the `[^label]:` prefix and continuation indentation are dropped).
///
/// Because cmark does the detection, every "should NOT be a footnote" case
/// (refs in code spans / fenced blocks, escaped `\[^1\]`, empty `[^]`,
/// whitespace labels) and every dangling `[^missing]` is handled for free:
/// they never become reference nodes, so their literal text survives untouched.
/// Structural footnote positions for Down-mode syntax highlighting. Unlike
/// ``FootnoteProcessor/process(_:mode:)``, this rewrites nothing — Down mode
/// shows the raw source verbatim and only needs to know *where* the references
/// and definitions live (by line and 1-based column) to drive highlighting.
struct FootnoteLayout {
    /// A `[^label]` reference occurrence. `endColumn` is the column of the
    /// closing `]`.
    struct Ref {
        let line: Int
        let startColumn: Int
        let endColumn: Int
    }

    /// A `[^label]:` definition block.
    struct Def {
        let startLine: Int
        let endLine: Int
        /// Column of the opening `[`.
        let startColumn: Int
        /// Column one past the `:` that closes the marker.
        let markerEndColumn: Int
        /// First body byte on the opener line (equals `markerEndColumn` when
        /// the opener carries no inline content).
        let contentStartColumn: Int
        /// Leading whitespace shared by the continuation lines — the indent
        /// `cmark` strips from the body, re-stripped before re-parsing. Capped
        /// at the GFM footnote content indent (4).
        let contentIndent: Int
    }

    let refs: [Ref]
    let defs: [Def]

    static let empty = FootnoteLayout(refs: [], defs: [])
}

/// The byte geometry of a single comment (a footnote whose label matches
/// `^comment-[\w-]+$`), used by ``CommentEditor`` for byte-surgical rewrites.
struct CommentLocation {
    let label: String
    /// Start byte of the definition's opener line (`[^label]:`).
    let defStart: Int
    /// End byte of the definition body's last line, before its newline — the
    /// span ``CommentEditor/rewrite(_:label:quotation:messages:)`` replaces.
    let defContentEnd: Int
    /// End byte past the definition block *and* its trailing blank lines — the
    /// span ``CommentEditor/delete(_:label:)`` removes.
    let defDeleteEnd: Int
    /// Byte ranges of each `[^label]` reference marker.
    let refRanges: [Range<Int>]
}

enum FootnoteProcessor {
    /// True when `label` is a comment label (`^comment-[\w-]+$`) rather than an
    /// authorial footnote label. The `comment-` prefix is the statement of
    /// intent; the suffix is any run of word characters or hyphens.
    static func isCommentLabel(_ label: String) -> Bool {
        let prefix = "comment-"
        guard label.hasPrefix(prefix) else { return false }
        let suffix = label.dropFirst(prefix.count)
        guard !suffix.isEmpty else { return false }
        return suffix.allSatisfy {
            $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-"
        }
    }

    /// Creates a `cmark-gfm` parser configured for footnote detection
    /// (`CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS`) with the GFM syntax
    /// extensions attached. The caller owns the lifecycle
    /// (`cmark_parser_free`).
    private static func makeFootnoteParser()
        -> UnsafeMutablePointer<cmark_parser>?
    {
        _ = registerGFMExtensions
        let options = CMARK_OPT_FOOTNOTES | CMARK_OPT_SOURCEPOS
        guard let parser = cmark_parser_new(options) else { return nil }
        for name in ["strikethrough", "table", "tasklist", "autolink"] {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }
        return parser
    }

    /// Byte/line geometry of a UTF-8 Markdown source, shared by ``process``,
    /// ``scan``, and ``CommentAnchor``. `lineStart[L]` is the 1-based byte
    /// offset of line `L`'s first byte, valid for `L` in `1...lastLine`.
    struct SourceGeometry {
        let bytes: [UInt8]
        let lineStart: [Int]
        let lastLine: Int

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
            var starts = [0, 0]
            for i in bytes.indices where bytes[i] == 0x0A { starts.append(i + 1) }
            self.lineStart = starts
            self.lastLine = starts.count - 1
        }

        /// Byte offset of a 1-based (line, column) position.
        func offset(line: Int, column: Int) -> Int {
            lineStart[line] + column - 1
        }

        /// Byte offset one past the last byte of `line` (start of the next
        /// line, or end of input on the last line).
        func lineEnd(_ line: Int) -> Int {
            line + 1 <= lastLine ? lineStart[line + 1] : bytes.count
        }

        /// Byte offset of the end of `line`'s content, before its terminating
        /// `\n` / `\r` (equals `lineEnd` on the last, unterminated line).
        func contentEnd(_ line: Int) -> Int {
            var e = lineEnd(line)
            while e > lineStart[line], bytes[e - 1] == 0x0A || bytes[e - 1] == 0x0D {
                e -= 1
            }
            return e
        }

        func lineIsBlank(_ line: Int) -> Bool {
            for i in lineStart[line]..<lineEnd(line) {
                let c = bytes[i]
                if c != 0x20 && c != 0x09 && c != 0x0A && c != 0x0D {
                    return false
                }
            }
            return true
        }

        /// A continuation line for a definition: empty, or indented.
        func isContinuation(_ line: Int) -> Bool {
            let s = lineStart[line]
            if s >= lineEnd(line) { return true }
            let c = bytes[s]
            return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D
        }

        /// True when the half-open byte range `[start, end)` actually delimits
        /// a `[^…]` token. Guards against any sourcepos/column miscalculation
        /// corrupting text or mis-driving highlighting.
        func delimitsFootnoteRef(start: Int, end: Int) -> Bool {
            start >= 0 && end <= bytes.count && start + 2 <= end
                && bytes[start] == 0x5B && bytes[start + 1] == 0x5E
                && bytes[end - 1] == 0x5D
        }

        /// Column (1-based) of the first non-whitespace byte on `line` — the
        /// `[` of a definition opener, after any leading indent.
        func firstNonSpaceColumn(line: Int) -> Int {
            var col = 1
            var i = lineStart[line]
            let end = lineEnd(line)
            while i < end {
                let c = bytes[i]
                if c == 0x0A || c == 0x0D { break }
                if c != 0x20 && c != 0x09 { return col }
                col += 1
                i += 1
            }
            return col
        }

        /// First non-whitespace column on `line` at or after `from` (1-based);
        /// returns `from` when the rest of the line is blank.
        func firstContentColumn(line: Int, from: Int) -> Int {
            var col = from
            var i = lineStart[line] + from - 1
            let end = lineEnd(line)
            while i < end {
                let c = bytes[i]
                if c == 0x0A || c == 0x0D { break }
                if c != 0x20 && c != 0x09 { return col }
                col += 1
                i += 1
            }
            return from
        }

        /// The leading-whitespace *byte* count common to a definition's
        /// continuation lines (those after the opener), capped at 4 — the
        /// indent to strip before re-parsing the body. Counted in bytes (space
        /// or tab, each one byte) so it stays consistent with the byte-based
        /// column model; blank lines are ignored.
        func continuationIndent(startLine: Int, endLine: Int) -> Int {
            guard endLine > startLine else { return 0 }
            var minIndent = Int.max
            for line in (startLine + 1)...endLine {
                let end = lineEnd(line)
                var indent = 0
                var blank = true
                var i = lineStart[line]
                loop: while i < end {
                    switch bytes[i] {
                    case 0x20, 0x09: indent += 1; i += 1   // space or tab
                    case 0x0A, 0x0D: break loop             // blank line
                    default: blank = false; break loop
                    }
                }
                if blank { continue }
                minIndent = min(minIndent, indent)
            }
            return minIndent == Int.max ? 0 : min(minIndent, 4)
        }
    }

    /// Parses `bytes` for footnote detection and invokes `body` with the root
    /// node, owning the parser/tree lifecycle. Returns `nil` if parsing fails
    /// (the caller supplies its own no-footnote fallback). Shared with
    /// ``CommentAnchor``, which walks the same footnote-aware AST.
    static func withFootnoteAST<T>(
        _ bytes: [UInt8],
        _ body: (UnsafeMutablePointer<cmark_node>) -> T
    ) -> T? {
        guard let parser = makeFootnoteParser() else { return nil }
        defer { cmark_parser_free(parser) }
        bytes.withUnsafeBytes { raw in
            cmark_parser_feed(
                parser, raw.bindMemory(to: CChar.self).baseAddress, bytes.count)
        }
        guard let root = cmark_parser_finish(parser) else { return nil }
        defer { cmark_node_free(root) }
        return body(root)
    }

    static func process(
        _ source: String, mode: FootnoteMode
    ) -> FootnoteProcessingResult {
        // Fast path: no possible footnote syntax → skip the cmark parse.
        guard source.contains("[^") else {
            return FootnoteProcessingResult(
                transformedMarkdown: source, footnotes: [], comments: [])
        }

        let geo = SourceGeometry(Array(source.utf8))
        let bytes = geo.bytes
        let lastLine = geo.lastLine

        struct RefHit {
            let number: Int
            let label: String
            let line: Int
            let start: Int   // byte range of `[^label]`
            let end: Int
        }
        struct DefRange {
            let startLine: Int
            let endLine: Int
        }

        let result: FootnoteProcessingResult? = withFootnoteAST(bytes) { root in
            var refs: [RefHit] = []
            var defEntries: [FootnoteEntry] = []   // authorial footnotes only
            var commentDefs: [(label: String, startLine: Int, body: String)] = []
            var defLineRanges: [DefRange] = []
            var referencedLabels = Set<String>()   // lowercased
            var codeBlockLines: [(Int, Int)] = []

            let iter = cmark_iter_new(root)
            defer { cmark_iter_free(iter) }

            while true {
                let ev = cmark_iter_next(iter)
                if ev == CMARK_EVENT_DONE { break }
                guard ev == CMARK_EVENT_ENTER else { continue }
                let node = cmark_iter_get_node(iter)
                let type = cmark_node_get_type(node)

                switch type {
                case CMARK_NODE_FOOTNOTE_REFERENCE:
                    // cmark replaces the reference's literal with its assigned
                    // number; the label lives on the parent definition.
                    guard let defNode = cmark_node_parent_footnote_def(node),
                          let numberCStr = cmark_node_get_literal(node),
                          let number = Int(String(cString: numberCStr)),
                          let labelCStr = cmark_node_get_literal(defNode)
                    else { continue }
                    let label = String(cString: labelCStr)
                    let startLine = Int(cmark_node_get_start_line(node))
                    let startCol = Int(cmark_node_get_start_column(node))
                    let endLine = Int(cmark_node_get_end_line(node))
                    let endCol = Int(cmark_node_get_end_column(node))
                    guard startLine == endLine, startLine >= 1, startLine <= lastLine
                    else { continue }
                    let start = geo.offset(line: startLine, column: startCol)
                    let end = geo.offset(line: endLine, column: endCol) + 1
                    guard geo.delimitsFootnoteRef(start: start, end: end)
                    else { continue }
                    refs.append(RefHit(
                        number: number, label: label, line: startLine,
                        start: start, end: end))
                    referencedLabels.insert(label.lowercased())

                case CMARK_NODE_FOOTNOTE_DEFINITION:
                    guard let labelCStr = cmark_node_get_literal(node) else { continue }
                    let label = String(cString: labelCStr)
                    let startLine = Int(cmark_node_get_start_line(node))
                    let endLine = Int(cmark_node_get_end_line(node))
                    guard startLine >= 1, endLine <= lastLine else { continue }
                    defLineRanges.append(DefRange(startLine: startLine, endLine: endLine))
                    let body = renderDefinitionBody(node)
                    // Classify by label: a comment definition is diverted to the
                    // comment model; everything else is an authorial footnote.
                    if isCommentLabel(label) {
                        commentDefs.append(
                            (label: label, startLine: startLine, body: body))
                    } else {
                        defEntries.append(FootnoteEntry(
                            label: label, number: 0, bodyMarkdown: body))
                    }

                case CMARK_NODE_CODE_BLOCK, CMARK_NODE_HTML_BLOCK:
                    let s = Int(cmark_node_get_start_line(node))
                    let e = Int(cmark_node_get_end_line(node))
                    if s >= 1 && e >= s { codeBlockLines.append((s, e)) }

                default:
                    break
                }
            }

            // Drop any references that live inside a definition body (the v1
            // limitation: nested footnotes are not recursively processed, and
            // their whole def block is deleted anyway).
            let bodyRefs = refs.filter { ref in
                !defLineRanges.contains { ref.line >= $0.startLine && ref.line <= $0.endLine }
            }

            // Assign authorial footnote numbers Mud-side — first-reference order
            // over **authorial** references only — so comments occupy no number
            // and leave no gap. cmark's own per-reference numbering counts every
            // footnote (comments included), so it is deliberately discarded.
            // Comment references divert to the `[⋯]` marker and never number.
            // Occurrence index per label drives back-link ids (fnref-N-K, K>1).
            struct Edit { let start: Int; let end: Int; let replacement: [UInt8] }
            var edits: [Edit] = []
            var authorialNumber: [String: Int] = [:]
            var nextNumber = 1
            var occurrence: [String: Int] = [:]
            let orderedRefs = bodyRefs.sorted(by: { $0.start < $1.start })
            for ref in orderedRefs {
                let marker: String
                if isCommentLabel(ref.label) {
                    marker = commentMarkerHTML(label: ref.label)
                } else {
                    let number = authorialNumber[ref.label] ?? nextNumber
                    if authorialNumber[ref.label] == nil {
                        authorialNumber[ref.label] = number
                        nextNumber += 1
                    }
                    let k = (occurrence[ref.label] ?? 0) + 1
                    occurrence[ref.label] = k
                    marker = markerHTML(
                        number: number, label: ref.label, occurrence: k)
                }
                edits.append(Edit(start: ref.start, end: ref.end,
                                  replacement: Array(marker.utf8)))
            }

            // Delete each referenced definition block, consuming trailing blanks.
            for range in defLineRanges {
                var stop = range.endLine + 1
                while stop <= lastLine, geo.lineIsBlank(stop) { stop += 1 }
                let end = stop <= lastLine ? geo.lineStart[stop] : bytes.count
                edits.append(Edit(start: geo.lineStart[range.startLine], end: end,
                                  replacement: []))
            }

            // Strip orphan (unreferenced) definitions, which cmark unlinks from
            // the tree. Scan column-0 `[^label]:` openers, skipping anything
            // inside a code/HTML block or already covered by a referenced
            // definition.
            func insideCodeBlock(_ line: Int) -> Bool {
                codeBlockLines.contains { line >= $0.0 && line <= $0.1 }
            }
            func insideReferencedDef(_ line: Int) -> Bool {
                defLineRanges.contains { line >= $0.startLine && line <= $0.endLine }
            }
            var line = 1
            while line <= lastLine {
                if !insideCodeBlock(line), !insideReferencedDef(line),
                   let label = openerLabel(at: geo.lineStart[line], bytes: bytes,
                                           lineEnd: geo.lineEnd(line)),
                   !referencedLabels.contains(label.lowercased()) {
                    var stop = line + 1
                    while stop <= lastLine, geo.isContinuation(stop) { stop += 1 }
                    let end = stop <= lastLine ? geo.lineStart[stop] : bytes.count
                    edits.append(Edit(start: geo.lineStart[line], end: end,
                                      replacement: []))
                    line = stop
                } else {
                    line += 1
                }
            }

            // Apply edits in descending start order so offsets stay valid.
            var out = bytes
            for edit in edits.sorted(by: { $0.start > $1.start }) {
                out.replaceSubrange(edit.start..<edit.end, with: edit.replacement)
            }
            let transformed = String(decoding: out, as: UTF8.self)

            let footnotes = defEntries
                .compactMap { entry -> FootnoteEntry? in
                    guard let number = authorialNumber[entry.label] else { return nil }
                    return FootnoteEntry(label: entry.label, number: number,
                                         bodyMarkdown: entry.bodyMarkdown)
                }
                .sorted { $0.number < $1.number }

            // Order comments by their first reference's position (the rendered
            // ordinal), falling back to definition order for any comment whose
            // reference cmark did not surface.
            var commentFirstRef: [String: Int] = [:]
            for ref in orderedRefs where isCommentLabel(ref.label) {
                if commentFirstRef[ref.label] == nil {
                    commentFirstRef[ref.label] = ref.start
                }
            }
            let comments = commentDefs
                .sorted {
                    let a = commentFirstRef[$0.label] ?? Int.max
                    let b = commentFirstRef[$1.label] ?? Int.max
                    return a != b ? a < b : $0.startLine < $1.startLine
                }
                .enumerated()
                .map { index, def -> Comment in
                    let (quotation, messages) =
                        CommentSerialization.parse(def.body)
                    return Comment(
                        label: def.label, ordinal: index + 1,
                        quotation: quotation, messages: messages)
                }

            return FootnoteProcessingResult(
                transformedMarkdown: transformed, footnotes: footnotes,
                comments: comments)
        }

        return result ?? FootnoteProcessingResult(
            transformedMarkdown: source, footnotes: [], comments: [])
    }

    /// Scans `source` for footnote references and definition blocks, returning
    /// their positions for Down-mode highlighting. Shares the `cmark-gfm`
    /// footnote parse used by ``process(_:mode:)`` but rewrites nothing.
    static func scan(_ source: String) -> FootnoteLayout {
        // Fast path: no possible footnote syntax → skip the cmark parse.
        guard source.contains("[^") else { return .empty }

        let geo = SourceGeometry(Array(source.utf8))
        let lastLine = geo.lastLine

        return withFootnoteAST(geo.bytes) { root in
            struct DefRange { let startLine: Int; let endLine: Int }
            var refHits: [(line: Int, startCol: Int, endCol: Int)] = []
            var defs: [FootnoteLayout.Def] = []
            var defRanges: [DefRange] = []

            let iter = cmark_iter_new(root)
            defer { cmark_iter_free(iter) }
            while true {
                let ev = cmark_iter_next(iter)
                if ev == CMARK_EVENT_DONE { break }
                guard ev == CMARK_EVENT_ENTER else { continue }
                let node = cmark_iter_get_node(iter)

                switch cmark_node_get_type(node) {
                case CMARK_NODE_FOOTNOTE_REFERENCE:
                    let line = Int(cmark_node_get_start_line(node))
                    let startCol = Int(cmark_node_get_start_column(node))
                    let endCol = Int(cmark_node_get_end_column(node))
                    guard line >= 1, line <= lastLine,
                          startCol >= 1, endCol >= startCol else { continue }
                    // Sanity: the range must actually delimit `[^…]`. `endCol`
                    // is the column of the closing `]`, so the half-open end is
                    // its offset plus one.
                    let s = geo.offset(line: line, column: startCol)
                    let e = geo.offset(line: line, column: endCol)
                    guard geo.delimitsFootnoteRef(start: s, end: e + 1)
                    else { continue }
                    refHits.append((line, startCol, endCol))

                case CMARK_NODE_FOOTNOTE_DEFINITION:
                    guard let labelCStr = cmark_node_get_literal(node)
                    else { continue }
                    let label = String(cString: labelCStr)
                    let startLine = Int(cmark_node_get_start_line(node))
                    let endLine = Int(cmark_node_get_end_line(node))
                    guard startLine >= 1, endLine <= lastLine,
                          endLine >= startLine else { continue }
                    defRanges.append(
                        DefRange(startLine: startLine, endLine: endLine))
                    // cmark's definition start_column points at the *body*, not
                    // the marker, so locate the `[` as the opener line's first
                    // non-whitespace byte.
                    let startColumn = geo.firstNonSpaceColumn(line: startLine)
                    // `[^` + label + `]:` → label.utf8.count + 4 chars.
                    let markerEndColumn = startColumn + label.utf8.count + 4
                    let contentStartColumn = geo.firstContentColumn(
                        line: startLine, from: markerEndColumn)
                    let contentIndent = geo.continuationIndent(
                        startLine: startLine, endLine: endLine)
                    defs.append(FootnoteLayout.Def(
                        startLine: startLine, endLine: endLine,
                        startColumn: startColumn,
                        markerEndColumn: markerEndColumn,
                        contentStartColumn: contentStartColumn,
                        contentIndent: contentIndent))

                default:
                    break
                }
            }

            // Drop references that live inside a definition body — those are
            // handled by re-parsing the body, not as standalone markers.
            let refs = refHits
                .filter { hit in
                    !defRanges.contains {
                        hit.line >= $0.startLine && hit.line <= $0.endLine
                    }
                }
                .map {
                    FootnoteLayout.Ref(
                        line: $0.line, startColumn: $0.startCol,
                        endColumn: $0.endCol)
                }

            return FootnoteLayout(refs: refs, defs: defs)
        } ?? .empty
    }

    /// Locates every comment (a footnote whose label matches
    /// `^comment-[\w-]+$`) in `source` by byte range, for byte-surgical edits.
    /// Shares the `cmark-gfm` footnote parse with ``process(_:mode:)`` and
    /// ``scan(_:)`` but rewrites nothing.
    static func locateComments(_ source: String) -> [CommentLocation] {
        guard source.contains("[^") else { return [] }
        let geo = SourceGeometry(Array(source.utf8))
        let lastLine = geo.lastLine

        struct DefHit { let label: String; let startLine: Int; let endLine: Int }

        return withFootnoteAST(geo.bytes) { root in
            var defs: [DefHit] = []
            var refsByLabel: [String: [Range<Int>]] = [:]

            let iter = cmark_iter_new(root)
            defer { cmark_iter_free(iter) }
            while true {
                let ev = cmark_iter_next(iter)
                if ev == CMARK_EVENT_DONE { break }
                guard ev == CMARK_EVENT_ENTER else { continue }
                let node = cmark_iter_get_node(iter)

                switch cmark_node_get_type(node) {
                case CMARK_NODE_FOOTNOTE_REFERENCE:
                    guard let defNode = cmark_node_parent_footnote_def(node),
                          let labelCStr = cmark_node_get_literal(defNode)
                    else { continue }
                    let label = String(cString: labelCStr)
                    guard isCommentLabel(label) else { continue }
                    let startLine = Int(cmark_node_get_start_line(node))
                    let startCol = Int(cmark_node_get_start_column(node))
                    let endLine = Int(cmark_node_get_end_line(node))
                    let endCol = Int(cmark_node_get_end_column(node))
                    guard startLine == endLine, startLine >= 1, startLine <= lastLine
                    else { continue }
                    let start = geo.offset(line: startLine, column: startCol)
                    let end = geo.offset(line: endLine, column: endCol) + 1
                    guard geo.delimitsFootnoteRef(start: start, end: end)
                    else { continue }
                    refsByLabel[label, default: []].append(start..<end)

                case CMARK_NODE_FOOTNOTE_DEFINITION:
                    guard let labelCStr = cmark_node_get_literal(node) else { continue }
                    let label = String(cString: labelCStr)
                    guard isCommentLabel(label) else { continue }
                    let startLine = Int(cmark_node_get_start_line(node))
                    let endLine = Int(cmark_node_get_end_line(node))
                    guard startLine >= 1, endLine <= lastLine, endLine >= startLine
                    else { continue }
                    defs.append(DefHit(
                        label: label, startLine: startLine, endLine: endLine))

                default:
                    break
                }
            }

            return defs.map { def in
                var stop = def.endLine + 1
                while stop <= lastLine, geo.lineIsBlank(stop) { stop += 1 }
                let deleteEnd = stop <= lastLine ? geo.lineStart[stop] : geo.bytes.count
                // cmark can fold a trailing blank line into the definition's end
                // line. Back up to the last non-blank line so `defContentEnd` is
                // the true end of content (before its newline); otherwise a
                // rewrite would swallow the blank line separating the definition
                // from the block after it.
                var contentLine = def.endLine
                while contentLine > def.startLine, geo.lineIsBlank(contentLine) {
                    contentLine -= 1
                }
                return CommentLocation(
                    label: def.label,
                    defStart: geo.lineStart[def.startLine],
                    defContentEnd: geo.contentEnd(contentLine),
                    defDeleteEnd: deleteEnd,
                    refRanges: refsByLabel[def.label] ?? [])
            }
        } ?? []
    }

    /// The 1-based line ranges (`startLine...endLine`) of every comment
    /// definition block in `source`, for diff consumers that need to exclude
    /// those lines from change tracking. Shares the `cmark-gfm` footnote parse
    /// with ``process(_:mode:)`` and ``locateComments(_:)`` but rewrites
    /// nothing. Empty when the source contains no comments.
    static func commentDefinitionLineRanges(
        _ source: String
    ) -> [ClosedRange<Int>] {
        guard source.contains("[^") else { return [] }
        let geo = SourceGeometry(Array(source.utf8))
        let lastLine = geo.lastLine

        return withFootnoteAST(geo.bytes) { root in
            var ranges: [ClosedRange<Int>] = []
            let iter = cmark_iter_new(root)
            defer { cmark_iter_free(iter) }
            while true {
                let ev = cmark_iter_next(iter)
                if ev == CMARK_EVENT_DONE { break }
                guard ev == CMARK_EVENT_ENTER else { continue }
                let node = cmark_iter_get_node(iter)
                guard cmark_node_get_type(node) == CMARK_NODE_FOOTNOTE_DEFINITION,
                      let labelCStr = cmark_node_get_literal(node) else { continue }
                let label = String(cString: labelCStr)
                guard isCommentLabel(label) else { continue }
                let startLine = Int(cmark_node_get_start_line(node))
                let endLine = Int(cmark_node_get_end_line(node))
                guard startLine >= 1, endLine >= startLine,
                      endLine <= lastLine else { continue }
                ranges.append(startLine...endLine)
            }
            return ranges
        } ?? []
    }

    /// Removes every comment from `source` — all `[^comment-x]` references and
    /// every comment-definition block (with its trailing blanks) — by byte
    /// range, reusing ``locateComments(_:)``. The result renders identically to
    /// `source` minus its comments, so it is a stable, comment-invariant content
    /// identity. A comment-free source is returned unchanged.
    static func removeComments(_ source: String) -> String {
        let locations = locateComments(source)
        guard !locations.isEmpty else { return source }
        var ranges: [Range<Int>] = []
        for loc in locations {
            ranges.append(contentsOf: loc.refRanges)
            ranges.append(loc.defStart..<loc.defDeleteEnd)
        }
        var bytes = Array(source.utf8)
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            bytes.removeSubrange(range)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Comment-only regex precompiled once: the raw reference form
    /// `[^comment-x]` and the baked marker HTML `<a class="mud-comment-marker"
    /// …>💬</a>`. Used by ``stripCommentTokens(_:)``.
    private static let commentTokenRegexes: [NSRegularExpression] = {
        let patterns = [
            #"\[\^comment-[\w-]+\]"#,
            #"<a class="mud-comment-marker"[^>]*>💬</a>"#,
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Strips comment tokens (raw refs and baked marker HTML) from a block
    /// fingerprint so a block that only gained a comment fingerprints
    /// identically to its pre-comment baseline. Self-gated to a strict no-op on
    /// comment-free input (the diff suite's hot path).
    static func stripCommentTokens(_ s: String) -> String {
        guard s.contains("[^") || s.contains("mud-comment-marker") else { return s }
        var result = s
        for regex in commentTokenRegexes {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result, range: range, withTemplate: "")
        }
        return result
    }

    /// Renders each child block of a footnote definition to CommonMark and
    /// joins them with a blank line. Rendering children individually avoids
    /// the `[^label]:` prefix and continuation indentation that
    /// `cmark_render_commonmark` emits for the definition node itself.
    private static func renderDefinitionBody(
        _ defNode: UnsafeMutablePointer<cmark_node>?
    ) -> String {
        var parts: [String] = []
        var child = cmark_node_first_child(defNode)
        while let node = child {
            if let cstr = cmark_render_commonmark(node, 0, 0) {
                parts.append(String(cString: cstr))
                free(cstr)
            }
            child = cmark_node_next(node)
        }
        return parts.joined(separator: "\n")
    }

    /// The inline-HTML marker that replaces a `[^label]` reference. Carries a
    /// real `#fn-N` anchor (for export/print) plus `data-*` attributes the
    /// in-app JS reads to trigger the popover.
    private static func markerHTML(number: Int, label: String, occurrence: Int) -> String {
        let idSuffix = occurrence > 1 ? "-\(occurrence)" : ""
        let escLabel = HTMLEscaping.escape(label)
        return "<sup class=\"footnote-ref\" id=\"fnref-\(number)\(idSuffix)\">"
            + "<a href=\"#fn-\(number)\" data-footnote-ref"
            + " data-fn-label=\"\(escLabel)\" data-fn-num=\"\(number)\">\(number)</a></sup>"
    }

    /// The inline-HTML marker that replaces a `[^comment-…]` reference: a `[⋯]`
    /// chip carrying the label. Unlike a footnote marker it has no number — so
    /// comments never consume a footnote number — and points at the bottom
    /// Comments section (`#cmt-LABEL`) as the no-JS fallback. The in-app JS reads
    /// `data-mud-label` to reveal the highlight and open the editor.
    private static func commentMarkerHTML(label: String) -> String {
        let escLabel = HTMLEscaping.escape(label)
        return "<a class=\"mud-comment-marker\" id=\"cmtref-\(escLabel)\""
            + " data-mud-label=\"\(escLabel)\" href=\"#cmt-\(escLabel)\">💬</a>"
    }

    /// If the line beginning at `start` is a column-0 footnote-definition
    /// opener (`[^label]:` with a non-empty, whitespace-free label), returns
    /// the label; otherwise nil.
    private static func openerLabel(
        at start: Int, bytes: [UInt8], lineEnd: Int
    ) -> String? {
        guard start + 1 < lineEnd,
              bytes[start] == 0x5B, bytes[start + 1] == 0x5E else { return nil }
        var i = start + 2
        var label: [UInt8] = []
        while i < lineEnd, bytes[i] != 0x5D {
            let c = bytes[i]
            if c == 0x20 || c == 0x09 { return nil }  // whitespace in label
            label.append(c)
            i += 1
        }
        guard i < lineEnd, bytes[i] == 0x5D else { return nil }  // need ]
        i += 1
        guard i < lineEnd, bytes[i] == 0x3A else { return nil }  // need :
        guard !label.isEmpty else { return nil }
        return String(decoding: label, as: UTF8.self)
    }
}
