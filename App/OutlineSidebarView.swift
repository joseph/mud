import SwiftUI
import MudCore

// MARK: - Outline Sidebar View

struct OutlineSidebarView: View {
    @ObservedObject var state: DocumentState
    var onSelect: (OutlineHeading) -> Void

    @State private var selection: String?
    @State private var expandedIDs: Set<String> = []

    private var tree: [OutlineNode] {
        OutlineNode.buildTree(from: state.outlineHeadings)
    }

    var body: some View {
        Group {
            if state.outlineHeadings.isEmpty {
                ContentUnavailableView(
                    "No Headings",
                    systemImage: "list.bullet.indent",
                    description: Text("This document has no headings.")
                )
            } else {
                List(selection: $selection) {
                    ForEach(tree) { node in
                        OutlineNodeRow(node: node, expandedIDs: $expandedIDs)
                    }
                }
                .listStyle(.sidebar)
                .onAppear {
                    expandedIDs = collectParentIDs(tree)
                }
                .onChange(of: state.outlineHeadings) { _, _ in
                    expandedIDs = collectParentIDs(tree)
                }
                .onChange(of: selection) { _, newValue in
                    guard let id = newValue,
                          let heading = state.outlineHeadings.first(
                              where: { $0.id == id }
                          ) else { return }
                    onSelect(heading)
                }
            }
        }
    }

    private func collectParentIDs(_ nodes: [OutlineNode]) -> Set<String> {
        var ids = Set<String>()
        for node in nodes where !node.children.isEmpty {
            ids.insert(node.id)
            ids.formUnion(collectParentIDs(node.children))
        }
        return ids
    }
}

// MARK: - Outline Node Row

private struct OutlineNodeRow: View {
    let node: OutlineNode
    @Binding var expandedIDs: Set<String>

    var body: some View {
        if node.children.isEmpty {
            label
        } else {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedIDs.contains(node.id) },
                    set: { newValue in
                        if newValue {
                            expandedIDs.insert(node.id)
                        } else {
                            expandedIDs.remove(node.id)
                        }
                    }
                )
            ) {
                ForEach(node.children) { child in
                    OutlineNodeRow(node: child, expandedIDs: $expandedIDs)
                }
            } label: {
                label
            }
        }
    }

    private var label: some View {
        styledText(from: node.heading.segments)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func styledText(
        from segments: [OutlineTextSegment]
    ) -> Text {
        segments.reduce(Text("")) { result, segment in
            switch segment {
            case .plain(let str):
                return result + Text(str)
            case .code(let str):
                return result + Text(str).font(
                    .system(.body, design: .monospaced)
                )
            }
        }
    }
}
