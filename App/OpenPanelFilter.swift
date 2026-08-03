import UniformTypeIdentifiers

// MARK: - Open Panel Filter

/// The open panel's file filter, offered in the panel's "Enable:" popup.
///
/// `allowedContentTypes` is a hard filter and AppKit has no way to *prefer*
/// types while still allowing the rest — `panel(_:shouldEnable:)` isn't
/// consulted about items the type filter already rejected, so it can only
/// narrow. A popup that switches the whole filter is the conventional stand-in,
/// and it's what lets a Quarto `.qmd` file be opened without associating the
/// extension first.
///
/// The raw values are the popup's item indices, so `allCases` order is the
/// menu order.
enum OpenPanelFilter: Int, CaseIterable {
    case markdownAndText
    case allFiles

    /// What a freshly built panel starts on.
    static let `default` = OpenPanelFilter.markdownAndText

    /// "and Text Files" because the filter has always included
    /// `public.plain-text`, so `.txt` and anything else conforming to it is
    /// selectable too — the title would otherwise undersell what's enabled.
    var title: String {
        switch self {
        case .markdownAndText: "Markdown and Text Files"
        case .allFiles: "All Files"
        }
    }

    /// The types to hand `NSOpenPanel.allowedContentTypes`. An **empty** array
    /// turns the panel's filtering off rather than allowing nothing, which is
    /// what makes `allFiles` work.
    ///
    /// Folders are absent from both cases on purpose: a type filter doesn't
    /// decide whether a folder can be chosen — `canChooseDirectories` does,
    /// and `DocumentController` sets it — while listing `public.folder` here
    /// would only change which folders the panel greys out.
    var contentTypes: [UTType] {
        switch self {
        case .markdownAndText: [.markdown, .plainText]
        case .allFiles: []
        }
    }
}
