import SwiftUI

// MARK: - CSS color parsing

extension Color {
    /// Creates a Color from a CSS hex string (`#RGB`, `#RRGGBB`, or
    /// `#RRGGBBAA`). Returns `.clear` for nil or malformed input.
    init(cssHex hex: String?) {
        guard let hex = hex?.trimmingCharacters(in: ["#"]),
              !hex.isEmpty else {
            self = .clear
            return
        }

        let expanded: String
        switch hex.count {
        case 3:
            expanded = hex.map { "\($0)\($0)" }.joined()
        case 4:
            expanded = hex.map { "\($0)\($0)" }.joined()
        case 6, 8:
            expanded = hex
        default:
            self = .clear
            return
        }

        guard let value = UInt64(expanded, radix: 16) else {
            self = .clear
            return
        }

        if expanded.count == 8 {
            self.init(
                red: Double((value >> 24) & 0xFF) / 255.0,
                green: Double((value >> 16) & 0xFF) / 255.0,
                blue: Double((value >> 8) & 0xFF) / 255.0,
                opacity: Double(value & 0xFF) / 255.0
            )
        } else {
            self.init(
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0
            )
        }
    }

    /// Parses CSS custom property values (`--name: #hexvalue`) from a CSS
    /// stylesheet. When `dark` is true, parses the
    /// `@media (prefers-color-scheme: dark)` block; otherwise the top-level
    /// `:root` block.
    static func cssProperties(from css: String, dark: Bool) -> [String: String] {
        let section: String
        if dark {
            guard let range = css.range(
                of: "prefers-color-scheme:\\s*dark",
                options: .regularExpression
            ) else { return [:] }
            section = String(css[range.lowerBound...])
        } else {
            section = css.components(separatedBy: "@media").first ?? css
        }

        var result: [String: String] = [:]
        let pattern = #"--([a-z-]+):\s*(#[0-9A-Fa-f]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return result
        }
        let nsSection = section as NSString
        let matches = regex.matches(
            in: section,
            range: NSRange(location: 0, length: nsSection.length)
        )
        for match in matches {
            let name = nsSection.substring(with: match.range(at: 1))
            let value = nsSection.substring(with: match.range(at: 2))
            result[name] = value
        }
        return result
    }
}
