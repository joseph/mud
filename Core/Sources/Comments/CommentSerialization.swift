import Foundation
import Markdown

/// The read/write codec for a comment definition's body — no IO. Mud *writes* a
/// strict canonical form but *reads* anything the convention in
/// `Doc/Examples/comments-spec.md` allows.
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
        // — is the root quotation. A blockquote that follows a `💬` header
        // belongs to that message's body.
        var quotation: String?
        if let first = blocks.first, let bq = first as? BlockQuote {
            quotation = flatten(plainText(of: bq))
            blocks.removeFirst()
        }

        // (2) Split the remaining blocks into messages at every paragraph that
        // *begins* with `💬`. Blocks before the first such paragraph (or all of
        // them, when there is no `💬` at all) form one implicit author-less
        // message.
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

    /// True when `block` is a paragraph whose text begins with the `💬` header
    /// emoji (after any leading whitespace). A `💬` anywhere else in running
    /// prose never splits a message.
    private static func isMessageStart(_ block: BlockMarkup) -> Bool {
        guard let para = block as? Paragraph else { return false }
        let text = plainText(of: para).drop { $0.isWhitespace }
        return text.hasPrefix(commentEmoji)
    }

    /// Builds a `CommentMessage` from its block group. The first paragraph is run
    /// through `parseAttribution`; if it yields an author or a timestamp, that
    /// paragraph is the header and the rest is the body, otherwise the whole
    /// group is an unattributed body.
    private static func buildMessage(_ blocks: [BlockMarkup]) -> CommentMessage {
        if let para = blocks.first as? Paragraph {
            let (author, created, inlineBody) = parseAttribution(plainText(of: para))
            if author != nil || created != nil {
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
    /// `💬 <author> (<timestamp>):` header per attributed message — alone on its
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

    /// The `💬 <author> (<timestamp>):` header for an attributed message, or
    /// `nil` for a bare unattributed message (which serializes as body alone).
    private static func headerLine(_ message: CommentMessage) -> String? {
        guard message.author != nil || message.created != nil else { return nil }
        var header = commentEmoji
        if let author = message.author, !author.isEmpty { header += " " + author }
        if let created = message.created {
            header += " (" + formatTimestamp(created) + ")"
        }
        return header + ":"
    }

    // MARK: - Attribution grammar

    /// Peels a leading `[💬 ]<author> (<timestamp>)[:]` from a message's first
    /// paragraph. The `💬` and trailing colon are both optional; attribution is
    /// recognized only when the parenthetical parses as a timestamp. When it does
    /// not, there is no attribution and the whole paragraph is commentary.
    static func parseAttribution(
        _ paragraphText: String
    ) -> (author: String?, created: Date?, inlineBody: String) {
        var scanner = paragraphText[...]
        scanner = scanner.drop { $0 == " " || $0 == "\t" }
        if scanner.hasPrefix(commentEmoji) {
            scanner = scanner.dropFirst(commentEmoji.count)
                .drop { $0 == " " || $0 == "\t" }
        }

        // `author (timestamp)` requires a " (" separating the two.
        guard let openParen = scanner.range(of: " (") else {
            return (nil, nil, String(scanner))
        }
        let author = scanner[scanner.startIndex..<openParen.lowerBound]
        let afterOpen = scanner[openParen.upperBound...]
        guard let closeIndex = afterOpen.firstIndex(of: ")") else {
            return (nil, nil, String(scanner))
        }
        let timestampText = afterOpen[afterOpen.startIndex..<closeIndex]
        guard let created = parseTimestamp(timestampText) else {
            return (nil, nil, String(scanner))
        }

        var rest = afterOpen[afterOpen.index(after: closeIndex)...]
        if rest.first == ":" { rest = rest.dropFirst() }
        rest = rest.drop { $0 == " " || $0 == "\t" }
        let trimmedAuthor = String(author).trimmingCharacters(in: .whitespaces)
        return (trimmedAuthor.isEmpty ? nil : trimmedAuthor, created, String(rest))
    }

    // MARK: - Timestamp grammar

    /// Parses `YYYY-MM-DD HH:MM[:SS]` (space-separated, seconds optional) as
    /// local wall-clock. The seconds form is tried first so a `HH:MM` formatter
    /// can't silently swallow a `HH:MM:SS` string.
    static func parseTimestamp(_ s: Substring) -> Date? {
        let text = String(s)
        return withSeconds.date(from: text) ?? withoutSeconds.date(from: text)
    }

    /// Formats a `Date` as the canonical `YYYY-MM-DD HH:MM:SS` local wall-clock.
    static func formatTimestamp(_ date: Date) -> String {
        withSeconds.string(from: date)
    }

    private static let withSeconds = makeFormatter("yyyy-MM-dd HH:mm:ss")
    private static let withoutSeconds = makeFormatter("yyyy-MM-dd HH:mm")

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
