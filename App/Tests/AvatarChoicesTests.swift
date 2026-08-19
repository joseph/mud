import Testing
import MudCore
@testable import Mud

/// The curated avatar list. Every entry has to satisfy the rule the write path
/// applies (`CommentAvatar.isValid`) — a choice that failed it would be offered
/// in the grid, picked, and then quietly written as `👤`, which is exactly the
/// silent substitution this control exists to make impossible. A mistyped
/// sequence (a missing variation selector, a broken ZWJ join) is easy to make
/// and invisible in review, so it gets checked here rather than in the eye.
@Suite struct AvatarChoicesTests {
    @Test func everyChoiceIsAValidAvatar() {
        for choice in AvatarChoices.all {
            #expect(CommentAvatar.isValid(choice), "\(choice) is not one emoji")
            #expect(CommentAvatar.resolve(choice) == choice)
        }
    }

    /// `ForEach(AvatarChoices.all, id: \.self)` needs distinct entries, and a
    /// duplicate would also highlight two cells at once.
    @Test func choicesAreDistinct() {
        #expect(Set(AvatarChoices.all).count == AvatarChoices.all.count)
    }

    /// The grid is laid out in fixed columns, so a list that isn't a whole
    /// number of rows leaves a ragged last row.
    @Test func choicesFillWholeRows() {
        #expect(AvatarChoices.all.count % AvatarChoices.columns == 0)
    }

    /// The default avatar is offered, so a reader who has changed it can get
    /// back to it from the grid.
    @Test func theStandardAvatarIsOffered() {
        #expect(AvatarChoices.all.contains(CommentAvatar.standard))
    }
}
