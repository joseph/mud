Syntax highlighting library research
===============================================================================

This document records the evaluation of Swift syntax highlighting libraries
considered as server-side replacements for highlight.js. See the
`2026-02-swift-markdown-migration.md` plan for context and the final decision.


## Evaluation criteria

**Must have:**

- Broad language coverage — at minimum: Swift, Python, Ruby, JavaScript/
  TypeScript, Go, Rust, C/C++, Java, shell, HTML, CSS, SQL, JSON, YAML, TOML,
  Markdown, XML, Dockerfile, Makefile
- Usable as a Swift Package dependency (SPM compatible)
- Runs synchronously in-process (no subprocess or runtime download)
- Produces HTML `<span>` output (or an intermediate representation we can
  convert to spans)
- Handles unknown/missing languages gracefully (plain text fallback, no crash)

**Strong preferences:**

- Grammar-based (tree-sitter or TextMate-style) rather than regex-based, for
  correctness on edge cases
- Actively maintained, with a release in the last 12 months
- Reasonable binary size — should not dwarf the 122KB it replaces
- Dark/light theming via CSS classes (not inline styles), so our existing
  `--syntax-*` variable system applies cleanly
- Auto-detection of language when no info string is given (highlight.js does
  this today; losing it would be a regression)

**Nice to have:**

- TextMate/VS Code grammar compatibility (huge grammar ecosystem)
- Ability to add custom grammars without forking
- Used by other known Swift projects (signal of reliability)


## Libraries surveyed

We evaluated 12 libraries. Eight are unsuitable:

| Library                | Approach             | Why ruled out                                |
| ---------------------- | -------------------- | -------------------------------------------- |
| Neon (ChimeHQ)         | tree-sitter          | Outputs AttributedString for editors         |
| Splash                 | Native regex         | Swift-only (1 language)                      |
| SyntaxKit (soffes)     | TextMate             | Archived since 2019, Swift 2                 |
| SyntaxHighlight        | TextMate             | SwiftUI Text output, not HTML                |
| Editor (mattDavo)      | TextMate             | Dormant since 2019, NSTextView only          |
| SwiftSyntaxHighlighter | Apple SwiftSyntax    | Swift-only, massive dependency (~50MB)       |
| SwiftPygments          | Python via PythonKit | Requires Python runtime, dead project        |
| pygments-swift         | Regex state machine  | Too immature (2 stars, Jan 2026, smoke-test) |

Two viable approaches remain, described below.


## Approach 1: highlight.js via JavaScriptCore

Three libraries wrap highlight.js in a `JSContext` so it runs during HTML
generation rather than inside WKWebView: Highlightr (1,800+ stars, v2.3.0 Jun
2025), HighlightSwift (194 stars, v1.1.0 Jun 2024), and HighlighterSwift (59
stars, v3.0.0 2025). The approach is the same in all three — load highlight.js
once into a `JSContext`, call `hljs.highlight()` per code block, get back an
HTML string with `<span class="hljs-*">` tags.

**What it gives us:**

- Eliminates the 122KB per-document overhead — highlight.js loads once into the
  JSContext, not per page load
- 185 languages, covering everything on our list including TOML, Makefile, XML
- Content-based language auto-detection (`highlightAuto`) — no regression from
  current behavior on unfenced code blocks
- Zero tokenization work — proven, battle-tested highlighting
- CSS-class theming (`hljs-*` classes work with our `--syntax-*` variable
  system)

**Tradeoffs:**

- highlight.js still ships in the app binary (~120KB), just not in every HTML
  document
- Regex-based highlighting (less accurate than grammar-based on edge cases)
- JSContext has startup cost (one-time, on first use)


### Wrapper library evaluation

None of the three wrappers expose the HTML intermediate through their public API
— they all convert it to `NSAttributedString` (or SwiftUI `AttributedString`),
which we don't need since Mud renders into a WKWebView that already understands
HTML. The useful kernel in each is ~30 lines of JSContext invocation; the rest
is machinery for a problem we don't have (theme CSS parsing,
HTML-to-attributed-string conversion, entity decoding).

| Library          | Stars | highlight.js | Themes      | Code style                                 |
| ---------------- | ----- | ------------ | ----------- | ------------------------------------------ |
| Highlightr       | 1,800 | 1.1MB (all)  | 271 CSS     | 2016-era, force-unwraps, NSString bridging |
| HighlightSwift   | 194   | 309KB (~50)  | 30 hardcode | Modern, actor-based, strict Sendable       |
| HighlighterSwift | 59    | 1.0MB (all)  | 103 CSS     | 2016-era, force-unwraps (Highlightr fork)  |

HighlightSwift is the cleanest of the three (modern Swift, actor concurrency)
but is heavily SwiftUI-oriented. Highlightr and HighlighterSwift share a
codebase lineage with dated code style.

**Conclusion: no third-party wrapper.** Rather than depend on any of these, we
write a small `CodeHighlighter` module (~50 lines) that loads highlight.js into
a `JSContext` and exposes a `highlight(_:language:) -> String` method returning
the raw HTML. This is simpler, smaller, and gives us exactly the HTML string we
need with no conversion step to undo and no third-party dependency — just
JavaScriptCore (system framework) and a bundled highlight.min.js.


## Approach 2: `swift-tree-sitter` + custom HTML emitter

[swift-tree-sitter](https://github.com/tree-sitter/swift-tree-sitter) (v0.9.0,
Nov 2024, 363 stars) provides Swift bindings for tree-sitter's grammar-based
parsing. It returns `NamedRange` objects (semantic name + NSRange) from
highlights queries. We would write a thin HTML emitter (~50–100 lines) that
converts these into `<span class="...">` tags.

**What it gives us:**

- Grammar-based parsing (not regex) — highest highlighting quality
- 39 languages with SPM-ready parsers, covering: Swift, Python, Ruby,
  JavaScript, TypeScript, Go, Rust, C, C++, Java, Bash, HTML, CSS, SQL, JSON,
  YAML, Markdown, and more
- Synchronous, in-process (pure C with Swift bindings)
- CSS-class theming (we control the span class names)
- Actively maintained by the tree-sitter org
- Used by Chime, Nova (Panic), Zed, Neovim, GitHub

**Tradeoffs:**

- Each language parser is a separate SPM dependency (20+ dependencies)
- TOML, Makefile, and XML lack SPM-ready parsers — these fall back to plain text
- No content-based language auto-detection (fence info strings provide this in
  most cases; unfenced code blocks fall back to plain text)
- Binary size grows with each parser (~100KB–2MB compiled per language)
