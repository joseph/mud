import Testing
@testable import MudCore

@Suite("ChangeGroup.build")
struct ChangeGroupTests {
  private func change(
    id: String, type: ChangeType, groupID: String, groupIndex: Int,
    isMixed: Bool = false, summary: String = "summary"
  ) -> DocumentChange {
    DocumentChange(
      id: id, type: type, summary: summary, sourceLine: 1,
      isConsecutive: false, groupID: groupID,
      groupIndex: groupIndex, isMixed: isMixed)
  }

  @Test func collapsesEntriesSharingAGroupID() {
    let groups = ChangeGroup.build(from: [
      change(id: "change-1", type: .insertion, groupID: "group-1", groupIndex: 1),
      change(id: "change-2", type: .insertion, groupID: "group-1", groupIndex: 1),
      change(id: "change-3", type: .insertion, groupID: "group-2", groupIndex: 2),
    ])
    #expect(groups.count == 2)
    #expect(groups[0].changeIDs == ["change-1", "change-2"])
    #expect(groups[0].count == 2)
    #expect(groups[1].changeIDs == ["change-3"])
  }

  @Test func preservesFirstOccurrenceOrder() {
    let groups = ChangeGroup.build(from: [
      change(id: "change-2", type: .deletion, groupID: "group-2", groupIndex: 2),
      change(id: "change-1", type: .insertion, groupID: "group-1", groupIndex: 1),
      change(id: "change-3", type: .insertion, groupID: "group-2", groupIndex: 2),
    ])
    #expect(groups.map(\.id) == ["group-2", "group-1"])
  }

  @Test func groupIsMixedWhenBothTypesPresent() {
    let groups = ChangeGroup.build(from: [
      change(id: "change-1", type: .deletion, groupID: "group-1", groupIndex: 1),
      change(id: "change-2", type: .insertion, groupID: "group-1", groupIndex: 1),
    ])
    #expect(groups.count == 1)
    #expect(groups[0].isMixed)
    #expect(groups[0].type == .insertion)
  }

  @Test func memberMixedFlagPropagates() {
    // A mermaid replacement emits only the insertion, but the change
    // carries isMixed from the plan's group info.
    let groups = ChangeGroup.build(from: [
      change(id: "change-2", type: .insertion, groupID: "group-1",
             groupIndex: 1, isMixed: true),
    ])
    #expect(groups.count == 1)
    #expect(groups[0].isMixed)
  }

  @Test func groupIndexAndMembersComeFromEntries() {
    let groups = ChangeGroup.build(from: [
      change(id: "change-1", type: .deletion, groupID: "group-3",
             groupIndex: 3, summary: "old line"),
      change(id: "change-1", type: .insertion, groupID: "group-3",
             groupIndex: 3, summary: "new line"),
    ])
    #expect(groups.count == 1)
    #expect(groups[0].groupIndex == 3)
    #expect(groups[0].members.map(\.summary) == ["old line", "new line"])
    #expect(groups[0].members.map(\.type) == [.deletion, .insertion])
  }

  @Test func emptyInputProducesNoGroups() {
    #expect(ChangeGroup.build(from: []).isEmpty)
  }
}
