/// What a folder means when Mud is handed one — from the command line, the
/// Open panel, Finder's Open With, or a drop on the Dock icon.
///
/// A folder is not a document, so Mud has to make something of it. The two
/// answers differ in how far they look: `index` walks the whole tree and
/// writes one document listing what it found; `tabs` takes the documents
/// directly inside the folder and opens each one.
public enum FolderOpenBehavior: String, CaseIterable, Sendable {
    /// One window holding a generated index: every Markdown file in the tree
    /// below the folder, as a nested list of links.
    case index = "index"
    /// One window per Markdown file directly inside the folder, tabbed
    /// together. Top level only — nothing deeper is opened.
    case tabs = "tabs"

    public var label: String {
        switch self {
        case .index: return "Shows an index of the tree"
        case .tabs: return "Opens each file in a tab"
        }
    }
}
