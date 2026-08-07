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
            /// Ask the reader for a folder Mud may read local content from,
            /// opening the panel at `startingAt`. Carried out by
            /// `AssetAccessStore.requestAccess`.
            case grantFolderAccess(startingAt: URL)
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
        /// The file couldn't be read, and there was no document on screen to
        /// keep. The content area shows the matching `ErrorPage` — blank for
        /// two of the three failures — and this names the failure over it.
        /// Cleared by the next successful read.
        case openFailed
        /// A document that had opened once couldn't be read again, so the
        /// window still shows the last version Mud read. Nothing is on screen
        /// to explain that but this. Cleared by the next successful read, or
        /// by the reader.
        case reloadFailed
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
        /// A comment couldn't be written to the file. Dismissible, like
        /// `reloadFailed`: the reader may be looking at a window nothing else
        /// will take the message off.
        case commentWriteFailed
        /// Local images this document references are in a folder Mud isn't
        /// allowed to read. Raised only in the sandboxed build, where a file
        /// the reader hasn't handed Mud is off limits and granting the folder
        /// is the remedy; an unsandboxed Mud reads what the file system lets
        /// it, and "grant a folder" would answer nothing. Cleared by a render
        /// that reads every image.
        case localAssetsBlocked
        #if DEBUG
        /// Raised only from the Debugging settings pane, to see the bar at
        /// each level in a real window. Not in a release build.
        case debug
        #endif
    }

    /// Why a read of the document's file failed, in the only three flavors
    /// Mud can tell apart (`DocumentModel.readDisk`). It exists to pick the
    /// sentence: `openFailed` and `reloadFailed` each say a different thing
    /// about each of these, and the two error pages that go with the first and
    /// last are blank, so the bar carries the diagnosis on its own.
    enum ReadFailure {
        /// Nothing at the path — deleted, renamed, or on a volume that went
        /// away.
        case notFound
        /// The file is there and Mud isn't allowed to read it. Common in the
        /// sandboxed build, where a path Mud wasn't handed by the reader is
        /// off limits.
        case noPermission
        /// The bytes read, and aren't UTF-8. Mud reads nothing else.
        case badEncoding

        /// What the bar says when this failure left the window with no
        /// document — an error page is showing, and this is the headline.
        func openMessage(fileName: String) -> String {
            switch self {
            case .notFound:
                return "The file “\(fileName)” couldn’t be found."
            case .noPermission:
                return "Mud doesn’t have permission to open “\(fileName)”."
            case .badEncoding:
                return "The file “\(fileName)” isn’t valid UTF-8 text."
            }
        }

        /// What the bar says when the document is still on screen: the file
        /// opened once, and this is what stopped it opening again.
        func reloadMessage(fileName: String) -> String {
            switch self {
            case .notFound:
                return "The file “\(fileName)” is missing."
            case .noPermission:
                return "Mud no longer has permission to read “\(fileName)”."
            case .badEncoding:
                return "The file “\(fileName)” is no longer valid UTF-8 text."
            }
        }
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

    /// The headline over the `ErrorPage` that took the document's place on a
    /// read that had no document to keep.
    ///
    /// Two of the three pages are blank (`ErrorPage.fileNotFound` and
    /// `.fileEncodingError`), so the bar is the only thing on screen naming
    /// the failure. That is why the message varies with `reason` rather than
    /// leaving the diagnosis to the page.
    static func openFailed(fileName: String, reason: ReadFailure) -> Self {
        return Self(
            kind: .openFailed,
            level: .warning,
            message: reason.openMessage(fileName: fileName)
        )
    }

    /// The document on screen is still the last version Mud read, so this says
    /// what the window can't: what you are reading is not what is on disk. No
    /// page underneath here at all, so `reason` is the only diagnosis there is.
    ///
    /// It carries an × where `openFailed` doesn't, because the reader is left
    /// with a document they can go on using. A file that stays unreadable — a
    /// rename, a delete, a volume that went away — would otherwise leave the
    /// bar up over a perfectly good document for as long as the window is
    /// open.
    static func reloadFailed(fileName: String, reason: ReadFailure) -> Self {
        return Self(
            kind: .reloadFailed,
            level: .warning,
            message: reason.reloadMessage(fileName: fileName),
            isDismissible: true
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
            message: "This folder holds more than \(limit.formatted()) Markdown files."
        )
    }

    /// Images this document points at are there, and Mud can't read them.
    ///
    /// The button opens a file panel with nothing in between, so the message
    /// carries the whole reason on its own — by the time the panel is up, the
    /// reader has to already know what they are being asked for and why.
    ///
    /// `folder` is where that panel opens: the document's own folder, since a
    /// document usually keeps its images below itself. It isn't a promise
    /// about which folder to choose — the reader can go anywhere, and an image
    /// somewhere else raises this again with the next render.
    ///
    /// Dismissible, because a reader who doesn't care about the images should
    /// be able to put the bar away; a render that reads every image also takes
    /// it down.
    static func localAssetsBlocked(folder: URL) -> Self {
        return Self(
            kind: .localAssetsBlocked,
            level: .warning,
            message: "Mud doesn’t have your permission to "
                + "access the images in this document.",
            action: Action(
                title: "Grant Access…",
                effect: .grantFolderAccess(startingAt: folder)),
            isDismissible: true
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
            return openFailed(fileName: "Notes.md", reason: .notFound).message
        case .error:
            return "Mud couldn’t write to this file, "
                + "so the comment couldn’t be saved."
        }
    }
}
#endif
