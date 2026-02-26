import SwiftUI

// MARK: - Theme color constants (mirrors CSS theme files)

struct ThemeColors {
    let bodyBg: Color
    let text: Color
    let heading: Color
    let link: Color
    let codeBg: Color
    let codeFg: Color

    struct Pair {
        let light: ThemeColors
        let dark: ThemeColors
    }
}

extension Theme {
    var colorPair: ThemeColors.Pair {
        switch self {
        case .austere:
            return ThemeColors.Pair(
                light: ThemeColors(
                    bodyBg: Color(hex: 0xFAFAFA),
                    text: Color(hex: 0x000000),
                    heading: Color(hex: 0x000000),
                    link: Color(hex: 0x0969DA),
                    codeBg: Color(hex: 0xF2F4F0),
                    codeFg: Color(hex: 0x265D1F)
                ),
                dark: ThemeColors(
                    bodyBg: Color(hex: 0x111111),
                    text: Color(hex: 0xE6E6E6),
                    heading: Color(hex: 0xE6E6E6),
                    link: Color(hex: 0x58A6FF),
                    codeBg: Color(hex: 0x1A1D18),
                    codeFg: Color(hex: 0xB1C3A2)
                )
            )
        case .blues:
            return ThemeColors.Pair(
                light: ThemeColors(
                    bodyBg: Color(hex: 0xF8F9FE),
                    text: Color(hex: 0x0D1030),
                    heading: Color(hex: 0x1B3560),
                    link: Color(hex: 0x2563EB),
                    codeBg: Color(hex: 0xEDF1FA),
                    codeFg: Color(hex: 0x0D1030)
                ),
                dark: ThemeColors(
                    bodyBg: Color(hex: 0x0E1020),
                    text: Color(hex: 0xE2E6F4),
                    heading: Color(hex: 0xA0B8E0),
                    link: Color(hex: 0x6EA8FE),
                    codeBg: Color(hex: 0x1A1D32),
                    codeFg: Color(hex: 0xE2E6F4)
                )
            )
        case .earthy:
            return ThemeColors.Pair(
                light: ThemeColors(
                    bodyBg: Color(hex: 0xFCFCFA),
                    text: Color(hex: 0x333333),
                    heading: Color(hex: 0x7A4A2A),
                    link: Color(hex: 0x8E4740),
                    codeBg: Color(hex: 0xF5F3EE),
                    codeFg: Color(hex: 0x5D662E)
                ),
                dark: ThemeColors(
                    bodyBg: Color(hex: 0x0E0C0B),
                    text: Color(hex: 0xCFC9C0),
                    heading: Color(hex: 0xD9B87C),
                    link: Color(hex: 0xC67467),
                    codeBg: Color(hex: 0x1A1816),
                    codeFg: Color(hex: 0xA8B36B)
                )
            )
        case .riot:
            return ThemeColors.Pair(
                light: ThemeColors(
                    bodyBg: Color(hex: 0xFDFCFB),
                    text: Color(hex: 0x2B2B2B),
                    heading: Color(hex: 0x6741D9),
                    link: Color(hex: 0xD6336C),
                    codeBg: Color(hex: 0xFEF6EE),
                    codeFg: Color(hex: 0xC65D07)
                ),
                dark: ThemeColors(
                    bodyBg: Color(hex: 0x14131A),
                    text: Color(hex: 0xE8E4E0),
                    heading: Color(hex: 0x9775FA),
                    link: Color(hex: 0xF06595),
                    codeBg: Color(hex: 0x1F1A1E),
                    codeFg: Color(hex: 0xFFA94D)
                )
            )
        }
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mud")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(colors.heading)

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
                    .padding(.vertical, 4)
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

// MARK: - Color hex init

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }
}
