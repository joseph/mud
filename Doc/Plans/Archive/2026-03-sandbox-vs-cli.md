Plan: Sandbox vs CLI
===============================================================================

> Status: Complete


## Context

The `mud` CLI helper (`Contents/Helpers/mud`, `ENABLE_APP_SANDBOX = NO`) and
its shell dispatcher (`Contents/Resources/mud.sh`) cannot appear in a Mac App
Store build: all executables must be sandboxed, and shell scripts are not
accepted as bundle executables. The current build includes them
unconditionally.

The fix is two-pronged:

- **Xcode project**: gate CLI asset inclusion on `ENABLE_APP_SANDBOX`. Both
  Debug and Release already have `ENABLE_APP_SANDBOX = YES` in Xcode; the
  GitHub Action overrides it to `NO` for Developer ID builds. No new build
  configuration or custom build setting is needed.
- **Command Line settings pane**: replace the current sandboxed
  (manual-symlink) view with an alias-based guide, plus a link to a bundled
  Markdown document that covers both distribution channels.

Direct (Developer ID) distribution is unchanged.


## Part 1 — Xcode project changes

`Doc/` is a folder reference, so files added under `Doc/Guides/` are bundled
automatically. No resource-phase edit is needed for the guide document.

`openBundledDocument(_:)` uses `Bundle.main.url(forResource:withExtension:)`,
which only searches the root of `Contents/Resources/`. It needs an optional
`subdirectory` parameter to reach `Doc/Guides/`.


### 1.1 Strip CLI assets (new Run Script phase in Mud target)

Add a Run Script phase **after** the existing Copy Files phase. Name it "Strip
CLI assets (sandboxed)":

```sh
if [ "${ENABLE_APP_SANDBOX}" = "YES" ]; then
  rm -rf "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Helpers"
  rm -f  "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/mud.sh"
fi
```

This strips the CLI from all sandboxed builds (Debug, Release, App Store
archive) and leaves it in place for the GitHub Action's Developer ID build,
which overrides `ENABLE_APP_SANDBOX=NO`.


### 1.2 Gate the existing `chmod +x` script

The existing "ShellScript" Run Script phase should begin with:

```sh
[ "${ENABLE_APP_SANDBOX}" = "YES" ] && exit 0
```


## Part 2 — Swift and content changes

### 2.1 New guide document: `Doc/Guides/command-line.md`

Bundled automatically via the `Doc/` folder reference. Opened via
`DocumentController.openBundledDocument("command-line", subdirectory: "Doc/Guides")`.
Contains three sections:

- **App Store release** — alias setup using `Bundle.main.bundlePath`, what it
  enables, its limitations; tip about removing the alias before switching to
  the direct release
- **Direct release** — full `mud` CLI, rendering flags, install instructions
- **Browser output** — `-b` flag, data URI image embedding with `-u -b`,
  multi-file tab behaviour


### 2.2 `DocumentController.swift`

Add an optional `subdirectory: String? = nil` parameter to
`openBundledDocument(_:)`, forwarded to
`Bundle.main.url(forResource:withExtension:subdirectory:)`.


### 2.3 Revised `CommandLineSettingsView` (`App/Settings/CommandLineSettingsView.swift`)

Replace `manualInstallView` (and its `executablePath` property) with
`appStoreView`. Keep `automaticInstallView` (non-sandboxed) unchanged.

The new `appStoreView` shows:

- A short explanation of the alias approach
- The alias command as a copyable monospaced code line, with the path derived
  from `Bundle.main.bundlePath` so it reflects the actual install location
- A brief note on what it enables and where to put it
- An inline link sentence — e.g. "Learn more about **command-line usage** of
  Mud." — where the linked text closes the Settings window and opens the guide

Closing the window: `SettingsWindowController.shared.window?.close()` Opening
the guide:
`DocumentController.openBundledDocument("command-line", subdirectory: "Doc/Guides")`


### 2.4 `Doc/AGENTS.md` update

Add `command-line.md` to the Resources section of the key files list.


## Files changed

| File                                         | Change                                            |
| -------------------------------------------- | ------------------------------------------------- |
| `Doc/Guides/command-line.md`                 | New — bundled guide document                      |
| `App/DocumentController.swift`               | Add subdirectory parameter to openBundledDocument |
| `App/Settings/CommandLineSettingsView.swift` | Replace `manualInstallView` with `appStoreView`   |
| `Doc/AGENTS.md`                              | Add guide to Resources key files                  |
| `Mud.xcodeproj/project.pbxproj`              | New strip script phase, gate chmod+x phase        |


## Verification

### App Store build

1. Archive using the Mud scheme (Release configuration,
   `ENABLE_APP_SANDBOX = YES`).
2. Confirm `Contents/Helpers/` is absent from the archive.
3. Confirm `Contents/Resources/mud.sh` is absent.
4. Confirm `Contents/Resources/Doc/Guides/command-line.md` is present.
5. Open Settings → Command Line: the alias view appears.
6. Click the inline link: Settings closes, the guide opens in Mud.


### Direct distribution build

1. Trigger the GitHub Action (or archive with `ENABLE_APP_SANDBOX=NO`).
2. Confirm `Contents/Helpers/mud` and `Contents/Resources/mud.sh` are present.
3. Open Settings → Command Line: the automatic installer appears (unchanged).


### Runtime sandbox check

The `isSandboxed` guard continues to work correctly at runtime, so an
unsandboxed build shows the installer and a sandboxed build shows the alias
view.
