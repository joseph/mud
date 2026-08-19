import Foundation

/// The read/write codec for a comment definition's body — no IO. Mud *writes* a
/// strict canonical form but *reads* anything the convention in
/// `Doc/Guides/spec-comments.md` allows.
///
/// `parse` takes the footnote definition's **de-indented body Markdown** (the
/// clean CommonMark `FootnoteProcessor` already produces via
/// `renderDefinitionBody`) and structures it into a root quotation plus ordered
/// messages. `serialize` is the strict inverse, with the round-trip invariant
/// `parse(serialize(quotation, messages)) == (quotation, messages)`. Two
/// exceptions. An unattributed message after the first has to be written with an
/// avatar attribution or the two messages merge back into one, so it parses back
/// carrying `CommentAvatar.fallback` — the avatar it already rendered as. And a
/// message with no content at all is outside the convention (a message always
/// has content): written out, it is indistinguishable from an attribution
/// standing at the head of the message below it, and the two merge on re-parse.
/// Nothing reaches `CommentEditor` that way — the compose box treats Done on an
/// empty box as Cancel.
///
/// Working on the already-de-indented body is what lets this stay pure,
/// testable Swift over one `CMarkDocument` parse: the multi-paragraph misparse
/// that forced cmark for footnote *bodies* does not bite a pre-normalized
/// string. Message bodies are sliced verbatim from the source by block
/// sourcepos rather than re-serialized, so a message no one has edited
/// round-trips byte-for-byte — including the remainder of a message written on
/// one line, `{JP @ …}: like this`, which is sliced from the same source and not
/// read off the flattened inline text.
///
/// A message attribution is `👤 {author @ timestamp}:` — an optional leading
/// emoji (the message's *avatar*), an optional brace group, and a **required**
/// colon. At least one of the avatar and the braces must be present. The colon
/// is the signal: a paragraph that merely opens with an emoji or a `{` and
/// never reaches one is ordinary content, so a message may begin with an emoji,
/// or be nothing but one. The grammar reads source text, so inline code is
/// opaque to it: backticking an emoji or a brace group keeps it content even
/// with a colon after it.
enum CommentSerialization {
    // MARK: - Read

    /// Structures a comment definition's de-indented body Markdown into the root
    /// quotation and ordered messages.
    static func parse(
        _ bodyMarkdown: String
    ) -> (quotation: String?, messages: [CommentMessage]) {
        guard let document = CMarkDocument(parsing: bodyMarkdown) else {
            return (nil, [])
        }
        // Source lines, 1-based by index + 1, so a block's `startLine` /
        // `endLine` slice its verbatim bytes back out. Both the message bodies
        // and the attribution grammar read this rather than the AST's flattened
        // inline text (see `sliceBody` and `sourceText`).
        let lines = bodyMarkdown.components(separatedBy: "\n")
        var blocks = Array(document.root.children)

        // (1) A leading blockquote — and only a leading one, before any message
        // — is the root quotation. A blockquote that follows a message header
        // belongs to that message's body.
        var quotation: String?
        if let first = blocks.first, first.kind == .blockQuote {
            quotation = flatten(plainText(of: first))
            blocks.removeFirst()
        }

        // (2) Split the remaining blocks into messages at every paragraph that
        // *begins* with a message attribution. Blocks before the first such
        // paragraph (or all of them, when there is none) form one implicit
        // author-less message. An attribution only splits once the message it
        // would close has content — see `hasContent`.
        var groups: [[CMarkNode]] = []
        var current: [CMarkNode] = []
        for block in blocks {
            if isMessageStart(block, lines: lines),
                hasContent(current, lines: lines)
            {
                groups.append(current)
                current = []
            }
            current.append(block)
        }
        if !current.isEmpty { groups.append(current) }

        let messages = groups.map { buildMessage($0, lines: lines) }
        return (quotation, messages)
    }

    /// True when `block` is a paragraph that opens with a message attribution.
    /// The whole grammar lives in `parseAttribution`, so what splits a thread and
    /// what a header parses to can never drift apart. An attribution anywhere
    /// but at a paragraph's start is running prose and never splits a message.
    private static func isMessageStart(
        _ block: CMarkNode, lines: [String]
    ) -> Bool {
        guard block.kind == .paragraph,
            let text = sourceText(of: block, lines: lines)
        else { return false }
        return parseAttribution(text).isHeader
    }

    /// Whether the message a block group has built so far carries any content —
    /// which is what an attribution needs before it may close that message and
    /// open the next.
    ///
    /// A group holding nothing but a bare attribution paragraph has none, so the
    /// paragraph below it is read as that message's content rather than as a
    /// second, empty message following an empty one. A message always has
    /// content — which is what lets a message be a single line that is itself
    /// attribution-shaped, the one ambiguity the colon can't settle.
    private static func hasContent(_ group: [CMarkNode], lines: [String]) -> Bool {
        guard let only = group.first else { return false }
        // Past the first block, everything in the group is content.
        guard group.count == 1, only.kind == .paragraph,
            let text = sourceText(of: only, lines: lines)
        else { return true }
        let parsed = parseAttribution(text)
        // An unattributed paragraph is itself content; an attribution counts
        // only when something follows its colon.
        return !parsed.isHeader || !parsed.inlineBody.isEmpty
    }

    /// Builds a `CommentMessage` from its block group. The first paragraph is run
    /// through `parseAttribution`; when it carries a header (an avatar and/or a
    /// `{…}` block, closed by a colon), that paragraph is the header and the rest
    /// is the body. Otherwise the whole group is an unattributed body.
    ///
    /// The header paragraph's remainder — the text after the colon, when a
    /// message is written on one line — comes off the same verbatim source slice
    /// as every other block, so it keeps its Markdown. Reading it off the
    /// flattened inline text instead would hand back `see the doc for details`
    /// for `see [the doc](x) for *details*`, and a later rewrite would write
    /// that back.
    private static func buildMessage(
        _ blocks: [CMarkNode], lines: [String]
    ) -> CommentMessage {
        if let para = blocks.first, para.kind == .paragraph,
            let paragraphSource = sourceText(of: para, lines: lines)
        {
            let (avatar, author, created, inlineBody, isHeader) =
                parseAttribution(paragraphSource)
            if isHeader {
                var parts: [String] = []
                if !inlineBody.isEmpty { parts.append(inlineBody) }
                if let body = sliceBody(blocks.dropFirst(), lines: lines) {
                    parts.append(body)
                }
                return CommentMessage(
                    avatar: avatar, author: author, created: created,
                    body: parts.joined(separator: "\n\n"))
            }
        }
        let body = sliceBody(blocks[...], lines: lines) ?? ""
        return CommentMessage(author: nil, created: nil, body: body)
    }

    // MARK: - Write

    /// Renders a quotation + messages into the strict canonical body Markdown
    /// (un-indented): the quotation as a leading blockquote, then one
    /// `👤 {author @ timestamp}:` header per attributed message — alone on its
    /// line, commentary in the block below. The caller (`CommentEditor`) prefixes
    /// `[^label]:` and indents continuation lines by four spaces.
    ///
    /// A message's avatar is written back exactly as it was read, and a message
    /// that carried none is written without one, so rewriting a thread never
    /// stamps Mud's own avatar onto someone else's message. The single
    /// exception is the message-boundary marker below, which structure demands.
    static func serialize(
        quotation: String?, _ messages: [CommentMessage]
    ) -> String {
        var blocks: [String] = []
        if let quotation, !quotation.isEmpty {
            blocks.append("> " + quotation)
        }
        for (index, message) in messages.enumerated() {
            let body = message.body
            if let header = headerLine(message) {
                blocks.append(header)
                if !body.isEmpty { blocks.append(body) }
                continue
            }
            // No attributes to put in braces, so the attribution is an avatar
            // and a colon. A message after the first still needs one to mark it
            // — without it, re-parsing would merge it into the previous message
            // — so an avatar-less one gets `CommentAvatar.fallback`, which is
            // what a message with no avatar already renders as and claims nobody
            // in particular wrote it. The first message needs no marker and
            // keeps only the avatar it came with. This is the one thing
            // serialize adds that the model did not carry, so such a message
            // parses back with that avatar.
            let marker = message.avatar
                ?? (index > 0 ? CommentAvatar.fallback : nil)
            if let marker { blocks.append("\(marker):") }
            if !body.isEmpty { blocks.append(body) }
        }
        return blocks.joined(separator: "\n\n")
    }

    /// The `👤 {author @ timestamp}:` header for an attributed message, or `nil`
    /// for a bare unattributed message (which serializes as body alone). The
    /// avatar is written only when the message carries one. With one field
    /// present the brace carries just that: `{author}` or `{@ timestamp}`.
    private static func headerLine(_ message: CommentMessage) -> String? {
        let author = message.author.flatMap { $0.isEmpty ? nil : $0 }
        guard author != nil || message.created != nil else { return nil }
        var interior = author ?? ""
        if let created = message.created {
            let stamp = formatTimestamp(created)
            interior = interior.isEmpty ? "@ \(stamp)" : "\(interior) @ \(stamp)"
        }
        let avatar = message.avatar.map { "\($0) " } ?? ""
        return "\(avatar){\(interior)}:"
    }

    // MARK: - Attribution grammar

    /// Peels a leading message attribution — `[<avatar>][{author @ timestamp}]:`
    /// — from a message's first paragraph. The avatar (any one emoji) and the
    /// brace group are each optional, but at least one must be present and the
    /// **colon is required**.
    ///
    /// The colon is what separates an attribution from ordinary content, so a
    /// paragraph that opens with an emoji or a `{…}` and never reaches one is
    /// body text and starts no message — which is what lets a message begin with
    /// an emoji, or be nothing but one. It must *immediately* follow the brace
    /// group (or the avatar, when there is no brace group), and be followed by a
    /// space or the end of the paragraph: a space before it, or a character
    /// other than a space after it, makes the whole paragraph content.
    ///
    /// Inside the braces, the **last** `@` whose trailing text parses as a
    /// timestamp splits `author` from `created`; with no such `@` the whole
    /// interior is the author (so an author may contain `@`).
    static func parseAttribution(
        _ paragraphText: String
    ) -> (
        avatar: String?, author: String?, created: Date?,
        inlineBody: String, isHeader: Bool
    ) {
        let content = (
            avatar: String?.none, author: String?.none, created: Date?.none,
            inlineBody: paragraphText, isHeader: false)

        var scanner = paragraphText[...]
        scanner = scanner.drop { $0 == " " || $0 == "\t" }

        var avatar: String?
        if let first = scanner.first, first.isEmoji {
            avatar = String(first)
            scanner = scanner.dropFirst()
        }

        // The brace group, when there is one, opens the post-avatar text; a `{`
        // later in the paragraph is ordinary prose.
        var author: String?
        var created: Date?
        var sawBraces = false
        let braced = scanner.drop { $0 == " " || $0 == "\t" }
        if braced.first == "{", let close = braced.firstIndex(of: "}") {
            let interior = braced[braced.index(after: braced.startIndex)..<close]
            (author, created) = parseBraceInterior(interior)
            scanner = braced[braced.index(after: close)...]
            sawBraces = true
        }
        guard avatar != nil || sawBraces else { return content }

        guard scanner.first == ":" else { return content }
        let rest = scanner.dropFirst()
        guard rest.isEmpty || rest.first == " " || rest.first == "\t"
        else { return content }

        return (
            avatar, author, created,
            String(rest.drop { $0 == " " || $0 == "\t" }), true)
    }

    /// Splits a brace interior into author and timestamp at the **last** `@`
    /// whose trailing text parses as a timestamp. With no such `@`, the whole
    /// (trimmed) interior is the author. An empty interior yields neither.
    private static func parseBraceInterior(
        _ interior: Substring
    ) -> (author: String?, created: Date?) {
        var end = interior.endIndex
        while let at = interior[interior.startIndex..<end].lastIndex(of: "@") {
            let suffix = String(interior[interior.index(after: at)...])
                .trimmingCharacters(in: .whitespaces)
            if let created = parseTimestamp(Substring(suffix)) {
                let author = String(interior[interior.startIndex..<at])
                    .trimmingCharacters(in: .whitespaces)
                return (author.isEmpty ? nil : author, created)
            }
            end = at
        }
        let author = String(interior).trimmingCharacters(in: .whitespaces)
        return (author.isEmpty ? nil : author, nil)
    }

    // MARK: - Timestamp grammar

    /// Parses `YYYY-MM-DD`, `YYYY-MM-DD HH:MM`, or `YYYY-MM-DD HH:MM:SS` as local
    /// wall-clock. The more specific (longer) forms are tried first so a date-only
    /// formatter can't silently swallow a date-time string.
    static func parseTimestamp(_ s: Substring) -> Date? {
        let text = String(s)
        return withSeconds.date(from: text)
            ?? withoutSeconds.date(from: text)
            ?? dateOnly.date(from: text)
    }

    /// Formats a `Date` as the canonical `YYYY-MM-DD HH:MM:SS` local wall-clock.
    static func formatTimestamp(_ date: Date) -> String {
        withSeconds.string(from: date)
    }

    /// The same wall clock as `formatTimestamp` in the form an HTML
    /// `<time datetime="…">` takes: `YYYY-MM-DDTHH:MM:SS`. Deliberately
    /// zone-less. A comment's on-disk stamp is a bare local wall clock, so a
    /// *floating* date-time is its honest HTML rendering: it says the same thing
    /// the source does and reads the same on every machine.
    static func isoTimestamp(_ date: Date) -> String {
        isoWithSeconds.string(from: date)
    }

    private static let withSeconds = makeFormatter("yyyy-MM-dd HH:mm:ss")
    private static let withoutSeconds = makeFormatter("yyyy-MM-dd HH:mm")
    private static let dateOnly = makeFormatter("yyyy-MM-dd")
    private static let isoWithSeconds = makeFormatter("yyyy-MM-dd'T'HH:mm:ss")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter
    }

    // MARK: - Helpers

    /// Recursively collects the text of a node **for the quotation**: a text or
    /// inline-code node contributes its literal, a soft or hard break
    /// contributes a space, and every container joins its children. Inline code
    /// gives up its backticks here because a quotation is matched against the
    /// document's *rendered* text, where `` `foo` `` reads as `foo`.
    ///
    /// Distinct from `CMarkNode.plainText`, which maps a hard break to a
    /// newline. The quotation is the only thing flattened this way — the
    /// attribution grammar reads source text (`sourceText(of:lines:)`), which is
    /// what keeps inline code opaque to it.
    private static func plainText(of node: CMarkNode) -> String {
        switch node.kind {
        case .text, .inlineCode:
            return node.literal ?? ""
        case .softBreak, .lineBreak:
            return " "
        default:
            return node.children.map(plainText(of:)).joined()
        }
    }

    /// Collapses every run of whitespace (including block boundaries flattened by
    /// `plainText(of:)`) to a single space and trims the ends.
    private static func flatten(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The verbatim source of a run of top-level blocks: the full lines from
    /// the first block's start through the last block's end, joined exactly as
    /// they appear in `lines`. Slicing the source — rather than re-serializing
    /// each block through a Markdown formatter — is what lets an unedited
    /// message round-trip byte-for-byte. Returns nil for an empty run, or
    /// when a block reports line numbers outside the source.
    private static func sliceBody(
        _ blocks: ArraySlice<CMarkNode>, lines: [String]
    ) -> String? {
        guard let first = blocks.first, let last = blocks.last else { return nil }
        return sourceLines(from: first.startLine, to: last.endLine, lines: lines)
    }

    /// The verbatim source of one block — the same slice `sliceBody` takes, for
    /// a single node. This is what the attribution grammar reads: scanning the
    /// source rather than the flattened inline text is what keeps inline code
    /// opaque to the grammar, and what lets a message written on one line keep
    /// the Markdown in its body.
    private static func sourceText(of block: CMarkNode, lines: [String]) -> String? {
        sourceLines(from: block.startLine, to: block.endLine, lines: lines)
    }

    /// Lines `start` through `end` of the source, 1-based and inclusive, joined
    /// as they appear. Nil when the range falls outside `lines`.
    private static func sourceLines(
        from start: Int, to end: Int, lines: [String]
    ) -> String? {
        guard start >= 1, end >= start, end <= lines.count else { return nil }
        return lines[(start - 1)...(end - 1)].joined(separator: "\n")
    }
}
