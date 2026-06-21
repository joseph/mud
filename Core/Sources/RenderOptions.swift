import Foundation

/// Bundles all rendering configuration into a single value type.
///
/// Passed to MudCore's public rendering functions. Adding a new option
/// means adding a field here — no function signatures change.
public struct RenderOptions: Sendable, Equatable {
    // Document wrapping
    public var title: String = ""
    public var baseURL: URL? = nil
    public var theme: String = "earthy"
    public var standalone: Bool = false
    public var blockRemoteContent: Bool = false
    public var extensions: Set<String> = []

    // Markdown processing
    public var docCAlertMode: DocCAlertMode = .extended
    public var footnoteMode: FootnoteMode = .section
    public var commentMode: CommentMode = .section

    /// Whether to embed the write-side comment styles (`mud-comments-edit.css`).
    /// Set by the app's live, editable view; left off for read-only exports so
    /// the compose-box and control styles don't ship with them.
    public var commentsEditable: Bool = false

    // Display state (baked into initial HTML for first-paint correctness;
    // also applied at runtime via JS for live updates without reload)
    public var htmlClasses: Set<String> = []
    public var zoomLevel: Double = 1.0

    // Change tracking
    public var waypoint: ParsedMarkdown?
    public var showInlineDeletions: Bool = false
    public var wordDiffThreshold: Double = 0.25

    public init() {}

    /// Identity string covering only content-affecting options.
    /// Display-only fields (htmlClasses, zoomLevel) are excluded because
    /// those can be applied via JS without a full page reload.
    public var contentIdentity: String {
        let waypointHash = waypoint.map {
            String($0.markdown.hashValue)
        } ?? ""
        return "\(theme)\(blockRemoteContent)\(docCAlertMode.rawValue)\(footnoteMode.rawValue)\(commentMode.rawValue)\(extensions.sorted())\(waypointHash)\(showInlineDeletions)\(wordDiffThreshold)"
    }
}
