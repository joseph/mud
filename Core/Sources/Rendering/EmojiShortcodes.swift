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

    /// Maps a rendered-character offset back into the raw source: returns the
    /// number of **raw** `Character`s of `raw` whose rendered form (shortcodes
    /// substituted) makes up the first `renderedCount` characters of
    /// `replaceShortcodes(in: raw)`. A `:shortcode:` span is atomic — the result
    /// never lands inside one (which would split and corrupt it), only before or
    /// after. Whitespace is untouched by substitution, so the un-collapsed
    /// alignment the anchor relies on is preserved. Used by `CommentAnchor` to
    /// place a marker byte when a text run contains emoji.
    static func rawOffset(forRendered renderedCount: Int, in raw: String) -> Int {
        if renderedCount <= 0 { return 0 }
        guard raw.contains(":") else { return min(renderedCount, raw.count) }
        let nsText = raw as NSString
        let matches = pattern.matches(
            in: raw, range: NSRange(location: 0, length: nsText.length))
        if matches.isEmpty { return min(renderedCount, raw.count) }

        var rawIdx = raw.startIndex
        var rawChars = 0   // raw Characters consumed — the answer
        var rendered = 0   // rendered Characters consumed so far
        for match in matches {
            // An unknown alias renders as-is (1:1), so skip it here and let the
            // next iteration's pre-run (or the tail) consume it as ordinary text.
            guard let range = Range(match.range, in: raw),
                  let emoji = aliasToEmoji[String(raw[range].dropFirst().dropLast())]
            else { continue }
            // Consume the unchanged run before this shortcode, one raw Character
            // to one rendered Character.
            while rawIdx < range.lowerBound {
                if rendered >= renderedCount { return rawChars }
                rawIdx = raw.index(after: rawIdx)
                rawChars += 1
                rendered += 1
            }
            // The shortcode renders as `emoji`, atomically: if reaching the target
            // means stopping within (or just before) the emoji, stop before the
            // shortcode so it isn't split.
            if rendered + emoji.count > renderedCount { return rawChars }
            rendered += emoji.count
            rawChars += raw.distance(from: range.lowerBound, to: range.upperBound)
            rawIdx = range.upperBound
        }
        // Tail after the last substituted shortcode, 1:1.
        while rawIdx < raw.endIndex, rendered < renderedCount {
            rawIdx = raw.index(after: rawIdx)
            rawChars += 1
            rendered += 1
        }
        return rawChars
    }
}
