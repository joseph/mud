import Foundation
import Testing
@testable import Mud

/// What a folder handed to Mud means: the Markdown files directly inside it.
/// `DocumentController` opens one window per file in this list, and the
/// empty-folder window (blank page, info-bar warning) is what an empty list
/// gets — so the distinction between nil (not a folder) and [] matters.
@Suite struct MarkdownFolderTests {

    private func makeFile(_ name: String, in directory: URL) throws {
        try "# Heading\n".write(
            to: directory.appendingPathComponent(name),
            atomically: true, encoding: .utf8)
    }

    /// nil, not [] — a file is a document to open, not a folder that turned
    /// out to be empty.
    @Test func aFileIsNotAFolder() throws {
        let directory = try makeTempDirectory()
        try makeFile("Notes.md", in: directory)

        #expect(MarkdownFolder.markdownFiles(
            in: directory.appendingPathComponent("Notes.md")) == nil)
    }

    @Test func markdownFilesAreListedInNameOrder() throws {
        let directory = try makeTempDirectory()
        try makeFile("Zebra.md", in: directory)
        try makeFile("apple.markdown", in: directory)
        try makeFile("Middle.mkd", in: directory)

        let names = MarkdownFolder.markdownFiles(in: directory)?
            .map(\.lastPathComponent)
        #expect(names == ["apple.markdown", "Middle.mkd", "Zebra.md"])
    }

    /// Everything else in the folder is left alone — a docs folder usually
    /// holds images and data files beside its documents.
    @Test func nonMarkdownFilesAreSkipped() throws {
        let directory = try makeTempDirectory()
        try makeFile("Notes.md", in: directory)
        try makeFile("diagram.png", in: directory)
        try makeFile("data.json", in: directory)
        try makeFile("README", in: directory)

        let names = MarkdownFolder.markdownFiles(in: directory)?
            .map(\.lastPathComponent)
        #expect(names == ["Notes.md"])
    }

    /// Only the top level. A folder of notes is a set of documents; its
    /// subfolders are their own thing, and a deep tree would open a window per
    /// file in it.
    @Test func subfolderContentsAreNotIncluded() throws {
        let directory = try makeTempDirectory()
        try makeFile("Top.md", in: directory)
        let nested = directory.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(
            at: nested, withIntermediateDirectories: true)
        try makeFile("Deep.md", in: nested)

        let names = MarkdownFolder.markdownFiles(in: directory)?
            .map(\.lastPathComponent)
        #expect(names == ["Top.md"])
    }

    /// A subfolder can carry a document's extension, and opening it as one
    /// would recurse into a tree this rule exists to stay out of.
    @Test func aSubfolderNamedLikeADocumentIsNotOne() throws {
        let directory = try makeTempDirectory()
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Notes.md"),
            withIntermediateDirectories: true)

        #expect(MarkdownFolder.markdownFiles(in: directory)?.isEmpty == true)
    }

    /// A dot-file is hidden because its author meant it to be; opening a
    /// window on it isn't what "open this folder" asked for.
    @Test func hiddenFilesAreSkipped() throws {
        let directory = try makeTempDirectory()
        try makeFile(".secret.md", in: directory)

        #expect(MarkdownFolder.markdownFiles(in: directory)?.isEmpty == true)
    }

    /// The two empty cases the notice covers: a folder with nothing in it, and
    /// one whose contents are all something else.
    @Test func aFolderWithNoMarkdownYieldsAnEmptyList() throws {
        let empty = try makeTempDirectory()
        #expect(MarkdownFolder.markdownFiles(in: empty)?.isEmpty == true)

        let other = try makeTempDirectory()
        try makeFile("notes.txt", in: other)
        #expect(MarkdownFolder.markdownFiles(in: other)?.isEmpty == true)
    }

    /// The window and its tab say "Doc/", not "Doc" — the folder window has a
    /// blank page, so its name is most of what says what it is.
    @Test func aFolderNameCarriesATrailingSlash() throws {
        let directory = try makeTempDirectory()
        try makeFile("Notes.md", in: directory)

        #expect(MarkdownFolder.displayName(for: directory)
            == directory.lastPathComponent + "/")
        #expect(MarkdownFolder.displayName(
            for: directory.appendingPathComponent("Notes.md")) == "Notes.md")
    }

    @Test func aFolderIsAFolderAndAFileIsNot() throws {
        let directory = try makeTempDirectory()
        try makeFile("Notes.md", in: directory)

        #expect(MarkdownFolder.isFolder(directory))
        #expect(!MarkdownFolder.isFolder(
            directory.appendingPathComponent("Notes.md")))
    }

    /// A package is a directory on disk, but the system shows it as one
    /// document — so Mud tries to read it as one rather than opening whatever
    /// Markdown happens to be inside it.
    @Test func aPackageIsTreatedAsAFileNotAFolder() throws {
        let directory = try makeTempDirectory()
        let package = directory.appendingPathComponent("Bundle.rtfd")
        try FileManager.default.createDirectory(
            at: package, withIntermediateDirectories: true)
        try makeFile("Inside.md", in: package)

        #expect(!MarkdownFolder.isFolder(package))
        #expect(MarkdownFolder.markdownFiles(in: package) == nil)
    }
}
