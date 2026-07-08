#if GIT_PROVIDER
import Foundation
import MudCore

// MARK: - Waypoint Provider conformance

/// The `WaypointProvider` for git-enabled builds: turned on by the "Git
/// commits" setting, querying the file's repository via `GitProvider`.
nonisolated struct GitWaypointProvider: WaypointProvider {
    @MainActor var isEnabled: Bool {
        AppState.shared.changesShowGitWaypoints
    }

    func queryWaypoints(for fileURL: URL, currentContent: String) -> [Waypoint] {
        GitProvider(fileURL: fileURL)
            .queryWaypoints(currentContent: currentContent)
    }
}

// MARK: - Git Provider

/// Queries git history for a file and produces external waypoints
/// for the "Changes since…" menu.
nonisolated struct GitProvider: Sendable {
    /// Runs one git invocation (arguments, working directory) and returns the
    /// exit status with trimmed stdout. Injected so tests can script git's
    /// output — `stagedMtime` scrapes undocumented `ls-files --debug` text
    /// that only a fake runner can pin down.
    typealias Runner =
        @Sendable ([String], URL) throws -> (status: Int32, output: String?)

    let fileURL: URL
    var runner: Runner = GitProvider.systemGit

    /// Maximum number of commits to fetch from the log.
    static let commitLimit = 5

    /// Returns external waypoints for the file's git history.
    /// Only includes waypoints whose content differs from `currentContent`
    /// and from each other. Safe to call from a background thread.
    func queryWaypoints(currentContent: String) -> [Waypoint] {
        guard let repoRoot = try? repoRoot() else { return [] }
        let relPath = relativePath(in: repoRoot)

        // Gather raw data. Each query can fail independently.
        let staged = try? stagedContent(relativePath: relPath, in: repoRoot)
        let stagedMtime = try? stagedMtime(relativePath: relPath, in: repoRoot)
        let commits = (try? recentCommits(
            relativePath: relPath, in: repoRoot,
            limit: Self.commitLimit)) ?? []

        // Fetch content for each commit.
        var commitContents: [(CommitInfo, String)] = []
        for commit in commits {
            if let content = try? contentAtCommit(
                hash: commit.hash, relativePath: relPath, in: repoRoot) {
                commitContents.append((commit, content))
            }
        }

        // Build waypoints, deduplicating by content.
        var waypoints: [Waypoint] = []
        var seenContents: Set<String> = [currentContent]

        // HEAD content (first commit in the log) — needed for staged check.
        let headContent = commitContents.first?.1

        // Staged: include only if the file has unstaged changes (git diff
        // --quiet exits 1) and staged content differs from HEAD.
        let hasUnstagedChanges = !((try? checkGit(
            ["diff", "--quiet", "--", relPath], in: repoRoot)) ?? true)
        if hasUnstagedChanges, let staged, !seenContents.contains(staged) {
            let differsFromHead = headContent.map { $0 != staged } ?? true
            if differsFromHead {
                seenContents.insert(staged)
                waypoints.append(Waypoint(
                    parsed: ParsedMarkdown(staged),
                    timestamp: stagedMtime ?? Date(),
                    kind: .external(
                        label: "since last staged",
                        detail: nil)))
            }
        }

        // Commits in reverse chronological order.
        for (commit, content) in commitContents {
            guard !seenContents.contains(content) else { continue }
            seenContents.insert(content)
            let shortHash = String(commit.hash.prefix(7))
            waypoints.append(Waypoint(
                parsed: ParsedMarkdown(content),
                timestamp: commit.date,
                kind: .external(
                    label: "since commit \(shortHash)",
                    detail: commit.message)))
        }

        return waypoints
    }

    // MARK: - Git commands

    private func repoRoot() throws -> URL {
        let output = try runGit(["rev-parse", "--show-toplevel"],
                             in: fileURL.deletingLastPathComponent())
        return URL(fileURLWithPath: output, isDirectory: true)
    }

    private func relativePath(in repoRoot: URL) -> String {
        let filePath = fileURL.standardized.path
        let rootPath = repoRoot.standardized.path
        if filePath.hasPrefix(rootPath) {
            let start = filePath.index(
                filePath.startIndex,
                offsetBy: rootPath.count)
            var rel = String(filePath[start...])
            if rel.hasPrefix("/") { rel.removeFirst() }
            return rel
        }
        return fileURL.lastPathComponent
    }

    private func stagedContent(
        relativePath: String, in repoRoot: URL
    ) throws -> String {
        try runGit(["show", ":\(relativePath)"], in: repoRoot)
    }

    private func stagedMtime(
        relativePath: String, in repoRoot: URL
    ) throws -> Date {
        let output = try runGit(
            ["ls-files", "--debug", "--", relativePath], in: repoRoot)
        // Parse "  mtime: <seconds>:<nanoseconds>" from the output.
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("mtime:") {
                let value = trimmed.dropFirst("mtime:".count)
                    .trimmingCharacters(in: .whitespaces)
                // Format: "seconds:nanoseconds"
                let parts = value.split(separator: ":")
                if let seconds = parts.first.flatMap({
                    TimeInterval($0)
                }) {
                    return Date(timeIntervalSince1970: seconds)
                }
            }
        }
        throw GitError.parseFailed
    }

    private func recentCommits(
        relativePath: String, in repoRoot: URL, limit: Int
    ) throws -> [CommitInfo] {
        let output = try runGit(
            ["log", "--format=%H%x00%aI%x00%s",
             "-n", "\(limit)", "--", relativePath],
            in: repoRoot)
        guard !output.isEmpty else { return [] }

        return output.components(separatedBy: "\n").compactMap { line in
            let parts = line.split(
                separator: "\u{0000}", maxSplits: 2,
                omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let hash = String(parts[0])
            let message = String(parts[2])
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds
            ]
            // Try with fractional seconds first, then without.
            let date = formatter.date(from: String(parts[1]))
                ?? {
                    formatter.formatOptions = [.withInternetDateTime]
                    return formatter.date(from: String(parts[1]))
                }()
                ?? Date()
            return CommitInfo(hash: hash, date: date, message: message)
        }
    }

    private func contentAtCommit(
        hash: String, relativePath: String, in repoRoot: URL
    ) throws -> String {
        try runGit(["show", "\(hash):\(relativePath)"], in: repoRoot)
    }

    // MARK: - Process execution

    /// Returns `true` if the command exits 0, `false` otherwise.
    private func checkGit(
        _ arguments: [String], in directory: URL
    ) throws -> Bool {
        try git(arguments, in: directory).status == 0
    }

    /// Runs a git command and returns its stdout. Throws on non-zero exit.
    private func runGit(
        _ arguments: [String], in directory: URL
    ) throws -> String {
        let result = try git(arguments, in: directory)
        guard result.status == 0 else {
            throw GitError.commandFailed(result.status)
        }
        guard let output = result.output else {
            throw GitError.invalidOutput
        }
        return output
    }

    private func git(
        _ arguments: [String], in directory: URL
    ) throws -> (status: Int32, output: String?) {
        try runner(arguments, directory)
    }

    /// The default runner: spawn `/usr/bin/git` and capture stdout.
    private static let systemGit: Runner = { arguments, directory in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardError = FileHandle.nullDevice

        let stdout = Pipe()
        process.standardOutput = stdout

        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .newlines)
        return (process.terminationStatus, output)
    }
}

// MARK: - Supporting types

private struct CommitInfo {
    let hash: String
    let date: Date
    let message: String
}

private enum GitError: Error {
    case commandFailed(Int32)
    case invalidOutput
    case parseFailed
}
#endif
