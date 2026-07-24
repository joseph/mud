/// Byte/line geometry of a UTF-8 Markdown source, shared by ``CMarkDocument``,
/// ``FootnoteProcessor``, and ``CommentAnchor``. `lineStart[L]` is the 1-based
/// byte offset of line `L`'s first byte, valid for `L` in `1...lastLine`.
///
/// This is a pure view over source bytes — no cmark, no rendering — so it lives
/// in `CMark/` alongside its lowest-level consumer (`CMarkDocument`), not in
/// `Rendering/`.
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

    /// Count of leading whitespace bytes on `line` — space or tab, each one
    /// byte — capped at `cap`. Byte-counted, and never past the line's
    /// content, so the width maps cleanly back to a source column.
    func leadingWhitespace(line: Int, max cap: Int) -> Int {
        var n = 0
        var i = lineStart[line]
        let end = contentEnd(line)
        while i < end, n < cap, bytes[i] == 0x20 || bytes[i] == 0x09 {
            n += 1
            i += 1
        }
        return n
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
