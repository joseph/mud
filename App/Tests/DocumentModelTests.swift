import Foundation
import MudCore
import MudPreferences
import Testing
@testable import Mud

private extension DocumentModel.Content {
    var markdown: String? {
        if case .parsed(let parsed) = self { return parsed.markdown }
        return nil
    }

    var isErrorPage: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - Self-write dedup policy

/// The registry that tells Mud's own comment-write echoes apart from
/// external edits (Phase 1 fix 7: ordered, oldest evicted first).
@MainActor
@Suite struct SelfWriteRegistryTests {
    private func makeModel() -> DocumentModel {
        let state = DocumentState()
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("never-created-\(UUID().uuidString).md")
        return DocumentModel(
            fileURL: url, state: state, changeTracker: state.changeTracker)
    }

    @Test func matchingEchoIsConsumedOnce() {
        let model = makeModel()
        model.registerSelfWrite("content A")
        #expect(model.consumeSelfWrite("content A"))
        #expect(!model.consumeSelfWrite("content A"))
    }

    @Test func duplicateWritesEachGetAnEcho() {
        let model = makeModel()
        model.registerSelfWrite("same")
        model.registerSelfWrite("same")
        #expect(model.consumeSelfWrite("same"))
        #expect(model.consumeSelfWrite("same"))
        #expect(!model.consumeSelfWrite("same"))
    }

    @Test func externalEditClearsStaleEntries() {
        let model = makeModel()
        model.registerSelfWrite("ours 1")
        model.registerSelfWrite("ours 2")
        #expect(!model.consumeSelfWrite("someone else's edit"))
        // The file has moved past the pending writes; they must be gone.
        #expect(!model.consumeSelfWrite("ours 1"))
    }

    @Test func registryHoldsEightEntries() {
        let model = makeModel()
        for i in 0..<8 { model.registerSelfWrite("write \(i)") }
        #expect(model.consumeSelfWrite("write 0"))
    }

    @Test func ninthEntryEvictsTheOldest() {
        let model = makeModel()
        for i in 0..<9 { model.registerSelfWrite("write \(i)") }
        #expect(!model.consumeSelfWrite("write 0"))
    }
}

// MARK: - File watcher hold/echo policy

/// The watcher policy end to end, against a real file: external edits
/// reload (and badge a non-key window), self-write echoes don't badge, and
/// an open compose box holds every change until composing ends. These tests
/// `await` so the watcher's main-queue DispatchSource handler can run.
@MainActor
@Suite struct DocumentModelWatcherTests {
    private let directory: URL
    private let fileURL: URL
    private let state: DocumentState
    private let model: DocumentModel

    init() throws {
        directory = try makeTempDirectory()
        fileURL = directory.appendingPathComponent("watched.md")
        try "one".write(to: fileURL, atomically: true, encoding: .utf8)
        state = DocumentState()
        model = DocumentModel(
            fileURL: fileURL, state: state, changeTracker: state.changeTracker)
    }

    private func overwrite(_ text: String) throws {
        // Non-atomic, so the watcher sees a plain write event rather than
        // the delete-and-reappear of an atomic save.
        try text.write(to: fileURL, atomically: false, encoding: .utf8)
    }

    @Test func loadReadsTheFile() {
        model.load()
        #expect(model.content.markdown == "one")
    }

    @Test func externalEditReloadsAndBadgesANonKeyWindow() async throws {
        model.load()
        try overwrite("two")
        #expect(await pumpUntil { model.content.markdown == "two" })
        // No window controller in tests, so the window is never key —
        // exactly the background-reload case.
        #expect(model.hasBackgroundReload)
    }

    @Test func atomicSaveIsPickedUpViaTheRewatch() async throws {
        model.load()
        try "two".write(to: fileURL, atomically: true, encoding: .utf8)
        #expect(await pumpUntil { model.content.markdown == "two" })
    }

    @Test func selfWriteEchoDoesNotBadge() async throws {
        model.load()
        model.registerSelfWrite("two")
        try overwrite("two")
        #expect(await pumpUntil { model.content.markdown == "two" })
        #expect(!model.hasBackgroundReload)
    }

    @Test func composingHoldsAnExternalChange() async throws {
        model.load()
        state.isColumnComposing = true
        try overwrite("two")
        // Give the watcher time to fire; the change must be held, not applied.
        await pump(0.5)
        #expect(model.content.markdown == "one")
        #expect(model.externalChangeHeld)

        state.isColumnComposing = false
        #expect(await pumpUntil { model.content.markdown == "two" })
        #expect(!model.externalChangeHeld)
    }

    @Test func composingHoldsOurOwnEchoWithoutTheBanner() async throws {
        model.load()
        state.isColumnComposing = true
        model.registerSelfWrite("two")
        try overwrite("two")
        await pump(0.5)
        #expect(model.content.markdown == "one")  // held with the box open
        #expect(!model.externalChangeHeld)  // but it isn't an external edit

        state.isColumnComposing = false
        #expect(await pumpUntil { model.content.markdown == "two" })
    }

    @Test func forcedLoadChangesTheContentIDWithIdenticalText() {
        model.load()
        let before = model.display().contentID
        #expect(model.display().contentID == before)  // cached and stable

        model.load(forced: true)
        #expect(model.display().contentID != before)
    }

    @Test func firstCommentRevealsTheColumnAndPrunesLocators() async throws {
        model.load()
        #expect(!state.commentsColumnVisible)
        model.pendingCommentLocators = ["comment-zz": CommentLocator(
            blockText: "gone", offset: 0, occurrence: 0)]

        let commented = """
        Hello world.[^comment-a]

        [^comment-a]: > Hello world.

            A note.
        """
        try overwrite(commented)
        #expect(await pumpUntil { model.content.markdown == commented })
        #expect(state.commentsColumnVisible)
        // The stale locator's label no longer exists; it must be pruned.
        #expect(model.pendingCommentLocators.isEmpty)
    }
}

// MARK: - A read that fails

/// What a failed read does to the window, which depends entirely on whether
/// there is a document in it. With one, the document stays and the bar says it
/// is no longer what's on disk; without one, the error page goes up as the
/// document's stand-in.
///
/// These stop the watcher after the first load, so the only reads are the ones
/// the test asks for.
@MainActor
@Suite struct DocumentModelReadFailureTests {
    private let directory: URL
    private let fileURL: URL
    private let state: DocumentState
    private let model: DocumentModel

    init() throws {
        directory = try makeTempDirectory()
        fileURL = directory.appendingPathComponent("Notes.md")
        state = DocumentState()
        model = DocumentModel(
            fileURL: fileURL, state: state, changeTracker: state.changeTracker)
    }

    /// Opens the file and drops the watcher, leaving a loaded document.
    private func openDocument() throws {
        try "# First".write(to: fileURL, atomically: true, encoding: .utf8)
        model.load()
        model.stopWatching()
    }

    private func removeFile() throws {
        try FileManager.default.removeItem(at: fileURL)
    }

    /// The point of the whole thing: a reload that can't read the file leaves
    /// the reader's document — and their place in it — exactly where it was.
    @Test func aFailedReloadKeepsTheDocument() throws {
        try openDocument()
        try removeFile()

        model.load(forced: true)

        #expect(model.content.markdown == "# First")
        #expect(state.notice?.kind == .reloadFailed)
        #expect(state.notice?.message
            == DocumentNotice.ReadFailure.notFound.reloadMessage(
                fileName: "Notes.md"))
    }

    /// The three failures don't read the same, so the read's classification
    /// has to reach the bar: a file that turns into bytes Mud can't decode
    /// must not borrow the missing-file sentence.
    @Test func aFileThatStopsBeingUTF8SaysSo() throws {
        try openDocument()
        try Data([0xFF, 0xFE, 0xFF]).write(to: fileURL)

        model.load(forced: true)

        #expect(model.content.markdown == "# First")
        #expect(state.notice?.message
            == DocumentNotice.ReadFailure.badEncoding.reloadMessage(
                fileName: "Notes.md"))
    }

    /// The reader can take the message down: nothing else will, and the
    /// document under it is still worth reading.
    @Test func theFailedReloadNoticeIsDismissible() throws {
        try openDocument()
        try removeFile()
        model.load(forced: true)

        state.dismissNotice()
        #expect(state.notice == nil)
    }

    @Test func aLaterGoodReloadClearsTheNotice() throws {
        try openDocument()
        try removeFile()
        model.load(forced: true)

        try "# Second".write(to: fileURL, atomically: true, encoding: .utf8)
        model.load(forced: true)

        #expect(model.content.markdown == "# Second")
        #expect(state.notice == nil)
    }

    /// With no document to keep, the error page is the better answer: it
    /// carries the diagnosis, and there is nothing behind it to lose.
    @Test func aFirstReadThatFailsShowsTheErrorPage() {
        model.load()

        #expect(model.content.isErrorPage)
        #expect(state.notice?.kind == .openFailed)
    }

    /// A retry over an error page is not a reload of a document — there is
    /// still nothing to keep, so the page and its `openFailed` headline stay.
    @Test func aRetryAfterAFailedOpenKeepsTheErrorPage() {
        model.load()
        model.load(forced: true)

        #expect(model.content.isErrorPage)
        #expect(state.notice?.kind == .openFailed)
    }
}

// MARK: - The empty-folder window

/// The model behind the window `DocumentController` opens on a folder that
/// held no Markdown. Its URL is not a document, and this is what it does with
/// it: the blank page under the `folderHasNoMarkdown` notice, and no watcher —
/// what moves inside the folder can't change either one, and Cmd+R
/// (`DocumentWindowController.reopenFolder`) is what picks up a new file.
///
/// Under the tab behavior, which these pin rather than read from the reader's
/// preferences, that is the only window a folder ever gets.
@MainActor
@Suite struct DocumentModelFolderTests {
    private let directory: URL
    private let state: DocumentState
    private let model: DocumentModel

    init() throws {
        directory = try makeTempDirectory()
        state = DocumentState()
        model = DocumentModel(
            fileURL: directory, state: state,
            changeTracker: state.changeTracker, folderBehavior: { .tabs })
    }

    @Test func aFolderLoadsAsABlankPageUnderTheNotice() {
        model.load()

        #expect(model.content.isErrorPage)
        #expect(state.notice == DocumentNotice.folderHasNoMarkdown)
    }

    /// No watcher runs on a folder, so a file appearing inside it leaves the
    /// window exactly as it was — including the badge a background reload
    /// would have set.
    @Test func aFileAppearingInTheFolderChangesNothing() async throws {
        model.load()

        try "# New".write(
            to: directory.appendingPathComponent("added.md"),
            atomically: false, encoding: .utf8)
        await pump(0.5)

        #expect(model.content.isErrorPage)
        #expect(state.notice == DocumentNotice.folderHasNoMarkdown)
        #expect(!model.hasBackgroundReload)
    }
}

// MARK: - The folder-index window

/// The same window under the index behavior: the folder's tree becomes the
/// document. The walk itself is `FolderIndexTests`' subject; this is about
/// what the model does with it — that a folder with something in it is a
/// document rather than an error page, that Cmd+R walks again, and that an
/// empty tree still falls back to the blank page.
@MainActor
@Suite struct DocumentModelFolderIndexTests {
    private let directory: URL
    private let state: DocumentState
    private let model: DocumentModel

    init() throws {
        directory = try makeTempDirectory()
        state = DocumentState()
        model = DocumentModel(
            fileURL: directory, state: state,
            changeTracker: state.changeTracker, folderBehavior: { .index })
    }

    private func write(_ path: String) throws {
        let url = directory.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        try "# Heading\n".write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func theTreeBecomesTheDocument() throws {
        try write("top.md")
        try write("Sub/deep.md")
        model.load()

        let source = try #require(model.content.markdown)
        #expect(source.contains("- [top.md](top.md)"))
        #expect(source.contains("- **Sub/**"))
        #expect(source.contains("- [deep.md](Sub/deep.md)"))
        #expect(state.notice == nil)
    }

    /// The window has no file watcher, so a document added since the index
    /// opened turns up on the next load — which is what Cmd+R does
    /// (`DocumentWindowController.reloadDocument`).
    @Test func aForcedLoadWalksTheTreeAgain() throws {
        try write("first.md")
        model.load()
        #expect(model.content.markdown?.contains("second.md") != true)

        try write("second.md")
        model.load(forced: true)

        #expect(model.content.markdown?.contains("second.md") == true)
    }

    /// Relative destinations only resolve if the page's `<base href>` names
    /// the folder as a folder.
    @Test func theBaseURLEndsInASlash() {
        #expect(model.baseURL.absoluteString.hasSuffix("/"))
    }

    @Test func aTreeWithNoMarkdownIsStillTheBlankPage() throws {
        try write("Assets/logo.png")
        model.load()

        #expect(model.content.isErrorPage)
        #expect(state.notice == DocumentNotice.folderHasNoMarkdown)
    }
}

// MARK: - External waypoint provider

/// The `WaypointProvider` seam (Phase 4g): a load queries the injected
/// provider and hands its waypoints to the change tracker; a disabled
/// provider clears them instead.
@MainActor
@Suite struct DocumentModelWaypointTests {
    private nonisolated struct FakeProvider: WaypointProvider {
        let enabled: Bool
        let waypoints: [Waypoint]
        @MainActor var isEnabled: Bool { enabled }
        func queryWaypoints(
            for fileURL: URL, currentContent: String
        ) -> [Waypoint] {
            waypoints
        }
    }

    private let fileURL: URL
    private let state = DocumentState()

    init() throws {
        let directory = try makeTempDirectory()
        fileURL = directory.appendingPathComponent("tracked.md")
        try "current".write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func makeModel(_ provider: FakeProvider) -> DocumentModel {
        DocumentModel(
            fileURL: fileURL, state: state,
            changeTracker: state.changeTracker, waypointProvider: provider)
    }

    private var externalWaypointIDs: [UUID] {
        state.changeTracker.waypoints.compactMap {
            if case .external = $0.kind { return $0.id }
            return nil
        }
    }

    @Test func loadHandsProviderWaypointsToTheTracker() async {
        let external = Waypoint(
            parsed: ParsedMarkdown("older"), timestamp: Date(),
            kind: .external(label: "since commit abc1234", detail: "Old."))
        let model = makeModel(FakeProvider(enabled: true, waypoints: [external]))
        model.load()
        // The query hops off the main thread; wait for it to land.
        #expect(await pumpUntil { externalWaypointIDs == [external.id] })
    }

    @Test func disabledProviderClearsExternalWaypoints() {
        let stale = Waypoint(
            parsed: ParsedMarkdown("older"), timestamp: Date(),
            kind: .external(label: "since commit abc1234", detail: nil))
        state.changeTracker.setExternalWaypoints([stale])
        let model = makeModel(FakeProvider(enabled: false, waypoints: [stale]))
        model.load()
        // The disabled guard clears synchronously — no query to wait for.
        #expect(externalWaypointIDs.isEmpty)
    }
}
