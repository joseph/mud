Setting preferences from the command line
===============================================================================

Mud keeps every user-visible preference in `UserDefaults.standard` under the
domain `org.josephpearson.Mud`. That means you can read, write, and reset any
preference from a terminal with the standard `defaults` tool — no plist-hacking
required, no hunting through Group Containers.

Writes made while Mud is running are picked up live: the app observes
`UserDefaults` per-key via KVO, so a `defaults write` hits the UI without a
relaunch. Every write also gets mirrored into the app-group suite so the Quick
Look extension renders with the same settings.

> Tip: Almost everything documented here has a toggle or picker in the Settings
> window. Reach for `defaults` when you want to script configuration, share
> settings between machines, or flip an option that does not have a UI.


## Basics

Read a value:

```sh
defaults read org.josephpearson.Mud theme
```

Read the entire Mud domain:

```sh
defaults read org.josephpearson.Mud
```

Write a value — the type flag matters because `defaults` infers a plain string
otherwise:

```sh
defaults write org.josephpearson.Mud theme -string earthy
defaults write org.josephpearson.Mud changes.enabled -bool true
defaults write org.josephpearson.Mud up-mode.zoom-level -float 1.25
defaults write org.josephpearson.Mud enabled-extensions -array mermaid copy-code
```

Remove a key (reverts to its built-in default on next read):

```sh
defaults delete org.josephpearson.Mud ui.floating-controls-position
```

Wipe every Mud preference in one go:

```sh
defaults delete org.josephpearson.Mud
```

> Note: Mud owns a handful of `internal.*` bookkeeping keys (launch state,
> window frame, CLI symlink path). They are not documented here — treat them as
> private and let Mud manage them.


## Appearance

### `lighting` — string

Controls the light/dark appearance of the app chrome and the rendered page
together.

- `auto` — follow the system appearance _(default)_
- `bright` — force light mode
- `dark` — force dark mode

```sh
defaults write org.josephpearson.Mud lighting -string dark
```


### `theme` — string

Selects the syntax-highlighting palette used in both Up and Down modes.

- `austere` — high-contrast monochrome
- `blues` — cool blue accents
- `earthy` — warm ochres _(default)_
- `riot` — saturated rainbow

```sh
defaults write org.josephpearson.Mud theme -string blues
```


### `ui.floating-controls-position` — string

Where the floating Changes bar anchors itself over the document.

- `topRight`
- `bottomRight`
- `bottomCenter` _(default)_

```sh
defaults write org.josephpearson.Mud ui.floating-controls-position -string topRight
```


### `ui.use-heading-as-title` — bool

When on, Mud uses the document's first heading as the window title instead of
the file name.

- Default: `true`

```sh
defaults write org.josephpearson.Mud ui.use-heading-as-title -bool false
```


### `ui.show-readable-column` — bool

Constrains the rendered body to a readable measure rather than filling the
window. Equivalent to **View → Readable Column** (⌃⌘R).

- Default: `false`

```sh
defaults write org.josephpearson.Mud ui.show-readable-column -bool true
```


## Up mode (rendered)

### `up-mode.zoom-level` — float

Zoom factor for Up mode, where `1.0` is actual size. Cmd-+ / Cmd-- / Cmd-0
write this key. Down mode has its own zoom level.

- Default: `1.0`
- Sensible range: `0.5` – `3.0`

```sh
defaults write org.josephpearson.Mud up-mode.zoom-level -float 1.25
```


### `up-mode.allow-remote-content` — bool

Allows `<img>` tags and other resources to load from `https://` URLs. When off,
Mud restricts the renderer to local `mud-asset:` and `data:` URLs only.

- Default: `true`

```sh
defaults write org.josephpearson.Mud up-mode.allow-remote-content -bool false
```


### `up-mode.show-code-header` — bool

Shows the small language label and copy button in the header of each fenced
code block.

- Default: `true`

```sh
defaults write org.josephpearson.Mud up-mode.show-code-header -bool false
```


## Down mode (source)

### `down-mode.zoom-level` — float

Zoom factor for Down mode. See `up-mode.zoom-level`; the two modes persist
independently.

- Default: `1.0`

```sh
defaults write org.josephpearson.Mud down-mode.zoom-level -float 0.9
```


### `down-mode.show-line-numbers` — bool

Shows a gutter of line numbers alongside the Markdown source.

- Default: `true`

```sh
defaults write org.josephpearson.Mud down-mode.show-line-numbers -bool false
```


### `down-mode.wrap-lines` — bool

Soft-wraps long lines in Down mode. When off, overflowing lines scroll
horizontally.

- Default: `true`

```sh
defaults write org.josephpearson.Mud down-mode.wrap-lines -bool false
```


## Sidebar

### `sidebar.enabled` — bool

Whether the sidebar is open when a new window is created. Equivalent to **View
→ Show Sidebar** (⌃⌘S or F3).

- Default: `false`

```sh
defaults write org.josephpearson.Mud sidebar.enabled -bool true
```


### `sidebar.pane` — string

Which pane the sidebar shows when it opens.

- `outline` — table of contents _(default)_
- `changes` — list of tracked changes

```sh
defaults write org.josephpearson.Mud sidebar.pane -string changes
```


## Change tracking

See [Change tracking](change-tracking.md) for the feature overview.


### `changes.enabled` — bool

Master on/off for the change-tracking feature. When off, Mud does not compute
or display diffs at all.

- Default: `true`

```sh
defaults write org.josephpearson.Mud changes.enabled -bool false
```


### `changes.show-inline-deletions` — bool

In Down mode, show the text of deleted lines inline in the gutter. When off,
only a deletion marker is shown.

- Default: `false`

```sh
defaults write org.josephpearson.Mud changes.show-inline-deletions -bool true
```


### `changes.show-git-waypoints` — bool

Include Git commit boundaries in the list of waypoints you can diff against, in
addition to in-session waypoints.

- Default: `false`

```sh
defaults write org.josephpearson.Mud changes.show-git-waypoints -bool true
```


### `changes.auto-expand-groups` — bool

Automatically expand collapsed change groups as they scroll into view.

- Default: `false`

```sh
defaults write org.josephpearson.Mud changes.auto-expand-groups -bool true
```


### `changes.word-diff-threshold` — float

Similarity threshold (0.0 – 1.0) that controls how aggressively Mud pairs
deleted and inserted lines for word-level diffing. Lower values pair more pairs
as edits rather than separate delete/insert operations.

- Default: `0.25`

```sh
defaults write org.josephpearson.Mud changes.word-diff-threshold -float 0.4
```


## Markdown parsing

### `markdown.docc-alert-mode` — string

Controls which DocC-style asides (`> Note:`, `> Tip:`, etc.) Mud renders as
styled alert callouts.

- `off` — never; treat every blockquote as a plain quote
- `common` — only the six canonical DocC kinds (note, tip, important, warning,
  experiment, and so on)
- `extended` — common kinds plus extended aliases _(default)_

```sh
defaults write org.josephpearson.Mud markdown.docc-alert-mode -string common
```


## Extensions

### `enabled-extensions` — array of strings

Which client-side render extensions are active. Extensions add runtime JS and
CSP sources to rendered pages; disabling one strips its scripts entirely.

- `mermaid` — Mermaid diagrams in `mermaid` fenced code blocks
- `copy-code` — the copy-to-clipboard button on code blocks
- Default: all registered extensions enabled

Write the full set you want active — `defaults write -array` replaces the
existing value, it does not merge.

```sh
defaults write org.josephpearson.Mud enabled-extensions -array mermaid
defaults write org.josephpearson.Mud enabled-extensions -array mermaid copy-code
defaults write org.josephpearson.Mud enabled-extensions -array
```

> Unknown extension names in the stored list are ignored silently, so upgrading
> to a Mud version that drops an extension will not error.


## Window and app behavior

### `quit-on-close` — bool

Quit Mud when the last window closes, rather than keeping the app running in
the background.

- Default: `true`

```sh
defaults write org.josephpearson.Mud quit-on-close -bool false
```


## Recipes

Reset a single preference to its built-in default:

```sh
defaults delete org.josephpearson.Mud ui.floating-controls-position
```

Export your current Mud preferences to share with another machine:

```sh
defaults export org.josephpearson.Mud ~/mud-prefs.plist
```

Import them on the other machine (close Mud first, or let KVO re-sync):

```sh
defaults import org.josephpearson.Mud ~/mud-prefs.plist
```

Switch to a minimal reading setup — earthy theme, dark, readable column, no
floating Changes bar:

```sh
defaults write org.josephpearson.Mud theme -string earthy
defaults write org.josephpearson.Mud lighting -string dark
defaults write org.josephpearson.Mud ui.show-readable-column -bool true
defaults write org.josephpearson.Mud changes.enabled -bool false
```
