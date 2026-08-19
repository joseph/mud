import Foundation
import Testing
@testable import Mud

// MARK: - Outbound script building

@MainActor
@Suite struct BridgeScriptTests {
    @Test func bareFunctionGuardsTheNamespaceOnly() throws {
        let js = try MudJSBridge.script(for: "layoutComments", args: [])
        #expect(js == "window.Mud && Mud.layoutComments()")
    }

    @Test func dottedFunctionGuardsEachNamespaceStep() throws {
        let js = try MudJSBridge.script(for: "comments.setData", args: ["x"])
        #expect(js == #"window.Mud && Mud.comments && Mud.comments.setData("x")"#)
    }

    @Test func encodesHeterogeneousArguments() throws {
        let js = try MudJSBridge.script(
            for: "findAdvance", args: ["needle", "backward"])
        #expect(js == #"window.Mud && Mud.findAdvance("needle","backward")"#)

        let flag = try MudJSBridge.script(
            for: "setClass", args: ["word-wrap", true])
        #expect(flag == #"window.Mud && Mud.setClass("word-wrap",true)"#)

        let number = try MudJSBridge.script(for: "setZoom", args: [1.5])
        #expect(number == "window.Mud && Mud.setZoom(1.5)")
    }

    /// The Phase 1 escaping fix, pinned: a newline (or quote, or backslash)
    /// in an argument must not produce a JS syntax error. The old
    /// hand-rolled escapers broke Find silently on exactly this input.
    @Test func escapesNewlinesAndQuotes() throws {
        let js = try MudJSBridge.script(
            for: "findFromTop", args: ["line one\nline \"two\" \\ end"])
        #expect(!js.contains("\n"))
        #expect(js.contains(#"\n"#))
        #expect(js.contains(#"\""#))
    }

    /// Whatever the encoder emits, the argument list must round-trip: it is
    /// exactly the inside of a JSON array. This covers escaping rules the
    /// individual assertions above don't enumerate (Unicode separators,
    /// control characters).
    @Test func argumentListRoundTripsAsJSON() throws {
        let nasty = "a\nb\u{2028}c\u{2029}d\te \"quoted\" \\slash\u{0}"
        let js = try MudJSBridge.script(for: "findFromTop", args: [nasty])
        let open = try #require(js.firstIndex(of: "("))
        let argList = String(js[js.index(after: open)..<js.index(before: js.endIndex)])
        let decoded = try JSONDecoder().decode(
            [String].self, from: Data("[\(argList)]".utf8))
        #expect(decoded == [nasty])
    }
}

// MARK: - Inbound message decoding

@MainActor
@Suite struct BridgeDecodeTests {
    private let bridge = MudJSBridge()

    @Test func openDecodesAValidURL() throws {
        let message = bridge.decode("https://example.com/page#x", for: .open)
        guard case .open(let url) = try #require(message) else {
            Issue.record("expected .open"); return
        }
        #expect(url.absoluteString == "https://example.com/page#x")
    }

    @Test func openRejectsNonStringAndEmptyBodies() {
        #expect(bridge.decode(42, for: .open) == nil)
        #expect(bridge.decode("", for: .open) == nil)
    }

    @Test func footnoteDecodesLabelAndRect() throws {
        let body: [String: Any] = [
            "label": "comment-a",
            "rect": ["x": 1.0, "y": 2.0, "width": 30.0, "height": 4.5],
        ]
        let message = bridge.decode(body, for: .footnote)
        guard case .footnoteClick(let click) = try #require(message) else {
            Issue.record("expected .footnoteClick"); return
        }
        #expect(click.label == "comment-a")
        #expect(click.rect.width == 30.0)
    }

    @Test func footnoteRejectsAMissingRect() {
        #expect(bridge.decode(["label": "1"], for: .footnote) == nil)
    }

    @Test func popoverDecodesBodyAndRect() throws {
        let body: [String: Any] = [
            "html": "<p class=\"mud-diagram-error\">Parse error on line 2.</p>",
            "rect": ["x": 1.0, "y": 2.0, "width": 30.0, "height": 4.5],
        ]
        let message = bridge.decode(body, for: .popover)
        guard case .popover(let request) = try #require(message) else {
            Issue.record("expected .popover"); return
        }
        #expect(request.html.contains("Parse error on line 2."))
        #expect(request.rect.height == 4.5)
    }

    @Test func popoverRejectsAMissingBody() {
        let rect: [String: Any] = ["x": 1.0, "y": 2.0, "width": 3.0, "height": 4.0]
        #expect(bridge.decode(["rect": rect], for: .popover) == nil)
    }

    @Test func commentSubmitAddAssemblesTheDraft() throws {
        let body: [String: Any] = [
            "action": "add",
            "body": "A note.",
            "quotation": "brave new world",
            "locator": [
                "blockText": "Hello brave new world.",
                "offset": 21,
                "occurrence": 1,
            ] as [String: Any],
        ]
        let message = bridge.decode(body, for: .commentSubmit)
        guard case .commentSubmit(let submission) = try #require(message) else {
            Issue.record("expected .commentSubmit"); return
        }
        #expect(submission.action == .add)
        #expect(submission.body == "A note.")
        let draft = try #require(submission.draft)
        #expect(draft.quotation == "brave new world")
        #expect(draft.blockText == "Hello brave new world.")
        #expect(draft.offsetInBlock == 21)
        #expect(draft.occurrence == 1)
    }

    @Test func commentSubmitAddDefaultsOccurrenceToZero() throws {
        let body: [String: Any] = [
            "action": "add",
            "quotation": "q",
            "locator": ["blockText": "q.", "offset": 1] as [String: Any],
        ]
        let message = bridge.decode(body, for: .commentSubmit)
        guard case .commentSubmit(let submission) = try #require(message) else {
            Issue.record("expected .commentSubmit"); return
        }
        #expect(try #require(submission.draft).occurrence == 0)
    }

    @Test func commentSubmitReplyCarriesNoDraft() throws {
        let body: [String: Any] = [
            "action": "reply", "label": "comment-a", "body": "A reply.",
        ]
        let message = bridge.decode(body, for: .commentSubmit)
        guard case .commentSubmit(let submission) = try #require(message) else {
            Issue.record("expected .commentSubmit"); return
        }
        #expect(submission.action == .reply)
        #expect(submission.label == "comment-a")
        #expect(submission.draft == nil)
    }

    @Test func commentSubmitRejectsAnUnknownAction() {
        #expect(bridge.decode(["action": "explode"], for: .commentSubmit) == nil)
    }

    @Test func scalarBodiesDecodeDirectly() throws {
        guard case .composing(true)? = bridge.decode(true, for: .composing) else {
            Issue.record("expected .composing(true)"); return
        }
        // A malformed body degrades to false rather than dropping the message.
        guard case .composing(false)? = bridge.decode("yes", for: .composing) else {
            Issue.record("expected .composing(false)"); return
        }
        guard case .commentableSelection(true)? =
            bridge.decode(true, for: .selection) else {
            Issue.record("expected .commentableSelection(true)"); return
        }
        guard case .columnWidth(320.0)? = bridge.decode(320.0, for: .columnWidth) else {
            Issue.record("expected .columnWidth(320)"); return
        }
        #expect(bridge.decode("wide", for: .columnWidth) == nil)
        guard case .revealColumn(label: "comment-a")? =
            bridge.decode("comment-a", for: .revealColumn) else {
            Issue.record("expected .revealColumn(comment-a)"); return
        }
        // The label is what makes the message actionable — without one there is
        // no comment to open the column to, so the message drops.
        #expect(bridge.decode(true, for: .revealColumn) == nil)
    }

    @Test func foldsDecodesTheWholeSet() throws {
        let message = bridge.decode(["install", "usage"], for: .folds)
        guard case .folds(let slugs) = try #require(message) else {
            Issue.record("expected .folds"); return
        }
        #expect(slugs == ["install", "usage"])

        // Empty is a real report — the page saying nothing is folded any more —
        // so it must decode rather than drop, or unfolding the last section
        // would leave the app still holding it.
        let cleared = bridge.decode([String](), for: .folds)
        guard case .folds(let none) = try #require(cleared) else {
            Issue.record("expected .folds"); return
        }
        #expect(none.isEmpty)

        #expect(bridge.decode("install", for: .folds) == nil)
        #expect(bridge.decode([1, 2], for: .folds) == nil)
    }
}
