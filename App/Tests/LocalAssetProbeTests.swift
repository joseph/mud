import Foundation
import Testing
@testable import Mud

/// The probe is what lets Mud tell a permission problem from a wrong path.
/// Both leave the reader with a broken image, but only the first is something
/// the info bar can offer to fix, so the three answers have to stay distinct.
@Suite struct LocalAssetProbeTests {

    @Test func aReadableFileIsReadable() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("diagram.png")
        try Data("not really a png".utf8).write(to: file)

        #expect(LocalAssetProbe.probe(file) == .readable)
    }

    @Test func aMissingFileIsMissing() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(
            LocalAssetProbe.probe(dir.appendingPathComponent("nope.png"))
                == .missing)
    }

    /// A path whose parent doesn't exist either — `ENOTDIR` rather than
    /// `ENOENT`, and just as much "not there".
    @Test func aFileUnderAMissingFolderIsMissing() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("gone").appendingPathComponent("x.png")

        #expect(LocalAssetProbe.probe(file) == .missing)
    }

    /// The case the whole feature turns on: the file is there and can't be
    /// read. Unix permissions stand in for the sandbox here — the sandbox
    /// denies the same `open(2)` with the same `errno`, and a test bundle
    /// can't put itself outside its own grants.
    ///
    /// Root ignores the mode bits, so the test is skipped rather than failed
    /// when the suite runs as root.
    @Test(.enabled(if: geteuid() != 0))
    func anUnreadableFileIsDenied() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("secret.png")
        try Data("bytes".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0], ofItemAtPath: file.path)

        #expect(LocalAssetProbe.probe(file) == .denied)

        // Readable again, so the directory removal above can't be blocked by
        // a file no one may touch.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: file.path)
    }
}
