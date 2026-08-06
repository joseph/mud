import Foundation
import MudCore

// MARK: - Error Page

/// Generates error-page HTML documents for display in a WKWebView.
enum ErrorPage {
    static func fileNotFound(error: Error) -> String {
        empty()
    }

    static func filePermissionDenied(path: String, error: Error) -> String {
        render("""
        > Tip: Try opening this document via File > Open.
        > ```\(path)```

        If this limitation is frustrating, consider installing the
        [notarized-but-not-sandboxed version
        of Mud](https://github.com/joseph/mud/releases).
        """)
    }

    static func fileEncodingError() -> String {
        empty()
    }

    /// A page with nothing on it, for a window whose content is absent rather
    /// than broken — the folder that held no Markdown. What happened is the
    /// info bar's to say (`DocumentNotice.folderHasNoMarkdown`), so the page
    /// itself says nothing.
    static func empty() -> String {
        render("")
    }

    private static func render(_ markdown: String) -> String {
        var opts = RenderOptions()
        opts.theme = .system
        return MudCore.renderUpModeDocument(markdown, options: opts)
    }
}
