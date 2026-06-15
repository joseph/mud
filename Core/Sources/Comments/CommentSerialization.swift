import Foundation
import Markdown

/// The read/write codec for a comment definition's body — no IO. Mud *writes* a
/// strict canonical form but *reads* anything the convention in
/// `Doc/Spec/comments.md` allows.
///
/// `parse` takes the footnote definition's **de-indented body Markdown** (the
/// clean CommonMark `FootnoteProcessor` already produces via
/// `renderDefinitionBody`) and structures it into a root quotation plus ordered
/// messages. `serialize` is the strict inverse, with the round-trip invariant
/// `parse(serialize(quotation, messages)) == (quotation, messages)`.
///
/// Working on the already-de-indented body is what lets this stay pure,
/// testable Swift on the swift-markdown AST: the multi-paragraph misparse that
/// forced cmark for footnote *bodies* does not bite a pre-normalized string.
///
/// Message attributes live in **braces** — `💬 {author @ timestamp}:` — where
/// the `💬`, both fields, and the trailing colon are each optional and a
/// paragraph-leading `{` is the signal.
enum CommentSerialization {
    static let commentEmoji = "💬"

    // MARK: - Read

    /// Structures a comment definition's de-indented body Markdown into the root
    /// quotation and ordered messages.
    static func parse(
        _ bodyMarkdown: String
    ) -> (quotation: String?, messages: [CommentMessage]) {
        var blocks = Document(parsing: bodyMarkdown)
            .children.compactMap { $0 as? BlockMarkup }

        // (1) A leading blockquote — and only a leading one, before any message
        // — is the root quotation. A blockquote that follows a message header
        // belongs to that message's body.
        var quotation: String?
        if let first = blocks.first, let bq = first as? BlockQuote {
            quotation = flatten(plainText(of: bq))
            blocks.removeFirst()
        }

        // (2) Split the remaining blocks into messages at every paragraph that
        // *begins* with a message attributes block — a `💬` or a `{`. Blocks
        // before the first such paragraph (or all of them, when there is none)
        // form one implicit author-less message.
        var groups: [[BlockMarkup]] = []
        var current: [BlockMarkup] = []
        for block in blocks {
            if isMessageStart(block), !current.isEmpty {
                groups.append(current)
                current = []
            }
            current.append(block)
        }
        if !current.isEmpty { groups.append(current) }

        let messages = groups.map(buildMessage)
        return (quotation, messages)
    }

    /// True when `block` is a paragraph whose text begins (after any leading
    /// whitespace) with a message attributes block — the `💬` header emoji or a
    /// `{` brace. A `💬` or `{` anywhere else in running prose never splits a
    /// message.
    private static func isMessageStart(_ block: BlockMarkup) -> Bool {
        guard let para = block as? Paragraph else { return false }
        let text = plainText(of: para).drop { $0.isWhitespace }
        return text.hasPrefix(commentEmoji) || text.first == "{"
    }

    /// Builds a `CommentMessage` from its block group. The first paragraph is run
    /// through `parseAttribution`; when it carries a header (a `💬` and/or a
    /// `{…}` block — even an empty or partial one), that paragraph is the header
    /// and the rest is the body. Otherwise the whole group is an unattributed
    /// body.
    private static func buildMessage(_ blocks: [BlockMarkup]) -> CommentMessage {
        if let para = blocks.first as? Paragraph {
            let (author, created, inlineBody, isHeader) =
                parseAttribution(plainText(of: para))
            if isHeader {
                var parts: [String] = []
                if !inlineBody.isEmpty { parts.append(inlineBody) }
                parts.append(contentsOf: blocks.dropFirst().map(formatBlock))
                return CommentMessage(
                    author: author, created: created,
                    body: parts.joined(separator: "\n\n"))
            }
        }
        let body = blocks.map(formatBlock).joined(separator: "\n\n")
        return CommentMessage(author: nil, created: nil, body: body)
    }

    // MARK: - Write

    /// Renders a quotation + messages into the strict canonical body Markdown
    /// (un-indented): the quotation as a leading blockquote, then one
    /// `💬 {author @ timestamp}:` header per attributed message — alone on its
    /// line, commentary in the block below. The caller (`CommentEditor`) prefixes
    /// `[^label]:` and indents continuation lines by four spaces.
    static func serialize(
        quotation: String?, _ messages: [CommentMessage]
    ) -> String {
        var blocks: [String] = []
        if let quotation, !quotation.isEmpty {
            blocks.append("> " + quotation)
        }
        for message in messages {
            if let header = headerLine(message) { blocks.append(header) }
            if !message.body.isEmpty { blocks.append(message.body) }
        }
        return blocks.joined(separator: "\n\n")
    }

    /// The `💬 {author @ timestamp}:` header for an attributed message, or `nil`
    /// for a bare unattributed message (which serializes as body alone). With
    /// only one field present the brace carries just that field: `{author}` or
    /// `{@ timestamp}`.
    private static func headerLine(_ message: CommentMessage) -> String? {
        let author = message.author.flatMap { $0.isEmpty ? nil : $0 }
        guard author != nil || message.created != nil else { return nil }
        var interior = author ?? ""
        if let created = message.created {
            let stamp = formatTimestamp(created)
            interior = interior.isEmpty ? "@ \(stamp)" : "\(interior) @ \(stamp)"
        }
        return "\(commentEmoji) {\(interior)}:"
    }

    // MARK: - Attribution grammar

    /// Peels a leading message attributes block — `[💬 ]{author @ timestamp}[:]`
    /// — from a message's first paragraph. The `💬` is optional and the braces
    /// are the signal: a paragraph that (after an optional `💬`) begins with `{`
    /// carries attributes, even when they are empty (`{}`) or hold one field. A
    /// `💬` with no following brace is itself a (no-attribute) header. The
    /// returned `isHeader` lets the caller peel such a bare marker even when it
    /// yields no author or timestamp.
    ///
    /// Inside the braces, the **last** `@` whose trailing text parses as a
    /// timestamp splits `author` from `created`; with no such `@` the whole
    /// interior is the author (so an author may contain `@`).
    static func parseAttribution(
        _ paragraphText: String
    ) -> (author: String?, created: Date?, inlineBody: String, isHeader: Bool) {
        var scanner = paragraphText[...]
        scanner = scanner.drop { $0 == " " || $0 == "\t" }

        var sawEmoji = false
        if scanner.hasPrefix(commentEmoji) {
            sawEmoji = true
            scanner = scanner.dropFirst(commentEmoji.count)
                .drop { $0 == " " || $0 == "\t" }
        }

        // Brace form (canonical). The `{…}` must open the (post-💬) text; a `{`
        // later in the paragraph is ordinary prose.
        if scanner.first == "{", let close = scanner.firstIndex(of: "}") {
            let interior = scanner[scanner.index(after: scanner.startIndex)..<close]
            let (author, created) = parseBraceInterior(interior)
            // The colon is optional but, when present, must *immediately* follow
            // `}` — a space before it makes the colon message content.
            var rest = scanner[scanner.index(after: close)...]
            if rest.first == ":" { rest = rest.dropFirst() }
            rest = rest.drop { $0 == " " || $0 == "\t" }
            return (author, created, String(rest), true)
        }

        // A bare `💬` with no brace is still a header carrying no attributes.
        if sawEmoji {
            return (nil, nil, String(scanner), true)
        }

        return (nil, nil, paragraphText, false)
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

    private static let withSeconds = makeFormatter("yyyy-MM-dd HH:mm:ss")
    private static let withoutSeconds = makeFormatter("yyyy-MM-dd HH:mm")
    private static let dateOnly = makeFormatter("yyyy-MM-dd")

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter
    }

    // MARK: - Helpers

    /// Recursively collects the text of a markup node. `plainText` is not
    /// available on every block type (notably `BlockQuote`), so we walk the
    /// inline descendants ourselves: `Text` and `InlineCode` contribute their
    /// content; breaks contribute a space.
    private static func plainText(of markup: Markup) -> String {
        if let text = markup as? Markdown.Text { return text.string }
        if let code = markup as? InlineCode { return code.code }
        if markup is SoftBreak || markup is LineBreak { return " " }
        return markup.children.map(plainText(of:)).joined()
    }

    /// Collapses every run of whitespace (including block boundaries flattened by
    /// `plainText(of:)`) to a single space and trims the ends.
    private static func flatten(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Renders a block back to Markdown, trimming the formatter's trailing
    /// newline so joins stay uniform.
    private static func formatBlock(_ block: BlockMarkup) -> String {
        block.format().trimmingCharacters(in: .newlines)
    }
}
