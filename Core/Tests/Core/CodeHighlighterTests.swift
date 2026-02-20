import Testing
@testable import MudCore

@Suite("CodeHighlighter")
struct CodeHighlighterTests {
    @Test func knownLanguageReturnsHighlightedHTML() {
        let result = CodeHighlighter.highlight("let x = 1", language: "swift")
        #expect(result != nil)
        #expect(result?.contains("hljs-") == true)
    }

    @Test func unknownLanguageReturnsNil() {
        let result = CodeHighlighter.highlight("hello", language: "doesnotexist")
        #expect(result == nil)
    }

    @Test func nilLanguageReturnsNil() {
        let result = CodeHighlighter.highlight("hello", language: nil)
        #expect(result == nil)
    }

    @Test func emptyCodeWithLanguage() {
        let result = CodeHighlighter.highlight("", language: "swift")
        #expect(result != nil)
    }

    @Test func htmlEntitiesEscaped() {
        let result = CodeHighlighter.highlight("<div>&</div>", language: "html")
        #expect(result != nil)
        #expect(result?.contains("&lt;") == true || result?.contains("hljs-") == true)
        // hljs escapes HTML entities in its output; the exact form depends on
        // the language grammar, but raw < should never appear unescaped.
        #expect(result?.contains("<div>") != true)
    }

    @Test func multipleLanguages() {
        // Verify a handful of common languages all produce output.
        for lang in ["python", "javascript", "ruby", "go", "rust"] {
            let result = CodeHighlighter.highlight("x = 1", language: lang)
            #expect(result != nil, "Expected output for language: \(lang)")
        }
    }
}
