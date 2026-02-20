import Testing
@testable import MudCore

@Suite("HTMLEscaping")
struct HTMLEscapingTests {
    @Test func ampersand() {
        #expect(HTMLEscaping.escape("&") == "&amp;")
    }

    @Test func lessThan() {
        #expect(HTMLEscaping.escape("<") == "&lt;")
    }

    @Test func greaterThan() {
        #expect(HTMLEscaping.escape(">") == "&gt;")
    }

    @Test func doubleQuote() {
        #expect(HTMLEscaping.escape("\"") == "&quot;")
    }

    @Test func singleQuoteNotEscaped() {
        #expect(HTMLEscaping.escape("'") == "'")
    }

    @Test func noDoubleEscaping() {
        #expect(HTMLEscaping.escape("&amp;") == "&amp;amp;")
    }

    @Test func emptyString() {
        #expect(HTMLEscaping.escape("") == "")
    }

    @Test func noSpecialCharacters() {
        #expect(HTMLEscaping.escape("hello world") == "hello world")
    }

    @Test func allSpecialCharacters() {
        #expect(HTMLEscaping.escape("<\"&>") == "&lt;&quot;&amp;&gt;")
    }

    @Test func mixedContent() {
        #expect(HTMLEscaping.escape("a < b & c > d") == "a &lt; b &amp; c &gt; d")
    }
}
