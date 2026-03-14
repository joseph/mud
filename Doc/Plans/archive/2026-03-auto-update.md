Plan: Auto-Update via Sparkle
===============================================================================

> Status: Complete


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

Four build configurations on the Mud app target: Debug-AppStore /
Release-AppStore (no Sparkle references) and Debug-Direct / Release-Direct
(`SPARKLE` compilation condition, `-framework Sparkle` linker flag,
`$(PROJECT_DIR)/Vendor/Sparkle` framework search path). Two shared schemes:
**Mud - Direct** and **Mud - AppStore**. A Copy Files build phase embeds
`Sparkle.framework`, with a belt-and-suspenders Run Script that strips it for
AppStore configurations.


### 2. Info.plist keys ✓

Added `SUFeedURL`, `SUPublicEDKey`, and `SUEnableAutomaticChecks` to
`App/Info.plist`. These keys are inert without the Sparkle framework, so they
are present in both configurations.


### 3. App code ✓

All Sparkle imports and usage are wrapped in `#if SPARKLE`. In App Store
builds, this code compiles out entirely.

**`App/CheckForUpdatesView.swift`** — `SparkleController` (static enum, single
point of updater access), `CheckForUpdatesViewModel` (KVO observer for
`canCheckForUpdates`), and `CheckForUpdatesView` (menu button).

**`App/MudApp.swift`** — "Check for Updates..." menu item after Settings,
guarded by `#if SPARKLE`. "Release Notes" added to the Help menu.

**`App/Settings/SettingsView.swift`** — `.updates` case added to `SettingsPane`
enum, guarded by `#if SPARKLE`.

**`App/Settings/UpdateSettingsView.swift`** — Radio-group picker for automatic
update mode (Off / Ask before installing / Install automatically), backed by
`@AppStorage` on Sparkle's own UserDefaults keys. Includes a "Check Now" button
and a release notes link.

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

Sparkle displays per-release notes in its update dialog via
`<sparkle:releaseNotesLink>` pointing at hosted HTML pages. Source is
`Doc/RELEASES.md` (hand-written, per-version sections). A Ruby script
(`.github/scripts/build-release-notes`) extracts each version's section and
renders HTML via the Mud CLI, producing per-version pages and a full history
page in `Site/releases/`. The `Site/` directory is committed to the repo; CI
uploads its contents to the website alongside the appcast.

**Local release workflow:**

1. Update `MARKETING_VERSION` in `App/Info.plist`
2. Add a section to `Doc/RELEASES.md` with compelling prose
3. Run `.github/scripts/build-release-notes` to generate `Site/releases/` HTML
4. Commit as: `VERSION: X.Y.Z`
5. Merge to the `main` branch
6. Tag the commit as `vX.Y.Z`
7. Push the tag to GitHub to trigger the release workflow


### 5. Release workflow scripts ✓

Three scripts in `.github/scripts/`, testable locally outside of CI:

- **`update-sparkle`** — downloads a Sparkle release and extracts the framework
  and CLI tools. Accepts an optional version argument (defaults to `2.9.0`).
- **`build-release-notes`** — Ruby script that extracts per-version sections
  from `Doc/RELEASES.md` and renders HTML via the Mud CLI.
- **`build-appcast`** — signs the DMG and generates a single-item
  `appcast.xml`. The appcast always contains only the latest release — no need
  to fetch or merge with a previous appcast.


### 6. Release workflow changes ✓

Updated `.github/workflows/release.yml`: scheme references changed from `Mud`
to `Mud - Direct` with `Release-Direct` configuration (the
`ENABLE_APP_SANDBOX=NO` override is no longer needed — the build configuration
handles it). Added a "Download Sparkle" step before "Resolve packages". Added a
"Build and publish appcast and site" step after "Create GitHub release" that
signs the DMG, generates the appcast, and deploys both the appcast and
`Site/releases/` to the website via SCP.


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

| File                                    | Change                                                      |
| --------------------------------------- | ----------------------------------------------------------- |
| `Vendor/Sparkle/`                       | Git-ignored; framework downloaded by script and CI          |
| `Mud.xcodeproj/project.pbxproj`         | Build configs, schemes, framework embed phase, linker flags |
| `App/Info.plist`                        | `SUFeedURL`, `SUPublicEDKey`, `SUEnableAutomaticChecks`     |
| `.gitignore`                            | Add `Vendor/Sparkle/`                                       |
| `.github/scripts/update-sparkle`        | New — download Sparkle framework + CLI tools                |
| `App/AppDelegate.swift`                 | Sparkle code removed (updater moved to SparkleController)   |
| `App/MudApp.swift`                      | `CheckForUpdatesView()` menu item; Release Notes help item  |
| `App/CheckForUpdatesView.swift`         | New — SparkleController, view model, menu button            |
| `App/Settings/SettingsView.swift`       | `.updates` pane (`#if SPARKLE`)                             |
| `App/Settings/UpdateSettingsView.swift` | New — radio-group picker, Check Now, release notes link     |
| `Doc/RELEASES.md`                       | Release notes in Markdown (already exists)                  |
| `Site/releases/`                        | Pre-rendered release notes HTML (generated by Ruby script)  |
| `.github/scripts/build-release-notes`   | New — Ruby script: extract + render release notes via Mud   |
| `.github/scripts/build-appcast`         | New — sign DMG, output appcast XML with releaseNotesLink    |
| `.github/workflows/release.yml`         | Download Sparkle, Release-Direct, appcast + site deploy     |
| `Doc/AGENTS.md`                         | File quick reference                                        |


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
