import MudCore
import SwiftUI

// MARK: - Theme colors (parsed from CSS)

struct ThemeColors {
    let bodyBg: Color
    let text: Color
    let heading: Color
    let link: Color
    let codeBg: Color
    let codeFg: Color
    let border: Color

    struct Pair {
        let light: ThemeColors
        let dark: ThemeColors
    }
}

extension Theme {
    var colorPair: ThemeColors.Pair {
        let css = HTMLTemplate.themeCSS(for: rawValue)
        let light = Self.parseProperties(from: css, dark: false)
        let dark = Self.parseProperties(from: css, dark: true)
        return ThemeColors.Pair(
            light: ThemeColors(properties: light),
            dark: ThemeColors(properties: dark)
        )
    }

    /// Extracts CSS custom properties as name→hex-value pairs from a theme
    /// stylesheet.  When `dark` is true, parses the
    /// `@media (prefers-color-scheme: dark)` block; otherwise parses the
    /// top-level `:root` block.
    private static func parseProperties(
        from css: String, dark: Bool
    ) -> [String: String] {
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

private extension ThemeColors {
    init(properties: [String: String]) {
        self.init(
            bodyBg: Color(cssHex: properties["body-bg"]),
            text: Color(cssHex: properties["text-color"]),
            heading: Color(cssHex: properties["heading-color"]),
            link: Color(cssHex: properties["link-color"]),
            codeBg: Color(cssHex: properties["code-bg"]),
            codeFg: Color(cssHex: properties["code-fg"]),
            border: Color(cssHex: properties["border-color"])
        )
    }
}

// MARK: - Preview card

struct ThemePreviewCard: View {
    let theme: Theme
    let isSelected: Bool
    let isDark: Bool
    let action: () -> Void

    private var colors: ThemeColors {
        isDark ? theme.colorPair.dark : theme.colorPair.light
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                VStack(alignment: .leading) {
                    Text(theme.rawValue.capitalized)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(colors.heading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(colors.border)
                                .frame(height: 1)
                        }

                    (Text("Paragraph text, containing ")
                        .foregroundStyle(colors.text)
                    + Text("a link")
                        .foregroundStyle(colors.link)
                    + Text(".")
                        .foregroundStyle(colors.text))
                        .font(.system(size: 11))

                    VStack(alignment: .leading, spacing: 0) {
                        Text("code_block do")
                        Text("  ...")
                        Text("end")
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(colors.codeFg)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(colors.codeBg)
                    )
                }
                .padding(10)
                .frame(width: 200, height: 120, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(colors.bodyBg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            isSelected ? Color.accentColor : .gray.opacity(0.3),
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                Text(theme.rawValue.capitalized)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Color from CSS hex string

private extension Color {
    /// Creates a Color from a CSS hex string (`#RGB`, `#RRGGBB`, or
    /// `#RRGGBBAA`).  Returns `.clear` for nil or malformed input.
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
}
