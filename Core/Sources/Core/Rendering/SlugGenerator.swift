import Foundation

/// Generates GitHub-style heading slugs for anchor links.
enum SlugGenerator {
    /// Converts heading text to a GitHub-style slug.
    ///
    /// Lowercases, strips non-word characters (except hyphens and spaces),
    /// trims whitespace, and converts spaces to hyphens.
    static func slugify(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(
                of: #"[^\w\s-]"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(
                of: #"\s+"#,
                with: "-",
                options: .regularExpression
            )
    }

    /// Stateful slug tracker that deduplicates within a single
    /// document walk.  First occurrence gets the bare slug; repeats
    /// get `-1`, `-2`, etc. — matching GitHub behavior.
    struct Tracker {
        private var counts: [String: Int] = [:]

        mutating func slug(for text: String) -> String {
            let base = SlugGenerator.slugify(text)
            let n = counts[base, default: 0]
            counts[base] = n + 1
            return n == 0 ? base : "\(base)-\(n)"
        }
    }
}
