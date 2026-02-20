import Foundation
import JavaScriptCore
import os

/// Server-side syntax highlighting via highlight.js in a JSContext.
///
/// Uses the highlight.js v11.9.0 "common" build, which ships 36 languages:
///
///   bash (sh), c (h), cpp (cc, c++, hpp, …), csharp (cs, c#), css,
///   diff (patch), go (golang), graphql (gql), ini (toml), java (jsp),
///   javascript (js, jsx, mjs, cjs), json, kotlin (kt, kts), less, lua,
///   makefile (mk, mak, make), markdown (md, mkdown, mkd),
///   objectivec (mm, objc, obj-c, …), perl (pl, pm), php, php-template,
///   plaintext (text, txt), python (py, gyp, ipython), python-repl (pycon),
///   r, ruby (rb, gemspec, podspec, thor, irb), rust (rs), scss,
///   shell (console, shellsession), sql, swift, typescript (ts, tsx, mts, cts),
///   vbnet (vb), wasm, xml (html, xhtml, svg, plist, …), yaml (yml)
///
/// Code blocks without a language specifier get no highlighting (plain text).
/// Unknown language identifiers also fall back to plain text.
enum CodeHighlighter {
    private static let lock = OSAllocatedUnfairLock()

    nonisolated(unsafe) private static var context: JSContext? = {
        guard let ctx = JSContext() else { return nil }
        guard let url = Bundle.module.url(
            forResource: "highlight.min", withExtension: "js"
        ),
            let source = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        ctx.evaluateScript(source)
        return ctx
    }()

    /// Highlights source code, returning HTML with `<span class="hljs-*">` tags.
    ///
    /// - Parameters:
    ///   - code: The raw source code string.
    ///   - language: An optional language identifier (e.g. "swift", "python").
    /// - Returns: Highlighted HTML, or `nil` on failure.
    static func highlight(_ code: String, language: String?) -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard let ctx = context,
              let hljs = ctx.objectForKeyedSubscript("hljs")
        else { return nil }

        var jsResult: JSValue?
        if let language {
            // Try the specified language first.
            let opts = JSValue(newObjectIn: ctx)!
            opts.setObject(language, forKeyedSubscript: "language" as NSString)
            jsResult = hljs.invokeMethod("highlight", withArguments: [code, opts])
            // hljs.highlight throws for unknown languages — check for exception.
            if ctx.exception != nil {
                ctx.exception = nil
                return nil
            }
        } else {
            // No language specified — skip highlighting entirely.
            return nil
        }

        guard let value = jsResult?.forProperty("value"),
              value.isString,
              let html = value.toString()
        else { return nil }

        return html
    }
}
