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
/// | `mudCommentSubmit` | `{action, label?, body?, quotation?, locator?}` | Comment write path (`CommentSubmissionHandler`)|
/// | `mudComposing`     | `Bool`                                          | `DocumentState.isColumnComposing`              |
/// | `mudSelection`     | `Bool`                                          | `DocumentState.commentableSelection`           |
/// | `mudColumnWidth`   | `Double`                                        | Persisted Comments Column width                |
/// | `mudRevealColumn`  | `Bool` (value unused)                           | Per-window `commentsColumnVisible`             |
enum MudJSMessage {
    case open(URL)
    case footnoteClick(FootnoteClick)
    case commentSubmit(CommentSubmission)
    case composing(Bool)
    case commentableSelection(Bool)
    case columnWidth(Double)
    case revealColumn
}

/// The `mudFootnote` payload: which marker was clicked and where. The rect is
/// in visual (zoomed) viewport coordinates with a top-left origin.
struct FootnoteClick: Decodable {
    struct Rect: Decodable {
        let x, y, width, height: Double
    }
    let label: String
    let rect: Rect
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
/// Shared by the document `WebView` (all handlers) and
/// `FootnotePopoverController` (`mudOpen` only), which also share
/// `makeConfiguration` and the link `navigationPolicy`.
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
        case commentSubmit = "mudCommentSubmit"
        case composing = "mudComposing"
        case selection = "mudSelection"
        case columnWidth = "mudColumnWidth"
        case revealColumn = "mudRevealColumn"
    }

    // MARK: Configuration

    /// A `WKWebViewConfiguration` with the `mud-asset:` scheme handler and the
    /// given user scripts (document-end, main frame only) — the setup shared
    /// by the document view and the footnote popover.
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
            return .revealColumn
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
