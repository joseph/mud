import Foundation
import MudCore

// MARK: - Waypoint Provider

/// Supplies external waypoints ("since last staged", "since commit …") for a
/// document's Changes menu. `DocumentModel` asks its provider after every
/// load. The git-backed implementation lives in `GitProvider.swift`, which is
/// compiled only under `GIT_PROVIDER`; other builds get the no-op below, so
/// the model, view, and settings need no conditionals of their own — the
/// factory at the bottom is the one `#if GIT_PROVIDER` outside that
/// whole-file-guarded file (and its tests).
nonisolated protocol WaypointProvider: Sendable {
    /// Whether the user preference for this provider is on. Read on the main
    /// thread before each query; when false, the model clears the external
    /// waypoints instead of querying.
    @MainActor var isEnabled: Bool { get }

    /// Returns the external waypoints for `fileURL`, excluding any whose
    /// content matches `currentContent`. Blocking — call off the main thread.
    func queryWaypoints(for fileURL: URL, currentContent: String) -> [Waypoint]
}

/// The provider for builds without one: disabled, no waypoints.
nonisolated struct NoWaypointProvider: WaypointProvider {
    @MainActor var isEnabled: Bool { false }
    func queryWaypoints(for fileURL: URL, currentContent: String) -> [Waypoint] {
        []
    }
}

/// The build's provider selection.
enum WaypointProviders {
    #if GIT_PROVIDER
    /// This build has a real provider, so Settings shows its toggle.
    static let isAvailable = true
    static func makeDefault() -> any WaypointProvider { GitWaypointProvider() }
    #else
    static let isAvailable = false
    static func makeDefault() -> any WaypointProvider { NoWaypointProvider() }
    #endif
}
