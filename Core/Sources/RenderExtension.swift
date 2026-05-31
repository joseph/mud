import Foundation

/// Encapsulates the full lifecycle of a client-side rendering feature.
///
/// Each extension follows the same pattern: detect a marker in the
/// rendered HTML, conditionally inject scripts for embedded export
/// (CLI `--browser`, Open In Browser), and conditionally inject
/// scripts at runtime in WKWebView.
public struct RenderExtension: Sendable {
    public let name: String
    public let marker: String
    let cspSources: [String]
    let embeddedScripts: [HTMLDocument.Script]
    let runtimeResources: [String]

    /// Loads runtime JS resources in order, for WKWebView injection.
    public func runtimeJS() -> [String] {
        runtimeResources.compactMap { HTMLTemplate.loadResource($0, type: "js") }
    }

    // MARK: - Built-in extensions

    private static let mermaidCDN =
        "https://cdn.jsdelivr.net/npm/mermaid@11.12.3/dist/mermaid.min.js"

    private static var mermaidInitJS: String {
        HTMLTemplate.loadResource("mermaid-init", type: "js") ?? ""
    }

    static let mermaid = RenderExtension(
        name: "mermaid",
        marker: "language-mermaid",
        cspSources: ["https://cdn.jsdelivr.net", "'unsafe-inline'"],
        embeddedScripts: [
            .src(mermaidCDN),
            .inline(mermaidInitJS),
        ],
        runtimeResources: ["mermaid.min", "mermaid-init"]
    )

    private static var copyCodeInitJS: String {
        HTMLTemplate.loadResource("copy-code", type: "js") ?? ""
    }

    static let copyCode = RenderExtension(
        name: "copyCode",
        marker: "mud-code",
        cspSources: ["'unsafe-inline'"],
        embeddedScripts: [.inline(copyCodeInitJS)],
        runtimeResources: ["copy-code"]
    )

    // MARK: - Registry

    public static let registry: [String: RenderExtension] = [
        mermaid.name: mermaid,
        copyCode.name: copyCode,
    ]
}
