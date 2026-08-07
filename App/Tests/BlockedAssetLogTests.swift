import Foundation
import Testing
@testable import Mud

/// The log is what carries a render's denials back out to the info bar. Its
/// one rule is that it collects denials and nothing else: a file that isn't
/// there looks the same to the reader, but it is not a permission Mud can ask
/// for, and offering to grant a folder for it would be a dead end.
///
/// So these go through the resolver rather than calling `record` directly —
/// the rule lives in which of the probe's three answers reaches the log, not
/// in the log's own bookkeeping.
@Suite struct BlockedAssetLogTests {

    /// A readable image resolves to a `mud-asset:` URL and reports nothing.
    @Test func aReadableImageIsResolvedAndNotRecorded() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = dir.appendingPathComponent("diagram.png")
        try Data("not really a png".utf8).write(to: image)
        let log = BlockedAssetLog()

        let resolved = log.resolver(
            "diagram.png", dir.appendingPathComponent("Notes.md"))

        #expect(resolved?.hasPrefix("mud-asset:") == true)
        #expect(log.denied.isEmpty)
    }

    /// A wrong path in the document. Nothing resolves, and nothing is
    /// recorded: no folder grant would put this image on the page.
    @Test func aMissingImageIsNotRecorded() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = BlockedAssetLog()

        let resolved = log.resolver(
            "gone.png", dir.appendingPathComponent("Notes.md"))

        #expect(resolved == nil)
        #expect(log.denied.isEmpty)
    }

    /// The case the info bar exists for. Unix permissions stand in for the
    /// sandbox, which denies the same `open(2)` with the same `errno`.
    @Test(.enabled(if: geteuid() != 0))
    func anUnreadableImageIsRecorded() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = dir.appendingPathComponent("secret.png")
        try Data("bytes".utf8).write(to: image)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0], ofItemAtPath: image.path)
        let log = BlockedAssetLog()

        let resolved = log.resolver(
            "secret.png", dir.appendingPathComponent("Notes.md"))

        #expect(resolved == nil)
        #expect(log.denied == [image.standardized])

        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: image.path)
    }
}
