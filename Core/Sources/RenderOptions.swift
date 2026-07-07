import Foundation

/// Bundles all rendering configuration into a single value type.
///
/// Passed to MudCore's public rendering functions. Adding a new option
/// means adding a field here — no function signatures change. Fields that
/// change the emitted HTML belong in ``ContentIdentity`` (with a forwarding
/// accessor below); fields stored directly on this struct are exempt from
/// the reload identity.
public struct RenderOptions: Sendable, Equatable {
    // Document wrapping. Identity-exempt: title and baseURL only change
    // with the document itself, and standalone never toggles on a live view.
    public var title: String = ""
    public var baseURL: URL? = nil
    public var standalone: Bool = false

    // Display state (baked into initial HTML for first-paint correctness;
    // also applied at runtime via JS for live updates without reload).
    // Identity-exempt for that reason.
    public var htmlClasses: Set<String> = []
    public var zoomLevel: Double = 1.0

    /// The content-affecting options. Stored together so that the synthesized
    /// `Hashable`/`Equatable` conformance *is* the reload identity: a field
    /// added here cannot be left out of it. The waypoint participates by its
    /// source text (`ParsedMarkdown` hashes and compares by `markdown`).
    public struct ContentIdentity: Sendable, Hashable {
        // Document wrapping
        public var theme: String = "earthy"
        public var blockRemoteContent: Bool = false
        public var extensions: Set<String> = []

        // Markdown processing
        public var docCAlertMode: DocCAlertMode = .extended
        public var footnoteMode: FootnoteMode = .section
        public var commentMode: CommentMode = .section

        /// Whether to embed the write-side comment styles
        /// (`mud-comments-edit.css`). Set by the app's live, editable view;
        /// left off for read-only exports so the compose-box and control
        /// styles don't ship with them.
        public var commentsEditable: Bool = false

        // Change tracking
        public var waypoint: ParsedMarkdown?
        public var showInlineDeletions: Bool = false
        public var wordDiffThreshold: Double = 0.25

        public init() {}
    }

    /// Identity value covering only content-affecting options: two options
    /// values with equal identities produce the same HTML for the same
    /// source, so a view can skip the reload. Display-only fields
    /// (htmlClasses, zoomLevel) are excluded because those are applied via
    /// JS without a full page reload.
    public var contentIdentity = ContentIdentity()

    // Forwarding accessors, so call sites keep reading and writing flat
    // fields (`options.theme`) while the storage carries the identity.
    public var theme: String {
        get { contentIdentity.theme }
        set { contentIdentity.theme = newValue }
    }
    public var blockRemoteContent: Bool {
        get { contentIdentity.blockRemoteContent }
        set { contentIdentity.blockRemoteContent = newValue }
    }
    public var extensions: Set<String> {
        get { contentIdentity.extensions }
        set { contentIdentity.extensions = newValue }
    }
    public var docCAlertMode: DocCAlertMode {
        get { contentIdentity.docCAlertMode }
        set { contentIdentity.docCAlertMode = newValue }
    }
    public var footnoteMode: FootnoteMode {
        get { contentIdentity.footnoteMode }
        set { contentIdentity.footnoteMode = newValue }
    }
    public var commentMode: CommentMode {
        get { contentIdentity.commentMode }
        set { contentIdentity.commentMode = newValue }
    }
    public var commentsEditable: Bool {
        get { contentIdentity.commentsEditable }
        set { contentIdentity.commentsEditable = newValue }
    }
    public var waypoint: ParsedMarkdown? {
        get { contentIdentity.waypoint }
        set { contentIdentity.waypoint = newValue }
    }
    public var showInlineDeletions: Bool {
        get { contentIdentity.showInlineDeletions }
        set { contentIdentity.showInlineDeletions = newValue }
    }
    public var wordDiffThreshold: Double {
        get { contentIdentity.wordDiffThreshold }
        set { contentIdentity.wordDiffThreshold = newValue }
    }

    public init() {}
}
