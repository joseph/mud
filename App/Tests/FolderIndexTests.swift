import Foundation
import Testing
@testable import Mud

/// The generated document a folder becomes under `FolderOpenBehavior.index`:
/// which files the walk finds, and what the writer makes of them. The two are
/// tested apart — the walk against real directories, the writing against trees
/// built by hand.
@Suite struct FolderIndexWalkTests {

    private func makeFile(_ path: String, in directory: URL) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "# Heading\n".write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func aFolderWithNoMarkdownAnywhereIsEmpty() throws {
        let directory = try makeTempDirectory()
        try makeFile("notes.txt", in: directory)
        try makeFile("Deep/Deeper/image.png", in: directory)

        #expect(FolderIndex.walk(directory).isEmpty)
    }

    /// The whole point of the index: a document three levels down is listed,
    /// where the tab behavior would never see it.
    @Test func filesAreFoundAtAnyDepth() throws {
        let directory = try makeTempDirectory()
        try makeFile("Guides/Deep/Deeper/buried.md", in: directory)

        let tree = FolderIndex.walk(directory)
        let deepest = tree.root.folders[0].folders[0].folders[0]
        #expect(deepest.name == "Deeper")
        #expect(deepest.files == ["buried.md"])
        #expect(!tree.isTruncated)
    }

    /// A folder is listed only for what it leads to. `Assets/` holds an image
    /// and nothing else, so it doesn't appear; `Plans/` holds only a
    /// subfolder, and appears because that subfolder holds a document.
    @Test func foldersWithoutMarkdownBeneathThemAreDropped() throws {
        let directory = try makeTempDirectory()
        try makeFile("Assets/logo.png", in: directory)
        try makeFile("Plans/archive/old.md", in: directory)

        let tree = FolderIndex.walk(directory)
        #expect(tree.root.folders.map(\.name) == ["Plans"])
        #expect(tree.root.folders[0].files.isEmpty)
        #expect(tree.root.folders[0].folders.map(\.name) == ["archive"])
    }

    @Test func filesAndFoldersAreEachInNameOrder() throws {
        let directory = try makeTempDirectory()
        try makeFile("Zebra.md", in: directory)
        try makeFile("apple.markdown", in: directory)
        try makeFile("Zulu/z.md", in: directory)
        try makeFile("alpha/a.md", in: directory)

        let tree = FolderIndex.walk(directory)
        #expect(tree.root.files == ["apple.markdown", "Zebra.md"])
        #expect(tree.root.folders.map(\.name) == ["alpha", "Zulu"])
    }

    @Test func hiddenEntriesAreSkipped() throws {
        let directory = try makeTempDirectory()
        try makeFile(".hidden.md", in: directory)
        try makeFile(".git/notes.md", in: directory)
        try makeFile("visible.md", in: directory)

        let tree = FolderIndex.walk(directory)
        #expect(tree.root.files == ["visible.md"])
        #expect(tree.root.folders.isEmpty)
    }

    /// A link pointing at an ancestor would otherwise be walked forever.
    @Test func symbolicLinksAreNotFollowed() throws {
        let directory = try makeTempDirectory()
        try makeFile("Sub/one.md", in: directory)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("Sub/loop"),
            withDestinationURL: directory)

        let tree = FolderIndex.walk(directory)
        #expect(tree.root.folders.map(\.name) == ["Sub"])
        #expect(tree.root.folders[0].folders.isEmpty)
    }

    @Test func theWalkStopsAtTheLimitAndSaysSo() throws {
        let directory = try makeTempDirectory()
        for name in ["a.md", "b.md", "c.md"] {
            try makeFile(name, in: directory)
        }
        try makeFile("Sub/d.md", in: directory)

        let tree = FolderIndex.walk(directory, limit: 2)
        #expect(tree.isTruncated)
        #expect(tree.root.files == ["a.md", "b.md"])
        // Out of room, so the subfolder isn't walked — and an empty branch is
        // never listed.
        #expect(tree.root.folders.isEmpty)
    }

    /// The limit can run out with folders still unwalked and nothing yet
    /// dropped. The index is short either way, so it has to say so.
    @Test func fillingTheLimitExactlyStillCountsAsTruncated() throws {
        let directory = try makeTempDirectory()
        try makeFile("a.md", in: directory)
        try makeFile("b.md", in: directory)
        try makeFile("Sub/c.md", in: directory)

        let tree = FolderIndex.walk(directory, limit: 2)
        #expect(tree.root.files == ["a.md", "b.md"])
        #expect(tree.isTruncated)
    }

    @Test func aTreeThatFitsExactlyIsNotTruncated() throws {
        let directory = try makeTempDirectory()
        try makeFile("a.md", in: directory)
        try makeFile("Sub/b.md", in: directory)

        let tree = FolderIndex.walk(directory, limit: 2)
        #expect(!tree.isTruncated)
        #expect(tree.root.folders[0].files == ["b.md"])
    }
}

// MARK: - The written document

@Suite struct FolderIndexMarkdownTests {

    private func tree(_ root: FolderIndex.Node) -> FolderIndex.Tree {
        FolderIndex.Tree(root: root, isTruncated: false)
    }

    private func node(
        _ name: String, files: [String] = [],
        folders: [FolderIndex.Node] = []
    ) -> FolderIndex.Node {
        FolderIndex.Node(name: name, files: files, folders: folders)
    }

    @Test func theFolderNameIsTheHeading() {
        let source = FolderIndex.markdown(for: tree(node("Doc", files: ["a.md"])))

        #expect(source.hasPrefix("Doc\n====="))
    }

    /// Files first, then folders, each level indented two spaces further —
    /// and every destination relative to the folder the index is for.
    @Test func nestingIsIndentedAndPathsAreRelative() {
        let source = FolderIndex.markdown(for: tree(node(
            "Doc",
            files: ["AGENTS.md"],
            folders: [node(
                "Plans",
                files: ["mud.md"],
                folders: [node("archive", files: ["old.md"])])])))

        #expect(source == """
        Doc
        \(String(repeating: "=", count: 79))

        - [AGENTS.md](AGENTS.md)
        - **Plans/**
          - [mud.md](Plans/mud.md)
          - **archive/**
            - [old.md](Plans/archive/old.md)

        """)
    }

    /// A name is text, not syntax: brackets and underscores in it must survive
    /// as themselves.
    @Test func namesAreMarkdownEscaped() {
        let source = FolderIndex.markdown(
            for: tree(node("Doc", files: ["Notes [draft]_v2.md"])))

        #expect(source.contains("[Notes \\[draft\\]\\_v2.md]"))
    }

    /// A space would end the destination and a `#` would start a fragment, so
    /// neither can reach the link as itself.
    @Test func destinationsArePercentEncoded() {
        let source = FolderIndex.markdown(for: tree(node(
            "Doc",
            folders: [node("My Plans", files: ["a #1 (final).md"])])))

        #expect(source.contains("(My%20Plans/a%20%231%20%28final%29.md)"))
    }
}
