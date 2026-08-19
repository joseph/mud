import Foundation
import WebKit

// MARK: - Messages from the page

/// A message posted by the page's JS over `window.webkit.messageHandlers`,
/// decoded into a typed value by `MudJSBridge`. The full message table
/// (handler name → payload → consumer):
///
/// | Handler            | Payload                                         | Consumer                                       |
/// | ------------------ | ----------------------------------------------- | ---------------------------------------------- |
/// | `mudOpen`          | `String` (resolved URL)                         | Link routing (document view, footnote popover) |
/// | `mudFootnote`      | `{label, num, rect: {x, y, width, height}}`     | Footnote popover presentation                  |
/// | `mudPopover`       | `{html, rect: {x, y, width, height}}`           | Page-supplied popover presentation             |
/// | `mudCommentSubmit` | `{action, label?, body?, quotation?, locator?}` | Comment write path (`CommentSubmissionHandler`)|
/// | `mudComposing`     | `Bool`                                          | `DocumentState.isColumnComposing`              |
/// | `mudSelection`     | `Bool`                                          | `DocumentState.commentableSelection`           |
/// | `mudColumnWidth`   | `Double`                                        | Persisted Comments Column width                |
/// | `mudRevealColumn`  | `String` (comment label)                        | `DocumentWindowController.revealComment`       |
/// | `mudFolds`         | `[String]` (folded heading slugs)               | `WebView.Coordinator.foldedHeadings`           |
///
/// `mudPopover` is the one case whose payload is HTML the bridge loads into a
/// WebView, rather than a label, a number, or a flag. Only Mud's own injected
/// `WKUserScript`s can post it: a rendered document is served
/// `script-src 'none'`, so nothing in the Markdown can run script and reach a
/// message handler at all. The popover is still not a place for anything a
/// document supplies verbatim — a caller showing document text escapes it
/// first (`mermaid-init.js` sets its message with `textContent` and never
/// builds HTML out of Mermaid's string).
enum MudJSMessage {
    case open(URL)
    case footnoteClick(FootnoteClick)
    /// The page asks for a popover over the HTML it supplies. See the note
    /// above on what may and may not go in one.
    case popover(PopoverRequest)
    case commentSubmit(CommentSubmission)
    case composing(Bool)
    case commentableSelection(Bool)
    case columnWidth(Double)
    /// A comment marker was clicked, naming the comment to open the column to.
    case revealColumn(label: String)
    /// The page's folded headings, by slug, reported after every fold change.
    /// The whole set travels each time, so the app's copy can't drift from the
    /// page's.
    case folds(slugs: [String])
}

/// Where on the page a popover should be anchored, in visual (zoomed) viewport
/// coordinates with a top-left origin — what `getBoundingClientRect` returns.
/// `WebView.Coordinator.anchorRect(from:in:)` converts it to AppKit space.
struct PopoverRect: Decodable {
    let x, y, width, height: Double
}

/// The `mudFootnote` payload: which marker was clicked and where.
struct FootnoteClick: Decodable {
    let label: String
    let rect: PopoverRect
}

/// The `mudPopover` payload: the body HTML to show and where to anchor it.
/// Unlike a footnote, whose body Swift rendered before the page loaded and
/// looks up by label, this content exists only in the page — a Mermaid parse
/// error, which nothing knows until Mermaid has failed.
struct PopoverRequest: Decodable {
    let html: String
    let rect: PopoverRect
}

// MARK: - Wire decoding

/// The `mudCommentSubmit` wire format. `.add` carries `quotation` plus a
/// `locator`, which assemble into the `CommentDraft`; reply/edit/delete
/// identify the comment by `label` alone.
extension CommentSubmission: Decodable {
    private enum CodingKeys: String, CodingKey {
        case action, label, body, quotation, locator
    }

    private struct Locator: Decodable {
        let blockText: String
        let offset: Int
        let occurrence: Int?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let action = try container.decode(Action.self, forKey: .action)
        var draft: CommentDraft?
        if action == .add,
           let quotation = try container.decodeIfPresent(
               String.self, forKey: .quotation),
           let locator = try container.decodeIfPresent(
               Locator.self, forKey: .locator) {
            draft = CommentDraft(
                quotation: quotation, blockText: locator.blockText,
                offsetInBlock: locator.offset,
                occurrence: locator.occurrence ?? 0)
        }
        self.init(
            action: action,
            label: try container.decodeIfPresent(String.self, forKey: .label),
            body: try container.decodeIfPresent(String.self, forKey: .body),
            draft: draft)
    }
}

extension CommentSubmission.Action: Decodable {}

// MARK: - Bridge

/// The one Swift ↔ page JS bridge, owning both directions:
///
/// - Outbound (`call`): JSON-encodes every argument, guards the `Mud`
///   namespace chain (legitimately absent before the page loads, and
///   `Mud.comments` only exists in Up mode), and logs JS errors — a missing
///   function on a present namespace is API drift and should be seen, not
///   swallowed.
/// - Inbound: decodes each `WKScriptMessage` into a `MudJSMessage` and hands
///   it to `onMessage`; malformed payloads are logged and dropped.
///
/// Shared by the document `WebView` (all handlers) and `HTMLPopoverController`
/// (`mudOpen` only), which also share `makeConfiguration` and the link
/// `navigationPolicy`.
final class MudJSBridge: NSObject, WKScriptMessageHandler {
    /// The page this bridge talks to; calls no-op while unset or gone.
    weak var webView: WKWebView?
    /// Receives every decoded inbound message.
    var onMessage: ((MudJSMessage) -> Void)?

    /// The inbound handler names the page can post to (see the message table
    /// on `MudJSMessage`).
    enum Handler: String, CaseIterable {
        case open = "mudOpen"
        case footnote = "mudFootnote"
        case popover = "mudPopover"
        case commentSubmit = "mudCommentSubmit"
        case composing = "mudComposing"
        case selection = "mudSelection"
        case columnWidth = "mudColumnWidth"
        case revealColumn = "mudRevealColumn"
        case folds = "mudFolds"
    }

    // MARK: Configuration

    /// A `WKWebViewConfiguration` with the `mud-asset:` scheme handler and the
    /// given user scripts (document-end, main frame only) — the setup shared
    /// by the document view and the popover.
    static func makeConfiguration(scripts: [String]) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(LocalFileSchemeHandler(),
                                   forURLScheme: "mud-asset")
        for source in scripts {
            config.userContentController.addUserScript(WKUserScript(
                source: source, injectionTime: .atDocumentEnd,
                forMainFrameOnly: true))
        }
        return config
    }

    /// Registers this bridge for the given inbound handlers.
    func register(_ handlers: [Handler],
                  on controller: WKUserContentController) {
        for handler in handlers {
            controller.add(self, name: handler.rawValue)
        }
    }

    // MARK: Navigation policy

    /// The link policy for every Mud-rendered page: allow programmatic loads
    /// (`.other` — `loadHTMLString` and same-document scrolls) and same-page
    /// anchor navigation; cancel everything else as a safety net behind the JS
    /// click interceptor, which routes clicks over `mudOpen`.
    static func navigationPolicy(
        for action: WKNavigationAction, baseURL: URL?
    ) -> WKNavigationActionPolicy {
        if action.navigationType == .other { return .allow }
        if let url = action.request.url,
           url.fragment != nil, url.path == baseURL?.path {
            return .allow
        }
        return .cancel
    }

    // MARK: Outbound

    /// Calls `Mud.<function>(<args>)` in the page, JSON-encoding every
    /// argument. `function` may be namespaced (`"comments.setData"`); each
    /// namespace is guarded, but the function itself is not — so a renamed or
    /// removed JS function raises a TypeError that gets logged instead of
    /// silently no-oping. `completion` receives the call's return value on the
    /// next run-loop turn (safe for `@Published` mutations).
    func call(_ function: String, _ args: (any Encodable)...,
              completion: ((Any?) -> Void)? = nil) {
        guard let webView else { return }
        let js: String
        do {
            js = try Self.script(for: function, args: args)
        } catch {
            NSLog("Mud: JS call \(function) dropped; "
                + "argument encoding failed: \(error)")
            return
        }
        webView.evaluateJavaScript(js) { result, error in
            if let error {
                NSLog("Mud: JS call \(function) failed: "
                    + error.localizedDescription)
            }
            if let completion {
                DispatchQueue.main.async { completion(result) }
            }
        }
    }

    /// Runs a raw script in the page, logging any error. For the few
    /// evaluations that aren't `Mud.*` calls (extension injection, the
    /// popover's height measurement). `completion` always runs, with `nil` on
    /// error.
    func evaluate(_ script: String, completion: ((Any?) -> Void)? = nil) {
        guard let webView else { return }
        webView.evaluateJavaScript(script) { result, error in
            if let error {
                NSLog("Mud: JS evaluation failed: \(error.localizedDescription)")
            }
            completion?(result)
        }
    }

    /// Builds the guarded call script `call` evaluates: each namespace step
    /// checked, every argument JSON-encoded. Throws when an argument fails to
    /// encode. Internal so tests can pin the escaping and guard structure.
    static func script(for function: String, args: [any Encodable]) throws -> String {
        // Encode all arguments as one JSON array, then strip the brackets:
        // the remainder is a valid JS argument list. (Also sidesteps
        // top-level-fragment limits for single scalar arguments.)
        let data = try JSONEncoder().encode(args.map(AnyEncodable.init))
        let argList = String(String(decoding: data, as: UTF8.self)
            .dropFirst().dropLast())
        var namespace = "Mud"
        var clauses = ["window.Mud"]
        let parts = function.split(separator: ".")
        for step in parts.dropLast() {
            namespace += ".\(step)"
            clauses.append(namespace)
        }
        return (clauses + ["\(namespace).\(parts.last ?? "")(\(argList))"])
            .joined(separator: " && ")
    }

    /// Type-erases a call argument so a heterogeneous argument list encodes
    /// as one JSON array. `nonisolated` because this is a pure encoding wrapper
    /// with no main-actor state: `script(for:args:)` builds its string off the
    /// main actor, and `encode(to:)` must stay nonisolated to satisfy
    /// `Encodable` under the target's default main-actor isolation.
    private nonisolated struct AnyEncodable: Encodable {
        let value: any Encodable
        init(_ value: any Encodable) { self.value = value }
        func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
        }
    }

    // MARK: Inbound

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let handler = Handler(rawValue: message.name) else { return }
        guard let decoded = decode(message.body, for: handler) else {
            NSLog("Mud: dropped malformed \(message.name) message from the page.")
            return
        }
        onMessage?(decoded)
    }

    /// Decodes a raw message body: scalar payloads cast directly; dictionary
    /// payloads round-trip through JSON into their `Decodable` structs.
    /// Internal so tests can drive it with raw bodies (the real entry point
    /// needs a `WKScriptMessage`, which can't be constructed in a test).
    func decode(_ body: Any, for handler: Handler) -> MudJSMessage? {
        switch handler {
        case .open:
            guard let string = body as? String,
                  let url = URL(string: string) else { return nil }
            return .open(url)
        case .footnote:
            guard let click: FootnoteClick = decodePayload(body) else { return nil }
            return .footnoteClick(click)
        case .popover:
            guard let request: PopoverRequest = decodePayload(body) else { return nil }
            return .popover(request)
        case .commentSubmit:
            guard let submission: CommentSubmission = decodePayload(body) else { return nil }
            return .commentSubmit(submission)
        case .composing:
            return .composing((body as? Bool) ?? false)
        case .selection:
            return .commentableSelection((body as? Bool) ?? false)
        case .columnWidth:
            guard let width = body as? Double else { return nil }
            return .columnWidth(width)
        case .revealColumn:
            guard let label = body as? String else { return nil }
            return .revealColumn(label: label)
        case .folds:
            guard let slugs = body as? [String] else { return nil }
            return .folds(slugs: slugs)
        }
    }

    /// A JS dictionary body → its `Decodable` payload struct (the body
    /// arrives as a property-list object graph, so it round-trips via
    /// `JSONSerialization`).
    private func decodePayload<T: Decodable>(_ body: Any) -> T? {
        guard JSONSerialization.isValidJSONObject(body),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
