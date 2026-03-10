import Foundation
import Markdown

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

/// Detects GFM alerts and DocC asides in blockquote nodes, mapping them
/// to visual alert categories.
///
/// Core DocC kinds (the six canonical categories) always map to a category.
/// Extended DocC aliases map only when `showExtendedAlerts` is true;
/// otherwise those blockquotes are left unstyled.
struct AlertDetector {
    /// When false, extended DocC aliases render as plain blockquotes.
    var showExtendedAlerts: Bool = true

    // MARK: - GFM detection

    private static let gfmAlertTags: [(String, AlertCategory)] = [
        ("[!NOTE]", .note), ("[!TIP]", .tip), ("[!IMPORTANT]", .important),
        ("[!STATUS]", .status),
        ("[!WARNING]", .warning), ("[!CAUTION]", .caution),
    ]

    /// Returns the alert category and display title for a GFM blockquote,
    /// or nil if the blockquote does not begin with a recognised `[!TAG]`.
    func detectGFMAlert(_ blockQuote: BlockQuote) -> (AlertCategory, String)? {
        let children = Array(blockQuote.children)
        guard let paragraph = children.first as? Paragraph else { return nil }
        let text = paragraph.plainText
        guard text.hasPrefix("[!") else { return nil }
        for (tag, category) in Self.gfmAlertTags where text.hasPrefix(tag) {
            return (category, category.title)
        }
        return nil
    }

    // MARK: - DocC detection

    /// Core DocC kinds — the six canonical categories in their DocC form.
    /// Always active regardless of `showExtendedAlerts`.
    private static let coreMap: [String: AlertCategory] = [
        "Note":      .note,
        "Tip":       .tip,
        "Important": .important,
        "Warning":   .warning,
        "Caution":   .caution,
        "Status":    .status,
    ]

    /// Extended DocC aliases — non-canonical kinds that map to a common
    /// category. Active only when `showExtendedAlerts` is true.
    private static let extendedMap: [String: AlertCategory] = [
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

    /// Returns the alert category, display title, and tag-stripped content
    /// for a DocC aside blockquote, or nil if the blockquote is not a
    /// recognised aside (or if it is an extended alias and
    /// `showExtendedAlerts` is false).
    func detectDocCAlert(
        _ blockQuote: BlockQuote
    ) -> (AlertCategory, String, [BlockMarkup])? {
        guard let aside = Aside(
            blockQuote, tagRequirement: .requireAnyLengthTag
        ) else { return nil }
        let raw = aside.kind.rawValue
        if let category = Self.coreMap[raw] {
            return (category, aside.kind.displayName, aside.content)
        }
        if showExtendedAlerts, let category = Self.extendedMap[raw] {
            return (category, aside.kind.displayName, aside.content)
        }
        return nil
    }
}
