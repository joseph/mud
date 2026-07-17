Plan: MudPreferences Module
===============================================================================

> Status: Complete

Extract the user-preference persistence layer out of `AppState` into a new
Swift package module, `MudPreferences`, shared by the main app and the Quick
Look extension (see
[Archive/2026-04-quicklook-extension.md](./Archive/2026-04-quicklook-extension.md)).

`AppState` keeps its `@Published` topology and remains the reactive owner of
runtime state. MudPreferences owns key strings, default values, the typed enums
backing user-facing preferences, and the read/write helpers that touch
`UserDefaults`. Preferences remain in `UserDefaults.standard` — the domain the
user's own `defaults write org.josephpearson.Mud …` commands target — and
MudPreferences mirrors every write into an app-group suite so the Quick Look
extension can read a stable snapshot.


## Status

The module, its public API, the mirror-to-app-group strategy, migration from
legacy `Mud-*` keys, the move of preference-shape enums into the module, and
the Quick Look extension's read path all shipped. Subsequent key renaming and
Swift-identifier alignment landed under
[Archive/2026-04-pref-key-conventions.md](./Archive/2026-04-pref-key-conventions.md);
the catalog and identifier tables below reflect the post-conventions names.

The stretch goal under
[External change propagation](#external-change-propagation-stretch) also
shipped — `defaults write` is picked up live while the app is running, via
per-key KVO on `UserDefaults.standard` (the originally-planned Darwin
notification path turned out not to fire for app-specific domains).

The legacy-key rename has since been retired; `syncMirror()` stays as the
startup fan-out from `defaults` into the app-group mirror.


## Goals

- One central home for everything the app persists to `UserDefaults`. No more
  scattered key strings and inline default literals. — **done**
- Keep `UserDefaults.standard` as the source of truth. Mud is a developer tool
  and users should be able to set preferences via
  `defaults write org.josephpearson.Mud …` without wrestling with the long,
  space-laden path of the app group's Group Containers plist. — **done**
- Every write mirrors into the app-group suite
  (`$(TeamIdentifierPrefix)org.josephpearson.Mud`) so the Quick Look extension
  has a separate, shared, readable copy. — **done**
- Provide a one-shot `Snapshot` value the extension can read without owning any
  reactive state. — **done**
- Per-key legacy rename inside `UserDefaults.standard`, plus a one-shot sync
  from standard into the app-group suite on app launch. — **done**


## Non-goals

- Replacing or restructuring `AppState`. AppState keeps its `@Published`
  properties and Combine sinks. MudPreferences sits underneath as the
  persistence layer.
- Hiding `UserDefaults` behind a property wrapper (e.g. `@MudPref`). Explicit
  read/write accessors keep migration visible and stay grep-friendly. Property
  wrappers add a layer of magic that is harder to use from the snapshot path.
- ~~Live propagation of external `defaults write` changes made while the app is
  running.~~ Originally deferred — now a stretch goal; see
  [External change propagation](#external-change-propagation-stretch).
- Observability hooks (KVO, Combine publishers) on MudPreferences itself.
  AppState's existing `@Published` properties already drive the UI.
- Supporting multiple writer targets. The mirror direction (standard as source
  of truth, app-group suite as read-only copy for the extension) is chosen
  because `defaults write org.josephpearson.Mud …` is a concrete day-one
  developer affordance. A hypothetical second writer — a sibling app, menu bar
  agent, preferences daemon — that wrote directly to the app-group suite would
  have its writes silently overwritten on the main app's next write, because
  the main app reads `.standard`, not the suite. Flipping the mirror direction
  would fix that but would break CLI override of UI-set preferences across
  launches, because the launch-time sync can't distinguish a fresh
  `defaults write` from a stale value the second writer already superseded.
  Without per-key timestamps you can have at most two of: (1) absorb external
  `defaults write` on launch, (2) preserve second-writer writes across
  launches, (3) no conflict resolution. We picked (1) and (3). If a second
  writer ever materializes, it should use real coordination (Darwin
  notifications, XPC) rather than silently contending at the UserDefaults
  layer.


## Module structure

A sibling Swift package next to `Core/`:

```
Preferences/
  Package.swift
  Sources/
    MudPreferences.swift              — struct, `.shared`, read/write helpers
    MudPreferencesSnapshot.swift      — value type for extension consumption
    MudPreferencesObserver.swift      — startup mirror sync + KVO observer
    Theme.swift                         — moved from App/
    ViewToggle.swift                    — moved from App/
    SidebarPane.swift                   — moved from App/AppState.swift
    FloatingControlsPosition.swift      — moved from App/
    Mode.swift                          — moved from App/
    Lighting.swift                      — bare enum, moved from App/
  Tests/
    TestPreferences.swift               — hermetic-suite helper
    MudPreferencesTests.swift           — round-trips, defaults, reset, catalog, mirror fan-out
    MudPreferencesObserverTests.swift   — startup mirror sync + KVO observer
    MudPreferencesSnapshotTests.swift   — snapshot + upModeHTMLClasses
```

Package product: `MudPreferences`. Depends on `MudCore` (for `DocCAlertMode`).
Foundation only — no AppKit, no SwiftUI.


## Dependency arrow

```
App ─┬─▶ MudPreferences ─▶ MudCore
     └─▶ MudCore

QuickLookExtension ─┬─▶ MudPreferences ─▶ MudCore
                    └─▶ MudCore
```

No cycles. MudCore stays platform-independent and unaware of UserDefaults.


## What moved into MudPreferences

### Typed enums

These have no platform dependencies and are pure preference shapes:

- `Theme` (was `App/Theme.swift`)
- `ViewToggle` (was `App/ViewToggle.swift`)
- `SidebarPane` (was nested in `App/AppState.swift`)
- `FloatingControlsPosition` (was `App/FloatingControlsPosition.swift`)
- `Mode` (was `App/Mode.swift`)
- `Lighting` — the bare enum only; see below


### Lighting split

The original `Lighting` type bundled two unrelated concerns:

- A bare enum (`bright` / `dark` / `auto`) — a pref shape with no platform
  dependency.
- AppKit/SwiftUI behavior — `appearance: NSAppearance?`,
  `colorScheme(environment:)`, `systemIsDark`, `toggled()` (which consumes
  `systemIsDark`).

The bare enum lives in `MudPreferences/Sources/Lighting.swift` so `Lighting`
can be persisted via the same `read`/ `write` path as every other pref. The
AppKit/SwiftUI methods live in `App/Lighting+AppKit.swift` as an extension on
the MudPreferences-hosted enum. No call-site change — `lighting.appearance`,
`lighting.colorScheme(...)`, `lighting.toggled()` remain available wherever
App/ is in scope.

Moving the entire type (including the AppKit methods) into MudPreferences would
force the module to import AppKit and SwiftUI, breaking the Foundation-only
boundary and adding unnecessary weight to the Quick Look extension's link
graph.


### Stays in MudCore

- `DocCAlertMode` — owned by MudCore because it controls parser behavior.
  MudPreferences imports MudCore and round-trips the type through its
  read/write helpers. Moving `DocCAlertMode` into MudPreferences would invert
  the dependency arrow (`MudCore → MudPreferences`), coupling the pure
  rendering library to the persistence layer for a modest consolidation win.
  Not worth it.


## Key naming convention

All keys use **lowercase-with-hyphens**, feature-grouped (`group.sub-name`), no
prefix, no leading underscore. The full convention — imperative verb-noun for
Bool preferences, past-tense for internal state, `.enabled` suffix for
master-switch Bools, Swift identifier alignment per layer — is documented in
[Archive/2026-04-pref-key-conventions.md](./Archive/2026-04-pref-key-conventions.md).

Rationale for the lowercase-hyphen base:

- The bundle domain (`org.josephpearson.Mud`) already namespaces every key — an
  app-level prefix like `Mud-` is structurally redundant. Apple's own
  first-party apps don't prefix keys within their own domains.
- macOS first-party precedent for the lowercase-with-hyphens style: the Dock
  (`com.apple.dock`) uses `tilesize`, `autohide`, `static-only`,
  `autohide-time-modifier`, `show-recents`; the screenshot service
  (`com.apple.screencapture`) uses `location`, `disable-shadow`,
  `include-date`.


## Key catalog

25 keys. Every key lives under `org.josephpearson.Mud` in
`UserDefaults.standard` (source of truth) and is mirrored into the Team-ID-
prefixed app-group suite for the extension. "Legacy key" is the name the value
was persisted under in `UserDefaults.standard` before this module shipped; used
only by one-time migration.

| Key                             | Type                       | Default         | Legacy key                     |
| ------------------------------- | -------------------------- | --------------- | ------------------------------ |
| `lighting`                      | `Lighting`                 | `.auto`         | `Mud-Lighting`                 |
| `theme`                         | `Theme`                    | `.earthy`       | `Mud-Theme`                    |
| `quit-on-close`                 | `Bool`                     | `true`          | `Mud-QuitOnClose`              |
| `enabled-extensions`            | `[String]`                 | all registered  | `Mud-EnabledExtensions`        |
| `changes.enabled`               | `Bool`                     | `true`          | `Mud-TrackChanges`             |
| `changes.show-inline-deletions` | `Bool`                     | `false`         | `Mud-InlineDeletions`          |
| `changes.show-git-waypoints`    | `Bool`                     | `false`         | `Mud-ShowGitWaypoints`         |
| `changes.auto-expand-groups`    | `Bool`                     | `false`         | `Mud-autoExpandChanges`        |
| `changes.word-diff-threshold`   | `Double`                   | `0.25`          | `Mud-WordDiffThreshold`        |
| `up-mode.zoom-level`            | `Double`                   | `1.0`           | `Mud-UpModeZoomLevel`          |
| `up-mode.allow-remote-content`  | `Bool`                     | `true`          | `Mud-AllowRemoteContent`       |
| `up-mode.show-code-header`      | `Bool` (ViewToggle)        | `true`          | `Mud-codeHeader`               |
| `down-mode.zoom-level`          | `Double`                   | `1.0`           | `Mud-DownModeZoomLevel`        |
| `down-mode.show-line-numbers`   | `Bool` (ViewToggle)        | `true`          | `Mud-lineNumbers`              |
| `down-mode.wrap-lines`          | `Bool` (ViewToggle)        | `true`          | `Mud-wordWrap`                 |
| `sidebar.enabled`               | `Bool`                     | `false`         | `Mud-SidebarVisible`           |
| `sidebar.pane`                  | `SidebarPane`              | `.outline`      | `Mud-SidebarPane`              |
| `markdown.docc-alert-mode`      | `DocCAlertMode`            | `.extended`     | `Mud-DoccAlertMode`            |
| `ui.use-heading-as-title`       | `Bool`                     | `true`          | `Mud-UseHeadingAsTitle`        |
| `ui.floating-controls-position` | `FloatingControlsPosition` | `.bottomCenter` | `Mud-FloatingControlsPosition` |
| `ui.show-readable-column`       | `Bool` (ViewToggle)        | `false`         | `Mud-readableColumn`           |
| `internal.has-launched`         | `Bool`                     | `false`         | `Mud-HasLaunched`              |
| `internal.window-frame`         | `String?`                  | `nil`           | `Mud-WindowFrame`              |
| `internal.cli-installed`        | `Bool`                     | `false`         | `Mud-CLIInstalled`             |
| `internal.cli-symlink-path`     | `String?`                  | `nil`           | `Mud-CLISymlinkPath`           |


## Public API

### Shape: two `UserDefaults` instances

`MudPreferences` is a `struct` holding two `UserDefaults` — a `defaults` used
for reads and writes (the source of truth) and an optional `mirror` that
receives a fan-out copy of every write. Production code uses
`MudPreferences.shared`, which points `defaults` at `.standard` and `mirror` at
the app-group suite. The Quick Look extension constructs its own instance with
`defaults` pointing at the suite and no mirror — it never writes, and the one
value-type it consumes is `MudPreferencesSnapshot`.

The app-group suite name is resolved at runtime from the calling process's
`com.apple.security.application-groups` entitlement via
`SecTaskCopyValueForEntitlement`. Xcode expands `$(TeamIdentifierPrefix)` in
the entitlements file at sign time, so the runtime value is already
Team-ID-prefixed — which macOS Sequoia+ requires for silent container access
without a TCC prompt. The hardcoded fallback guards `SecTask` failure (e.g.
unsigned test processes) and must match the entitlements file.


### Keys

Key strings live in a `String`-backed `CaseIterable` enum on `MudPreferences`.
The Swift identifier is camelCase (Swift requirement for readable case names);
the `rawValue` is the grouped persistence string.


### Per-key accessors

Reads hit `defaults`. Writes fan out — they set both `defaults` and, when
present, `mirror`. Under the hood, a private `write(_:forKey:)` helper and a
pair of generic `read(_:default:)` overloads keep per-key accessors tight.

Each pref exposes a `nonmutating` get/set computed property on `MudPreferences`
(e.g. `theme`, `upModeZoomLevel`, `sidebarEnabled`, `markdownDocCAlertMode`).
Two exceptions stay as methods because their shape doesn't fit a bare property:

- `enabledExtensions` — takes a caller-supplied default set because
  MudPreferences doesn't own the registry of available extensions. Exposed as
  `readEnabledExtensions(defaultValue:)` / `writeEnabledExtensions(_:)`.
- `ViewToggle` accessors — parameterized by the toggle itself. Exposed as
  `readViewToggle(_:)` / `writeViewToggle(_:enabled:)`, plus a
  `viewToggles: Set<ViewToggle>` convenience property that filters and writes
  all cases.

`ViewToggle` itself defines `key: MudPreferences.Keys` and `defaultValue: Bool`
mappings alongside `className: String`; `isEnabled` and `save(_:)` delegate to
`MudPreferences.shared`.


### Snapshot for the extension

`MudPreferencesSnapshot` is a value type exposing the fields a Quick Look
preview consumes (the ones that flow into `RenderOptions`): `theme`,
`upModeZoomLevel`, `viewToggles`, `upModeAllowRemoteContent`,
`enabledExtensions`, `markdownDocCAlertMode`. Plus a derived
`upModeHTMLClasses` that turns the Up-mode-relevant view toggles into CSS class
names.

Built via `MudPreferences.snapshot(defaultEnabledExtensions:)`, which reads
from `defaults` in both app and extension — same code, same read path, just
aimed at different stores.

Preferences outside a preview's concern (lighting, sidebar state,
quit-on-close, etc.) aren't in the snapshot. Future callers can add fields as
needed without affecting AppState.


### Startup mirror sync

`syncMirror()` copies every current `defaults` value into `mirror`, including
clearing mirror keys whose source value has since been removed. Idempotent;
no-op when the instance has no mirror.

`MudPreferences.shared.syncMirror()` runs once in `AppState.init()` before any
other preference read, ensuring the mirror reflects any `defaults write`
changes the user made while the app was not running. The extension doesn't sync
— it has no mirror. If the app has never launched since install, the suite is
empty and the extension falls back to hard-coded defaults (documented edge case
in the QL plan).


### Reset

`reset()` walks `Keys.allCases` and calls `write(nil, forKey:)`, which
`UserDefaults` documents as equivalent to `removeObject(forKey:)`. Because
writes fan out, reset clears both `defaults` and `mirror` synchronously —
important because the Quick Look extension reads the mirror on the next preview
request. Used by the Debugging settings pane in debug builds.


## AppState changes

`AppState` keeps every `@Published` property it had. The persistence topology
is:

- Legacy `Self.fooKey` constants removed — keys live in `MudPreferences.Keys`.
- `init()` reads each property's starting value from
  `MudPreferences.shared.<pref>`.
- Each `@Published` property carries a `didSet` that writes the new value back
  to `MudPreferences.shared`.
- `ViewToggle.isEnabled` / `ViewToggle.save(_:)` delegate to
  `MudPreferences.shared.readViewToggle(_:)` /
  `MudPreferences.shared.writeViewToggle(_:enabled:)`.

Identifiers match the grouped Swift names from the conventions plan:
`sidebarEnabled`, `changesEnabled`, `changesShowInlineDeletions`,
`upModeAllowRemoteContent`, `markdownDocCAlertMode`, `uiUseHeadingAsTitle`,
`changesWordDiffThreshold`, `uiFloatingControlsPosition`,
`changesShowGitWaypoints`, etc.


## Tests

Swift Testing (matching `MudCoreTests`'s `import Testing` / `@Test` / `@Suite`
conventions). Three test files plus one helper, split by concern. Every test
creates its own `MudPreferences` instance with a hermetic per-test `defaults`
suite via the `TestPreferences` helper, and most also supply a hermetic
per-test `mirror` suite, so Swift Testing's default parallel execution is safe.

- `TestPreferences.swift` — hermetic-suite helper: builds a `MudPreferences`
  with per-test `defaults` and `mirror` suite names derived from a fresh UUID,
  and tears both down after the test.
- `MudPreferencesTests.swift` — round-trips per type shape, empty-suite
  defaults, fallback when a stored enum raw value doesn't match any case,
  `reset()` clears both stores, mirror fan-out on every write, key-catalog
  invariants (`Keys.allCases.count == 25`, distinct rawValues), and a second
  MudPreferences whose `defaults` points at the first's mirror reads back
  exactly what the app wrote.
- `MudPreferencesObserverTests.swift` — KVO observer surfaces external writes
  and key removals as `onChange` callbacks and mirror updates, self-filter
  suppresses in-app writes, lifecycle (refresh before observing is a no-op,
  re-registering replaces the callback). Also covers `syncMirror()`: copies
  present keys, clears absent ones, no-op when no mirror, idempotent.
- `MudPreferencesSnapshotTests.swift` — snapshot of empty suite returns all
  defaults, snapshot reflects each written field, mirror-backed snapshot equals
  defaults-backed snapshot after the same writes, `upModeHTMLClasses` includes
  only Up-mode-relevant toggles.


### Not tested

- Thread safety — `UserDefaults` handles it.
- Persistence across process restarts — `UserDefaults` handles it.
- Observability — no KVO/Combine on MudPreferences; nothing to test.
- Cross-process visibility between the app and the QL extension — a runtime
  integration concern, not a unit test. Verified by running the extension
  against a real dev build.
- Darwin-notification plumbing itself — a runtime-integration concern; see
  [External change propagation → Tests](#tests-1).


## External change propagation (stretch)

> Status: Complete — shipped with KVO on `UserDefaults.standard` rather than
> the originally-planned Darwin notification (see mechanism section).

Pick up external `defaults write` / `defaults delete` on
`org.josephpearson.Mud` while the app is running, so that:

- AppState reloads its `@Published` properties — the running UI reflects the
  change without a restart.
- The app-group mirror re-syncs so the Quick Look extension's next render picks
  up the change.

The one-writer, "user's CLI overrides UI on next launch" contract from the
Non-goals discussion is unchanged. This stretch adds observation only, not a
second writer: the app still reads and writes `.standard`; the extension still
reads the mirror.


### Mechanism: KVO on `UserDefaults.standard`

The original plan proposed subscribing to a Darwin notification
`com.apple.cfprefsd.domain.<bundle-id>`. In practice cfprefsd does **not** post
a public Darwin notification for app-specific domain changes (empirically
verified with `notifyutil -w` and `log stream --process cfprefsd`). Instead it
signals subscribers over private XPC — each process's `NSUserDefaults` instance
is an XPC peer, and cfprefsd invalidates their caches directly.

Foundation surfaces that XPC-driven invalidation as per-key KVO on the same
`NSUserDefaults` instance. Registering
`addObserver(_:forKeyPath:options: context:)` for each `Keys.rawValue` on
`UserDefaults.standard` therefore fires on external writes — this is how we get
notified.

A single `KVOBridge: NSObject` is created per `MudPreferences.State` and added
as observer for every key. Its `observeValue` calls `state.scheduleRefresh()`,
which uses an `NSLock`-guarded `refreshPending` flag to enqueue at most one
main-queue diff pass per run-loop turn. cfprefsd invalidates the whole domain
at once, so 25 KVO callbacks per external write are expected — they coalesce
into a single diff pass that fires `onChange` exactly once per actually-
changed key.

The observer lifetime matches the process: no `removeObserver` is exposed.
Hermetic test suites (where `defaults !== UserDefaults.standard`) skip the KVO
registration and drive the diff pass directly — see the Tests section.


### Feedback-loop mitigation: last-known snapshot

KVO fires regardless of which process caused the change, so an in-app write
would otherwise trigger a reload-from-prefs, which would trigger another write
via AppState's `didSet`, idempotently pinging back and forth.

`MudPreferences.shared` keeps a private `lastKnown: [Keys: NSObject?]` map
(UserDefaults values are always `NSObject` subclasses — `NSNumber`, `NSString`,
`NSArray`, `NSDictionary`, `NSData`, `NSDate` — so `isEqual:` comparison is
straightforward).

- Seeded after `migrate()` at startup by reading every key once.
- Every in-app `write(_:forKey:)` updates `lastKnown` before touching
  `defaults` and `mirror`.
- On each KVO callback: iterate `Keys.allCases`, read
  `defaults.object(forKey:)`, compare against `lastKnown`. For each diff,
  update `lastKnown`, write the new value to `mirror`, and dispatch a
  `(Keys) -> Void` callback on the main queue.

Self-triggered callbacks see no diffs because in-app writes keep `lastKnown` in
lockstep with `defaults`. External writes bypass `lastKnown`, so the diff
surfaces and the handler acts.


### Public API

A single new entry point on `MudPreferences`:

```swift
extension MudPreferences {
    /// Start observing external changes to `defaults`. Idempotent. The
    /// callback is dispatched on the main queue, once per changed key.
    /// Not called by the Quick Look extension — it re-reads the snapshot
    /// on every preview request.
    public func startObservingExternalChanges(
        onChange: @escaping (Keys) -> Void
    )
}
```

The subscription lives for the process lifetime; no removal is exposed.
`lastKnown` becomes a `nonmutating` private stored state (boxed in a reference
type since `MudPreferences` is a struct).


### AppState integration

`AppState.init()` calls `startObservingExternalChanges` with a handler that
switches on `Keys` and assigns the freshly-read value to the matching
`@Published` property. Each assignment fires `didSet`, which writes back to
`MudPreferences.shared`, which updates `lastKnown`. Subsequent notifications
for that key see no diff — the loop terminates at one round.

Keys with no `@Published` representative in AppState (e.g.
`internal.window-frame`, `internal.cli-installed`) are ignored by the handler.
The mirror still receives them so the extension stays in sync.


### Tests

The `lastKnown`-based diff machinery is unit-testable with the existing
hermetic-suite helper — no cfprefsd or KVO involved:

- In-app writes update `lastKnown` before `defaults`, so a manually-triggered
  diff pass emits nothing.
- Direct mutation of the underlying suite (simulating an external write)
  surfaces through the diff pass as a callback with the right key.
- Removing a key via `defaults.removeObject(forKey:)` surfaces as a callback
  with the `nil` path.
- Writing every key in sequence, externally, produces one callback per changed
  key and leaves `lastKnown` equal to `defaults`.

The KVO bridge itself (NSObject subclass, observer registration, main-queue
dispatch) is a runtime-integration concern — unit tests can't drive
cross-process cfprefsd invalidations. Verify manually with the app running:

```
defaults write org.josephpearson.Mud theme blues
```

The app window should switch themes without a restart, and a Quick Look preview
opened afterward in Finder should render with the new theme.
