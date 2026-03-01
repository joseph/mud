import Foundation
import Testing
@testable import MudCore

@Suite("EmojiShortcodes")
struct EmojiShortcodesTests {
    @Test func knownShortcode() {
        #expect(EmojiShortcodes.replaceShortcodes(in: ":rocket:") == "🚀")
    }

    @Test func specialCharInShortcode() {
        #expect(EmojiShortcodes.replaceShortcodes(in: ":+1:") == "👍")
    }

    @Test func unknownShortcode() {
        let input = ":not_a_real_shortcode:"
        #expect(EmojiShortcodes.replaceShortcodes(in: input) == input)
    }

    @Test func noColons() {
        #expect(EmojiShortcodes.replaceShortcodes(in: "hello world") == "hello world")
    }

    @Test func mixedText() {
        let result = EmojiShortcodes.replaceShortcodes(
            in: "I gave this a :+1: because it was :fire:"
        )
        #expect(result == "I gave this a 👍 because it was 🔥")
    }

    @Test func consecutiveShortcodes() {
        #expect(EmojiShortcodes.replaceShortcodes(in: ":smile::+1:") == "😄👍")
    }

    @Test func emptyBetweenColons() {
        #expect(EmojiShortcodes.replaceShortcodes(in: "::") == "::")
    }

    @Test func timeFormat() {
        #expect(EmojiShortcodes.replaceShortcodes(in: "10:30:00") == "10:30:00")
    }
}
