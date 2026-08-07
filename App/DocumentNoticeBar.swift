import SwiftUI

// MARK: - Document Notice Bar

/// The info bar: the notice's symbol, then its message, wrapping to as many
/// lines as it needs. `DocumentContentView` attaches it with
/// `.safeAreaInset(edge: .top)`, so it pushes the page down rather than
/// covering it, and SwiftUI sizes it from its own content.
///
/// It is deliberately *not* an `NSTitlebarAccessoryViewController`, which is
/// the AppKit class for a bar under the toolbar. AppKit places app-supplied
/// bottom accessories directly beneath the toolbar and inserts the window's
/// tab bar below them, so a notice about one document would sit above the
/// tabs, reading as though it applied to all of them. Below the tab bar is the
/// only honest place for it, and that means living in the content.
struct DocumentNoticeBar: View {
    let notice: DocumentNotice
    /// Takes the bar down. Only reachable for a notice that sets
    /// `isDismissible`.
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // The message names the problem in words, so the symbol is
            // decoration as far as VoiceOver is concerned.
            // Scaled up and padded, the icon is the tallest thing in the row —
            // which is what keeps a bar with buttons the same height as one
            // without.
            Image(systemName: notice.level.symbolName)
                .symbolRenderingMode(.multicolor)
                .imageScale(.large)
                .accessibilityHidden(true)

            Text(notice.message)
                // Wrap and grow rather than truncate. The message takes the
                // width so the controls sit at the trailing edge.
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)

            if let action = notice.action {
                Button(action.title) { perform(action.effect) }
                    .controlSize(.small)
            }

            if notice.isDismissible {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("Dismiss")
            }
        }
        .font(.callout)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        // The material the toolbar and tab bar use, so the bar reads as chrome
        // continuous with them rather than a panel over the document. It is
        // not an exact match — the join with the chrome above shows as a faint
        // hairline — but every closer-looking alternative tried so far was
        // worse somewhere else. See the plan's "The edges".
        .background(.bar)
        // The system separator, at its own thickness and color, so it tracks
        // lighting on its own and matches the seam above the bar rather than
        // competing with it.
        .overlay(alignment: .bottom) { Divider() }
        .onChange(of: notice.message, initial: true) { _, message in
            // The bar appears on its own and takes no focus, so without this
            // it is silent to VoiceOver.
            AccessibilityNotification.Announcement(message).post()
        }
    }

    /// Carries out a notice's action. It lives here, not on `DocumentNotice`,
    /// so the notice stays a plain value that describes what a button offers
    /// rather than one that can reach out and do it.
    ///
    /// No confirmation afterwards, deliberately: copying is silent everywhere
    /// else on the platform, and a button that rewrote its own label to say so
    /// would be the odd one out.
    ///
    /// The grant panel is hung on `NSApp.keyWindow` rather than on a window
    /// passed in. The reader has just clicked a button in this bar, so the
    /// window holding it is key by definition — and a bar that had to be told
    /// its own window would need one threaded through every call site,
    /// including the previews, for a fact AppKit already knows.
    private func perform(_ effect: DocumentNotice.Action.Effect) {
        switch effect {
        case .copyToPasteboard(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        case .grantFolderAccess(let folder):
            AssetAccessStore.shared.requestAccess(
                startingAt: folder, in: NSApp.keyWindow)
        }
    }
}

#if DEBUG
/// The three levels side by side. Isolated from a real window, so it shows the
/// symbols and the wrapping but not how the bar meets the chrome above it —
/// for that, use the Debugging pane's Notice Bar buttons.
#Preview("Levels") {
    VStack(spacing: 0) {
        DocumentNoticeBar(notice: .sample(.info))
        DocumentNoticeBar(notice: .sample(.warning))
        DocumentNoticeBar(notice: .sample(.error))
    }
    .frame(width: 520)
}
#endif
