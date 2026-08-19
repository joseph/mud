import Foundation
import Testing
@testable import MudCore

/// `MudCore.renderPopoverDocument` — the general popover-document producer, for
/// a body the page supplies rather than one Swift renders ahead of time.
@Suite("Popover documents")
struct PopoverDocumentTests {
    @Test func wrapsTheBodyInAThemedDocument() {
        var options = RenderOptions()
        options.theme = .riot
        let doc = MudCore.renderPopoverDocument(
            body: "<p class=\"mud-diagram-error\">Parse error on line 2.</p>",
            options: options)

        // A self-contained document, not a fragment.
        #expect(doc.contains("<!DOCTYPE html>"))
        #expect(doc.contains("<article class=\"up-mode-output\">"))
        #expect(doc.contains("Parse error on line 2."))
        // The window's theme, so the popover matches what it opened from.
        #expect(doc.contains(HTMLTemplate.themeCSS(for: .riot)))
    }

    /// A popover is its own tiny page. It must not draw the host document's
    /// change overlay, and it must not reserve the Comments column's gutter.
    @Test func dropsTheHostWindowState() {
        var options = RenderOptions()
        options.waypoint = ParsedMarkdown("An earlier draft.\n")
        options.commentMode = .interactive
        options.commentsEditable = true
        options.htmlClasses.insert("is-comments-column")
        let doc = MudCore.renderPopoverDocument(body: "<p>hi</p>",
                                                options: options)

        #expect(!doc.contains("--change-ins"))
        guard let start = doc.range(of: "<html"),
              let end = doc[start.lowerBound...].firstIndex(of: ">")
        else { Issue.record("no root element"); return }
        #expect(!doc[start.lowerBound...end].contains("comments-column"))
    }

    /// The diagram stylesheet is normally reserved for a document that will
    /// draw one. The error popover holds the parser's message and no block, so
    /// it matches on the message's own class instead.
    @Test func carriesTheDiagramStylesForAnErrorMessage() {
        var options = RenderOptions()
        options.extensions = ["mermaid"]
        let doc = MudCore.renderPopoverDocument(
            body: "<p class=\"mud-diagram-error\">Parse error.</p>",
            options: options)

        #expect(doc.contains(".mud-diagram-error"))
    }

    /// The Handwritten look's label font is roughly 100 KB of data URI, for
    /// labels the popover never letters.
    @Test func leavesTheDiagramFontOutOfAnErrorMessage() {
        var options = RenderOptions()
        options.extensions = ["mermaid"]
        options.diagramLook = .handwritten
        let doc = MudCore.renderPopoverDocument(
            body: "<p class=\"mud-diagram-error\">Parse error.</p>",
            options: options)

        #expect(!doc.contains("@font-face"))
        #expect(!doc.contains("font-src"))
    }
}
