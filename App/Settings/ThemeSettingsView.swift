import SwiftUI
import MudPreferences
import MudCore

struct ThemeSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18),
    ]

    var body: some View {
        List {
            LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                ForEach(Theme.allCases, id: \.self) { theme in
                    ThemePreviewCard(
                        theme: theme,
                        isSelected: appState.theme == theme,
                        isDark: appState.lighting.isDark()
                    ) {
                        appState.theme = theme
                    }
                }
            }
            .padding([.horizontal, .bottom], 18)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
    }
}
