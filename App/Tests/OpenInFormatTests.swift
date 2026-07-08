import Testing
import MudPreferences
@testable import Mud

/// The `.auto` resolution truth table for the Open In handoff: HTML goes
/// only to an app that accepts HTML and doesn't claim markdown (a browser);
/// everything else gets the markdown source.
@MainActor
@Suite struct OpenInFormatTests {
    @Test func autoSendsHTMLOnlyToAnHTMLOnlyApp() {
        #expect(OpenInMenuModel.resolveFormat(
            .auto, claimsMarkdown: false, claimsHTML: true) == .html)
    }

    @Test func autoPrefersMarkdownWhenTheAppClaimsIt() {
        #expect(OpenInMenuModel.resolveFormat(
            .auto, claimsMarkdown: true, claimsHTML: true) == .markdown)
        #expect(OpenInMenuModel.resolveFormat(
            .auto, claimsMarkdown: true, claimsHTML: false) == .markdown)
    }

    @Test func autoFallsBackToMarkdownWhenTheAppClaimsNeither() {
        #expect(OpenInMenuModel.resolveFormat(
            .auto, claimsMarkdown: false, claimsHTML: false) == .markdown)
    }

    @Test func explicitFormatsPassThroughUnchanged() {
        for claimsMarkdown in [true, false] {
            for claimsHTML in [true, false] {
                #expect(OpenInMenuModel.resolveFormat(
                    .markdown, claimsMarkdown: claimsMarkdown,
                    claimsHTML: claimsHTML) == .markdown)
                #expect(OpenInMenuModel.resolveFormat(
                    .html, claimsMarkdown: claimsMarkdown,
                    claimsHTML: claimsHTML) == .html)
            }
        }
    }
}
