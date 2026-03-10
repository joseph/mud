Plan: Standardize Alerts
===============================================================================

> Status: Complete


## Context

Mud renders alerts from two syntaxes: GFM (`[!NOTE]`) and DocC (`Note:`). The
current implementation covers five GFM types and six DocC categories (including
`Status:`), but they are not consistently aligned. Several gaps exist:

- `[!STATUS]` is missing from GFM (only the DocC form exists).
- `ToDo:` maps to `.note` (should be `.status`) via the catch-all.
- Extended DocC aliases (e.g. `Remark:`, `Bug:`, `Experiment:`) are always
  rendered with no way to disable them.
- Down Mode shows all blockquotes with the same plain `md-blockquote` style,
  regardless of alert type.

The goal is to close these gaps and introduce an optional extended-alerts
setting.


## Definitions

**Common alerts** — the six canonical categories, each with a GFM and DocC
form:

| Category  | GFM            | DocC core form |
| --------- | -------------- | -------------- |
| Note      | `[!NOTE]`      | `Note:`        |
| Tip       | `[!TIP]`       | `Tip:`         |
| Important | `[!IMPORTANT]` | `Important:`   |
| Status    | `[!STATUS]`    | `Status:`      |
| Warning   | `[!WARNING]`   | `Warning:`     |
| Caution   | `[!CAUTION]`   | `Caution:`     |

**Extended DocC aliases** — non-canonical DocC asides that map to a common
category. Toggleable, on by default.

| Common category | Extended aliases                                                                                                   |
| --------------- | ------------------------------------------------------------------------------------------------------------------ |
| Note            | Remark, Complexity, Author, Authors, Copyright, Date, Since, Version, SeeAlso, MutatingVariant, NonMutatingVariant |
| Status          | ToDo                                                                                                               |
| Tip             | Experiment                                                                                                         |
| Important       | Attention                                                                                                          |
| Warning         | Precondition, Postcondition, Requires, Invariant                                                                   |
| Caution         | Bug, Throws, Error                                                                                                 |

When extended alerts are disabled, extended aliases render as plain
blockquotes. Core aliases always render as styled alerts.


## Phase 1: Core rendering (steps 1–4) ✓

### 1. Shared alert detector

Create `Core/Sources/Core/Rendering/AlertDetector.swift`. This extracts
detection logic currently private to `UpHTMLVisitor` so both Up and Down modes
can share it.

```swift
struct AlertDetector {
    /// Whether extended DocC aliases are recognised as styled alerts.
    var showExtendedAlerts: Bool = true

    /// Returns the alert category and display title for a GFM blockquote,
    /// or nil if the blockquote is not a GFM alert.
    func detectGFMAlert(_ blockQuote: BlockQuote) -> (AlertCategory, String)?

    /// Returns the alert category, display title, and content for a DocC
    /// blockquote, or nil if the blockquote is not a recognised aside.
    func detectDocCAlert(_ blockQuote: BlockQuote)
        -> (AlertCategory, String, [BlockMarkup])?
}
```

Internally, `AlertDetector` holds two maps:

- `coreMap: [String: AlertCategory]` — the six canonical kinds plus the custom
  rawValue kinds (`Error`, `Caution`, `Status`). Always active.
- `extendedMap: [String: AlertCategory]` — all other aliases. Active only when
  `showExtendedAlerts = true`.

`detectDocCAlert` looks up `aside.kind.rawValue` in core, then (if enabled) in
extended, returning `nil` if neither matches (→ plain blockquote).


### 2. GFM Status tag

In `AlertDetector` (extracted from `UpHTMLVisitor`), add `[!STATUS]` to the GFM
tag list:

```swift
private static let gfmAlertTags: [(String, AlertCategory)] = [
    ("[!NOTE]", .note), ("[!TIP]", .tip), ("[!IMPORTANT]", .important),
    ("[!STATUS]", .status),
    ("[!WARNING]", .warning), ("[!CAUTION]", .caution),
]
```


### 3. DocC mapping fixes

In `AlertDetector.extendedMap` (moved from `UpHTMLVisitor.doccCategoryMap`):

- Map `Aside.Kind.todo` → `.status` (was falling through to `.note`).
- Map `Aside.Kind.mutatingVariant` and `.nonMutatingVariant` → `.note`
  explicitly rather than via catch-all.


### 4. UpHTMLVisitor: use AlertDetector

Remove the private `detectGFMAlert`, `detectDocCAlert`, `gfmAlertTags`, and
`doccCategoryMap` from `UpHTMLVisitor`. Replace with a stored `AlertDetector`:

```swift
var alertDetector = AlertDetector()
```

Update `visitBlockQuote` to call `alertDetector.detectGFMAlert` and
`alertDetector.detectDocCAlert`.


## Phase 2: Settings and app wiring (steps 5–8) ✓

### 5. MudCore API: showExtendedAlerts parameter

Add `showExtendedAlerts: Bool = true` to:

- `renderUpToHTML(_:baseURL:resolveImageSource:showExtendedAlerts:)`
- `renderUpModeDocument(_:...:showExtendedAlerts:)`
- `renderDownToHTML(_:showExtendedAlerts:)`
- `renderDownModeDocument(_:...:showExtendedAlerts:)`

Pass the flag into the visitor in each case. Existing callers (CLI, tests) use
the default and are unaffected.


### 6. AppState: showExtendedAlerts

In `App/MudApp.swift`:

```swift
@Published var showExtendedAlerts: Bool
private static let showExtendedAlertsKey = "Mud-ShowExtendedAlerts"
```

Load from `UserDefaults` in `init()` (default `true`). Add
`saveShowExtendedAlerts()` following the same pattern as
`saveAllowRemoteContent()`.


### 7. DocumentContentView: wire up the flag

In `App/DocumentContentView.swift`:

- Include `appState.showExtendedAlerts` in `displayContentID` so content
  re-renders when the toggle changes.
- Pass `showExtendedAlerts: appState.showExtendedAlerts` to
  `renderUpModeDocument` and `renderDownModeDocument` in `modeHTML` and the
  export path.


### 8. UpModeSettingsView: settings toggle

In `App/Settings/UpModeSettingsView.swift`, add a second `Section` below the
existing remote-content toggle:

```
Section {
    Toggle("Show extended DocC alerts", ...)
    Text("Render DocC aliases such as Remark:, Bug:, Experiment: as
          styled alerts. When off, they appear as plain blockquotes.")
        .foregroundStyle(.secondary)
}
```

Call `appState.saveShowExtendedAlerts()` in the `set` closure.


## Phase 3: Down Mode (step 9) ✓

### 9. Down Mode: alert highlighting

**`DownHTMLVisitor.EventCollector`** — update `visitBlockQuote` to detect
alerts via `AlertDetector`:

```swift
mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
    if let (category, _) = alertDetector.detectGFMAlert(blockQuote) {
        emitContainer(blockQuote, cssClass: "md-blockquote md-alert-\(category.rawValue)")
    } else if let (category, _, _) = alertDetector.detectDocCAlert(blockQuote) {
        emitContainer(blockQuote, cssClass: "md-blockquote md-alert-\(category.rawValue)")
    } else {
        emitContainer(blockQuote, cssClass: "md-blockquote")
    }
}
```

`EventCollector` stores an `AlertDetector` value passed in from
`highlightAsTable(_:showExtendedAlerts:)`.

**`Core/Sources/Core/Resources/mud-down.css`** — add left-border color rules
for each alert category that mirror the Up Mode colors:

```css
.md-alert-note      { border-left-color: var(--alert-note-border); }
.md-alert-tip       { border-left-color: var(--alert-tip-border); }
.md-alert-important { border-left-color: var(--alert-important-border); }
.md-alert-status    { border-left-color: var(--alert-status-border); }
.md-alert-warning   { border-left-color: var(--alert-warning-border); }
.md-alert-caution   { border-left-color: var(--alert-caution-border); }
```

CSS custom properties for alert colors are already defined in `mud-up.css` and
shared via the base `mud.css`. Verify they are accessible from Down Mode
documents; if not, copy the property declarations into `mud.css` so both modes
share them.


## Documentation updates

**Phase 1** — restructure `Doc/Examples/alerts.md` to cover the full set of
common alerts (including the new `[!STATUS]` GFM form) and all extended DocC
aliases, grouped by their mapped category. The current file mixes structural
and extended DocC examples without a clear hierarchy.

**Phase 2** — update `Doc/Guides/` if any guide references alert rendering or
Up Mode settings, to document the new extended-alerts toggle.


## Files to modify

**Phase 1**

| File                                              | Change                                        |
| ------------------------------------------------- | --------------------------------------------- |
| `Core/Sources/Core/Rendering/AlertDetector.swift` | **New.** Shared detection logic               |
| `Core/Sources/Core/Rendering/UpHTMLVisitor.swift` | Remove private detection; use `AlertDetector` |

**Phase 2**

| File                                    | Change                                                      |
| --------------------------------------- | ----------------------------------------------------------- |
| `Core/Sources/Core/MudCore.swift`       | Add `showExtendedAlerts` parameter to four public functions |
| `App/MudApp.swift`                      | Add `showExtendedAlerts` published property + persistence   |
| `App/DocumentContentView.swift`         | Include flag in `displayContentID`; pass to renderers       |
| `App/Settings/UpModeSettingsView.swift` | Add extended-alerts toggle                                  |

**Phase 3**

| File                                                | Change                                            |
| --------------------------------------------------- | ------------------------------------------------- |
| `Core/Sources/Core/Rendering/DownHTMLVisitor.swift` | Detect alerts in `visitBlockQuote`; pass detector |
| `Core/Sources/Core/Resources/mud-down.css`          | Alert left-border CSS classes                     |
| `Core/Sources/Core/Resources/mud.css`               | Move alert color variables here if not shared     |


## Testing

**Phase 1** — unit tests (`Core/Tests/`):

- `[!STATUS]` GFM tag renders as `.status` alert
- `> ToDo: text` renders as `.status` alert
- `> MutatingVariant: text` renders as `.note` alert when extended enabled

**Phase 2** — unit tests (`Core/Tests/`):

- Extended alias renders as plain `<blockquote>` when
  `showExtendedAlerts = false`
- Core alias (`Note:`) still renders as alert when `showExtendedAlerts = false`

**Phase 3** — manual:

Build the app, open a Markdown file containing all six GFM tags, extended DocC
aliases, and standard DocC asides. Verify correct left-border colors in Down
Mode. Toggle the setting off and confirm extended asides lose their color; core
alerts retain it.
