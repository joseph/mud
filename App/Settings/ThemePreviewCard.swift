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
        return ThemeColors.Pair(
            light: ThemeColors(properties: Color.cssProperties(from: css, dark: false)),
            dark: ThemeColors(properties: Color.cssProperties(from: css, dark: true))
        )
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
                .frame(maxWidth: .infinity, alignment: .topLeading)
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

