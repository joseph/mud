import Foundation

// MARK: - Document Notice

/// A short, non-blocking message about the document, shown in the info bar
/// (`DocumentNoticeBar`). `DocumentState.notice` holds the one on screen.
struct DocumentNotice: Equatable {

    /// A button at the bar's trailing edge. Only for something the reader can
    /// usefully do about the notice from there — not a way to acknowledge it,
    /// which is what `isDismissible` is for.
    ///
    /// What the button does is a value, not a closure. Three things follow:
    /// `DocumentNotice` keeps a synthesized `Equatable` (a closure can't be
    /// compared, and a hand-written `==` silently rots when a field is added);
    /// this file stays free of AppKit; and a test can assert what a button
    /// *would* do. `DocumentNoticeBar.perform(_:)` is what actually does it.
    struct Action: Equatable {
        let title: String
        let effect: Effect

        enum Effect: Equatable {
            /// Replace the pasteboard's contents with this string.
            case copyToPasteboard(String)
        }
    }

    /// How much weight a notice is drawn with. The levels differ only in their
    /// symbol — all three sit on the same chrome background, so none of them
    /// competes with the document for attention. The symbols are drawn
    /// `.multicolor`, which is where the blue, yellow, and red come from.
    enum Level {
        /// Worth knowing, but nothing is wrong: the view is a version behind
        /// and will catch up on its own.
        case info
        /// The document isn't what it should be — it couldn't be read, or
        /// what's on screen can't be trusted.
        case warning
        /// An operation failed and the user's work is at stake.
        case error

        var symbolName: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "exclamationmark.octagon.fill"
            }
        }
    }

    /// Why a notice was raised. Also its identity: `DocumentState.clear` takes
    /// a kind rather than clearing whatever is showing, so one condition
    /// ending can't take down another condition's notice.
    enum Kind {
        /// The file couldn't be read. The content area shows the matching
        /// `ErrorPage` with the details; this is the headline over it. Cleared
        /// by the next successful read.
        case openFailed
        /// An external edit arrived while a comment compose box was open, so
        /// the edit is being held: the page shows a version behind the file on
        /// disk until the box closes. See `DocumentModel.externalChangeHeld`.
        case externalChangeHeld
        /// Mud was asked to open a folder that holds no Markdown files. The
        /// window exists only to carry this message, so the content area is a
        /// blank page (`ErrorPage.empty`).
        case folderHasNoMarkdown
        /// The generated folder index hit `FolderIndex.fileLimit`, so it lists
        /// part of the tree rather than all of it. Cleared by a later walk
        /// that fits.
        case folderIndexTruncated
        /// A comment couldn't be written to the file. The only notice a reader
        /// can dismiss — nothing else takes it down, because nothing else
        /// knows they have read it.
        case commentWriteFailed
        #if DEBUG
        /// Raised only from the Debugging settings pane, to see the bar at
        /// each level in a real window. Not in a release build.
        case debug
        #endif
    }

    let kind: Kind
    let level: Level
    let message: String
    /// A button at the trailing edge, or nil for a notice with nothing to do.
    var action: Action?
    /// Whether the reader can take the bar down themselves. False for a notice
    /// that clears itself when its condition ends — an × there would suggest
    /// the condition can be dismissed too.
    var isDismissible: Bool = false
}

// MARK: - The Notices

extension DocumentNotice {
    /// Raised and cleared by `DocumentModel.externalChangeHeld`.
    static let externalChangeHeld = Self(
        kind: .externalChangeHeld,
        level: .info,
        message: "The file has changed. "
            + "Your view refreshes when you finish this comment."
    )

    /// The headline over an `ErrorPage`. Deliberately short and free of
    /// diagnosis — which of the three read failures it was, and what to do
    /// about it, is what the page underneath is for.
    static func openFailed(fileName: String) -> Self {
        return Self(
            kind: .openFailed,
            level: .warning,
            message: "The file “\(fileName)” couldn’t be opened."
        )
    }

    /// Nothing is broken — the folder just isn't a document and holds none —
    /// so this is a warning, like a file that couldn't be read, rather than an
    /// error. There is nothing to do about it from the bar and nothing that
    /// clears it, so it carries neither a button nor an ×.
    static let folderHasNoMarkdown = Self(
        kind: .folderHasNoMarkdown,
        level: .warning,
        message: "This folder does not contain Markdown files."
    )

    /// The folder index stopped at its limit. Nothing is wrong — the document
    /// is just not the whole tree — so it reads as information, like a held
    /// change. There is nothing to do about it from the bar, and a walk that
    /// fits takes it down, so it carries neither a button nor an ×.
    static func folderIndexTruncated(limit: Int) -> Self {
        return Self(
            kind: .folderIndexTruncated,
            level: .info,
            message: "This folder holds more than \(limit.formatted()) "
                + "Markdown files. The list shows the first "
                + "\(limit.formatted())."
        )
    }

    /// A comment edit that didn't reach the file. `note` is the body the
    /// reader wrote, offered to the pasteboard when there is one: on every
    /// failure but a delete the compose box stays open holding this text, so
    /// the button is a second copy rather than the only one.
    ///
    /// `composeIsOpen` decides whether the bar gets an ×. When a box survived
    /// the failure, closing it clears this notice
    /// (`DocumentState.isColumnComposing`), and that is the better way out —
    /// it settles the comment and the message about it together. An × beside
    /// it would be a second control that takes down only half of that, leaving
    /// a box the reader was told nothing about. A delete has no box, so the ×
    /// is the only thing that knows when they have read it.
    static func commentWriteFailed(
        message: String, note: String, composeIsOpen: Bool
    ) -> Self {
        return Self(
            kind: .commentWriteFailed,
            level: .error,
            message: message,
            action: note.isEmpty
                ? nil
                : Action(
                    title: "Copy Comment",
                    effect: .copyToPasteboard(note)),
            isDismissible: !composeIsOpen
        )
    }
}

#if DEBUG
extension DocumentNotice {
    /// A stand-in notice per level, for the Debugging pane and the
    /// `DocumentNoticeBar` preview. Each one mirrors the real notice at that
    /// level — same message length, same trailing controls — so what the pane
    /// shows is what the app shows. `.info` and `.warning` carry neither
    /// control, as `externalChangeHeld` and `openFailed` don't.
    ///
    /// `.error` carries both, which is one more than any single real notice
    /// has: `commentWriteFailed` takes the × only when no compose box is open
    /// to clear it, and that variant (a failed delete) has no text to copy. The
    /// sample shows both anyway, because the widest row is the one whose
    /// spacing is worth looking at.
    ///
    /// The sample's button works, and copies the stand-in note below. With the
    /// effect a value rather than a closure there is nothing to stub out — a
    /// no-op would mean an `Effect` case that exists only for samples, which is
    /// more to carry than just letting the button do what it says.
    static func sample(_ level: Level) -> Self {
        let hasControls = level == .error
        return Self(
            kind: .debug,
            level: level,
            message: sampleMessage(level),
            action: hasControls
                ? Action(
                    title: "Copy Comment",
                    effect: .copyToPasteboard("A sample comment body."))
                : nil,
            isDismissible: hasControls
        )
    }

    private static func sampleMessage(_ level: Level) -> String {
        switch level {
        case .info:
            return externalChangeHeld.message
        case .warning:
            return openFailed(fileName: "Notes.md").message
        case .error:
            return "Mud couldn’t write to this file, "
                + "so the comment couldn’t be saved."
        }
    }
}
#endif
