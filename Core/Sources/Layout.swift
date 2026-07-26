import Foundation

/// Layout constants the app chrome needs to agree with the rendered page on.
///
/// A media query can only be written in CSS, so the number lives in
/// `mud-narrow.css` as well as here. `HTMLTemplateTests` reads the stylesheet
/// and checks the two stay in step rather than trusting a comment to keep them
/// aligned.
public enum Layout {
    /// The Compact tier breakpoint in `mud-narrow.css`, in CSS pixels.
    ///
    /// At or below this viewport width the Comments column stands down in
    /// favor of the bottom Comments section. Reading comments still works, but
    /// there is nowhere to draw a compose box, so the app explains that instead
    /// of opening one (`DocumentWindowController.addComment`).
    ///
    /// On macOS a WKWebView's CSS pixel is one AppKit point, so a hosting
    /// view's width compares against this directly.
    public static let compactBreakpoint: Double = 700
}
