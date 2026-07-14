import Foundation

/// Visual category for GFM alerts and DocC asides.
public enum AlertCategory: String, CaseIterable, Sendable {
    case note, tip, important, warning, caution, status

    var cssClass: String { "alert-\(rawValue)" }

    public var title: String { rawValue.capitalized }

    /// URL of the icon SVG resource (GitHub Octicons, MIT licensed).
    public var iconURL: URL? {
        Bundle.module.url(forResource: "alert-\(rawValue)", withExtension: "svg")
    }

    /// Inline SVG icon string (GitHub Octicons, MIT licensed).
    var icon: String { Self.icons[self]! }

    private static let icons: [AlertCategory: String] = {
        var map: [AlertCategory: String] = [:]
        for category in allCases {
            let name = "alert-\(category.rawValue)"
            guard let url = Bundle.module.url(
                forResource: name, withExtension: "svg"
            ), let svg = try? String(
                contentsOf: url, encoding: .utf8
            ) else { continue }
            map[category] = svg.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return map
    }()
}

/// Controls how DocC asides are processed.
public enum DocCAlertMode: String, CaseIterable, Sendable {
    /// No DocC asides are processed; all blockquotes render as plain.
    case off
    /// Only the 6 canonical DocC kinds are processed.
    case common
    /// All DocC kinds, including extended aliases, are processed.
    case extended
}

/// Detects GFM alerts and DocC asides in blockquote nodes, mapping them
/// to visual alert categories.
///
/// The six canonical DocC kinds map to a category when `docCAlertMode` is
/// `.common` or `.extended`. Extended aliases map only when `.extended`.
/// When `.off`, no DocC asides are processed.
struct AlertDetector {
    /// Controls which DocC asides are processed.
    var docCAlertMode: DocCAlertMode = .extended

    // MARK: - GFM detection

    private static let gfmAlertTags: [(String, AlertCategory)] = [
        ("[!NOTE]", .note), ("[!TIP]", .tip), ("[!IMPORTANT]", .important),
        ("[!STATUS]", .status),
        ("[!WARNING]", .warning), ("[!CAUTION]", .caution),
    ]

    /// Returns the alert category and display title for a GFM blockquote,
    /// or nil if the blockquote does not begin with a recognised `[!TAG]`.
    func detectGFMAlert(_ blockQuote: CMarkNode) -> (AlertCategory, String)? {
        guard let paragraph = blockQuote.firstChild,
              paragraph.kind == .paragraph else { return nil }
        let text = paragraph.plainText
        guard text.hasPrefix("[!") else { return nil }
        for (tag, category) in Self.gfmAlertTags where text.hasPrefix(tag) {
            return (category, category.title)
        }
        return nil
    }

    // MARK: - DocC detection

    /// Core DocC kinds — the six canonical categories in their DocC form.
    /// Active when `docCAlertMode` is `.common` or `.extended`.
    /// Internal (not private) so the parity tests can sweep every tag.
    static let coreMap: [String: AlertCategory] = [
        "Note":      .note,
        "Tip":       .tip,
        "Important": .important,
        "Warning":   .warning,
        "Caution":   .caution,
        "Status":    .status,
    ]

    /// Extended DocC aliases — non-canonical kinds that map to a common
    /// category. Active only when `docCAlertMode` is `.extended`.
    /// Internal (not private) so the parity tests can sweep every tag.
    static let extendedMap: [String: AlertCategory] = [
        // Note
        "Remark":             .note,
        "Complexity":         .note,
        "Author":             .note,
        "Authors":            .note,
        "Copyright":          .note,
        "Date":               .note,
        "Since":              .note,
        "Version":            .note,
        "SeeAlso":            .note,
        "MutatingVariant":    .note,
        "NonMutatingVariant": .note,
        // Status
        "ToDo":               .status,
        // Tip
        "Experiment":         .tip,
        // Important
        "Attention":          .important,
        // Warning
        "Precondition":       .warning,
        "Postcondition":      .warning,
        "Requires":           .warning,
        "Invariant":          .warning,
        // Caution
        "Bug":                .caution,
        "Throws":             .caution,
        "Error":              .caution,
    ]

    /// Returns the alert category, display title, and the UTF-8 byte length
    /// of the leading `Kind:` tag for a DocC aside blockquote, or nil if the
    /// blockquote is not a recognised aside (or if `docCAlertMode` excludes
    /// it). Parses the tag itself rather than using swift-markdown's `Aside`,
    /// which splices a shortened text node into a rebuilt tree and can crash
    /// on smart-typography input when the decoded string outgrows its source
    /// span; measuring the literal directly has no arithmetic that can invert.
    /// The caller skips `tagByteLength` bytes when it renders the first
    /// paragraph.
    func detectDocCAlert(
        _ blockQuote: CMarkNode
    ) -> (category: AlertCategory, title: String, tagByteLength: Int)? {
        guard docCAlertMode != .off else { return nil }
        guard let (tag, byteLength) = Self.parseAsideTag(blockQuote) else {
            return nil
        }
        if let category = Self.coreMap[tag] {
            return (category, Self.docCDisplayName(for: tag), byteLength)
        }
        if docCAlertMode == .extended, let category = Self.extendedMap[tag] {
            return (category, Self.docCDisplayName(for: tag), byteLength)
        }
        return nil
    }

    /// Parses a leading `Kind:` tag off `blockQuote`'s first paragraph's
    /// first text node. Returns the raw tag and the UTF-8 byte length of the
    /// tag plus its colon and any trailing spaces/tabs, or nil if there's no
    /// leading text node or no colon in it.
    ///
    /// Unlike `Aside.parseAsideTag`, this never compares the decoded string
    /// against a source byte range — it only measures substrings of the
    /// (already smart-typography-substituted) literal itself — so there is
    /// no arithmetic that can invert and crash.
    private static func parseAsideTag(
        _ blockQuote: CMarkNode
    ) -> (tag: String, byteLength: Int)? {
        guard let paragraph = blockQuote.firstChild,
              paragraph.kind == .paragraph,
              let text = paragraph.firstChild, text.kind == .text,
              let literal = text.literal,
              let colonIndex = literal.firstIndex(of: ":")
        else { return nil }

        let tag = String(literal[..<colonIndex])
        let afterColon = literal[literal.index(after: colonIndex)...]
        let trailingWhitespace = afterColon.prefix { $0 == " " || $0 == "\t" }
        return (tag, tag.utf8.count + 1 + trailingWhitespace.utf8.count)
    }

    /// The aside's display title — matches swift-markdown's
    /// `Aside.Kind.displayName` for the tags this app recognizes.
    private static func docCDisplayName(for tag: String) -> String {
        switch tag {
        case "SeeAlso": return "See Also"
        case "NonMutatingVariant": return "Non-Mutating Variant"
        case "MutatingVariant": return "Mutating Variant"
        case "ToDo": return "To Do"
        default: return tag
        }
    }
}
