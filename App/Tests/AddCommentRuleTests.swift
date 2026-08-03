import Testing
import MudCore
@testable import Mud

/// The truth table behind every Add Comment affordance — the Edit menu item,
/// the toolbar button, and the WebView context menu. All three read
/// `ActiveDocumentSnapshot.canAddComment`, so this is the one place the rule is
/// checked.
@Suite struct AddCommentRuleTests {
    @Test func appliesToACommentableSelectionInAWritableUpModeDocument() {
        #expect(ActiveDocumentSnapshot.canAddComment(
            mode: .up, commentable: true, editable: true))
    }

    @Test func downModeNeverApplies() {
        for commentable in [true, false] {
            for editable in [true, false] {
                #expect(!ActiveDocumentSnapshot.canAddComment(
                    mode: .down, commentable: commentable, editable: editable))
            }
        }
    }

    /// A selection in a code block, a Mermaid diagram, math, or a deletion
    /// overlay has no source byte to anchor to, so the page reports it as not
    /// commentable and no affordance offers the action.
    @Test func anUncommentableSelectionDoesNotApply() {
        #expect(!ActiveDocumentSnapshot.canAddComment(
            mode: .up, commentable: false, editable: true))
    }

    /// The bundled guides and release notes are read-only.
    @Test func anUneditableDocumentDoesNotApply() {
        #expect(!ActiveDocumentSnapshot.canAddComment(
            mode: .up, commentable: true, editable: false))
    }
}
