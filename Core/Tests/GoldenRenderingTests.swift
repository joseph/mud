import Foundation
import Testing

@testable import MudCore

/// Whole-document golden tests: each case renders a corpus document or an edit
/// pair through a public `MudCore` entry point and compares the HTML against a
/// checked-in fixture under `Core/Tests/Golden/`.
///
/// These restore the per-construct output coverage the single-parser cutover
/// removed when it deleted the legacy visitors' HTML-assertion suites
/// (`UpHTMLVisitorTests`, `DownHTMLVisitorTests`). A whole-document pin is a
/// blunter instrument than a per-construct assertion, but it covers every node
/// type at once and gives the mechanical cleanup slices a byte-for-byte safety
/// net: a change meant to alter no output alters no fixture.
///
/// Rendering goes through the body-level entry points (`renderUpToHTML` /
/// `renderDownToHTML`), not the full-document ones, on purpose: the body
/// output is a pure function of source and options — no clock, no environment,
/// and no `Set`-ordered class list from the document template — so fixtures are
/// stable across runs and machines.
///
/// ## Regenerating
///
/// Run the suite with `MUD_REGENERATE_GOLDENS=1` set. Each case then writes its
/// current output to the fixture instead of asserting, creating
/// `Core/Tests/Golden/` on first run. Regenerating is deliberate: review the
/// resulting `git diff` before committing — an unexpected fixture change is a
/// real output change. A normal run (variable unset) asserts, and fails on any
/// mismatch or missing fixture.
@Suite("Golden rendering")
struct GoldenRenderingTests {

    // MARK: - Plain rendering

    // The whole corpus at the default alert mode. Every document renders the
    // same regardless of `DocCAlertMode` unless it holds an aside-shaped
    // blockquote, so the mode dimension lives in the `docCVariants` sweep
    // below rather than multiplying every fixture threefold.

    @Test(arguments: ParityCorpus.all)
    func upPlain(_ document: ParityCorpus.Document) throws {
        let html = MudCore.renderUpToHTML(document.markdown, options: .init())
        try Golden.check(html, "up-\(document.name)")
    }

    @Test(arguments: ParityCorpus.all)
    func downPlain(_ document: ParityCorpus.Document) throws {
        let html = MudCore.renderDownToHTML(document.markdown, options: .init())
        try Golden.check(html, "down-\(document.name)")
    }

    // MARK: - DocC alert mode

    // The default mode (`.extended`) is already pinned by the plain sweep, so
    // this covers the mode-sensitive documents at the other two modes.
    static let nonDefaultModes =
        DocCAlertMode.allCases.filter { $0 != RenderOptions().docCAlertMode }

    @Test(arguments: ParityCorpus.docCVariants, nonDefaultModes)
    func upDocCMode(
        _ document: ParityCorpus.Document, _ mode: DocCAlertMode
    ) throws {
        var options = RenderOptions()
        options.docCAlertMode = mode
        let html = MudCore.renderUpToHTML(document.markdown, options: options)
        try Golden.check(html, "up-\(document.name)-\(mode.rawValue)")
    }

    @Test(arguments: ParityCorpus.docCVariants, nonDefaultModes)
    func downDocCMode(
        _ document: ParityCorpus.Document, _ mode: DocCAlertMode
    ) throws {
        var options = RenderOptions()
        options.docCAlertMode = mode
        let html = MudCore.renderDownToHTML(document.markdown, options: options)
        try Golden.check(html, "down-\(document.name)-\(mode.rawValue)")
    }

    // MARK: - Diffed rendering

    // The change-tracked paths — the deletion placer and word-span emitter in
    // Up mode, the line diff map in Down mode — are the subtlest code in the
    // pipeline, so the diffed goldens sweep the full edit corpus: the
    // cross-mode change-ID shapes plus every deletion and word-span shape. Up
    // renders with inline deletions shown, the richer of its two paths.
    static let diffCases =
        ChangeIDParityTests.corpus + UpRenderingTests.diffEditCases

    @Test(arguments: diffCases)
    func upDiffed(_ c: ChangeIDParityTests.EditCase) throws {
        var options = RenderOptions()
        options.showInlineDeletions = true
        options.waypoint = ParsedMarkdown(c.old)
        let html = MudCore.renderUpToHTML(c.new, options: options)
        try Golden.check(html, "up-diff-\(Golden.slug(c.label))")
    }

    @Test(arguments: diffCases)
    func downDiffed(_ c: ChangeIDParityTests.EditCase) throws {
        var options = RenderOptions()
        options.waypoint = ParsedMarkdown(c.old)
        let html = MudCore.renderDownToHTML(c.new, options: options)
        try Golden.check(html, "down-diff-\(Golden.slug(c.label))")
    }
}

/// Fixture IO for the golden suite: locate, compare, and — when regenerating —
/// rewrite the `.html` fixtures.
private enum Golden {
    static let regenerating =
        ProcessInfo.processInfo.environment["MUD_REGENERATE_GOLDENS"] != nil

    /// `Core/Tests/Golden`, resolved from this file's own path, so the suite
    /// needs no bundled test resources and regeneration writes straight into
    /// the source tree.
    static let directory =
        URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Golden")

    static func check(
        _ actual: String, _ name: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let url = directory.appendingPathComponent(name + ".html")
        if regenerating {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try actual.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        guard let expected = try? String(contentsOf: url, encoding: .utf8)
        else {
            Issue.record(
                """
                Missing golden \(name).html — regenerate with \
                MUD_REGENERATE_GOLDENS=1
                """,
                sourceLocation: sourceLocation)
            return
        }
        #expect(
            actual == expected,
            """
            Golden mismatch for \(name). If the change is intended, regenerate \
            with MUD_REGENERATE_GOLDENS=1 and review the diff.
            """,
            sourceLocation: sourceLocation)
    }

    /// A filesystem-safe fixture stem from a human edit-case label: lowercased,
    /// with every run of non-alphanumeric characters collapsed to one dash.
    static func slug(_ label: String) -> String {
        var out = ""
        var pendingDash = false
        for character in label.lowercased() {
            if character.isLetter || character.isNumber {
                if pendingDash, !out.isEmpty { out.append("-") }
                pendingDash = false
                out.append(character)
            } else {
                pendingDash = true
            }
        }
        return out
    }
}
