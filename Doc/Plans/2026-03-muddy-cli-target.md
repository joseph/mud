Plan: Muddy CLI Target
===============================================================================

> Status: Planning


## Context

The current CLI feature embeds argument parsing and HTML rendering directly in
the Mud app binary, activated when the app is launched via a symlink. This
breaks under sandboxing: a sandboxed process cannot spawn child processes or
receive documents via command-line arguments. The feature is currently hidden
for sandboxed builds but the dead code remains in the app.

The new approach cleanly separates concerns:

- `muddy` — a standalone Swift command-line tool that renders Markdown to HTML
- `mud.sh` — a shell-script dispatcher (the user-facing `mud` command) that
  routes to `muddy` for rendering or to `open -a Mud.app` for GUI use
- The Mud app binary has no CLI awareness whatsoever


-------------------------------------------------------------------------------


## Overview of bundle layout after change

```
Mud.app/
  Contents/
    MacOS/
      Mud          ← GUI app (no CLI code)
      muddy        ← new Swift CLI tool
    Resources/
      mud.sh       ← new shell dispatcher (the installed symlink target)
      …
```


-------------------------------------------------------------------------------


## Step 1: Create the `muddy` Swift CLI target

### Source file

Create `App/CLI/main.swift`. The logic is adapted from
`App/CommandLineInterface.swift`'s `run()` method — the same argument parsing,
the same rendering calls into `MudCore`, the same `--browser` temp-file flow —
minus the `openInApp`, `launchedViaSymlink`, and system-flag-skipping code
(those are handled by `mud.sh`).

Key details:

- Import `Foundation` and `MudCore` only; no AppKit or SwiftUI.
- Error prefix stays `"mud: "` (users see `mud`, not `muddy`).
- Exit codes: 0 success, 1 argument error, 2 I/O error.
- `--version` prints `MudCore.version` (`App/CLI/main.swift` line TBD).
- `--browser` opens temp HTML files via `/usr/bin/open` using `Process`.
- `ImageDataURI.encode(source:baseURL:)` (public in `MudCore`) handles
  self-contained HTML for `--browser` + `-u`.
- Flags supported: `-u`/ `--html-up`, `-d`/ `--html-down`, `-b`/ `--browser`,
  `-f`/ `--fragment`, `--theme NAME`, `--line-numbers`, `--word-wrap`,
  `--readable-column`, `--help`/ `-h`, `--version`/ `-v`.

A bare `muddy` call (no render-mode flag) prints usage and exits with code 1.


### Xcode target setup (via Xcode GUI)

1. File > New > Target > macOS > Command Line Tool. Name: `muddy`. Language:
   Swift. Deployment target: macOS 14.0.
2. Replace the skeleton `main.swift` with our `App/CLI/main.swift`.
3. Under `muddy`'s Frameworks and Libraries, add `MudCore` (it's already a
   local package reference in the project).
4. Build settings: `ENABLE_APP_SANDBOX = NO`, `ENABLE_HARDENED_RUNTIME = YES`,
   `MACOSX_DEPLOYMENT_TARGET = 14.0`.


### Bundle `muddy` inside Mud.app

On the **Mud app target**:

1. Add `muddy` as a target dependency (Build Phases > Dependencies > `+`).
2. Add a **Copy Files** build phase: destination = Executables
   (`Contents/MacOS/`), add the `muddy` product.

This ensures `muddy` is built first and copied into the app bundle.


-------------------------------------------------------------------------------


## Step 2: Create and bundle `mud.sh`

### Script content (`App/mud.sh`)

```sh
#!/bin/sh
# mud — Mud.app CLI dispatcher
#
# Invoked with rendering flags (-u, -d, etc.): delegates to `muddy`.
# Invoked without rendering flags: opens files in the Mud GUI.

set -eu

# Resolve symlinks to find the real location of this script.
SOURCE="$0"
while [ -h "$SOURCE" ]; do
  DIR="$(cd "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  case "$SOURCE" in
    /*) ;;
    *) SOURCE="$DIR/$SOURCE" ;;
  esac
done
SCRIPT_DIR="$(cd "$(dirname "$SOURCE")" && pwd)"

# muddy is at Contents/MacOS/muddy; this script is at Contents/Resources/mud.sh
MUDDY="$(dirname "$SCRIPT_DIR")/MacOS/muddy"
BUNDLE="$(dirname "$(dirname "$SCRIPT_DIR")")"

if [ ! -x "$MUDDY" ]; then
  printf 'mud: muddy not found at %s\n' "$MUDDY" >&2
  exit 1
fi

# If any rendering or meta flag is present, delegate entirely to muddy.
for arg in "$@"; do
  case "$arg" in
    -u|--html-up|-d|--html-down|-b|--browser|-f|--fragment|\
    --line-numbers|--word-wrap|--readable-column|--theme|\
    -h|--help|-v|--version)
      exec "$MUDDY" "$@"
      ;;
  esac
done

# No rendering flags: open in the Mud GUI.
if [ $# -eq 0 ]; then
  if [ ! -t 0 ]; then
    # Piped stdin with no render flags — write to temp file and open in GUI
    tmp="$(mktemp /tmp/mud-stdin.XXXXXX.md)"
    cat > "$tmp"
    open -a "$BUNDLE" "$tmp"
  else
    open -a "$BUNDLE"
  fi
else
  open -a "$BUNDLE" "$@"
fi
```


### Bundling `mud.sh` (via Xcode GUI)

1. Add `App/mud.sh` to the project and to the **Mud app** Copy Bundle Resources
   phase. Xcode will copy it to `Contents/Resources/mud.sh`.
2. Add a **Run Script** build phase (after Copy Resources):

   ```sh
   chmod +x "$BUILT_PRODUCTS_DIR/$CONTENTS_FOLDER_PATH/Resources/mud.sh"
   ```

   Name it "Set mud.sh permissions". This ensures the execute bit survives.


-------------------------------------------------------------------------------


## Step 3: Update `CommandLineInstaller.swift`

**File:** `App/CommandLineInstaller.swift`

Change the symlink target from the app executable to `mud.sh` in Resources.

Replace lines 69–73:

```swift
// Before:
let executablePath = Bundle.main.executablePath ?? ""
guard !executablePath.isEmpty else {
    throw InstallError.noExecutablePath
}
```

With:

```swift
// After:
guard let resourcesURL = Bundle.main.resourceURL else {
    throw InstallError.noExecutablePath
}
let executablePath = resourcesURL.appendingPathComponent("mud.sh").path
```

Also update the `noExecutablePath` error description (line 52) from "Could not
determine the application executable path." to "Could not locate mud.sh in the
application bundle."

No other changes to `CommandLineInstaller.swift` are needed.


-------------------------------------------------------------------------------


## Step 4: Update `CommandLineSettingsView.swift`

**File:** `App/Settings/CommandLineSettingsView.swift`

The sandboxed manual-install view shows the executable path inline. Update the
`executablePath` computed property (lines 14–16) to point at `mud.sh`:

```swift
// Before:
private var executablePath: String {
    Bundle.main.executablePath ?? "/Applications/Mud.app/Contents/MacOS/Mud"
}
```

```swift
// After:
private var executablePath: String {
    Bundle.main.resourceURL?
        .appendingPathComponent("mud.sh")
        .path
        ?? "/Applications/Mud.app/Contents/Resources/mud.sh"
}
```

No other changes to this file are needed.


-------------------------------------------------------------------------------


## Step 5: Remove CLI code from the Mud app target

### `App/AppDelegate.swift`

Remove the CLI detection blocks from `applicationWillFinishLaunching` (lines
8–30). After removal, the method body becomes:

```swift
func applicationWillFinishLaunching(_ notification: Notification) {
    // Suppress system Edit menu items irrelevant for a read-only app
    UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
    UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")

    // Install our custom document controller before anything else
    _ = DocumentController()
}
```


### `App/CommandLineInterface.swift`

Delete this file from the filesystem and remove it from the Xcode project
(select in navigator, press Delete, choose "Move to Trash").


-------------------------------------------------------------------------------


## Verification

### Bundle structure

After building:

```sh
ls DerivedData/.../Mud.app/Contents/MacOS/
# Mud  muddy

ls -l DerivedData/.../Mud.app/Contents/Resources/mud.sh
# -rwxr-xr-x ... mud.sh
```


### `muddy` directly

```sh
echo "# Hello" | ./muddy -u              # full HTML doc on stdout
./muddy -d README.md | head -5           # syntax-highlighted HTML table
./muddy --version                        # mud 0.1.0
./muddy --help                           # usage text
./muddy README.md                        # exits with code 1 + usage (no mode flag)
```


### `mud.sh` dispatcher

```sh
# Rendering path
./mud.sh -u README.md | head -3          # delegates to muddy
echo "# Hi" | ./mud.sh -d               # stdin through muddy

# GUI path (requires Mud.app accessible via bundle path resolved from script)
./mud.sh README.md                       # opens README.md in Mud.app
./mud.sh                                 # opens Mud.app
echo "test" | ./mud.sh                   # writes temp file, opens in Mud.app
```


### Symlink flow

```sh
ln -sf /path/to/Mud.app/Contents/Resources/mud.sh /tmp/test-mud
/tmp/test-mud -u README.md | head -3     # renders via muddy
/tmp/test-mud README.md                  # opens in GUI
```


### Settings pane

- Non-sandboxed: Install button creates symlink → verify it points to `mud.sh`;
  verify installed `mud` command works.
- Sandboxed build: manual instruction shows `.../Resources/mud.sh` path.


### App launch

Launch `Mud.app` directly; confirm normal GUI startup with no CLI-related
console output.
