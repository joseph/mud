import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(Theme.allCases, id: \.self) { theme in
                ThemePreviewCard(
                    theme: theme,
                    isSelected: appState.theme == theme,
                    isDark: appState.lighting.isDark()
                ) {
                    appState.theme = theme
                    appState.saveTheme(theme)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
