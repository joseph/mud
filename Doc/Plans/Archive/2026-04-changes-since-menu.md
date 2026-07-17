Plan: Changes Since Menu
===============================================================================

> Status: Complete


## Goal

Replace the stub menu in the Changes bar with a "Changes since…" picker that
lets the user choose which historical snapshot to diff against. The primary
choice is "since last accepted" (falling back to "since document opened" if
never accepted). Below that, time-bucketed choices show the most recent reload
snapshot older than each threshold.


## Current state

`ChangeTracker` keeps a list of **waypoints** — but currently only two kinds of
waypoint exist:

1. The initial waypoint, created on first `update()` call (document open).
2. Accept waypoints, created by `accept()`.

Every file reload calls `update(_:)`, which diffs the new content against the
_last_ waypoint. Intermediate reload snapshots are not stored, so there's no
history to diff against.

The Changes bar menu is a stub that just shows "Since {time}".


## Design

### Waypoint history

Expand the existing `Waypoint` struct with a `kind` field and store one on
every `update()` call (i.e. every file reload), not just on open/accept:

```swift
struct Waypoint: Identifiable {
  enum Kind { case initial, reload, accept }
  let id = UUID()
  let parsed: ParsedMarkdown
  let timestamp: Date
  let kind: Kind
}
```

Store these in an array on `ChangeTracker` (replacing the current `waypoints`
array, which only holds open/accept entries):

```swift
@Published private(set) var waypoints: [Waypoint] = []
```

The `.initial` waypoint is never dropped. There is at most one `.accept`
waypoint at any time — a new accept replaces the previous one. Only `.reload`
waypoints accumulate; cap those at a reasonable limit (e.g. 100).


### Active waypoint

Add a concept of the **active waypoint** — the waypoint the diff is computed
against. Currently this is always the last waypoint. With the menu, the user
can select any waypoint.

```swift
@Published var activeWaypointID: UUID?
```

When nil, defaults to the most recent `.accept` waypoint (or `.initial` if no
accepts). When set, diffs against that specific waypoint.


### Menu items

The menu shows up to these entries:

1. **"Since last accepted"** — the most recent accept waypoint. If no accepts
   have occurred, this item is labeled "Since document opened" and points to
   the initial waypoint. Always shown.

2. **Time-bucketed waypoints** — for each threshold in [1, 2, 3, 4, 5, 10, 15]
   minutes, find the most recent waypoint older than that threshold.
   Deduplicate (skip if same waypoint as a previous bucket). Skip if same
   waypoint as the "last accepted" or "document opened" entry.

3. **"Since document opened"** — always shown at the bottom if distinct from
   item 1 (i.e. if accepts have occurred).

Each item shows:

- Change count (computed on demand by diffing current content against that
  waypoint)
- Relative label ("since last accepted", "since 3 minutes ago", etc.)
- Absolute timestamp ("at 10:29am")


### Example

At 10:33am, with accepts at 10:19am and document opened at 9:52am, and reloads
scattered throughout:

```
 (7) changes since last accepted
     … at 10:19am
 (3) changes since 1 minute ago
     … at 10:32am
 (5) changes since 4 minutes ago
     … at 10:29am
 (6) changes since 10 minutes ago
     … at 10:23am
(11) changes since document opened
     … at 9:52am
```


## Implementation

### Step 0: Move ChangeTracker and ChangeGroup to Core

Move `App/ChangeTracker.swift` into `Core/Sources/Core/`. It depends only on
`ParsedMarkdown` and `MudCore.computeChanges` (both Core) plus `Combine`
(`ObservableObject`, `@Published`), which is available on all Apple platforms.
No AppKit or SwiftUI dependencies.

Move `ChangeGroup` and `ChangeGroup.build` from `App/ChangesSidebarView.swift`
into `Core/Sources/Core/Diff/ChangeGroup.swift`. The struct and its `build`
method are pure logic over `DocumentChange` and `ChangeType` (both Core). The
SwiftUI view (`ChangeGroupRow`) stays in App. This lets `ChangeTracker` use
`ChangeGroup.build` directly for menu item change counts.

In the App layer, `DocumentContentView`, `ChangesBar`, and `ChangesSidebarView`
continue to use these types as before — the only change is the import path.


### Step 1: Expand waypoint storage in ChangeTracker

- Add `Kind` enum to `Waypoint` (`.initial`, `.reload`, `.accept`).
- In `update(_:)`, append a waypoint (`.initial` on first call, `.reload` on
  subsequent calls) — but skip if the most recent `.reload` waypoint is less
  than 60 seconds old. The existing waypoint keeps its original content and
  timestamp, aging naturally into time buckets. (Replacing instead of skipping
  would cause the reload to slide forward indefinitely with frequent saves.)
- Prune `.reload` waypoints older than 15 minutes (they're beyond the last time
  bucket and no longer useful).
- Never drop the `.initial` waypoint. Never drop the `.accept` waypoint — but
  only keep one: `accept()` replaces the existing `.accept` waypoint (if any)
  rather than appending a second one.


### Step 2: Active waypoint selection

- Add `@Published var activeWaypointID: UUID?` to `ChangeTracker`.
- Extract a computed `activeWaypoint: ParsedMarkdown?` that resolves to either
  the waypoint matching `activeWaypointID`, or falling back to the most recent
  `.accept` (or `.initial`).
- Change `update(_:)` to diff against `activeWaypoint` instead of the last
  waypoint.
- When `accept()` is called, reset `activeWaypointID` to nil (so it defaults
  back to the new accept waypoint).


### Step 3: Menu item computation

Add a method or computed property on `ChangeTracker` that returns menu items:

```swift
struct ChangeMenuItem: Identifiable {
  let id: UUID          // waypoint ID
  let label: String     // "since last accepted", "since 3 minutes ago", etc.
  let timestamp: Date
  let changeCount: Int
  let isActive: Bool    // currently selected waypoint
}

func menuItems() -> [ChangeMenuItem]
```

This method:

1. Identifies the "last accepted" waypoint (or "document opened" fallback).
2. Walks the time thresholds, finding matching waypoints.
3. Adds "document opened" at the bottom if distinct.
4. For each, computes `MudCore.computeChanges(old:new:)` to get the count.

**Caching strategy:** Compute lazily on first `menuItems()` call, then cache
the result. `update()` and `accept()` invalidate the cache (set it to nil).
This avoids redundant diffs when the menu is opened multiple times between
reloads, while keeping `update()` cheap.

```swift
private var cachedMenuItems: [ChangeMenuItem]?

func menuItems() -> [ChangeMenuItem] {
  if let cached = cachedMenuItems { return cached }
  let items = computeMenuItems()
  cachedMenuItems = items
  return items
}
```

Both `update(_:)` and `accept()` set `cachedMenuItems = nil`.


### Step 4: Xcode integration and menu UI

Replace the stub `Menu` in `ChangesBar` with the real picker. Each item is a
`Button` that sets `changeTracker.activeWaypointID`. The active item gets a
checkmark.

Layout per item:

```
(N) changes since {label}
    … at {time}
```

Use two text lines within each menu item. The count badge should match the
Changes bar badge style (colored circle).


## Testing

All tests go in `Core/Tests/Core/` alongside the existing diff tests. The test
file should be `ChangeTrackerTests.swift`.


### Waypoint lifecycle

- **Initial waypoint:** First `update()` creates an `.initial` waypoint.
- **Reload waypoints:** Subsequent `update()` calls create `.reload` waypoints.
- **Coalescing:** Two `update()` calls < 60s apart produce one `.reload`
  waypoint (the second replaces the first). Two calls >= 60s apart produce two.
- **Pruning:** `.reload` waypoints > 15m old are removed on `update()`.
  `.initial` and `.accept` are never removed regardless of age.
- **Accept replacement:** `accept()` creates an `.accept` waypoint. A second
  `accept()` replaces it — there is never more than one `.accept` waypoint.


### Active waypoint resolution

- With no `activeWaypointID` and no accepts, resolves to `.initial`.
- With no `activeWaypointID` and an accept, resolves to `.accept`.
- With `activeWaypointID` set, resolves to that specific waypoint.
- `accept()` resets `activeWaypointID` to nil.


### Menu item computation

- **Basic structure:** Menu includes "since last accepted" (or "since document
  opened") at top, time-bucketed entries in the middle, "since document opened"
  at bottom (if distinct from top).
- **Deduplication:** Time buckets that resolve to the same waypoint are
  collapsed. Buckets matching the accepted/initial waypoint are skipped.
- **Change counts:** Each menu item's `changeCount` matches the result of
  diffing that waypoint against the current content.
- **Active flag:** The menu item matching the current active waypoint has
  `isActive: true`.


### Cache behavior

- `menuItems()` called twice without intervening `update()` or `accept()`
  returns the same result (cached).
- `update()` invalidates the cache — next `menuItems()` recomputes.
- `accept()` invalidates the cache.
