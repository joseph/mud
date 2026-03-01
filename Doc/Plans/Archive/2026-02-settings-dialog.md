Settings dialog
===============================================================================

> Status: Complete


## Context

The app's Settings scene currently contains a single toggle ("Quit when last
window closes") in a bare `Form`. We want to expand it into a full settings
window modeled after Xcode's: a sidebar listing categories on the left, with
structured settings panes on the right.

Settings that already exist as menu items (lighting, theme, view toggles) will
**continue** to appear in their menus. The settings dialog provides a second,
browseable home for them. "Quit when last window closes" moves out of the
Window menu and lives only in settings.

Per-mode syntax-highlighting toggles are deferred to a future iteration. Up
Mode will appear in the sidebar but its pane will be empty initially.


## Categories and controls

### General (`gearshape`)

| Control                      | Type             | Notes                           |
| ---------------------------- | ---------------- | ------------------------------- |
| Lighting                     | Segmented picker | Auto / Bright / Dark            |
| Readable Column              | Toggle           | Binds to existing ViewToggle    |
| Quit When Last Window Closes | Toggle           | Existing `quitOnClose` property |


### Theme (`paintpalette`)

Four selectable preview cards — one per theme. Each card is a small rounded
rectangle that samples the theme's key colors (background, heading, body text,
link, code background). The active theme shows a selection indicator (e.g.
highlighted border or checkmark overlay). Cards should respect the current
lighting so users see what they'll actually get.

No other controls in this pane.


### Up Mode (`arrowshape.up.circle`)

Empty for now. Placeholder for future per-mode settings (e.g. syntax
highlighting in code blocks).


### Down Mode (`arrowshape.down.circle`)

| Control      | Type   | Notes                        |
| ------------ | ------ | ---------------------------- |
| Line Numbers | Toggle | Binds to existing ViewToggle |
| Word Wrap    | Toggle | Binds to existing ViewToggle |


## Layout

```
┌──────────────────────────────────────────────────────────┐
│ Settings                                                 │
├──────────────┬───────────────────────────────────────────┤
│              │                                           │
│  ⚙ General   │  Section heading / controls               │
│  🎨 Theme    │                                           │
│  ↑ Up Mode   │                                           │
│  ↓ Down Mode │                                           │
│              │                                           │
├──────────────┴───────────────────────────────────────────┤
```

The window uses a `NavigationSplitView` inside the `Settings` scene. The
sidebar is a `List(selection:)` with `Label` rows (SF Symbol + title). The
detail area renders the appropriate pane view based on selection.

Fixed window size — wide enough for the theme preview cards to sit in a
horizontal row (~560pt content width, ~180pt sidebar).


## File changes

### New files

- `App/SettingsView.swift` — Root settings view with `NavigationSplitView`,
  category enum, sidebar list, and detail switch.
- `App/GeneralSettingsView.swift` — General pane (lighting picker, readable
  column toggle, quit toggle).
- `App/ThemeSettingsView.swift` — Theme pane with preview cards.
- `App/UpModeSettingsView.swift` — Up Mode pane (empty placeholder).
- `App/DownModeSettingsView.swift` — Down Mode pane.
- `App/ThemePreviewCard.swift` — Reusable preview card view.


### Modified files

- `App/MudApp.swift` — Replace the `Settings { Form { ... } }` block with
  `Settings { SettingsView() }`.
- `Doc/AGENTS.md` — Update file quick reference with new settings view files.


## Theme preview card design

Each card (~120×80pt) shows a miniature representation of the theme:

```
┌─────────────────────┐
│ ▊▊▊▊▊▊▊▊           │  ← heading-color bar
│ ▊▊▊▊▊▊▊▊▊▊▊▊       │  ← text-color bar
│ ▊▊▊▊▊▊▊▊▊          │  ← text-color bar
│ ▊▊▊▊▊▊▊  ▊▊▊▊▊▊▊▊  │  ← text + link-color
│      ┌──────────┐   │
│      │ ▊▊▊▊▊▊▊▊ │   │  ← code-bg with code-fg text
│      └──────────┘   │
│          Theme Name  │
└─────────────────────┘
```

Background fills with `body-bg`. Colored bars are rounded rectangles or thick
lines sampling the respective CSS variable colors. The card border highlights
when selected.

The cards need to read the theme CSS color values. Since the themes are defined
as CSS, the simplest approach is to duplicate the key color values as Swift
constants — a `ThemeColors` struct with light/dark variants for each theme,
kept in sync with the CSS files. This avoids parsing CSS at runtime.


## Verification

Build and run. Confirm:

- Cmd+, opens the settings window with a four-item sidebar
- Sidebar icons and labels match the spec
- General pane: lighting segmented control, readable column toggle, and quit
  toggle all work and persist across relaunch
- Theme pane: four preview cards displayed; selecting one changes the theme
  immediately in all open documents; selected card has a visual indicator
- Theme previews respect current lighting (show dark colors when in dark mode)
- Up Mode pane: appears in sidebar, pane is empty (placeholder)
- Down Mode pane: line numbers and word wrap toggles work and persist
- Existing menu items for lighting, theme, readable column, line numbers, and
  word wrap continue to function and stay in sync with the settings dialog
- "Quit when last window closes" no longer appears in the Window menu
