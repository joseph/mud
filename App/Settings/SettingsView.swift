import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case markdown
    case theme
    case upMode
    case downMode
    case commandLine
    #if DEBUG
    case debugging
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .markdown: return "Markdown"
        case .theme: return "Theme"
        case .upMode: return "Up Mode"
        case .downMode: return "Down Mode"
        case .commandLine: return "Command Line"
        #if DEBUG
        case .debugging: return "Debugging"
        #endif
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .markdown: return "text.document"
        case .theme: return "paintpalette"
        case .upMode: return "arrowshape.up.circle"
        case .downMode: return "arrowshape.down.circle"
        case .commandLine: return "terminal"
        #if DEBUG
        case .debugging: return "ladybug"
        #endif
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedPane: SettingsPane = .general

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsPane.allCases, selection: $selectedPane) { pane in
                Label(pane.title, systemImage: pane.icon)
                    .tag(pane)
            }
            .toolbar(removing: .sidebarToggle)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selectedPane.title)
        }
        .frame(width: 700, height: 380)
        .preferredColorScheme(appState.lighting.isDark() ? .dark : .light)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedPane {
        case .general:
            GeneralSettingsView()
        case .markdown:
            MarkdownSettingsView()
        case .theme:
            ThemeSettingsView()
        case .upMode:
            UpModeSettingsView()
        case .downMode:
            DownModeSettingsView()
        case .commandLine:
            CommandLineSettingsView()
        #if DEBUG
        case .debugging:
            DebuggingSettingsView()
        #endif
        }
    }
}
