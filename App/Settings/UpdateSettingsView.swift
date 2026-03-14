#if SPARKLE
import Sparkle
import SwiftUI

private enum AutoUpdateMode: String, CaseIterable, Identifiable {
    case off
    case check
    case install

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .check: return "Ask before installing"
        case .install: return "Install automatically"
        }
    }
}

struct UpdateSettingsView: View {
    @AppStorage("SUEnableAutomaticChecks") private var autoCheck = true
    @AppStorage("SUAutomaticallyUpdate") private var autoInstall = false

    private var mode: Binding<AutoUpdateMode> {
        Binding(
            get: {
                if !autoCheck { return .off }
                return autoInstall ? .install : .check
            },
            set: { newMode in
                autoCheck = newMode != .off
                autoInstall = newMode == .install
            }
        )
    }

    var body: some View {
        Form {
            Picker("Automatic updates", selection: mode) {
                ForEach(AutoUpdateMode.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.radioGroup)

            Section {
                Button("Check Now") {
                    SparkleController.updater.checkForUpdates()
                }
            }

            Section {
                Text("View the latest [release notes](https://apps.josephpearson.org/mud/releases/history.html) in your browser.")
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18)
    }
}
#endif
