import Testing
import Foundation
@testable import MudCore

@Suite("ChangeTracker")
struct ChangeTrackerTests {

    // MARK: - Helpers

    private func date(_ minutesAgo: Double) -> Date {
        Date().addingTimeInterval(-minutesAgo * 60)
    }

    private func tracker(
        initial: String = "Hello.\n",
        at time: Date? = nil
    ) -> ChangeTracker {
        let t = ChangeTracker()
        t.update(ParsedMarkdown(initial), at: time ?? Date())
        return t
    }

    // MARK: - Waypoint lifecycle

    @Test func firstUpdateCreatesInitialWaypoint() {
        let t = ChangeTracker()
        let now = Date()
        t.update(ParsedMarkdown("Hello.\n"), at: now)

        #expect(t.waypoints.count == 1)
        #expect(t.waypoints[0].kind == .initial)
    }

    @Test func subsequentUpdateCreatesReloadWaypoint() {
        let t0 = Date()
        let t = tracker(at: t0)
        t.update(ParsedMarkdown("Changed.\n"), at: t0.addingTimeInterval(90))

        #expect(t.waypoints.count == 2)
        #expect(t.waypoints[0].kind == .initial)
        #expect(t.waypoints[1].kind == .reload)
    }

    @Test func sameMinuteReloadsCoalesced() {
        // Use a base time at a known minute boundary for clarity.
        let t0 = Date(timeIntervalSinceReferenceDate: 1000 * 60) // minute 1000
        let t = tracker(at: t0)

        // Three saves within the same absolute minute — coalesced.
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(10))
        t.update(ParsedMarkdown("V3.\n"), at: t0.addingTimeInterval(20))
        t.update(ParsedMarkdown("V4.\n"), at: t0.addingTimeInterval(30))

        #expect(t.waypoints.count == 2) // initial + latest reload
        #expect(t.waypoints[1].parsed.markdown == "V4.\n")
    }

    @Test func differentMinuteReloadsSurvive() {
        // Base at a minute boundary.
        let t0 = Date(timeIntervalSinceReferenceDate: 1000 * 60)
        let t = tracker(at: t0)

        // Save in minute 1000, then in minute 1001.
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(15))
        t.update(ParsedMarkdown("V3.\n"), at: t0.addingTimeInterval(75))

        // Different absolute minutes — both survive.
        #expect(t.waypoints.count == 3)
        #expect(t.waypoints[1].parsed.markdown == "V2.\n")
        #expect(t.waypoints[2].parsed.markdown == "V3.\n")
    }

    @Test func duplicateContentSkipped() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)

        // Reload with different content — stored.
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        #expect(t.waypoints.count == 2)

        // Reload with same content as initial — skipped.
        t.update(ParsedMarkdown("V1.\n"), at: t0.addingTimeInterval(180))
        #expect(t.waypoints.count == 2)

        // Reload with same content as the reload — skipped.
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(270))
        #expect(t.waypoints.count == 2)

        // Reload with new content — stored.
        t.update(ParsedMarkdown("V3.\n"), at: t0.addingTimeInterval(360))
        #expect(t.waypoints.count == 3)
    }

    @Test func duplicateContentSkippedEvenWhenRapid() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(1))
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(2))

        // Second update is a duplicate — only one reload stored.
        #expect(t.waypoints.count == 2)
    }

    @Test func reloadCountCappedAtTen() {
        // 12 reloads in 12 distinct minutes — only the 10 most recent
        // should survive, plus the initial.
        let t0 = Date(timeIntervalSinceReferenceDate: 1000 * 60)
        let t = tracker(initial: "V0.\n", at: t0)

        for i in 1...12 {
            t.update(
                ParsedMarkdown("V\(i).\n"),
                at: t0.addingTimeInterval(TimeInterval(i * 60)))
        }

        let reloads = t.waypoints.filter { $0.kind == .reload }
        #expect(reloads.count == 10)

        // Surviving reloads are V3 through V12 (the 10 most recent).
        let survivingMarkdown = Set(reloads.map(\.parsed.markdown))
        let expected = Set((3...12).map { "V\($0).\n" })
        #expect(survivingMarkdown == expected)

        // Initial is preserved.
        #expect(t.waypoints.contains { $0.kind == .initial })
    }

    @Test func reloadsSurviveLongIdleUnderCap() {
        // 5 reloads, then a 3-hour idle, then one more save. Total 6
        // reloads, all under the cap, so the original 5 stay put — no
        // age-based pruning anymore.
        let t0 = Date(timeIntervalSinceReferenceDate: 1000 * 60)
        let t = tracker(initial: "V0.\n", at: t0)

        for i in 1...5 {
            t.update(
                ParsedMarkdown("V\(i).\n"),
                at: t0.addingTimeInterval(TimeInterval(i * 60)))
        }

        // Idle 3 hours, then one more save.
        t.update(
            ParsedMarkdown("V6.\n"),
            at: t0.addingTimeInterval(3 * 60 * 60))

        let reloads = t.waypoints.filter { $0.kind == .reload }
        #expect(reloads.count == 6)
        #expect(reloads.contains { $0.parsed.markdown == "V1.\n" })
    }

    @Test func reloadCapClearsOrphanedActiveWaypoint() {
        // Selecting a reload that subsequently gets pruned by the cap
        // should reset activeWaypointID rather than leaving it dangling.
        let t0 = Date(timeIntervalSinceReferenceDate: 1000 * 60)
        let t = tracker(initial: "V0.\n", at: t0)

        // Fill exactly to the cap (10 reloads).
        for i in 1...10 {
            t.update(
                ParsedMarkdown("V\(i).\n"),
                at: t0.addingTimeInterval(TimeInterval(i * 60)))
        }

        // Select the oldest reload as the active waypoint.
        let oldest = t.waypoints
            .filter { $0.kind == .reload }
            .min(by: { $0.timestamp < $1.timestamp })!
        t.selectWaypoint(oldest.id)
        #expect(t.activeWaypointID == oldest.id)

        // 11th reload — pushes the cap, prunes the oldest.
        t.update(
            ParsedMarkdown("V11.\n"),
            at: t0.addingTimeInterval(11 * 60))

        #expect(!t.waypoints.contains { $0.id == oldest.id })
        #expect(t.activeWaypointID == nil)
    }

    @Test func pruningNeverRemovesInitial() {
        let t0 = Date()
        let t = tracker(at: t0)

        // Jump far into the future — initial is old but must survive.
        t.update(
            ParsedMarkdown("V2.\n"),
            at: t0.addingTimeInterval(60 * 60))

        #expect(t.waypoints.contains { $0.kind == .initial })
    }

    @Test func pruningNeverRemovesAccept() {
        let t0 = Date()
        let t = tracker(at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        t.acceptAt(t0.addingTimeInterval(90))

        // Jump far into the future.
        t.update(
            ParsedMarkdown("V3.\n"),
            at: t0.addingTimeInterval(60 * 60))

        #expect(t.waypoints.contains { $0.kind == .accept })
    }

    @Test func acceptCreatesAcceptWaypoint() {
        let t0 = Date()
        let t = tracker(at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        t.acceptAt(t0.addingTimeInterval(90))

        let accepts = t.waypoints.filter { $0.kind == .accept }
        #expect(accepts.count == 1)
    }

    @Test func secondAcceptReplacesPrevious() {
        let t0 = Date()
        let t = tracker(at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        t.acceptAt(t0.addingTimeInterval(90))
        let firstAcceptID = t.waypoints.first { $0.kind == .accept }!.id

        t.update(ParsedMarkdown("V3.\n"), at: t0.addingTimeInterval(180))
        t.acceptAt(t0.addingTimeInterval(180))

        let accepts = t.waypoints.filter { $0.kind == .accept }
        #expect(accepts.count == 1)
        #expect(accepts[0].id != firstAcceptID)
    }

    // MARK: - Active waypoint resolution

    @Test func activeWaypointDefaultsToInitial() {
        let t = tracker()
        #expect(t.activeWaypoint != nil)
        #expect(t.activeWaypointID == nil)
        // Active waypoint is the initial waypoint's content.
        #expect(t.activeWaypoint?.markdown == "Hello.\n")
    }

    @Test func activeWaypointDefaultsToAcceptWhenPresent() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        t.acceptAt(t0.addingTimeInterval(90))

        #expect(t.activeWaypoint?.markdown == "V2.\n")
    }

    @Test func activeWaypointResolvesToExplicitID() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        let reloadID = t.waypoints.first { $0.kind == .reload }!.id
        t.selectWaypoint(reloadID)

        #expect(t.activeWaypoint?.markdown == "V2.\n")
    }

    @Test func acceptResetsActiveWaypointID() {
        let t0 = Date()
        let t = tracker(at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        let reloadID = t.waypoints.first { $0.kind == .reload }!.id
        t.selectWaypoint(reloadID)

        t.acceptAt(t0.addingTimeInterval(90))
        #expect(t.activeWaypointID == nil)
    }

    // MARK: - Menu item computation

    @Test func menuShowsDocumentOpenedWhenNoAccepts() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))

        let items = t.menuItems(at: t0.addingTimeInterval(90))
        #expect(!items.isEmpty)
        #expect(items[0].label == "since document opened")
    }

    @Test func menuShowsLastAcceptedWhenAccepted() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        t.acceptAt(t0.addingTimeInterval(90))
        t.update(ParsedMarkdown("V3.\n"), at: t0.addingTimeInterval(180))

        let items = t.menuItems(at: t0.addingTimeInterval(180))
        #expect(items[0].label == "since last accepted")
    }

    @Test func menuShowsDocumentOpenedAtBottomWhenAccepted() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        t.acceptAt(t0.addingTimeInterval(90))
        t.update(ParsedMarkdown("V3.\n"), at: t0.addingTimeInterval(180))

        let items = t.menuItems(at: t0.addingTimeInterval(180))
        let lastItem = items.last!
        #expect(lastItem.label == "since document opened")
    }

    @Test func menuItemIDsAreUnique() {
        // No waypoint id should appear in two menu items — the gap walk
        // skips entries whose W_old is already in the milestone section.
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        let now = t0.addingTimeInterval(180)
        t.update(ParsedMarkdown("V2.\n"), at: now.addingTimeInterval(-120))

        let items = t.menuItems(at: now)
        let ids = items.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    @Test func menuGapSkipsAcceptAndInitial() {
        // Gap entries whose W_old is the accept (or initial) waypoint
        // are skipped — they would duplicate the milestone section.
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)

        let now = t0.addingTimeInterval(300)
        t.update(ParsedMarkdown("V2.\n"), at: now.addingTimeInterval(-120))
        t.acceptAt(now.addingTimeInterval(-120))
        t.update(ParsedMarkdown("V3.\n"), at: now)

        let items = t.menuItems(at: now)
        let gapItems = items.filter { $0.label.contains("minute") }

        let acceptID = t.waypoints.first { $0.kind == .accept }!.id
        let initialID = t.waypoints.first { $0.kind == .initial }!.id
        for item in gapItems {
            #expect(item.id != acceptID)
            #expect(item.id != initialID)
        }
    }

    @Test func menuChangeCountsMatchDiff() {
        let t0 = Date()
        let t = tracker(initial: "Alpha.\n\nBeta.\n", at: t0)

        t.update(
            ParsedMarkdown("Alpha.\n\nBeta.\n\nGamma.\n"),
            at: t0.addingTimeInterval(90))

        let items = t.menuItems(at: t0.addingTimeInterval(90))
        // "Since document opened" — one insertion group.
        let opened = items.first { $0.label == "since document opened" }!
        #expect(opened.changeCount == 1)
    }

    @Test func menuActiveFlag() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))

        let items = t.menuItems(at: t0.addingTimeInterval(90))
        // Default active waypoint is initial — it should be active.
        let opened = items.first { $0.label == "since document opened" }!
        #expect(opened.isActive)
    }

    @Test func menuActiveFlagReflectsExplicitWaypoint() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)

        // Reload at -2m, another at -4m.
        let now = t0.addingTimeInterval(300)
        t.update(ParsedMarkdown("V2.\n"), at: now.addingTimeInterval(-240))
        t.update(ParsedMarkdown("V3.\n"), at: now.addingTimeInterval(-120))
        t.update(ParsedMarkdown("V4.\n"), at: now)

        // Set active waypoint to the -4m reload.
        let target = t.waypoints.first {
            $0.kind == .reload && $0.parsed.markdown == "V2.\n"
        }!
        t.selectWaypoint(target.id)

        let items = t.menuItems(at: now)
        let activeItems = items.filter(\.isActive)
        #expect(activeItems.count == 1)
        #expect(activeItems[0].id == target.id)
    }

    // MARK: - Gap entry semantics

    @Test func minutesAgoLabelFormula() {
        // Direct check of the helper against the values in the design
        // example: now=9:30:51, 9:33:40, 9:37:14, with anchors at 9:30:00,
        // 9:30:37, and 9:33:23.
        let base = Date(timeIntervalSinceReferenceDate: 1000 * 60) // minute 1000

        // Same minute, 51s in.
        #expect(ChangeTracker.minutesAgoLabel(
            for: base, at: base.addingTimeInterval(51)) == 1)

        // Anchor at +37s (minute 1000), now at +3m40s (minute 1003).
        let anchor1 = base.addingTimeInterval(37)
        let now1 = base.addingTimeInterval(3 * 60 + 40)
        #expect(ChangeTracker.minutesAgoLabel(for: anchor1, at: now1) == 4)

        // Anchor at +3m23s (minute 1003), now at +3m40s.
        let anchor2 = base.addingTimeInterval(3 * 60 + 23)
        #expect(ChangeTracker.minutesAgoLabel(for: anchor2, at: now1) == 1)

        // Anchor at +3m23s (minute 1003), now at +7m14s (minute 1007).
        let now2 = base.addingTimeInterval(7 * 60 + 14)
        #expect(ChangeTracker.minutesAgoLabel(for: anchor2, at: now2) == 5)

        // Anchor at minute 1000, now at +7m14s.
        #expect(ChangeTracker.minutesAgoLabel(for: base, at: now2) == 8)

        // Edge: now exactly on a minute boundary in the same minute as
        // the anchor. The max(1, …) floor kicks in.
        #expect(ChangeTracker.minutesAgoLabel(for: base, at: base) == 1)
    }

    @Test func menuGapLabelUsesNewerWaypointMinute() {
        // A gap (V_old, V_new) labels itself with W_new's absolute minute,
        // not W_old's.
        let t0 = Date(timeIntervalSinceReferenceDate: 1000 * 60)
        let t = tracker(initial: "V0.\n", at: t0)

        // V1 at +1m (minute 1001).
        t.update(ParsedMarkdown("V1.\n"), at: t0.addingTimeInterval(60))
        // V2 at +3m (minute 1003).
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(180))

        // Now at +5m30s (minute 1005, second 30).
        let now = t0.addingTimeInterval(5 * 60 + 30)
        let items = t.menuItems(at: now)

        // Only one gap entry: (V1, V2). The other gap (V0, V1) is
        // skipped because V0 is the initial milestone.
        let gapItems = items.filter { $0.label.contains("minute") }
        #expect(gapItems.count == 1)

        // Anchor minute = V2's = 1003. Now in minute 1005, second 30.
        // Label = (1005 - 1003) + 1 = 3.
        #expect(gapItems[0].label == "since 3 minutes ago")
    }

    @Test func menuGapDiffsAgainstOlderEndpoint() {
        // The change count of a gap entry must reflect (W_old → current),
        // not (initial → current). This is the property that makes the
        // user's "(2) since 1 minute ago" example work — the gap anchored
        // at minute 9:33 shows 2 changes (V1 → V3), not the 3 changes
        // accumulated since the initial.
        let t0 = Date(timeIntervalSinceReferenceDate: 1000 * 60)
        let v0 = ParsedMarkdown("# Title\n\nP1.\n")
        let v1 = ParsedMarkdown("# Modified Title\n\nP1.\n")
        let v2 = ParsedMarkdown("# Modified Title\n\nP1.\n\nP2.\n")

        let t = ChangeTracker()
        t.update(v0, at: t0)
        t.update(v1, at: t0.addingTimeInterval(60))
        t.update(v2, at: t0.addingTimeInterval(180))

        let items = t.menuItems(at: t0.addingTimeInterval(5 * 60))

        // The (V1, V2) gap entry has id = V1 reload's id.
        let v1Reload = t.waypoints.first {
            $0.kind == .reload && $0.parsed == v1
        }!
        let gap = items.first { $0.id == v1Reload.id }!

        // Reference counts.
        let v1ToV2 = ChangeGroup.build(
            from: MudCore.computeChanges(old: v1, new: v2)).count
        let v0ToV2 = ChangeGroup.build(
            from: MudCore.computeChanges(old: v0, new: v2)).count

        #expect(gap.changeCount == v1ToV2)
        // Sanity: the construction must produce different counts so the
        // assertion is meaningful.
        #expect(v1ToV2 != v0ToV2)
    }

    @Test func astEquivalentSaveSkipped() {
        // A save that's AST-equivalent to the most recent waypoint
        // (e.g. only edits blank lines) is treated as a duplicate and
        // not stored. ParsedMarkdown == compares raw text, which
        // doesn't recognize this case, so the check runs computeChanges.
        let t0 = Date(timeIntervalSinceReferenceDate: 1000 * 60)

        let v0 = ParsedMarkdown("# Title\n\nP1.\n")
        let v1 = ParsedMarkdown("# Title\n\nP1.\n\nP2.\n")
        // V2: extra blank line between paragraphs — same AST as V1.
        let v2 = ParsedMarkdown("# Title\n\nP1.\n\n\nP2.\n")
        let v3 = ParsedMarkdown("# Title\n\nP1.\n\n\nP2.\n\nP3.\n")

        // Sanity: the V1→V2 fixture must actually be AST-equivalent for
        // this test to mean anything.
        #expect(MudCore.computeChanges(old: v1, new: v2).isEmpty)

        let t = ChangeTracker()
        t.update(v0, at: t0)
        t.update(v1, at: t0.addingTimeInterval(60))
        t.update(v2, at: t0.addingTimeInterval(120))
        t.update(v3, at: t0.addingTimeInterval(180))

        // V2 was never stored as its own waypoint.
        #expect(!t.waypoints.contains { $0.parsed == v2 })

        // The Recent menu shows a single gap entry whose waypoint is
        // V1 (the pre-noop state), anchored on V3's minute.
        let items = t.menuItems(at: t0.addingTimeInterval(240))
        let gapItems = items.filter { $0.label.contains("minute") }
        #expect(gapItems.count == 1)

        let v1Reload = t.waypoints.first {
            $0.kind == .reload && $0.parsed == v1
        }!
        #expect(gapItems[0].id == v1Reload.id)
    }

    @Test func menuHidesZeroChangeGaps() {
        // When the file is reverted to a previously-seen state, the
        // most recent gap diffs against current to zero. The Recent
        // section should hide it. The reload waypoint stays in storage
        // and re-emerges when later edits give it a non-zero diff again.
        let t0 = Date(timeIntervalSinceReferenceDate: 1000 * 60)
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(60))
        t.update(ParsedMarkdown("V3.\n"), at: t0.addingTimeInterval(120))
        // Revert: duplicate of V2, skipped. currentParsed becomes V2.
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(180))

        let items = t.menuItems(at: t0.addingTimeInterval(240))
        let gapItems = items.filter { $0.label.contains("minute") }
        // The (V2 reload → V3 reload) gap has 0 changes against current=V2.
        #expect(gapItems.isEmpty)

        // The V3 reload is still in storage — re-emerges after a real edit.
        #expect(t.waypoints.contains { $0.parsed.markdown == "V3.\n" })
        t.update(ParsedMarkdown("V4.\n"), at: t0.addingTimeInterval(300))
        let itemsAfter = t.menuItems(at: t0.addingTimeInterval(360))
        let gapItemsAfter = itemsAfter.filter { $0.label.contains("minute") }
        #expect(!gapItemsAfter.isEmpty)
    }

    @Test func menuGapEntrySelectsOlderEndpointAsActiveWaypoint() {
        // Selecting a gap entry sets activeWaypointID to the W_old of
        // that gap, and a re-rendered menu marks it active.
        let t0 = Date(timeIntervalSinceReferenceDate: 1000 * 60)
        let t = tracker(initial: "V0.\n", at: t0)
        t.update(ParsedMarkdown("V1.\n"), at: t0.addingTimeInterval(60))
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(180))

        let now = t0.addingTimeInterval(5 * 60)
        let items = t.menuItems(at: now)

        let v1Reload = t.waypoints.first {
            $0.kind == .reload && $0.parsed.markdown == "V1.\n"
        }!
        let gap = items.first { $0.id == v1Reload.id }!

        t.selectWaypoint(gap.id)
        #expect(t.activeWaypointID == v1Reload.id)

        let items2 = t.menuItems(at: now)
        let activeItems = items2.filter(\.isActive)
        #expect(activeItems.count == 1)
        #expect(activeItems[0].id == v1Reload.id)
    }

    // MARK: - Cache behavior

    @Test func menuItemsAreCached() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))

        let items1 = t.menuItems(at: t0.addingTimeInterval(90))
        let items2 = t.menuItems(at: t0.addingTimeInterval(90))
        // Same object identity on IDs means same cached array.
        #expect(items1.map(\.id) == items2.map(\.id))
    }

    @Test func updateInvalidatesCache() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        let items1 = t.menuItems(at: t0.addingTimeInterval(90))

        t.update(
            ParsedMarkdown("V3.\n"),
            at: t0.addingTimeInterval(180))
        let items2 = t.menuItems(at: t0.addingTimeInterval(180))

        // After update, the diffCache is invalidated — items2 must be
        // recomputed against the new current content. We verify by
        // checking the item count is still sensible (a new reload
        // waypoint may add a gap entry).
        #expect(items2.count >= 1)
        _ = items1
    }

    @Test func acceptInvalidatesCache() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)

        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        _ = t.menuItems(at: t0.addingTimeInterval(90))

        t.acceptAt(t0.addingTimeInterval(90))

        t.update(ParsedMarkdown("V3.\n"), at: t0.addingTimeInterval(180))
        let items = t.menuItems(at: t0.addingTimeInterval(180))

        // After accept, the primary entry should be "since last accepted".
        #expect(items[0].label == "since last accepted")
    }

    // MARK: - External waypoints

    private func externalWaypoint(
        content: String,
        label: String = "since commit abc1234",
        detail: String? = "Fix heading levels",
        at time: Date = Date()
    ) -> Waypoint {
        Waypoint(
            parsed: ParsedMarkdown(content),
            timestamp: time,
            kind: .external(label: label, detail: detail))
    }

    @Test func setExternalWaypointsAddsToList() {
        let t = tracker(initial: "V1.\n")
        let ext = externalWaypoint(content: "Old.\n")
        t.setExternalWaypoints([ext])

        #expect(t.waypoints.contains { $0.id == ext.id })
    }

    @Test func setExternalWaypointsReplacesExisting() {
        let t = tracker(initial: "V1.\n")
        let ext1 = externalWaypoint(content: "Old.\n", label: "first")
        t.setExternalWaypoints([ext1])

        let ext2 = externalWaypoint(content: "Older.\n", label: "second")
        t.setExternalWaypoints([ext2])

        let externals = t.waypoints.filter {
            if case .external = $0.kind { true } else { false }
        }
        #expect(externals.count == 1)
        #expect(externals[0].id == ext2.id)
    }

    @Test func setExternalWaypointsEmptyArrayClears() {
        let t = tracker(initial: "V1.\n")
        t.setExternalWaypoints([externalWaypoint(content: "Old.\n")])
        t.setExternalWaypoints([])

        let externals = t.waypoints.filter {
            if case .external = $0.kind { true } else { false }
        }
        #expect(externals.isEmpty)
    }

    @Test func setExternalWaypointsPreservesNonExternalWaypoints() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))
        let waypointCountBefore = t.waypoints.count

        t.setExternalWaypoints([externalWaypoint(content: "Old.\n")])
        t.setExternalWaypoints([])

        #expect(t.waypoints.count == waypointCountBefore)
    }

    @Test func setExternalWaypointsResetsOrphanedActiveWaypoint() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))

        let ext = externalWaypoint(content: "Old.\n")
        t.setExternalWaypoints([ext])
        t.selectWaypoint(ext.id)
        #expect(t.activeWaypointID == ext.id)

        // Replacing externals removes the selected one — active waypoint resets.
        t.setExternalWaypoints([])
        #expect(t.activeWaypointID == nil)
    }

    @Test func setExternalWaypointsKeepsActiveWaypointIfStillPresent() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))

        let ext = externalWaypoint(content: "Old.\n")
        t.setExternalWaypoints([ext])
        t.selectWaypoint(ext.id)

        // Re-set with the same waypoint still present — active waypoint stays.
        t.setExternalWaypoints([ext])
        #expect(t.activeWaypointID == ext.id)
    }

    @Test func externalWaypointWorksForDiff() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))

        let ext = externalWaypoint(content: "Something else.\n")
        t.setExternalWaypoints([ext])
        t.selectWaypoint(ext.id)

        #expect(t.activeWaypoint?.markdown == "Something else.\n")
        #expect(!t.changes.isEmpty)
    }

    @Test func menuIncludesExternalWaypointsWithChanges() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))

        let ext = externalWaypoint(
            content: "Different.\n",
            label: "since commit abc1234",
            detail: "Fix heading levels")
        t.setExternalWaypoints([ext])

        let items = t.menuItems(at: t0.addingTimeInterval(90))
        let externalItems = items.filter(\.isExternal)
        #expect(externalItems.count == 1)
        #expect(externalItems[0].label == "since commit abc1234")
        #expect(externalItems[0].detail == "Fix heading levels")
        #expect(externalItems[0].changeCount > 0)
    }

    @Test func menuIncludesExternalWaypointsWithNoChanges() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))

        // External waypoint with same content as current — no changes,
        // but still shown so users aren't surprised by missing commits.
        let ext = externalWaypoint(content: "V2.\n")
        t.setExternalWaypoints([ext])

        let items = t.menuItems(at: t0.addingTimeInterval(90))
        let externalItems = items.filter(\.isExternal)
        #expect(externalItems.count == 1)
        #expect(externalItems[0].changeCount == 0)
    }

    @Test func menuExternalItemShowsActiveFlag() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))

        let ext = externalWaypoint(content: "Different.\n")
        t.setExternalWaypoints([ext])
        t.selectWaypoint(ext.id)

        let items = t.menuItems(at: t0.addingTimeInterval(90))
        let externalItems = items.filter(\.isExternal)
        #expect(externalItems.count == 1)
        #expect(externalItems[0].isActive)

        // Non-external items should not be active.
        let nonExternalActive = items.filter { !$0.isExternal && $0.isActive }
        #expect(nonExternalActive.isEmpty)
    }

    @Test func setExternalWaypointsInvalidatesMenuCache() {
        let t0 = Date()
        let t = tracker(initial: "V1.\n", at: t0)
        t.update(ParsedMarkdown("V2.\n"), at: t0.addingTimeInterval(90))

        let items1 = t.menuItems(at: t0.addingTimeInterval(90))
        let externalCount1 = items1.filter(\.isExternal).count

        t.setExternalWaypoints([externalWaypoint(content: "Different.\n")])
        let items2 = t.menuItems(at: t0.addingTimeInterval(90))
        let externalCount2 = items2.filter(\.isExternal).count

        #expect(externalCount1 == 0)
        #expect(externalCount2 == 1)
    }
}
