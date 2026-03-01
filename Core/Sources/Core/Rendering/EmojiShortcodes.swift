import Foundation

/// Replaces `:shortcode:` sequences with Unicode emoji using
/// GitHub's gemoji database (~1,800 aliases).
enum EmojiShortcodes {
    /// Alias → emoji lookup, built lazily from the bundled JSON.
    private static let aliasToEmoji: [String: String] = {
        struct Entry: Decodable {
            let emoji: String
            let aliases: [String]
        }
        guard let url = Bundle.module.url(
            forResource: "emoji", withExtension: "json"
        ), let data = try? Data(contentsOf: url),
            let entries = try? JSONDecoder().decode(
                [Entry].self, from: data
            )
        else { return [:] }

        var map: [String: String] = [:]
        map.reserveCapacity(2000)
        for entry in entries {
            for alias in entry.aliases {
                map[alias] = entry.emoji
            }
        }
        return map
    }()

    /// Matches potential shortcodes: `:` + one or more word chars / + / - + `:`.
    private static let pattern = try! NSRegularExpression(
        pattern: ":[a-zA-Z0-9_+\\-]+:"
    )

    /// Replaces known `:shortcode:` sequences with their Unicode emoji.
    /// Unknown shortcodes are left as-is. Returns immediately if the
    /// text contains no colon.
    static func replaceShortcodes(in text: String) -> String {
        guard text.contains(":") else { return text }

        let nsText = text as NSString
        let matches = pattern.matches(
            in: text, range: NSRange(location: 0, length: nsText.length)
        )
        guard !matches.isEmpty else { return text }

        var result = ""
        var lastEnd = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[lastEnd..<range.lowerBound]
            let alias = String(text[range].dropFirst().dropLast())
            if let emoji = aliasToEmoji[alias] {
                result += emoji
            } else {
                result += text[range]
            }
            lastEnd = range.upperBound
        }
        result += text[lastEnd...]
        return result
    }
}
