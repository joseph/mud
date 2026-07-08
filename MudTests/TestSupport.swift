import Foundation
import MudCore

/// Swift Testing also exports a `Comment` type, so test files (which all
/// import Testing) can't use the bare name — and the `MudCore.Comment`
/// spelling is unavailable because the `MudCore` facade enum shadows the
/// module name. This file doesn't import Testing, so the bare name is
/// unambiguous here; tests use the alias.
typealias MudComment = Comment

/// Yields the main actor briefly so queued main-thread work lands: the file
/// watcher's DispatchSource handlers and `deferMutation` blocks run on the
/// main queue, and Combine values received on `RunLoop.main` are delivered
/// by the host app's run loop. Suspending is required — test bodies execute
/// as main-queue blocks, and the serial main queue can't be re-entered, so
/// a synchronous run-loop spin would never deliver main-queue work.
@MainActor
func pump(_ interval: TimeInterval = 0.05) async {
    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
}

/// Yields the main actor until `condition` holds or `timeout` elapses.
/// Returns whether the condition held — callers `#expect` on it, so a
/// timeout fails the test rather than hanging it.
@MainActor
@discardableResult
func pumpUntil(
    timeout: TimeInterval = 2, _ condition: () -> Bool
) async -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return condition()
}

/// A fresh directory under the temporary directory, for tests that need
/// real files (comment writes, the file watcher).
func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MudTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
        at: url, withIntermediateDirectories: true)
    return url
}
