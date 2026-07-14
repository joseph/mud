/// A group of consecutive, related changes in the document.
///
/// Groups are built from `DocumentChange` arrays by collapsing entries
/// that share a `groupID`. The sidebar and changes bar use these for
/// navigation and counts.
public struct ChangeGroup: Identifiable, Sendable {
    /// The group ID (e.g. "group-1"), the group's stable identity.
    public let id: String
    /// All change IDs in this group.
    public let changeIDs: [String]
    /// The primary change type in the group.
    public let type: ChangeType
    /// True when the group contains both insertions and deletions.
    public let isMixed: Bool
    /// 1-based group index, matching the overlay badge number.
    public let groupIndex: Int
    /// Per-change summaries and types, for multi-line display.
    public let members: [MemberInfo]

    /// Number of individual changes in this group.
    public var count: Int { members.count }

    /// A single change within a group.
    public struct MemberInfo: Sendable {
        public let type: ChangeType
        public let summary: String
    }

    public static func build(from changes: [DocumentChange]) -> [ChangeGroup] {
        // Group by the pre-computed groupID from CMarkDiffContext.
        // Preserve document order (first occurrence of each groupID).
        var order: [String] = []
        var buckets: [String: [DocumentChange]] = [:]

        for change in changes {
            if buckets[change.groupID] == nil {
                order.append(change.groupID)
            }
            buckets[change.groupID, default: []].append(change)
        }

        return order.compactMap { gid in
            guard let members = buckets[gid], let first = members.first
            else { return nil }
            let hasIns = members.contains { $0.type == .insertion }
            let hasDel = members.contains { $0.type == .deletion }
            let isMixed = (hasIns && hasDel)
                || members.contains(where: \.isMixed)
            return ChangeGroup(
                id: gid,
                changeIDs: members.map(\.id),
                type: hasIns ? .insertion : .deletion,
                isMixed: isMixed,
                groupIndex: first.groupIndex,
                members: members.map {
                    MemberInfo(type: $0.type, summary: $0.summary)
                }
            )
        }
    }
}
