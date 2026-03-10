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

    public init() {}
}
