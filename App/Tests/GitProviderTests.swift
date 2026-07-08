#if GIT_PROVIDER
import Foundation
import MudCore
import Testing
@testable import Mud

/// `GitProvider` output parsing and waypoint assembly, with git's output
/// scripted through the injected runner — the only way to pin the scrape of
/// undocumented `ls-files --debug` text and the `%aI` date fallback.
@MainActor
@Suite struct GitProviderTests {
    private static let hashA = String(repeating: "a", count: 40)
    private static let hashB = String(repeating: "b", count: 40)

    /// A full happy-path repo: unstaged changes on top of a staged version,
    /// and two commits with distinct content. Keys are the joined git
    /// arguments; any unscripted invocation fails like a real git error.
    private static let baseResponses: [String: (Int32, String?)] = [
        "rev-parse --show-toplevel": (0, "/repo"),
        "show :notes.md": (0, "staged content"),
        "diff --quiet -- notes.md": (1, nil),  // unstaged changes exist
        "ls-files --debug -- notes.md": (0, """
        notes.md
          ctime: 1699000000:0
          mtime: 1700000000:123456789
          dev: 16777231\tino: 8631556
          uid: 501\tgid: 20
          size: 42\tflags: 0
        """),
        "log --format=%H%x00%aI%x00%s -n 5 -- notes.md": (0, """
        \(hashA)\u{0}2026-07-01T12:00:00+00:00\u{0}Newest commit
        \(hashB)\u{0}2026-06-30T08:15:30.123+00:00\u{0}Older commit
        """),
        "show \(hashA):notes.md": (0, "head content"),
        "show \(hashB):notes.md": (0, "older content"),
    ]

    private func provider(
        overriding overrides: [String: (Int32, String?)] = [:]
    ) -> GitProvider {
        let responses = Self.baseResponses.merging(overrides) { _, new in new }
        return GitProvider(
            fileURL: URL(fileURLWithPath: "/repo/notes.md"),
            runner: { arguments, _ in
                responses[arguments.joined(separator: " ")] ?? (128, nil)
            })
    }

    private func labels(_ waypoints: [Waypoint]) -> [String] {
        waypoints.compactMap {
            if case .external(let label, _) = $0.kind { return label }
            return nil
        }
    }

    private func detail(_ waypoint: Waypoint) -> String? {
        if case .external(_, let detail) = waypoint.kind { return detail }
        return nil
    }

    @Test func buildsStagedThenCommitWaypoints() {
        let waypoints = provider().queryWaypoints(currentContent: "current")
        #expect(labels(waypoints) == [
            "since last staged",
            "since commit \(Self.hashA.prefix(7))",
            "since commit \(Self.hashB.prefix(7))",
        ])
        #expect(waypoints.map(\.parsed.markdown)
            == ["staged content", "head content", "older content"])
    }

    @Test func stagedTimestampComesFromTheIndexMtime() {
        let waypoints = provider().queryWaypoints(currentContent: "current")
        // Seconds only — the parser drops the nanosecond half.
        #expect(waypoints.first?.timestamp
            == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func commitDatesParseWithAndWithoutFractionalSeconds() {
        let waypoints = provider().queryWaypoints(currentContent: "current")
        let iso = ISO8601DateFormatter()
        #expect(waypoints[1].timestamp
            == iso.date(from: "2026-07-01T12:00:00+00:00"))
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(waypoints[2].timestamp
            == fractional.date(from: "2026-06-30T08:15:30.123+00:00"))
        #expect(detail(waypoints[1]) == "Newest commit")
        #expect(detail(waypoints[2]) == "Older commit")
    }

    @Test func stagedIsSkippedWithoutUnstagedChanges() {
        // diff --quiet exiting 0 means the working tree matches the index:
        // the staged version is what the user is looking at.
        let waypoints = provider(overriding: [
            "diff --quiet -- notes.md": (0, nil),
        ]).queryWaypoints(currentContent: "current")
        #expect(labels(waypoints).allSatisfy { $0.hasPrefix("since commit") })
    }

    @Test func stagedIsSkippedWhenItMatchesHead() {
        let waypoints = provider(overriding: [
            "show :notes.md": (0, "head content"),
        ]).queryWaypoints(currentContent: "current")
        #expect(labels(waypoints).allSatisfy { $0.hasPrefix("since commit") })
    }

    @Test func waypointsDeduplicateByContent() {
        // The older commit didn't touch the file's content.
        let waypoints = provider(overriding: [
            "show \(Self.hashB):notes.md": (0, "head content"),
        ]).queryWaypoints(currentContent: "current")
        #expect(labels(waypoints) == [
            "since last staged",
            "since commit \(Self.hashA.prefix(7))",
        ])
    }

    @Test func contentMatchingTheCurrentTextIsExcluded() {
        let waypoints = provider()
            .queryWaypoints(currentContent: "head content")
        #expect(labels(waypoints) == [
            "since last staged",
            "since commit \(Self.hashB.prefix(7))",
        ])
    }

    @Test func outsideARepositoryThereAreNoWaypoints() {
        let waypoints = provider(overriding: [
            "rev-parse --show-toplevel": (128, nil),
        ]).queryWaypoints(currentContent: "current")
        #expect(waypoints.isEmpty)
    }

    @Test func aFailedLogYieldsNoCommitWaypoints() {
        let waypoints = provider(overriding: [
            "log --format=%H%x00%aI%x00%s -n 5 -- notes.md": (129, nil),
        ]).queryWaypoints(currentContent: "current")
        // Staged survives on its own; without HEAD content the staged
        // version can't be compared against it, so it's kept.
        #expect(labels(waypoints) == ["since last staged"])
    }
}
#endif
