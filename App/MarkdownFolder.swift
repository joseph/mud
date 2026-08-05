import Foundation
import UniformTypeIdentifiers

// MARK: - Markdown Folder

/// What a folder means to Mud under `FolderOpenBehavior.tabs`: the Markdown
/// files directly inside it, one window each.
///
/// Only the top level, never a walk of the tree — `open -a Mud.app Doc/` on a
/// project's docs folder should open that folder's documents, not every
/// document beneath it, which could be hundreds of windows from one command.
/// The walk is what the other behavior does, in `FolderIndex`, where the whole
/// tree lands in one document instead of one window per file.
///
/// The two rules below — what counts as a folder, and what counts as a
/// Markdown file — are shared with that walk, so both behaviors take the same
/// view of what they are looking at.
enum MarkdownFolder {

    /// The Markdown files directly inside `url`, ordered by name, or nil when
    /// `url` isn't a folder. An empty array means a folder with nothing in it
    /// Mud can open — a different answer from nil, and the caller treats it as
    /// such.
    static func markdownFiles(in url: URL) -> [URL]? {
        guard isFolder(url) else { return nil }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentTypeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles])) ?? []
        return contents
            .filter(isMarkdown)
            .sorted {
                $0.lastPathComponent.localizedStandardCompare(
                    $1.lastPathComponent) == .orderedAscending
            }
    }

    /// What to call `url` in a window title and its tab. A folder takes a
    /// trailing "/", so the one window a folder gets — a blank page under the
    /// "no Markdown files" notice — reads as the folder it is rather than as a
    /// document that happens to have no extension.
    static func displayName(for url: URL) -> String {
        let name = url.lastPathComponent
        return isFolder(url) ? name + "/" : name
    }

    /// Whether `url` is a folder to open the contents of. A package (`.app`,
    /// `.rtfd`, …) is a directory too, but the system presents it as a single
    /// document, so Mud does the same and tries to read it as one.
    static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    /// Whether a file in the folder is a Markdown document.
    ///
    /// The rule is conformance to `net.daringfireball.markdown`, the type Mud
    /// imports. The extension check behind it is a fallback for the case where
    /// LaunchServices resolves `.md` to some other app's exported type, which
    /// wouldn't conform: these three extensions are exactly the ones Mud's own
    /// `UTTypeTagSpecification` claims for that type, so the fallback only
    /// restates what the app already declares. Dialect extensions (`.qmd`,
    /// `.mdx`, …) have no Markdown UTI and are deliberately not included —
    /// they can still be opened one at a time.
    static func isMarkdown(_ url: URL) -> Bool {
        let values = try? url.resourceValues(
            forKeys: [.contentTypeKey, .isDirectoryKey])
        // A subfolder can be named `Notes.md` too, and the extension fallback
        // below would take it for a document.
        guard values?.isDirectory != true else { return false }
        if let type = values?.contentType, type.conforms(to: .markdown) {
            return true
        }
        return markdownExtensions.contains(url.pathExtension.lowercased())
    }

    private static let markdownExtensions: Set<String> = [
        "md", "markdown", "mkd",
    ]
}
