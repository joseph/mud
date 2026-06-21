import SwiftUI
import MudPreferences
import MudCore

struct SidebarView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject var state: DocumentState
    @ObservedObject var changeTracker: ChangeTracker
    var onSelectHeading: (OutlineHeading) -> Void
    var onSelectChange: ([String]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $appState.sidebarPane) {
                Text("Outline").tag(SidebarPane.outline)
                Text("Changes").tag(SidebarPane.changes)
            }
            .pickerStyle(.segmented)
            .padding(8)

            Group {
                switch appState.sidebarPane {
                case .outline:
                    OutlineSidebarView(state: state, onSelect: onSelectHeading)
                case .changes:
                    ChangesSidebarView(changeTracker: changeTracker,
                                       onSelectChange: onSelectChange)
                }
            }
            .animation(.none, value: appState.sidebarPane)
        }
    }
}
