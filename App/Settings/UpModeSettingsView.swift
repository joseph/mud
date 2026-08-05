import MudPreferences
import MudCore
import SwiftUI

struct UpModeSettingsView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $appState.upModeAllowRemoteContent) {
                    Text("Allow remote content")
                    Text("Load remote images and other external resources referenced in Markdown documents.")
                }
            }
            Section {
                Toggle(isOn: Binding(
                    get: { appState.viewToggles.contains(.foldableHeadings) },
                    set: { _ in appState.toggle(.foldableHeadings) }
                )) {
                    Text("Foldable headings")
                    Text("Click a heading arrow in Mark Up mode to show or hide its section.")
                }
            }
            Section {
                Toggle(isOn: Binding(
                    get: { appState.enabledExtensions.contains("mermaid") },
                    set: { newValue in
                        if newValue {
                            appState.enabledExtensions.insert("mermaid")
                        } else {
                            appState.enabledExtensions.remove("mermaid")
                        }
                    }
                )) {
                    Text("Generate diagrams")
                    HStack(spacing: 0) {
                        Text("Learn more: ")
                        Button("mermaid-diagrams.md") {
                            SettingsWindowController.shared.window?.close()
                            DocumentController.openBundledDocument(
                                "mermaid-diagrams", subdirectory: "Doc/Examples")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.link)
                    }
                }
            }
            Section("Code blocks") {
                Toggle(isOn: Binding(
                    get: { appState.viewToggles.contains(.codeHeader) },
                    set: { _ in appState.toggle(.codeHeader) }
                )) {
                    Text("Language name")
                    Text("Show the name of the code language in a bar above code blocks.")
                }
                Toggle(isOn: Binding(
                    get: { appState.enabledExtensions.contains("copyCode") },
                    set: { newValue in
                        if newValue {
                            appState.enabledExtensions.insert("copyCode")
                        } else {
                            appState.enabledExtensions.remove("copyCode")
                        }
                    }
                )) {
                    Text("Copy button")
                    Text("Hover over code blocks to reveal a button that copies the contents to your clipboard.")
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }
}
