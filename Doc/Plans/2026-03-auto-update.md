Plan: Auto-Update via Sparkle
===============================================================================

> Status: Underway


## Context

Mud's direct distribution (Developer ID signed, notarized DMGs via GitHub
Releases) has no update mechanism. Users must manually check for new releases.
The conventional solution for macOS apps outside the App Store is Sparkle 2.

The Mac App Store build must not contain Sparkle at all — Apple rejects apps
that bundle update frameworks, even if the code is never called. This rules out
SPM (which unconditionally links and embeds the dynamic framework for all build
configurations). Instead, Sparkle is embedded manually with per-configuration
linker flags, so the App Store binary never references it.


## Approach

Embed Sparkle 2 as a manually managed framework (git-ignored, downloaded in CI)
with per-configuration build settings. Create four build configurations:
Debug-AppStore, Release-AppStore (for App Store), and Debug-Direct,
Release-Direct (for direct distribution). Only the Direct configurations link
and embed the framework. All Sparkle-related code is wrapped in `#if SPARKLE`.
Two Xcode schemes select the appropriate configurations.

On launch (Sparkle builds only), initialize the updater. Add a "Check for
Updates..." menu item and an "Updates" settings pane. Modify the release
workflow to EdDSA-sign the DMG and publish an appcast with release notes.


## Prerequisites (manual, one-time)

All prerequisites are complete.

1. ~~**Generate EdDSA key pair**~~ — done via
   `Vendor/Sparkle/bin/generate_keys`. Public key added to `App/Info.plist` as
   `SUPublicEDKey`.
2. ~~**Store private key**~~ — stored as GitHub Actions secret
   `SPARKLE_PRIVATE_KEY`.
3. ~~**Website deploy access**~~ — SSH key pair generated, public key added to
   server. Stored as GitHub Actions secrets: `WEBSITE_SSH_KEY`,
   `WEBSITE_SSH_USER`, `WEBSITE_SSH_HOST`. Appcast destination directory exists
   on the server.
4. ~~**Download Sparkle 2 locally**~~ — `.github/scripts/update-sparkle`
   created and run. Sparkle 2.9.0 framework and CLI tools installed to
   `Vendor/Sparkle/` (git-ignored).


## Implementation

### 1. Build configurations and schemes ✓

Done. Four build configurations on the Mud app target:

- **Debug-AppStore / Release-AppStore** — no Sparkle references.
- **Debug-Direct / Release-Direct** — `SPARKLE` compilation condition,
  `-framework Sparkle` linker flag, `$(PROJECT_DIR)/Vendor/Sparkle` framework
  search path.

Two shared schemes: **Mud - Direct** (Debug-Direct / Release-Direct) and **Mud
\- AppStore** (Debug-AppStore / Release-AppStore).

Copy Files build phase embeds `Sparkle.framework`, with a belt-and-suspenders
Run Script that strips it for AppStore configurations.


### 2. Info.plist keys ✓

Done. Added `SUFeedURL`, `SUPublicEDKey`, and `SUEnableAutomaticChecks` to
`App/Info.plist`. These keys are inert without the Sparkle framework, so they
are present in both configurations.


### 3. App code ✓

All Sparkle imports and usage are wrapped in `#if SPARKLE`. In App Store
builds, this code compiles out entirely.

**`App/CheckForUpdatesView.swift`** — Contains three components, all wrapped in
`#if SPARKLE`:

- `SparkleController` — a static enum that owns the
  `SPUStandardUpdaterController` and exposes its `SPUUpdater` via a computed
  property. This is the single point of access to the updater throughout the
  app. Initialized eagerly as a static property so the updater is available
  before SwiftUI evaluates any view bodies.
- `CheckForUpdatesViewModel` — observes `canCheckForUpdates` via KVO using
  `assign(to: &$canCheckForUpdates)` (no cancellable, no retain cycle).
  Parameterless init — reads the updater from `SparkleController`.
- `CheckForUpdatesView` — a `Button` for the app menu, disabled when the
  updater can't check. Uses `@StateObject` for the view model.

**`App/MudApp.swift`** — "Check for Updates..." menu item after Settings,
guarded by `#if SPARKLE`. No parameters passed — `CheckForUpdatesView()` is
self-contained. Also adds "Release Notes" to the Help menu (opens bundled
`Doc/RELEASES.md`).

**`App/Settings/SettingsView.swift`** — `.updates` case added to `SettingsPane`
enum, guarded by `#if SPARKLE`. Routes to `UpdateSettingsView()` with no
parameters.

**`App/Settings/UpdateSettingsView.swift`** — Settings pane with a single
radio-group picker ("Automatic updates") offering three modes: Off, Ask before
installing, Install automatically. Backed by two `@AppStorage` properties using
Sparkle's own UserDefaults keys (`SUEnableAutomaticChecks` and
`SUAutomaticallyUpdate`), so changes from Sparkle's dialogs and the settings
pane stay in sync. Default: "Ask before installing" (auto-check on,
auto-install off). Includes a "Check Now" button that calls
`SparkleController.updater.checkForUpdates()` directly, and a release notes
link to the project website.

**`App/AppDelegate.swift`** — No Sparkle code. The updater lifecycle is fully
managed by `SparkleController`.


#### Design notes

- **`SparkleController` rather than `AppDelegate`** — SwiftUI's
  `@NSApplicationDelegateAdaptor` wraps the delegate, so
  `NSApp.delegate as? AppDelegate` fails. A static enum avoids the problem
  entirely and gives the updater a single, reliable access path.
- **`@AppStorage` rather than `SPUUpdater` bindings** — manual
  `Binding(get:set:)` to the updater's properties doesn't trigger SwiftUI
  re-renders (no `@Published`, no `@State` change). Since Sparkle stores
  preferences in UserDefaults, `@AppStorage` reads and writes the same backing
  store with full SwiftUI reactivity.
- **Radio group rather than two toggles** — auto-install without auto-check is
  nonsensical. A three-mode picker eliminates the impossible state.


### 4. Release notes ✓

Sparkle displays per-release notes in its update dialog. Rather than embedding
HTML inline in the appcast, use `<sparkle:releaseNotesLink>` to point at hosted
HTML pages. This keeps the appcast simple and gives us web-browsable release
notes as a bonus.

**Source:** `Doc/RELEASES.md` (already exists in the repo). Each release gets a
`## vX.Y.Z` heading followed by prose describing what changed. This is written
by hand as part of the release workflow — it's not a mechanical changelog, it's
user-facing copy.

**Rendering:** a Ruby script (`.github/scripts/build-release-notes`) extracts
each version's section from `Doc/RELEASES.md` and calls the Mud CLI to render
it to HTML. It produces two outputs:

- `Site/releases/vX.Y.Z.html` — per-version release notes page
- `Site/releases/history.html` — full release history (the entire
  `Doc/RELEASES.md` rendered)

The `Site/` directory is committed to the repo. CI uploads its contents to the
website alongside the appcast.

**Local release workflow:**

1. Update `MARKETING_VERSION` in `App/Info.plist`
2. Add a section to `Doc/RELEASES.md` with compelling prose
3. Run `.github/scripts/build-release-notes` to generate `Site/releases/` HTML
4. Commit as: `VERSION: X.Y.Z`
5. Merge to the `main` branch
6. Tag the commit as `vX.Y.Z`
7. Push the tag to GitHub to trigger the release workflow


### 5. Release workflow scripts ✓

The release workflow's Sparkle-related logic lives in scripts under
`.github/scripts/`, testable locally outside of CI.

**`.github/scripts/update-sparkle`** — downloads a Sparkle release and extracts
the framework and CLI tools. Used by both developers (for the framework) and CI
(for the framework + `sign_update` tool). Accepts an optional version argument
(defaults to `2.9.0`).

**`.github/scripts/build-release-notes`** — Ruby script that reads
`Doc/RELEASES.md`, extracts each version section, and renders HTML via the Mud
CLI. Produces `Site/releases/vX.Y.Z.html` for each version and
`Site/releases/history.html` for the full document.

**`.github/scripts/build-appcast`** — given a signed DMG, generates an
`appcast.xml` containing a single item for the current release. Uses
`<sparkle:releaseNotesLink>` pointing at the hosted per-version HTML page.

The appcast always contains only the latest release. Sparkle checks whether the
appcast has a version newer than what's installed, so a single-item appcast
works for users on any older version. This avoids fetching and merging with a
previous appcast from the website — eliminating a network dependency and the
risk of silently losing previous entries if the server is unreachable.

All three scripts live in `.github/scripts/` (not in the git-ignored
`Vendor/Sparkle/` directory).


### 6. Release workflow changes

Modify `.github/workflows/release.yml`:

**Update the scheme references** — the old `-scheme Mud` no longer exists.
Update both the "Resolve packages" and "Archive" steps:

```yaml
- name: Resolve packages
  run: |
    xcodebuild -resolvePackageDependencies \
      -project Mud.xcodeproj \
      -scheme "Mud - Direct"
```

```yaml
- name: Archive
  run: |
    xcodebuild archive \
      -project Mud.xcodeproj \
      -scheme "Mud - Direct" \
      -configuration Release-Direct \
      -archivePath "$RUNNER_TEMP/Mud.xcarchive" \
      CODE_SIGN_STYLE=Manual \
      "CODE_SIGN_IDENTITY=Developer ID Application" \
      DEVELOPMENT_TEAM=XVL2AFNXH5
```

Note: the `ENABLE_APP_SANDBOX=NO` command-line override that was in the
original workflow is no longer needed — the `Release-Direct` build
configuration now sets `ENABLE_APP_SANDBOX = NO` at the project level, along
with its own entitlements file (`App/MudDirect.entitlements`).

**Add a "Download Sparkle" step before "Resolve packages"** — this provides
both the framework (for the build) and `sign_update` (for appcast generation):

```yaml
- name: Download Sparkle
  run: .github/scripts/update-sparkle
```

**Add appcast and site deploy steps after "Create GitHub release":**

```yaml
- name: Build and publish appcast and site
  env:
    SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
    WEBSITE_SSH_KEY: ${{ secrets.WEBSITE_SSH_KEY }}
    WEBSITE_SSH_USER: ${{ secrets.WEBSITE_SSH_USER }}
    WEBSITE_SSH_HOST: ${{ secrets.WEBSITE_SSH_HOST }}
  run: |
    VERSION=${{ steps.version.outputs.version }}
    TAG=${{ steps.version.outputs.tag }}
    DMG="Mud-${TAG}.dmg"

    # Write key files
    echo "$SPARKLE_PRIVATE_KEY" > "$RUNNER_TEMP/sparkle_key"
    echo "$WEBSITE_SSH_KEY" > "$RUNNER_TEMP/deploy_key"
    chmod 600 "$RUNNER_TEMP/deploy_key"

    # Build appcast (single-item, no fetch needed)
    .github/scripts/build-appcast \
      "$DMG" "$VERSION" "$RUNNER_TEMP/sparkle_key" \
      > appcast.xml

    # Publish appcast and release notes
    scp -i "$RUNNER_TEMP/deploy_key" -o StrictHostKeyChecking=no \
      appcast.xml \
      "${WEBSITE_SSH_USER}@${WEBSITE_SSH_HOST}:mud/appcast.xml"
    scp -i "$RUNNER_TEMP/deploy_key" -o StrictHostKeyChecking=no \
      -r Site/releases/ \
      "${WEBSITE_SSH_USER}@${WEBSITE_SSH_HOST}:mud/releases/"

    # Clean up
    rm -f "$RUNNER_TEMP/sparkle_key" "$RUNNER_TEMP/deploy_key"
```


### 7. Documentation ✓

`Vendor/Sparkle/` added to `.gitignore`. `Doc/AGENTS.md` file quick reference
updated with all new files.


## Why not SPM?

Sparkle's SPM package ships as a pre-built dynamic framework. When added via
SPM, Xcode unconditionally links and embeds the framework for all build
configurations — there is no per-configuration toggle. The Mach-O binary gets
an `LC_LOAD_DYLIB` load command referencing `Sparkle.framework`, which means:

- Stripping the framework from the bundle post-build causes a dyld crash at
  launch.
- Weak linking doesn't help — Apple rejects apps that weak-link frameworks they
  don't ship.
- SPM package traits (SE-0450) can't gate binary targets per build
  configuration.

Manual framework embedding with per-configuration `OTHER_LDFLAGS` is the
standard solution. The App Store binary never links Sparkle — no load command,
no framework in the bundle, no rejection.


## Files changed

| File                                    | Change                                                      | Status |
| --------------------------------------- | ----------------------------------------------------------- | ------ |
| `Vendor/Sparkle/`                       | Git-ignored; framework downloaded by script and CI          | ✓      |
| `Mud.xcodeproj/project.pbxproj`         | Build configs, schemes, framework embed phase, linker flags | ✓      |
| `App/Info.plist`                        | `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`     | ✓      |
| `.gitignore`                            | Add `Vendor/Sparkle/`                                       | ✓      |
| `.github/scripts/update-sparkle`        | New — download Sparkle framework + CLI tools                | ✓      |
| `App/AppDelegate.swift`                 | Sparkle code removed (updater moved to SparkleController)   | ✓      |
| `App/MudApp.swift`                      | `CheckForUpdatesView()` menu item; Release Notes help item  | ✓      |
| `App/CheckForUpdatesView.swift`         | New — SparkleController, view model, menu button            | ✓      |
| `App/Settings/SettingsView.swift`       | `.updates` pane (`#if SPARKLE`)                             | ✓      |
| `App/Settings/UpdateSettingsView.swift` | New — radio-group picker, Check Now, release notes link     | ✓      |
| `Doc/RELEASES.md`                       | Release notes in Markdown (already exists)                  | ✓      |
| `Site/releases/`                        | Pre-rendered release notes HTML (generated by Ruby script)  | ✓      |
| `.github/scripts/build-release-notes`   | New — Ruby script: extract + render release notes via Mud   | ✓      |
| `.github/scripts/build-appcast`         | New — sign DMG, output appcast XML with releaseNotesLink    | ✓      |
| `.github/workflows/release.yml`         | Download Sparkle, Release-Direct, appcast + site deploy     | ✓      |
| `Doc/AGENTS.md`                         | File quick reference                                        | ✓      |


## Verification

### UI verification

1. Build with the **Mud - Direct** scheme — confirm "Check for Updates..."
   appears in app menu, and "Updates" appears in Settings sidebar.
2. Build with the **Mud - AppStore** scheme — confirm both are absent.
3. Inspect the App Store binary with `otool -L` — confirm no reference to
   `Sparkle.framework`.


### Production verification

1. Tag a real release — verify the workflow generates `appcast.xml` with
   release notes and uploads it to
   `https://apps.josephpearson.org/mud/appcast.xml`.
2. With the previous version installed, launch and trigger "Check for Updates"
   — verify Sparkle finds and offers the new version with the correct release
   notes.
