import Foundation
import MudCore
import Testing
@testable import Mud

// MARK: - parseMatchInfo

@MainActor
@Suite struct ParseMatchInfoTests {
    @Test func parsesWellFormedResult() {
        let info = WebView.parseMatchInfo(["current": 2, "total": 5])
        #expect(info == MatchInfo(current: 2, total: 5))
    }

    @Test func rejectsMissingKeys() {
        #expect(WebView.parseMatchInfo(["current": 2]) == nil)
        #expect(WebView.parseMatchInfo(["total": 5]) == nil)
        #expect(WebView.parseMatchInfo([String: Any]()) == nil)
    }

    @Test func rejectsWrongTypes() {
        #expect(WebView.parseMatchInfo(
            ["current": "2", "total": 5] as [String: Any]) == nil)
        #expect(WebView.parseMatchInfo("2 of 5") == nil)
        #expect(WebView.parseMatchInfo(nil) == nil)
    }
}

// MARK: - commentSignature

@MainActor
@Suite struct CommentSignatureTests {
    // `MudComment` (see TestSupport.swift): Swift Testing exports a
    // `Comment` type too, so the bare name is ambiguous in test files.
    private func comment(
        label: String = "comment-a", quotation: String? = "quoted text",
        author: String? = "JP", created: Date? = Date(timeIntervalSince1970: 100),
        body: String = "A note."
    ) -> MudComment {
        MudComment(
            label: label, ordinal: 1, quotation: quotation,
            messages: [CommentMessage(author: author, created: created,
                                      body: body)])
    }

    @Test func identicalListsProduceEqualSignatures() {
        #expect(WebView.Coordinator.commentSignature([comment()])
            == WebView.Coordinator.commentSignature([comment()]))
    }

    @Test func emptyListSignatureIsEmpty() {
        #expect(WebView.Coordinator.commentSignature([]).isEmpty)
    }

    @Test func eachContentFieldChangesTheSignature() {
        let base = WebView.Coordinator.commentSignature([comment()])
        let variants = [
            comment(label: "comment-b"),
            comment(quotation: "other text"),
            comment(quotation: nil),
            comment(author: "Someone Else"),
            comment(author: nil),
            comment(created: Date(timeIntervalSince1970: 200)),
            comment(body: "An edited note."),
        ]
        for variant in variants {
            #expect(WebView.Coordinator.commentSignature([variant]) != base)
        }
    }

    @Test func replyChangesTheSignature() {
        let single = comment()
        let replied = MudComment(
            label: single.label, ordinal: single.ordinal,
            quotation: single.quotation,
            messages: single.messages + [CommentMessage(
                author: "JP", created: Date(timeIntervalSince1970: 300),
                body: "A reply.")])
        #expect(WebView.Coordinator.commentSignature([replied])
            != WebView.Coordinator.commentSignature([single]))
    }

    @Test func orderMatters() {
        let a = comment(label: "comment-a")
        let b = comment(label: "comment-b")
        #expect(WebView.Coordinator.commentSignature([a, b])
            != WebView.Coordinator.commentSignature([b, a]))
    }
}
