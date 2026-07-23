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

/// The footnotes and comments collected from a Markdown source, for the
/// bottom sections and the comment layer. No source rewriting: the render
/// visitor emits footnote/comment markers from the AST directly.
struct FootnoteProcessingResult {
    let footnotes: [FootnoteEntry]
    let comments: [Comment]
}

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

    /// Collects the authorial footnotes and comments in `source` for the
    /// bottom sections and the comment layer. It rewrites nothing — the render
    /// visitor (`CMarkUpHTMLVisitor`) emits the footnote/comment markers from
    /// the AST. Its only real work is classifying comment definitions apart
    /// from footnotes and assigning authorial footnote numbers in
    /// first-reference order (comments consume no number and leave no gap).
    ///
    /// The result is `mode`-independent (the mode only selects section
    /// visibility at render time), so the underlying ``FootnoteScan`` memo
    /// keys on the source alone. Every "should NOT be a footnote" case (refs
    /// in code spans / fenced blocks, escaped `\[^1\]`, whitespace labels) and
    /// every dangling `[^missing]` is handled for free by cmark: they never
    /// become reference nodes.
    static func process(
        _ source: String, mode: FootnoteMode
    ) -> FootnoteProcessingResult {
        // Fast path: no possible footnote syntax → skip the scan.
        guard source.contains("[^") else {
            return FootnoteProcessingResult(footnotes: [], comments: [])
        }

        let facts = FootnoteScan.scan(source)
        let geo = facts.geometry
        let lastLine = geo.lastLine

        struct RefHit {
            let label: String
            let line: Int
            let start: Int   // byte offset of the `[` in `[^label]`
        }
        struct DefRange {
            let startLine: Int
            let endLine: Int
        }

        // cmark keeps a reference's resolved label on its parent definition; a
        // ref lacking a label or a valid number literal is skipped, as is any
        // whose sourcepos does not delimit `[^…]`.
        var refs: [RefHit] = []
        for ref in facts.refs {
            guard let label = ref.label, ref.hasValidNumber,
                  ref.startLine == ref.endLine,
                  ref.startLine >= 1, ref.startLine <= lastLine
            else { continue }
            let start = geo.offset(line: ref.startLine, column: ref.startColumn)
            let end = geo.offset(line: ref.endLine, column: ref.endColumn) + 1
            guard geo.delimitsFootnoteRef(start: start, end: end)
            else { continue }
            refs.append(RefHit(label: label, line: ref.startLine, start: start))
        }

        // Classify definitions by label: a comment definition is diverted to
        // the comment model; everything else is an authorial footnote.
        var defEntries: [FootnoteEntry] = []   // authorial footnotes only
        var commentDefs: [(label: String, startLine: Int, body: String)] = []
        var defLineRanges: [DefRange] = []
        for def in facts.defs {
            guard def.startLine >= 1, def.endLine <= lastLine else { continue }
            defLineRanges.append(
                DefRange(startLine: def.startLine, endLine: def.endLine))
            if isCommentLabel(def.label) {
                commentDefs.append((
                    label: def.label, startLine: def.startLine,
                    body: def.bodyMarkdown))
            } else {
                defEntries.append(FootnoteEntry(
                    label: def.label, number: 0, bodyMarkdown: def.bodyMarkdown))
            }
        }

        // Drop any references that live inside a definition body (nested
        // footnotes are not recursively processed).
        let bodyRefs = refs.filter { ref in
            !defLineRanges.contains { ref.line >= $0.startLine && ref.line <= $0.endLine }
        }
        let orderedRefs = bodyRefs.sorted(by: { $0.start < $1.start })

        // Assign authorial footnote numbers in first-reference order over
        // **authorial** references only, so comments occupy no number and
        // leave no gap. Record each comment's first-reference byte offset for
        // ordering the bottom Comments section.
        var authorialNumber: [String: Int] = [:]
        var nextNumber = 1
        var commentFirstRef: [String: Int] = [:]
        for ref in orderedRefs {
            if isCommentLabel(ref.label) {
                if commentFirstRef[ref.label] == nil {
                    commentFirstRef[ref.label] = ref.start
                }
            } else if authorialNumber[ref.label] == nil {
                authorialNumber[ref.label] = nextNumber
                nextNumber += 1
            }
        }

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

        return FootnoteProcessingResult(footnotes: footnotes, comments: comments)
    }

    /// Scans `source` for footnote references and definition blocks, returning
    /// their positions for Down-mode highlighting. Derives from the cached
    /// ``FootnoteScan`` shared with ``process(_:mode:)`` and rewrites nothing.
    static func scan(_ source: String) -> FootnoteLayout {
        // Fast path: no possible footnote syntax → skip the scan.
        guard source.contains("[^") else { return .empty }

        let facts = FootnoteScan.scan(source)
        let geo = facts.geometry
        let lastLine = geo.lastLine

        struct DefRange { let startLine: Int; let endLine: Int }
        var defs: [FootnoteLayout.Def] = []
        var defRanges: [DefRange] = []
        for def in facts.defs {
            guard def.startLine >= 1, def.endLine <= lastLine,
                  def.endLine >= def.startLine else { continue }
            defRanges.append(
                DefRange(startLine: def.startLine, endLine: def.endLine))
            // cmark's definition start_column points at the *body*, not
            // the marker, so locate the `[` as the opener line's first
            // non-whitespace byte.
            let startColumn = geo.firstNonSpaceColumn(line: def.startLine)
            // `[^` + label + `]:` → label.utf8.count + 4 chars.
            let markerEndColumn = startColumn + def.label.utf8.count + 4
            let contentStartColumn = geo.firstContentColumn(
                line: def.startLine, from: markerEndColumn)
            let contentIndent = geo.continuationIndent(
                startLine: def.startLine, endLine: def.endLine)
            defs.append(FootnoteLayout.Def(
                startLine: def.startLine, endLine: def.endLine,
                startColumn: startColumn,
                markerEndColumn: markerEndColumn,
                contentStartColumn: contentStartColumn,
                contentIndent: contentIndent))
        }

        // Sanity: a ref's range must actually delimit `[^…]`. `endColumn` is
        // the column of the closing `]`, so the half-open end is its offset
        // plus one. Drop references that live inside a definition body —
        // those are handled by re-parsing the body, not as standalone markers.
        var refs: [FootnoteLayout.Ref] = []
        for ref in facts.refs {
            guard ref.startLine >= 1, ref.startLine <= lastLine,
                  ref.startColumn >= 1, ref.endColumn >= ref.startColumn
            else { continue }
            let s = geo.offset(line: ref.startLine, column: ref.startColumn)
            let e = geo.offset(line: ref.startLine, column: ref.endColumn)
            guard geo.delimitsFootnoteRef(start: s, end: e + 1)
            else { continue }
            guard !defRanges.contains(where: {
                ref.startLine >= $0.startLine && ref.startLine <= $0.endLine
            }) else { continue }
            refs.append(FootnoteLayout.Ref(
                line: ref.startLine, startColumn: ref.startColumn,
                endColumn: ref.endColumn))
        }

        return FootnoteLayout(refs: refs, defs: defs)
    }

    /// Locates every comment (a footnote whose label matches
    /// `^comment-[\w-]+$`) in `source` by byte range, for byte-surgical edits.
    /// Derives from the cached ``FootnoteScan`` shared with
    /// ``process(_:mode:)`` and ``scan(_:)`` but rewrites nothing.
    static func locateComments(_ source: String) -> [CommentLocation] {
        guard source.contains("[^") else { return [] }
        let facts = FootnoteScan.scan(source)
        let geo = facts.geometry
        let lastLine = geo.lastLine

        var refsByLabel: [String: [Range<Int>]] = [:]
        for ref in facts.refs {
            guard let label = ref.label, isCommentLabel(label),
                  ref.startLine == ref.endLine,
                  ref.startLine >= 1, ref.startLine <= lastLine
            else { continue }
            let start = geo.offset(line: ref.startLine, column: ref.startColumn)
            let end = geo.offset(line: ref.endLine, column: ref.endColumn) + 1
            guard geo.delimitsFootnoteRef(start: start, end: end)
            else { continue }
            refsByLabel[label, default: []].append(start..<end)
        }

        return facts.defs.compactMap { def in
            guard isCommentLabel(def.label),
                  def.startLine >= 1, def.endLine <= lastLine,
                  def.endLine >= def.startLine
            else { return nil }
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
    }

    /// The 1-based line ranges (`startLine...endLine`) of every comment
    /// definition block in `source`, for diff consumers that need to exclude
    /// those lines from change tracking. Derives from the cached
    /// ``FootnoteScan`` shared with ``process(_:mode:)`` and
    /// ``locateComments(_:)`` but rewrites nothing. Empty when the source
    /// contains no comments.
    static func commentDefinitionLineRanges(
        _ source: String
    ) -> [ClosedRange<Int>] {
        guard source.contains("[^") else { return [] }
        let facts = FootnoteScan.scan(source)
        let lastLine = facts.geometry.lastLine
        return facts.defs.compactMap { def in
            guard isCommentLabel(def.label),
                  def.startLine >= 1, def.endLine >= def.startLine,
                  def.endLine <= lastLine
            else { return nil }
            return def.startLine...def.endLine
        }
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

    /// The CSS class of a baked comment marker. ``commentMarkerHTML(label:)``
    /// emits it and ``commentTokenRegexes`` re-recognizes it; both derive from
    /// this one constant so the emitter and the stripper cannot drift apart.
    /// The JS layer names the same class (`makeMarker` / `markerFreeText` in
    /// the comments scripts) — pinned by `CommentResourcesTests`.
    static let commentMarkerClass = "mud-comment-marker"

    /// The marker glyph, shared by the emitter and the strip pattern.
    private static let commentMarkerGlyph = "💬"

    /// Comment-only regex precompiled once: the raw reference form
    /// `[^comment-x]` and the baked marker HTML, whose pattern is built from
    /// the same constants ``commentMarkerHTML(label:)`` emits. Used by
    /// ``stripCommentTokens(_:)``.
    private static let commentTokenRegexes: [NSRegularExpression] = {
        let cls = NSRegularExpression.escapedPattern(for: commentMarkerClass)
        let glyph = NSRegularExpression.escapedPattern(for: commentMarkerGlyph)
        let patterns = [
            #"\[\^comment-[\w-]+\]"#,
            "<a class=\"\(cls)\"[^>]*>\(glyph)</a>",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0) }
    }()

    /// Strips comment tokens (raw refs and baked marker HTML) from a block
    /// fingerprint so a block that only gained a comment fingerprints
    /// identically to its pre-comment baseline. Self-gated to a strict no-op on
    /// comment-free input (the diff suite's hot path).
    static func stripCommentTokens(_ s: String) -> String {
        guard s.contains("[^") || s.contains(commentMarkerClass) else { return s }
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
    /// Fileprivate so ``FootnoteScan`` can pre-render bodies during its walk.
    fileprivate static func renderDefinitionBody(
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
    /// in-app JS reads to trigger the popover. Internal (not private) because
    /// `CMarkUpHTMLVisitor` emits the same marker from its footnote-reference
    /// visit case — one implementation, so its callers cannot drift.
    static func markerHTML(number: Int, label: String, occurrence: Int) -> String {
        let idSuffix = occurrence > 1 ? "-\(occurrence)" : ""
        let escLabel = HTMLEscaping.escape(label)
        return "<sup class=\"footnote-ref\" id=\"fnref-\(number)\(idSuffix)\">"
            + "<a href=\"#fn-\(number)\" data-footnote-ref"
            + " data-fn-label=\"\(escLabel)\" data-fn-num=\"\(number)\">\(number)</a></sup>"
    }

    /// The inline-HTML marker that replaces a `[^comment-…]` reference: a `💬`
    /// chip carrying the label. Unlike a footnote marker it has no number — so
    /// comments never consume a footnote number — and points at the bottom
    /// Comments section (`#cmt-LABEL`) as the no-JS fallback. The in-app JS reads
    /// `data-mud-label` to reveal the highlight and open the editor. Internal
    /// for the same reason as ``markerHTML(number:label:occurrence:)`` above.
    static func commentMarkerHTML(label: String) -> String {
        let escLabel = HTMLEscaping.escape(label)
        return "<a class=\"\(commentMarkerClass)\" id=\"cmtref-\(escLabel)\""
            + " data-mud-label=\"\(escLabel)\" href=\"#cmt-\(escLabel)\">\(commentMarkerGlyph)</a>"
    }

}

// MARK: - FootnoteScan

/// The raw facts one footnote-aware `cmark-gfm` parse of a source yields,
/// computed at most once per source (see ``scan(_:)``). Every
/// `FootnoteProcessor` entry point — `process`, `scan`, `locateComments`,
/// `commentDefinitionLineRanges`, and (via `locateComments`) `removeComments`
/// — derives its result from these facts instead of re-parsing; one live-edit
/// render cycle used to parse the same text up to eight times. The facts are
/// mode-independent (`FootnoteMode` only selects section visibility at render
/// time), so the memo keys on the source alone. A failed cmark parse yields an
/// empty scan, which each derivation turns into its no-footnotes fallback.
struct FootnoteScan {
    /// One `[^label]` reference node, raw from cmark. Consumers apply their
    /// own validity guards (line bounds, the `[^…]` delimiter check).
    struct Ref {
        /// The label of the definition the reference resolves to (cmark keeps
        /// it on the parent definition node); nil when cmark supplies none.
        let label: String?
        /// Whether cmark's number literal for the reference parses as an
        /// integer. Mud assigns its own numbers, but `process` skips refs
        /// without a valid literal.
        let hasValidNumber: Bool
        let startLine: Int
        let endLine: Int
        let startColumn: Int
        let endColumn: Int
    }

    /// One `[^label]:` definition block, raw from cmark, with its body
    /// pre-rendered to clean CommonMark.
    struct Def {
        let label: String
        let startLine: Int
        let endLine: Int
        let bodyMarkdown: String
    }

    let geometry: FootnoteProcessor.SourceGeometry
    let refs: [Ref]
    let defs: [Def]
}

extension FootnoteScan {
    private static let cacheLock = NSLock()
    nonisolated(unsafe) private static var cache:
        [(source: String, scan: FootnoteScan)] = []
    private static let cacheLimit = 8

    /// Returns the scan for `source`, computing it at most once per source
    /// (keyed by the source text, LRU-bounded — the same pattern as
    /// `CMarkChangePlan.plan`).
    static func scan(_ source: String) -> FootnoteScan {
        cacheLock.lock()
        if let index = cache.firstIndex(where: { $0.source == source }) {
            let entry = cache.remove(at: index)
            cache.insert(entry, at: 0)
            cacheLock.unlock()
            return entry.scan
        }
        cacheLock.unlock()

        let scan = compute(source)

        cacheLock.lock()
        cache.insert((source, scan), at: 0)
        if cache.count > cacheLimit {
            cache.removeLast(cache.count - cacheLimit)
        }
        cacheLock.unlock()
        return scan
    }

    /// One iterator pass over the footnote-aware AST, collecting reference
    /// and definition facts.
    private static func compute(_ source: String) -> FootnoteScan {
        let geo = FootnoteProcessor.SourceGeometry(Array(source.utf8))
        var refs: [Ref] = []
        var defs: [Def] = []

        _ = FootnoteProcessor.withFootnoteAST(geo.bytes) { root -> Void in
            let iter = cmark_iter_new(root)
            defer { cmark_iter_free(iter) }
            while true {
                let ev = cmark_iter_next(iter)
                if ev == CMARK_EVENT_DONE { break }
                guard ev == CMARK_EVENT_ENTER else { continue }
                let node = cmark_iter_get_node(iter)

                switch cmark_node_get_type(node) {
                case CMARK_NODE_FOOTNOTE_REFERENCE:
                    var label: String?
                    if let defNode = cmark_node_parent_footnote_def(node),
                       let labelCStr = cmark_node_get_literal(defNode) {
                        label = String(cString: labelCStr)
                    }
                    var hasValidNumber = false
                    if let numberCStr = cmark_node_get_literal(node),
                       Int(String(cString: numberCStr)) != nil {
                        hasValidNumber = true
                    }
                    refs.append(Ref(
                        label: label, hasValidNumber: hasValidNumber,
                        startLine: Int(cmark_node_get_start_line(node)),
                        endLine: Int(cmark_node_get_end_line(node)),
                        startColumn: Int(cmark_node_get_start_column(node)),
                        endColumn: Int(cmark_node_get_end_column(node))))

                case CMARK_NODE_FOOTNOTE_DEFINITION:
                    guard let labelCStr = cmark_node_get_literal(node)
                    else { break }
                    defs.append(Def(
                        label: String(cString: labelCStr),
                        startLine: Int(cmark_node_get_start_line(node)),
                        endLine: Int(cmark_node_get_end_line(node)),
                        bodyMarkdown:
                            FootnoteProcessor.renderDefinitionBody(node)))

                default:
                    break
                }
            }
        }

        return FootnoteScan(geometry: geo, refs: refs, defs: defs)
    }
}
