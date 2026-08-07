import Foundation

// MARK: - Blocked Asset Log

/// The local images one render couldn't read, collected as the render runs.
///
/// The image resolver is handed to `MudCore` as a bare closure and has
/// nowhere to report to. A log goes with it for the length of one render: the
/// resolver records each denied file as it meets it, and `DocumentModel.render`
/// reads the list once the render returns and raises or clears the info bar's
/// notice from it.
///
/// Only denials are collected. A file that simply isn't there is the
/// document's problem, not a permission Mud can ask for.
final class BlockedAssetLog {

    /// The denied files, in the order the render met them, without repeats —
    /// one image referenced twice is one blocked file.
    private(set) var denied: [URL] = []

    func record(_ url: URL) {
        guard !denied.contains(url) else { return }
        denied.append(url)
    }

    /// The resolver to hand `MudCore`, closed over this log. Resolution itself
    /// is `DocumentModel`'s — this only adds the recording.
    var resolver: (_ source: String, _ baseURL: URL) -> String? {
        return { [self] source, baseURL in
            DocumentModel.resolve(
                source: source, baseURL: baseURL, onDenied: record)
        }
    }
}
