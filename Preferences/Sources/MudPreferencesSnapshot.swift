import Foundation
import MudCore

/// A one-shot read of the preferences a Quick Look preview (or any other
/// non-reactive consumer) needs. Built from `MudPreferences.snapshot()`.
///
/// The surface area covers only the fields that flow into `RenderOptions`.
/// Preferences that don't affect a preview (lighting, sidebar state,
/// quit-on-close, etc.) are deliberately omitted.
public struct MudPreferencesSnapshot: Sendable {
    public let theme: Theme
    public let upModeZoomLevel: Double
    public let viewToggles: Set<ViewToggle>
    public let upModeAllowRemoteContent: Bool
    public let enabledExtensions: Set<String>
    public let diagramLook: DiagramLook
    public let markdownDocCAlertMode: DocCAlertMode

    public init(
        theme: Theme,
        upModeZoomLevel: Double,
        viewToggles: Set<ViewToggle>,
        upModeAllowRemoteContent: Bool,
        enabledExtensions: Set<String>,
        diagramLook: DiagramLook,
        markdownDocCAlertMode: DocCAlertMode
    ) {
        self.theme = theme
        self.upModeZoomLevel = upModeZoomLevel
        self.viewToggles = viewToggles
        self.upModeAllowRemoteContent = upModeAllowRemoteContent
        self.enabledExtensions = enabledExtensions
        self.diagramLook = diagramLook
        self.markdownDocCAlertMode = markdownDocCAlertMode
    }

    /// CSS classes derived from the Up-mode-relevant view toggles.
    /// Down-mode-only toggles (code header, auto-expand changes) are excluded.
    public var upModeHTMLClasses: Set<String> {
        let upModeToggles: Set<ViewToggle> = [
            .readableColumn, .wordWrap, .lineNumbers,
        ]
        return Set(
            viewToggles
                .intersection(upModeToggles)
                .map(\.className)
        )
    }
}

extension RenderOptions {
    /// The one mapping from stored preferences to a `RenderOptions`, covering
    /// the fields the app and the Quick Look extension set identically. This
    /// package is the only place that sees both types, so the mapping lives
    /// here rather than being written twice.
    ///
    /// The app calls this too, then overrides the two window-specific display
    /// fields (the mode-dependent `zoomLevel` and the all-toggles
    /// `htmlClasses`) and sets the change-tracking fields; those inputs aren't
    /// in the snapshot.
    public init(snapshot: MudPreferencesSnapshot, baseURL: URL?) {
        self.init()
        self.baseURL = baseURL
        self.theme = snapshot.theme
        self.extensions = snapshot.enabledExtensions
        self.diagramLook = snapshot.diagramLook
        self.htmlClasses = snapshot.upModeHTMLClasses
        self.zoomLevel = snapshot.upModeZoomLevel
        self.blockRemoteContent = !snapshot.upModeAllowRemoteContent
        self.docCAlertMode = snapshot.markdownDocCAlertMode
    }
}

extension MudPreferences {
    public func snapshot(defaultEnabledExtensions: Set<String> = []) -> MudPreferencesSnapshot {
        MudPreferencesSnapshot(
            theme: theme,
            upModeZoomLevel: upModeZoomLevel,
            viewToggles: viewToggles,
            upModeAllowRemoteContent: upModeAllowRemoteContent,
            enabledExtensions: readEnabledExtensions(defaultValue: defaultEnabledExtensions),
            diagramLook: upModeDiagramLook,
            markdownDocCAlertMode: markdownDocCAlertMode
        )
    }
}
