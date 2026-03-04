import Foundation
import MudCore

// MARK: - Error Page

/// Generates error-page HTML documents for display in a WKWebView.
enum ErrorPage {
    static func fileNotFound(error: Error) -> String {
        render("> Error: \(error.localizedDescription)")
    }

    static func filePermissionDenied(path: String, error: Error) -> String {
        render("""
        > Error: \(error.localizedDescription)

        This can happen when you try to load another local document by
        following a link.

        ----

        > Tip: Try opening this document via File > Open.
        > ```\(path)```

        If this limitation is frustrating, consider installing the
        [notarized-but-not-sandboxed version
        of Mud](https://github.com/joseph/mud/releases).
        """)
    }

    static func fileEncodingError() -> String {
        render("> Error: The file's text encoding couldn't be determined.")
    }

    private static func render(_ markdown: String) -> String {
        MudCore.renderUpModeDocument(markdown, theme: "system")
    }
}
