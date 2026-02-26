import SwiftUI

enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
    case theme
    case commandLine
    case upMode
    case downMode

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .theme: return "Theme"
        case .commandLine: return "Command Line"
        case .upMode: return "Up Mode"
        case .downMode: return "Down Mode"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .theme: return "paintpalette"
        case .commandLine: return "terminal"
        case .upMode: return "arrowshape.up.circle"
        case .downMode: return "arrowshape.down.circle"
        }
    }

    /// Categories visible in the current environment.
    /// Filters out sandbox-incompatible items in App Store builds.
    static var visible: [SettingsCategory] {
        allCases.filter { category in
            switch category {
            case .commandLine: return !isSandboxed
            default: return true
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedCategory: SettingsCategory = .general

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsCategory.visible, selection: $selectedCategory) { category in
                Label(category.title, systemImage: category.icon)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: 6)
            }
            .frame(width: 180)

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 700, height: 380)
        .preferredColorScheme(appState.lighting.isDark() ? .dark : .light)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedCategory {
        case .general:
            GeneralSettingsView()
        case .theme:
            ThemeSettingsView()
        case .commandLine:
            CommandLineSettingsView()
        case .upMode:
            UpModeSettingsView()
        case .downMode:
            DownModeSettingsView()
        }
    }
}
