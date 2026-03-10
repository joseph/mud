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
    public var includeBaseTag: Bool = true
    public var blockRemoteContent: Bool = false
    public var embedMermaid: Bool = false

    // Markdown processing
    public var doccAlertMode: DocCAlertMode = .extended

    // Display state (baked into initial HTML for first-paint correctness;
    // also applied at runtime via JS for live updates without reload)
    public var htmlClasses: Set<String> = []
    public var zoomLevel: Double = 1.0

    public init() {}

    /// Identity string covering only content-affecting options.
    /// Display-only fields (htmlClasses, zoomLevel) are excluded because
    /// those can be applied via JS without a full page reload.
    public var contentIdentity: String {
        "\(theme)\(blockRemoteContent)\(doccAlertMode.rawValue)\(embedMermaid)"
    }
}
