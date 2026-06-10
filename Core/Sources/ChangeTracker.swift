import Foundation
import Combine

// MARK: - Waypoint

public struct Waypoint: Identifiable, Sendable {
    public enum Kind: Equatable, Sendable {
        case initial, reload, accept
        /// A waypoint injected from outside the normal reload flow (e.g. git).
        case external(label: String, detail: String?)
    }
    public let id = UUID()
    public let parsed: ParsedMarkdown
    public let timestamp: Date
    public let kind: Kind

    public init(parsed: ParsedMarkdown, timestamp: Date, kind: Kind) {
        self.parsed = parsed
        self.timestamp = timestamp
        self.kind = kind
    }
}

// MARK: - Change Menu Item

public struct ChangeMenuItem: Identifiable {
    public let id: UUID
    public let label: String
    public let timestamp: Date
    public let changeCount: Int
    public let isActive: Bool
    public let hasInsertions: Bool
    public let hasDeletions: Bool
    public let detail: String?
    public let isExternal: Bool

    public init(
        id: UUID, label: String, timestamp: Date, changeCount: Int,
        isActive: Bool, hasInsertions: Bool, hasDeletions: Bool,
        detail: String? = nil, isExternal: Bool = false
    ) {
        self.id = id
        self.label = label
        self.timestamp = timestamp
        self.changeCount = changeCount
        self.isActive = isActive
        self.hasInsertions = hasInsertions
        self.hasDeletions = hasDeletions
        self.detail = detail
        self.isExternal = isExternal
    }
}

// MARK: - Change Tracker

public class ChangeTracker: ObservableObject {
    @Published public private(set) var waypoints: [Waypoint] = []
    @Published public private(set) var changes: [DocumentChange] = []
    @Published public var selectedChangeID: String?
    @Published public private(set) var activeWaypointID: UUID?

    /// The most recent content passed to `update(_:)`.
    public private(set) var currentParsed: ParsedMarkdown?

    /// Per-waypoint diff summary cache. Cleared when content or waypoints
    /// change; time-bucket assignment and labels are recomputed every call.
    private var diffCache: [UUID: DiffSummary] = [:]

    /// Maximum number of `.reload` waypoints to retain. Older reloads are
    /// pruned once this cap is exceeded; `.initial` and `.accept` waypoints
    /// don't count toward the cap and are never pruned.
    static let maxReloadCount = 10

    public init() {}

    // MARK: - Active waypoint

    /// The waypoint the diff is computed against.
    public var activeWaypoint: ParsedMarkdown? {
        if let id = activeWaypointID,
           let waypoint = waypoints.first(where: { $0.id == id }) {
            return waypoint.parsed
        }
        // Fall back to most recent .accept, then .initial.
        if let accept = waypoints.last(where: { $0.kind == .accept }) {
            return accept.parsed
        }
        return waypoints.first(where: { $0.kind == .initial })?.parsed
    }

    /// The timestamp of the active waypoint (for bar display).
    public var activeWaypointTimestamp: Date? {
        if let id = activeWaypointID,
           let waypoint = waypoints.first(where: { $0.id == id }) {
            return waypoint.timestamp
        }
        if let accept = waypoints.last(where: { $0.kind == .accept }) {
            return accept.timestamp
        }
        return waypoints.first(where: { $0.kind == .initial })?.timestamp
    }

    // MARK: - Update

    /// Returns true when a save should be treated as a no-op and not
    /// stored as its own waypoint. Catches two cases:
    ///
    /// 1. Raw-text duplicates of any existing waypoint
    ///    (`ParsedMarkdown ==` is byte-for-byte).
    /// 2. Saves that are AST-equivalent to the most recent non-external
    ///    waypoint — e.g. a save that only edits blank lines. Without
    ///    this, the menu would later render a redundant gap entry.
    ///
    /// The cheap raw-text check runs first so the AST diff is only
    /// computed when necessary.
    private func isRedundantSave(_ parsed: ParsedMarkdown) -> Bool {
        if waypoints.contains(where: { $0.parsed == parsed }) {
            return true
        }
        let mostRecent = waypoints.last { wp in
            if case .external = wp.kind { return false }
            return true
        }
        guard let mostRecent else { return false }
        return MudCore.computeChanges(
            old: mostRecent.parsed, new: parsed).isEmpty
    }

    /// Called on each file load. On the first call, creates the initial
    /// waypoint (no changes). On subsequent calls, diffs against the
    /// active waypoint and updates the change list.
    public func update(_ parsed: ParsedMarkdown) {
        update(parsed, at: Date())
    }

    /// Testable variant that accepts a timestamp.
    func update(_ parsed: ParsedMarkdown, at now: Date) {
        currentParsed = parsed
        diffCache = [:]

        if waypoints.isEmpty {
            waypoints.append(Waypoint(
                parsed: parsed, timestamp: now, kind: .initial))
        } else {
            if !isRedundantSave(parsed) {
                // Coalesce: keep at most one .reload per absolute minute
                // (the most recent). Drop any existing reload that shares
                // the new save's minute, then append.
                let nowMinute = Self.absoluteMinute(now)
                waypoints.removeAll { waypoint in
                    waypoint.kind == .reload
                        && Self.absoluteMinute(waypoint.timestamp) == nowMinute
                }
                waypoints.append(Waypoint(
                    parsed: parsed, timestamp: now, kind: .reload))

                // Cap reload waypoints. Drop oldest first.
                let reloads = waypoints
                    .filter { $0.kind == .reload }
                    .sorted { $0.timestamp < $1.timestamp }
                if reloads.count > Self.maxReloadCount {
                    let dropCount = reloads.count - Self.maxReloadCount
                    let dropIDs = Set(reloads.prefix(dropCount).map(\.id))
                    waypoints.removeAll { dropIDs.contains($0.id) }

                    // If pruning removed the user's selected waypoint,
                    // fall back to the default.
                    if let id = activeWaypointID,
                       !waypoints.contains(where: { $0.id == id }) {
                        selectWaypoint(nil)
                    }
                }
            }

            // Diff against the active waypoint.
            if let waypoint = activeWaypoint {
                changes = MudCore.computeChanges(old: waypoint, new: parsed)
            }
        }
    }

    // MARK: - Select waypoint

    /// Selects a waypoint as the diff reference and recomputes changes.
    public func selectWaypoint(_ id: UUID?) {
        activeWaypointID = id
        if let current = currentParsed, let waypoint = activeWaypoint {
            changes = MudCore.computeChanges(old: waypoint, new: current)
        } else {
            changes = []
        }
        selectedChangeID = nil
    }

    // MARK: - Accept

    /// Accepts the current content as a new waypoint. Clears all changes
    /// until the next file modification.
    public func accept() {
        guard currentParsed != nil else { return }
        acceptAt(Date())
    }

    /// Testable variant that accepts a timestamp.
    func acceptAt(_ now: Date) {
        guard let current = currentParsed else { return }

        // Replace existing .accept waypoint, or append.
        if let index = waypoints.firstIndex(where: { $0.kind == .accept }) {
            waypoints[index] = Waypoint(
                parsed: current, timestamp: now, kind: .accept)
        } else {
            waypoints.append(Waypoint(
                parsed: current, timestamp: now, kind: .accept))
        }

        changes = []
        selectedChangeID = nil
        activeWaypointID = nil
        diffCache = [:]
    }

    // MARK: - External waypoints

    /// Replaces all external waypoints (e.g. from git) with the given set.
    /// If the active waypoint pointed to a now-removed external waypoint,
    /// resets to the default.
    public func setExternalWaypoints(_ waypoints: [Waypoint]) {
        self.waypoints.removeAll { if case .external = $0.kind { true } else { false } }
        self.waypoints.append(contentsOf: waypoints)
        diffCache = [:]

        // Reset active waypoint if it pointed to a removed external waypoint.
        if let id = activeWaypointID,
           !self.waypoints.contains(where: { $0.id == id }) {
            selectWaypoint(nil)
        }
    }

    // MARK: - Menu items

    /// Returns menu items for the "Changes since…" picker.
    /// Gap labels are recomputed each call so relative times stay accurate;
    /// per-waypoint diffs are cached until content changes.
    public func menuItems() -> [ChangeMenuItem] {
        menuItems(at: Date())
    }

    /// Testable variant that accepts a timestamp.
    func menuItems(at now: Date) -> [ChangeMenuItem] {
        computeMenuItems(at: now)
    }

    private func computeMenuItems(at now: Date) -> [ChangeMenuItem] {
        guard let current = currentParsed else { return [] }

        var items: [ChangeMenuItem] = []
        var usedWaypointIDs: Set<UUID> = []

        // 1. "Since last accepted" or "Since document opened"
        let acceptWaypoint = waypoints.last(where: { $0.kind == .accept })
        let initialWaypoint = waypoints.first(where: { $0.kind == .initial })
        let primaryWaypoint = acceptWaypoint ?? initialWaypoint

        if let wp = primaryWaypoint {
            let label = acceptWaypoint != nil
                ? "since last accepted" : "since document opened"
            let diff = diffSummary(from: wp.parsed, to: current, waypointID: wp.id)
            items.append(ChangeMenuItem(
                id: wp.id, label: label, timestamp: wp.timestamp,
                changeCount: diff.groupCount,
                isActive: isActiveWaypoint(wp),
                hasInsertions: diff.hasInsertions,
                hasDeletions: diff.hasDeletions))
            usedWaypointIDs.insert(wp.id)
        }

        // Reserve the initial waypoint so time buckets don't claim it
        // (it appears at the bottom when distinct from the primary).
        if let wp = initialWaypoint {
            usedWaypointIDs.insert(wp.id)
        }

        // 2. Gap-based "since X minutes/hours/… ago" entries. Walk consecutive
        //    pairs of non-external waypoints (sorted by timestamp). Each
        //    gap (W_old, W_new) yields one menu entry whose diff is
        //    (W_old → current) and whose label uses W_new's absolute
        //    minute. Skip if W_old is already a milestone.
        let gapStart = items.count
        let nonExternal = waypoints
            .filter {
                if case .external = $0.kind { return false }
                return true
            }
            .sorted { $0.timestamp < $1.timestamp }
        if nonExternal.count >= 2 {
            for i in 0..<(nonExternal.count - 1) {
                let oldWP = nonExternal[i]
                let newWP = nonExternal[i + 1]
                guard !usedWaypointIDs.contains(oldWP.id) else { continue }

                let diff = diffSummary(
                    from: oldWP.parsed, to: current, waypointID: oldWP.id)
                // Hide gaps with no changes against current — happens
                // when the file has been reverted to an earlier state.
                guard diff.groupCount > 0 else { continue }

                let label = "since \(Self.timeAgoPhrase(for: newWP.timestamp, at: now)) ago"
                items.append(ChangeMenuItem(
                    id: oldWP.id, label: label, timestamp: newWP.timestamp,
                    changeCount: diff.groupCount,
                    isActive: isActiveWaypoint(oldWP),
                    hasInsertions: diff.hasInsertions,
                    hasDeletions: diff.hasDeletions))
                usedWaypointIDs.insert(oldWP.id)
            }
        }
        // Reverse so the most recent gap appears at the top.
        items[gapStart...].reverse()

        // 3. "Since document opened" at the bottom (if distinct from primary)
        if acceptWaypoint != nil, let wp = initialWaypoint,
           wp.id != primaryWaypoint?.id {
            let diff = diffSummary(from: wp.parsed, to: current, waypointID: wp.id)
            items.append(ChangeMenuItem(
                id: wp.id, label: "since document opened",
                timestamp: wp.timestamp, changeCount: diff.groupCount,
                isActive: isActiveWaypoint(wp),
                hasInsertions: diff.hasInsertions,
                hasDeletions: diff.hasDeletions))
        }

        // 4. External waypoints (e.g. git). Only shown when they have changes.
        let externals = waypoints.filter {
            if case .external = $0.kind { true } else { false }
        }
        for wp in externals {
            guard case .external(let label, let detail) = wp.kind else {
                continue
            }
            let diff = diffSummary(from: wp.parsed, to: current, waypointID: wp.id)
            items.append(ChangeMenuItem(
                id: wp.id, label: label, timestamp: wp.timestamp,
                changeCount: diff.groupCount,
                isActive: isActiveWaypoint(wp),
                hasInsertions: diff.hasInsertions,
                hasDeletions: diff.hasDeletions,
                detail: detail, isExternal: true))
        }

        return items
    }

    private struct DiffSummary {
        let groupCount: Int
        let hasInsertions: Bool
        let hasDeletions: Bool
    }

    private func diffSummary(
        from old: ParsedMarkdown, to new: ParsedMarkdown,
        waypointID: UUID
    ) -> DiffSummary {
        if let cached = diffCache[waypointID] { return cached }
        let changes = MudCore.computeChanges(old: old, new: new)
        let groups = ChangeGroup.build(from: changes)
        let summary = DiffSummary(
            groupCount: groups.count,
            hasInsertions: changes.contains { $0.type == .insertion },
            hasDeletions: changes.contains { $0.type == .deletion })
        diffCache[waypointID] = summary
        return summary
    }

    /// Returns an integer key representing the absolute clock-minute a
    /// timestamp falls in (for coalescing by minute).
    static func absoluteMinute(_ date: Date) -> Int {
        Int(date.timeIntervalSinceReferenceDate) / 60
    }

    /// Computes the "X minutes ago" label value for an anchor timestamp,
    /// rounding up to the start of the anchor's absolute minute. Floors
    /// at 1 to handle the (rare) case where `now` lands exactly on a
    /// minute boundary in the same minute as the anchor.
    static func minutesAgoLabel(for anchorTime: Date, at now: Date) -> Int {
        let anchorMin = absoluteMinute(anchorTime)
        let nowMin = absoluteMinute(now)
        let secsIntoNowMin = Int(now.timeIntervalSinceReferenceDate) % 60
        return max(1, (nowMin - anchorMin) + (secsIntoNowMin > 0 ? 1 : 0))
    }

    /// Formats a gap-entry time distance as a human phrase: exact minutes
    /// under an hour, then whole hours, days, and weeks — rounded down,
    /// matching how people describe elapsed time.
    static func timeAgoPhrase(for anchorTime: Date, at now: Date) -> String {
        let minutes = minutesAgoLabel(for: anchorTime, at: now)
        func phrase(_ count: Int, _ unit: String) -> String {
            "\(count) \(unit)\(count == 1 ? "" : "s")"
        }
        if minutes < 60 { return phrase(minutes, "minute") }
        let hours = minutes / 60
        if hours < 24 { return phrase(hours, "hour") }
        let days = hours / 24
        if days < 7 { return phrase(days, "day") }
        return phrase(days / 7, "week")
    }

    private func isActiveWaypoint(_ waypoint: Waypoint) -> Bool {
        if let id = activeWaypointID {
            return waypoint.id == id
        }
        // Default: most recent .accept, then .initial.
        if let accept = waypoints.last(where: { $0.kind == .accept }) {
            return waypoint.id == accept.id
        }
        return waypoint.kind == .initial
    }
}
