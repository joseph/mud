import Foundation

/// Resolves local image paths to `data:` URIs for self-contained HTML export.
///
/// Uses the same extension whitelist as `LocalFileSchemeHandler` so both
/// rendering paths agree on which files are serveable.
public enum ImageDataURI {
    /// Known image extensions and their MIME types.
    public static let mimeTypes: [String: String] = [
        "png":  "image/png",
        "jpg":  "image/jpeg",
        "jpeg": "image/jpeg",
        "gif":  "image/gif",
        "svg":  "image/svg+xml",
        "webp": "image/webp",
    ]

    /// Resolves `source` against `baseURL`, reads the file, and returns a
    /// base64 data URI.  Returns `nil` if the source is an external URL,
    /// the file doesn't exist, or the extension is not in the whitelist.
    public static func encode(source: String, baseURL: URL) -> String? {
        guard !isExternal(source) else { return nil }

        let resolved = baseURL.deletingLastPathComponent()
            .appendingPathComponent(source)
            .standardized

        let ext = resolved.pathExtension.lowercased()
        guard let mime = mimeTypes[ext] else { return nil }
        guard let data = try? Data(contentsOf: resolved) else { return nil }

        return "data:\(mime);base64,\(data.base64EncodedString())"
    }

    /// Returns `true` for URLs that should be left as-is (remote, data, etc.).
    public static func isExternal(_ source: String) -> Bool {
        let lower = source.lowercased()
        return lower.hasPrefix("http://")
            || lower.hasPrefix("https://")
            || lower.hasPrefix("data:")
            || lower.hasPrefix("mailto:")
    }
}
