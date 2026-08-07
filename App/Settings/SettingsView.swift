import SwiftUI
import MudPreferences

enum SettingsPane: String, CaseIterable, Identifiable {
    case general
    case markdown
    case theme
    case changes
    case comments
    case upMode
    case downMode
    case commandLine
    #if SPARKLE
    case updates
    #endif
    #if DEBUG
    case debugging
    #endif

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .markdown: return "Markdown"
        case .theme: return "Theme"
        case .changes: return "Change Tracking"
        case .comments: return "Comments"
        case .upMode: return "Up Mode"
        case .downMode: return "Down Mode"
        case .commandLine: return "Command Line"
        #if SPARKLE
        case .updates: return "Updates"
        #endif
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
        case .changes: return "document.badge.clock"
        case .comments: return "text.bubble"
        case .upMode: return "arrow.uturn.up.circle"
        case .downMode: return "arrow.uturn.down.circle"
        case .commandLine: return "terminal"
        #if SPARKLE
        case .updates: return "arrow.triangle.2.circlepath"
        #endif
        #if DEBUG
        case .debugging: return "ladybug"
        #endif
        }
    }
}

struct SettingsView: View {
    /// The window's size: a fixed width, and a height the user can drag
    /// between the two bounds. `SettingsWindowController` reads these for the
    /// window's own limits, opens at `defHeight`, and asks the hosting
    /// controller to turn the frame below into the constraints the window
    /// resizes against.
    static let width: CGFloat = 700
    static let defHeight: CGFloat = 512
    static let minHeight: CGFloat = 420
    static let maxHeight: CGFloat = 900

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
        .frame(
            minWidth: Self.width, maxWidth: Self.width,
            minHeight: Self.minHeight, maxHeight: Self.maxHeight)
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
        case .changes:
            ChangesSettingsView()
        case .comments:
            CommentsSettingsView()
        case .upMode:
            UpModeSettingsView()
        case .downMode:
            DownModeSettingsView()
        case .commandLine:
            CommandLineSettingsView()
        #if SPARKLE
        case .updates:
            UpdateSettingsView()
        #endif
        #if DEBUG
        case .debugging:
            DebuggingSettingsView()
        #endif
        }
    }
}
