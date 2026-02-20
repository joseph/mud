import MudCore

// MARK: - Outline Node

struct OutlineNode: Identifiable {
    let heading: OutlineHeading
    var children: [OutlineNode]
    var id: String { heading.id }

    var optionalChildren: [OutlineNode]? {
        children.isEmpty ? nil : children
    }
}

// MARK: - Tree Builder

extension OutlineNode {
    /// Builds a tree from a flat list of headings using strict nesting:
    /// any heading deeper than the current level becomes a child.
    static func buildTree(from headings: [OutlineHeading]) -> [OutlineNode] {
        var index = 0
        return buildLevel(headings: headings, index: &index, parentLevel: 0)
    }

    private static func buildLevel(
        headings: [OutlineHeading],
        index: inout Int,
        parentLevel: Int
    ) -> [OutlineNode] {
        var nodes: [OutlineNode] = []
        while index < headings.count {
            let heading = headings[index]
            if heading.level <= parentLevel {
                break
            }
            index += 1
            let children = buildLevel(
                headings: headings,
                index: &index,
                parentLevel: heading.level
            )
            nodes.append(OutlineNode(heading: heading, children: children))
        }
        return nodes
    }
}
