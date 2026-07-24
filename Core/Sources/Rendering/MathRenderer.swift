import Foundation
import JavaScriptCore
import os

/// Server-side TeX-to-MathML conversion via Temml in a JSContext.
///
/// Temml (https://temml.org) is a KaTeX fork that emits MathML Core and no
/// HTML/CSS, so the output renders natively in WebKit with no client-side
/// JavaScript — nothing math-related ships in an exported document. This is
/// the same pattern ``CodeHighlighter`` uses for highlight.js.
///
/// `renderToString` runs entirely without a DOM (`document`/`window`), which
/// is what lets it work in a bare `JSContext`.
enum MathRenderer {
    private static let lock = OSAllocatedUnfairLock()

    nonisolated(unsafe) private static var context =
        BundledJSContext.load(resource: "temml.min")

    /// Converts a TeX expression to a MathML string.
    ///
    /// Invalid TeX does not fail: Temml runs with `throwOnError: false`, so a
    /// malformed expression renders as a `<span class="temml-error">` carrying
    /// the offending source — the same in-place error GitHub shows. A `nil`
    /// return means the JS layer itself was unavailable (Temml failed to load,
    /// or `renderToString` produced no string); the caller falls back to plain
    /// rendering so document content is never lost.
    ///
    /// - Parameters:
    ///   - tex: The raw TeX source (without delimiters).
    ///   - displayMode: `true` for block/display math (`$$…$$`, ```` ```math ````),
    ///     `false` for inline math (`` $`…`$ ``).
    /// - Returns: A MathML string, or `nil` on a JS-layer failure.
    static func render(_ tex: String, displayMode: Bool) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let ctx = context,
              let temml = ctx.objectForKeyedSubscript("temml")
        else { return nil }

        let opts = JSValue(newObjectIn: ctx)!
        opts.setObject(displayMode, forKeyedSubscript: "displayMode" as NSString)
        opts.setObject(false, forKeyedSubscript: "throwOnError" as NSString)

        let jsResult = temml.invokeMethod(
            "renderToString", withArguments: [tex, opts]
        )
        if ctx.exception != nil {
            ctx.exception = nil
            return nil
        }

        guard let value = jsResult, value.isString,
              let html = value.toString()
        else { return nil }

        return html
    }
}
