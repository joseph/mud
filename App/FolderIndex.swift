import Foundation

// MARK: - Folder Index

/// The other thing a folder can be to Mud: one generated document listing
/// every Markdown file in the tree below it.
///
/// `MarkdownFolder` answers the shallow question — the documents directly
/// inside a folder, which `FolderOpenBehavior.tabs` opens one tab each. This
/// walks the whole tree instead and writes a nested list of links, which
/// `DocumentModel` renders in place of a file's contents. Nothing is written
/// to disk: the index exists for as long as the window is open, and Cmd+R
/// walks again.
///
/// The walk and the writing are separate calls so the source can be checked
/// against a tree built by hand, without a directory of fixtures.
enum FolderIndex {

    /// How many files one index lists before the walk gives up. It exists so
    /// that pointing Mud at a home folder answers in a moment with a partial
    /// list and a notice (`DocumentNotice.folderIndexTruncated`), rather than
    /// walking a few hundred thousand directories while the window sits empty.
    static let fileLimit = 1000

    // MARK: The tree

    /// One folder in the tree: its own Markdown files and the subfolders kept
    /// under it, both in name order.
    struct Node: Equatable {
        let name: String
        /// File names, not paths. The path is the names of the folders above
        /// it, which only the writer below needs to know.
        let files: [String]
        let folders: [Node]

        /// True when nothing under this folder is Markdown, at any depth.
        /// `walk` drops such a folder rather than listing an empty branch.
        var isEmpty: Bool { files.isEmpty && folders.isEmpty }
    }

    /// A walked folder: what was found, and whether the file limit stopped the
    /// walk before it had seen everything.
    struct Tree: Equatable {
        let root: Node
        let isTruncated: Bool

        var isEmpty: Bool { root.isEmpty }
    }

    // MARK: Walking

    /// Walks the tree below `folder` and returns the Markdown files in it.
    ///
    /// Files come before subfolders at every level, both in name order. A
    /// subfolder is kept only when it holds a Markdown file or a kept
    /// subfolder, so a tree of images and source code yields an empty node
    /// rather than a page of empty branches.
    static func walk(_ folder: URL, limit: Int = fileLimit) -> Tree {
        var walker = Walker(remaining: limit)
        let root = walker.node(at: folder, named: folder.lastPathComponent)
        return Tree(root: root, isTruncated: walker.didTruncate)
    }

    /// The recursion's running state: how many more files may be listed, and
    /// whether anything was dropped for want of room.
    private struct Walker {
        var remaining: Int
        var didTruncate = false

        mutating func node(at folder: URL, named name: String) -> Node {
            // Out of room. Stop here rather than walk a tree whose files can't
            // be listed anyway — the limit is there to bound the walk, not
            // just the document. Whatever is under this folder is left out, so
            // the index can no longer claim to be the whole tree. (A folder
            // that would have turned out to hold nothing counts too: the walk
            // stopped before it could find that out.)
            guard remaining > 0 else {
                didTruncate = true
                return Node(name: name, files: [], folders: [])
            }

            let contents = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [
                    .contentTypeKey, .isDirectoryKey, .isPackageKey,
                    .isSymbolicLinkKey,
                ],
                options: [.skipsHiddenFiles])) ?? []

            var fileURLs: [URL] = []
            var folderURLs: [URL] = []
            for url in contents {
                if MarkdownFolder.isMarkdown(url) {
                    fileURLs.append(url)
                } else if FolderIndex.isTraversable(url) {
                    folderURLs.append(url)
                }
            }
            fileURLs.sort(by: FolderIndex.byName)
            folderURLs.sort(by: FolderIndex.byName)

            var files: [String] = []
            for url in fileURLs {
                guard remaining > 0 else {
                    didTruncate = true
                    break
                }
                remaining -= 1
                files.append(url.lastPathComponent)
            }

            var folders: [Node] = []
            for url in folderURLs {
                let child = node(at: url, named: url.lastPathComponent)
                if !child.isEmpty { folders.append(child) }
            }

            return Node(name: name, files: files, folders: folders)
        }
    }

    /// Whether the walk descends into `url`: a folder, and not a symbolic
    /// link. A link pointing at an ancestor would otherwise be followed
    /// forever. `MarkdownFolder.isFolder` is what excludes a package (`.app`,
    /// `.rtfd`), which the system presents as one document.
    private static func isTraversable(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink != true else { return false }
        return MarkdownFolder.isFolder(url)
    }

    private static func byName(_ a: URL, _ b: URL) -> Bool {
        a.lastPathComponent.localizedStandardCompare(b.lastPathComponent)
            == .orderedAscending
    }

    // MARK: Writing

    /// The index document for a walked tree: a heading naming the folder, then
    /// one nested list of every file under it.
    ///
    /// Link destinations are relative to the folder, which is also what the
    /// page's `<base href>` is set to (`DocumentModel.baseURL`) — so a click
    /// resolves to the real file and `WebView`'s link routing opens it.
    static func markdown(for tree: Tree) -> String {
        var lines = [
            escape(tree.root.name),
            String(repeating: "=", count: 79),
            "",
        ]
        appendRows(tree.root, path: "", depth: 0, to: &lines)
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendRows(
        _ node: Node, path: String, depth: Int, to lines: inout [String]
    ) {
        let indent = String(repeating: "  ", count: depth)
        for file in node.files {
            lines.append(
                "\(indent)- [\(escape(file))](\(destination(path + file)))")
        }
        for folder in node.folders {
            // A folder is a row of its own, not a link: there is no document
            // behind it to open.
            lines.append("\(indent)- **\(escape(folder.name))/**")
            appendRows(
                folder, path: path + folder.name + "/", depth: depth + 1,
                to: &lines)
        }
    }

    /// Backslash-escapes the Markdown syntax a file name can contain, so
    /// `Notes [draft].md` reads as its name instead of breaking the link
    /// around it, and `a_b_c.md` keeps its underscores.
    private static func escape(_ name: String) -> String {
        var escaped = ""
        for character in name {
            if markdownSyntax.contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    private static let markdownSyntax: Set<Character> = [
        "\\", "`", "*", "_", "[", "]", "<", ">", "&",
    ]

    /// Percent-encodes a path for use as a link destination. Everything but
    /// the unreserved URL characters and the separator goes, which covers the
    /// three that would otherwise change what the link means: a space ends the
    /// destination, `#` starts a fragment, and `%` starts an escape.
    private static func destination(_ path: String) -> String {
        path.addingPercentEncoding(withAllowedCharacters: destinationAllowed)
            ?? path
    }

    private static let destinationAllowed = CharacterSet(
        charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~/")
}
