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

    // MARK: - rawOffset (rendered → raw character mapping)

    @Test func rawOffsetWithoutShortcodesIsIdentity() {
        #expect(EmojiShortcodes.rawOffset(forRendered: 0, in: "hello") == 0)
        #expect(EmojiShortcodes.rawOffset(forRendered: 3, in: "hello") == 3)
        // A bare colon that forms no shortcode maps 1:1 too.
        #expect(EmojiShortcodes.rawOffset(forRendered: 5, in: "10:30 am") == 5)
    }

    @Test func rawOffsetSkipsASubstitutedSpan() {
        // "Hi :tada: world" renders "Hi 🎉 world": rendered offset 4 (just past the
        // emoji) maps to raw character 9 (just past ":tada:").
        let raw = "Hi :tada: world"
        #expect(EmojiShortcodes.rawOffset(forRendered: 3, in: raw) == 3)
        #expect(EmojiShortcodes.rawOffset(forRendered: 4, in: raw) == 9)
        #expect(EmojiShortcodes.rawOffset(forRendered: 10, in: raw) == 15)
    }

    @Test func rawOffsetNeverLandsInsideAShortcode() {
        // A rendered offset that falls within the emoji's footprint stops before
        // the shortcode, so it can't be split.
        #expect(EmojiShortcodes.rawOffset(forRendered: 3, in: "Hi :tada:") == 3)
    }

    @Test func rawOffsetTreatsUnknownAliasAsText() {
        // An unknown shortcode isn't substituted, so it maps 1:1.
        let raw = ":nope: tail"
        #expect(EmojiShortcodes.rawOffset(forRendered: 6, in: raw) == 6)
    }
}
