import Foundation
import JavaScriptCore

/// Loads a bundled JavaScript library into a fresh `JSContext`.
///
/// `CodeHighlighter` (highlight.js) and `MathRenderer` (Temml) both run a
/// self-contained JS library server-side; this is their shared bootstrap.
/// Returns nil when the context can't be created or the resource can't be
/// read — the callers treat that as "engine unavailable" and fall back to
/// plain output.
enum BundledJSContext {
    static func load(resource: String) -> JSContext? {
        guard let ctx = JSContext(),
              let url = Bundle.module.url(
                  forResource: resource, withExtension: "js"
              ),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        ctx.evaluateScript(source)
        return ctx
    }
}
