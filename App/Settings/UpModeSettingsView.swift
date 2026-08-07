import AppKit
import MudPreferences
import MudCore
import SwiftUI

struct UpModeSettingsView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var access = AssetAccessStore.shared

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(
                    get: { appState.viewToggles.contains(.foldableHeadings) },
                    set: { _ in appState.toggle(.foldableHeadings) }
                )) {
                    Text("Foldable headings")
                    Text("Click the arrow beside a heading to show or hide its section.")
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
                    Text("Hover over code blocks for a button that copies it to your clipboard.")
                }
            }
            Section("Content permissions") {
                Toggle(isOn: $appState.upModeAllowRemoteContent) {
                    Text("Allow remote content")
                    Text("Load images and other resources from the web.")
                }
                // Only the sandboxed build needs permission to read a local
                // file. An unsandboxed Mud reads whatever the file system
                // allows, so an always-empty list here would describe a
                // restriction that doesn't exist.
                if isSandboxed {
                    grantedFolders
                }
            }
        }
        .formStyle(.grouped)
        .padding(.top, -18) // XXX-03-2026-JP -- hack to align top-of-pane with top-of-sidebar
    }

    /// The folders Mud may read local content from, one row each, under a
    /// header row carrying the Add button.
    ///
    /// Add exists so this isn't only somewhere a permission can be taken away.
    /// A reader who knows where their images live can say so here rather than
    /// waiting to meet a document that doesn't show them.
    @ViewBuilder
    private var grantedFolders: some View {
        LabeledContent {
            Button("Add…") {
                access.requestAccess(in: SettingsWindowController.shared.window)
            }
        } label: {
            Text("Allow local content from:")
            Text("Mud can show images and other local files in these folders.")
        }

        if !access.grants.isEmpty {
            ForEach(access.grants) { grant in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: grant.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                        .opacity(grant.isAvailable ? 1 : 0.5)
                    // Middle-truncated: the folder's own name is the end of the
                    // path and the part worth keeping.
                    Text(displayPath(grant.path))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(pathStyle(grant))
                        .help(grant.path)
                    if !grant.isAvailable {
                        Text("Unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help(Self.unavailableHelp)
                    }
                    Spacer()
                    Button {
                        access.revoke(grant)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        "Remove \((grant.path as NSString).lastPathComponent)")
                }
            }
        }
    }

    /// A folder Mud can't reach right now is dimmed, so the list reads at a
    /// glance as what is working and what isn't. Named rather than written
    /// inline because a ternary of two leading-dot shape styles has no type to
    /// be inferred from.
    private func pathStyle(
        _ grant: AssetAccessStore.Grant
    ) -> HierarchicalShapeStyle {
        return grant.isAvailable ? .primary : .secondary
    }

    /// Why a row says "Unavailable", for the reader who hovers it. The
    /// permission is real and kept; it is the folder that isn't here.
    private static let unavailableHelp =
        "Mud couldn’t find this folder when it started. It may be on a disk "
        + "that isn’t connected. The permission is kept, and works again once "
        + "the folder is back."

    /// The reader's own way of writing the path — `~/Documents/Notes` rather
    /// than the container-relative absolute path.
    private func displayPath(_ path: String) -> String {
        return (path as NSString).abbreviatingWithTildeInPath
    }
}
