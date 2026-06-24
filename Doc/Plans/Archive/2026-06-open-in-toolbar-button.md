Plan: Open In Toolbar Button
===============================================================================

> Status: Complete


## Context

The "Open In…" feature lived only in the menu bar (`File ▸ Open In…`). It hands
the current document to another Markdown editor and remembers one app as the
default (`open-in.default-bundle-id`). We added the same feature to the window
toolbar as a split button, matching the interaction in the referenced
`CatalystToolbarMenuButton`:

- **No default app yet:** a grid icon. Clicking the body or the chevron opens a
  menu of the installed Markdown apps plus "Choose…".
- **A default app is set:** that app's icon. Clicking the body launches it
  directly; the chevron still opens the menu to switch or re-choose.


## What changed

**Toolbar item (`App/DocumentWindowController.swift`).** A new `.openIn`
toolbar item, built as an `NSMenuToolbarItem` — the native AppKit control that
already gives a body action plus a chevron-triggered menu, so no custom split
view was needed. `showsIndicator` stays on so the chevron is always present.
`updateOpenInItem(_:configured:)` flips the item between its two states: with a
default set it shows that app's icon and an action that launches it; with none
it shows the grid icon (`square.grid.3x3.square.badge.ellipsis`, falling back
to `square.grid.2x2`) and clears the action so a body click opens the menu. The
item is in the allowed set only, so it ships off by default and a user adds it
through Customize Toolbar. A Combine sink on
`OpenInMenuModel.shared.$configured` keeps every window's icon current; it
reads the value the publisher emits, not the property, because `@Published`
fires in `willSet` and the property is still stale at that point.

**Shared menu model (`App/OpenInEditor.swift`).** `OpenInMenuModel` became an
`NSObject` so it can be the toolbar menu's target and `NSMenuDelegate`;
`menuNeedsUpdate(_:)` rebuilds the menu each time it opens, so a newly
installed app or a changed default appears with no manual reload. Both menus
now render from one source: `menuApps: [Entry]`, an ordered list (default
first, then the rest) where `Entry` carries the handler, an `isDefault` flag,
and the display `title` — the single home for the "(default)" marker. The
AppKit `populate(_:)` and the SwiftUI `File ▸ Open In…` menu
(`App/MudApp.swift`) both iterate it, so they can't drift on ordering, the
marker, or separator placement. Each renderer still owns what is genuinely
framework-specific: SwiftUI keeps the `Cmd+Shift+E` shortcut placement, and
each adds its own separators from the same rule.

**Clear-choice control (`App/Settings/DebuggingSettingsView.swift`).** An "Open
In" section with a "Clear Choice for "Open In…"" button. It clears the stored
bundle ID, resets the format to `.auto`, and refreshes the model; because the
pane observes the model, the toolbar buttons revert and the button disables
itself in the same update. The button is disabled when no default is set.
(Debug builds only.)

The launch and format logic was reused unchanged — `launch(with:)` already
picks the stored format for the default app and `.auto` for others. The
menu-bar submenu and its shortcut are unchanged. Open In works in both the
sandboxed (MAS) and direct builds, so the toolbar item needs no `isSandboxed`
guard.


## Verification

Build and run, then:

1. With no default set, the toolbar shows a grid-icon button with a chevron;
   both the body and the chevron open the menu of installed apps and "Choose…".
2. Pick an app — it launches and the button icon becomes that app's icon
   immediately.
3. The body now relaunches that app directly; the chevron still opens the menu
   with the app marked "(default)".
4. "Choose…" updates the icon and default, and `File ▸ Open In…` agrees. Both
   menus look identical, including the default-only case (one app installed): a
   single separator before "Choose…".
5. A second window shows the same default icon.
6. In the Debugging pane, "Clear Choice for "Open In…"" reverts the toolbar to
   the grid icon and disables itself.
