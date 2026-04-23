AGENTS Guide to Mud
===============================================================================

## Project overview

Mud (Mark Up & Down) is a macOS Markdown preview app targeting macOS Sonoma
(14.0+). Built with SwiftUI and AppKit. Opens .md files and offers two views:
"Mark Up" (rendered GFM with syntax highlighting) and "Mark Down"
(syntax-highlighted raw source with line numbers). Auto-reloads on file change.
Includes a CLI tool for HTML output. The user-facing `mud` command is a shell
script (`mud.sh`) bundled in the app that dispatches to a standalone `mud`
Swift executable (also bundled) for rendering, or to `open -a Mud.app` for GUI
use.

See [Doc/Plans/2026-02-mud-app.md](./Plans/2026-02-mud-app.md) for the original
MVP plan.


## Features

- GFM rendering with syntax highlighting (highlight.js)
- Two modes: Mark Up (rendered) and Mark Down (raw, syntax-highlighted)
- Space bar toggles modes; scroll position preserved
- Auto-reload on file change (DispatchSource)
- Manual reload (Cmd+R)
- Four themes: Austere, Blues, Earthy (default), Riot
- Lighting: Auto/Bright/Dark cycle
- Zoom In/Out/Actual Size (per-mode, persisted)
- Readable Column, Line Numbers, Word Wrap toggles
- Table of contents sidebar
- Find (Cmd+F), Find Next/Previous (Cmd+G, Cmd+Shift+G)
- Print / Save as PDF (Cmd+P)
- Open in Browser (Cmd+Shift+B) with image data-URI embedding
- Local images via custom `mud-asset:` URL scheme
- Remote images allowed
- Link handling: anchors, local .md, external URLs
- Quit on last window close
- CLI tool: `mud -u` / `-d` for HTML output, `-f` for fragment output, stdin
  support, theme and view-option flags


## Targets

- **Mud** (App/) -- macOS app, SwiftUI + AppKit hybrid
- **Mud CLI** (App/CLI/) -- standalone Swift CLI tool (`mud`), bundled in
  Mud.app
- **MudCore** (Core/) -- Swift Package, platform-independent rendering and
  syntax highlighting
- **MudPreferences** (Preferences/) -- Swift Package, Foundation-only
  preference persistence shared between the app and the Quick Look extension.
  Depends on MudCore.
- **QuickLook** (QuickLook/) -- `.appex` Quick Look preview extension, bundled
  in `Mud.app/Contents/PlugIns/`. Renders `.md` previews via MudCore and reads
  preferences from the app-group mirror via MudPreferences.
- **Thumbnail** (Thumbnail/) -- `.appex` Quick Look thumbnail extension,
  bundled in `Mud.app/Contents/PlugIns/`. Renders a portrait thumbnail from the
  file's first heading. Sandboxed; no app-group entitlement (so no
  MudPreferences access).


## File quick reference

**App/ key files:**

- `MudApp.swift` — @main, menu commands

- `AppState.swift` — Singleton observable state; persistence delegated to
  `MudPreferences.shared`

- `AppDelegate.swift` — Lifecycle and document handling

- `DocumentController.swift` — NSDocumentController subclass

- `DocumentWindowController.swift` — Per-window state, toolbar, zoom, lighting

- `DocumentState.swift` — Per-window observable state

- `DocumentContentView.swift` — Main SwiftUI view for a document

- `WebView.swift` — WKWebView wrapper, JS bridge

- `OutlineSidebarView.swift` — Table of contents sidebar

- `OutlineNode.swift` — Sidebar data model

- `FindFeature.swift` — Search state and UI

- `ChangesFeature.swift` — Floating Changes bar and overlay

- `GitProvider.swift` — Git history queries for external waypoints
  (`#if GIT_PROVIDER`)

- `FileWatcher.swift` — DispatchSource file monitoring

- `CommandLineInstaller.swift` — CLI symlink creation with elevation support

- `LocalFileSchemeHandler.swift` — `mud-asset:` URL scheme for local images

- `DeferMutation.swift` — Run-loop deferred state mutation helper

- `Lighting+AppKit.swift` — AppKit/SwiftUI behavior (`appearance`,
  `colorScheme`, `toggled()`, `systemIsDark`) on the bare `Lighting` enum that
  lives in MudPreferences

- `ErrorPage.swift` — Error-page HTML generator (renders Markdown via MudCore)

- `ChangesSidebarView.swift` — Changes pane listing tracked changes

- `SidebarView.swift` — Sidebar tab container (outline vs changes panes)

- `ReselectMonitor.swift` — NSViewRepresentable that detects clicks on
  already-selected List rows

- `TabReloadBadgeView.swift` — Small brown-dot NSView attached to
  `NSWindowTab.accessoryView` when a tab's document reloaded while the window
  was not key; cleared when the tab becomes key

- `View+Modify.swift` — SwiftUI `modify(_:)` view modifier helper

- `Date+Formatting.swift` — `shortTimestamp` formatting extension

- `CheckForUpdatesView.swift` — SparkleController (static updater owner),
  CheckForUpdatesViewModel (KVO observer), and menu button (`#if SPARKLE`)

**App/CLI/ key files:**

- `main.swift` — `mud` CLI: argument parsing, rendering via MudCore, stdout and
  browser output. No AppKit or SwiftUI.

- `mud.sh` — Shell dispatcher: routes to the bundled `mud` CLI when rendering
  flags are present, otherwise opens files in the Mud GUI via `open -a`.
  Bundled in `Contents/Resources/mud.sh`; the installed `mud` symlink points
  here. The `mud` CLI binary lives at `Contents/Helpers/mud` (not `MacOS/`, to
  avoid a case-insensitive filename collision with the `Mud` app executable).

**App/Settings/ key files:**

- `SettingsView.swift` — Settings window root with NavigationSplitView sidebar

- `GeneralSettingsView.swift` — General settings pane

- `ThemeSettingsView.swift` — Theme selection pane with preview cards

- `ThemePreviewCard.swift` — Theme color constants and preview card view

- `MarkdownSettingsView.swift` — Markdown settings pane (DocC alert mode)

- `UpModeSettingsView.swift` — Up Mode settings pane (Allow Remote Content,
  Mermaid Diagrams)

- `DownModeSettingsView.swift` — Down Mode settings pane

- `ChangesSettingsView.swift` — Changes settings pane (inline deletions, git
  waypoints toggle)

- `CommandLineSettingsView.swift` — Command Line settings pane

- `UpdateSettingsView.swift` — Updates pane: auto-update radio group, Check
  Now, release notes link (`#if SPARKLE`)

- `SettingsWindowController.swift` — Settings window lifecycle (singleton
  NSWindowController)

- `CSSColors.swift` — CSS hex color parsing extension on `Color`

- `LightingPreviewCard.swift` — Lighting selection preview card

- `DebuggingSettingsView.swift` — Debugging pane (debug builds only; reset
  preferences)

**Preferences/ key files:**

- `MudPreferences.swift` — Struct with `.shared`. Source of truth is
  `UserDefaults.standard`; every write is mirrored into the Team-ID-prefixed
  app-group suite `XVL2AFNXH5.org.josephpearson.Mud` so the Quick Look
  extension can read a snapshot. Holds the `Keys` enum, per-key read/write
  methods, and `reset()`.

- `MudPreferencesMigration.swift` — `migrateLegacyKeys()` renames legacy
  `Mud-*` keys in `UserDefaults.standard` to the lowercase-hyphen names;
  `syncMirror()` fans every current `defaults` value into the mirror (so
  `defaults write` changes made while the app was not running get picked up).
  `migrate()` runs both and is called once at launch.

- `MudPreferencesSnapshot.swift` — Value-type snapshot of the prefs that flow
  into `RenderOptions`, plus derived `upModeHTMLClasses`. Consumed by the Quick
  Look extension.

- `Theme.swift` — austere/blues/earthy/riot enum

- `Lighting.swift` — auto/bright/dark enum (bare; AppKit behavior in
  `App/Lighting+AppKit.swift`)

- `Mode.swift` — up/down enum

- `ViewToggle.swift` — readableColumn/lineNumbers/wordWrap/codeHeader/
  autoExpandChanges toggles; `isEnabled`/ `save(_:)` delegate to
  `MudPreferences.shared`

- `SidebarPane.swift` — outline/changes enum

- `FloatingControlsPosition.swift` — Top right / bottom right / bottom center
  enum for floating bar placement

**Core/ key files:**

- `ParsedMarkdown.swift` — Parse-once handle: AST, headings, and title
- `RenderExtension.swift` — Client-side rendering extension type and registry
- `RenderOptions.swift` — Rendering configuration value type
- `MudCore.swift` — Public API: rendering functions (String and ParsedMarkdown
  overloads), extractHeadings convenience
- `Rendering/UpHTMLVisitor.swift` — AST → rendered HTML
- `Rendering/DownHTMLVisitor.swift` — AST → syntax-highlighted raw HTML
- `Rendering/HTMLDocument.swift` — Structured HTML document builder
- `Rendering/HTMLTemplate.swift` — Document wrapping and resource loading
- `Rendering/MarkdownParser.swift` — swift-cmark wrapper
- `Rendering/SlugGenerator.swift` — Heading ID generation
- `Rendering/HeadingExtractor.swift` — Heading extraction for sidebar
- `Rendering/CodeHighlighter.swift` — Syntax highlighting via highlight.js
- `Rendering/EmojiShortcodes.swift` — `:shortcode:` → emoji replacement
- `Rendering/AlertDetector.swift` — GFM alert and DocC aside detection and
  rendering
- `Rendering/HTMLEscaping.swift` — Shared HTML entity escaping utilities
- `Rendering/HTMLLineSplitter.swift` — Splits HTML by line while preserving
  `<span>` tag balance (for diff display)
- `Rendering/ImageDataURI.swift` — Image encoding for browser export
- `OutlineHeading.swift` — Heading model shared between Core and App
- `Diff/BlockMatcher.swift` — Block-level diff: leaf block collection,
  fingerprinting, `CollectionDifference` matching
- `Diff/LineLevelDiff.swift` — Shared line-level diff algorithm used by both
  `CodeBlockDiff` and `LineDiffMap`
- `Diff/LineDiffMap.swift` — Down mode change tracking: line-level annotations,
  deletion groups, per-line word data (separate del/ins maps)
- `Diff/CodeBlockDiff.swift` — Line-level diff within paired code blocks (Up
  mode): highlighted HTML, change IDs, group IDs, word markers
- `Diff/DiffContext.swift` — Up mode change tracking: block annotations,
  rendered deletions, group info, code block diffs, word spans
- `Diff/WordDiff.swift` — Word-level diff and inline text extraction
- `Diff/WordPairing.swift` — Best-match pairing of deleted/inserted lines by
  word overlap (greedy algorithm)
- `Diff/ChangeList.swift` — Sidebar change list computed from `DiffContext`
- `Diff/ChangeGroup.swift` — Group consecutive changes by `groupID` for
  navigation and counts
- `ChangeTracker.swift` — Waypoint history, active waypoint selection, menu
  item computation with caching

**QuickLook/ key files:**

- `PreviewProvider.swift` — `MudPreviewProvider`, an `NSViewController`
  subclass conforming to `QLPreviewingController` (view-based, not data-based —
  required for Finder's column-view preview pane to live-render our output).
  Hosts a `WKWebView`. Reads the shared configuration snapshot from the
  app-group `UserDefaults` suite and renders the preview as self-contained HTML
  via `MudCore.renderUpModeDocument`. Inlines local images as data URIs via
  `ImageDataURI.encode`.
- `Info.plist` — `NSExtensionPointIdentifier = com.apple.quicklook.preview`,
  `NSExtensionPrincipalClass = MudPreviewProvider`,
  `QLSupportedContentTypes = [net.daringfireball.markdown]`.
- `QuickLook.entitlements` / `QuickLookDirect.entitlements` — sandboxed
  extension. MAS variant carries app-sandbox, network.client, and the app-group
  entitlement. Direct variant adds a read-only absolute-path temporary
  exception so the extension can inline sibling images into previews. Selected
  per build config via `CODE_SIGN_ENTITLEMENTS`, same pattern as
  `App/Mud.entitlements` / `App/MudDirect.entitlements`.

**Thumbnail/ key files:**

- `ThumbnailProvider.swift` — `MudThumbnailProvider`, a `QLThumbnailProvider`
  subclass. Returns the largest 3:4-portrait size that fits inside
  `QLFileThumbnailRequest.maximumSize`, fills it flat with the card grey, draws
  the file's first heading (via `MudCore.extractHeadings`, falling back to the
  filename), then composites the bundled `thumbnail-dynamic.png` drip on top.
  No explicit clipping: the drip overlay visually swallows headings that wrap
  into its territory. Finder wraps the reply in its own paper chrome at the
  reply's aspect.
- `Info.plist` — `NSExtensionPointIdentifier = com.apple.quicklook.thumbnail`,
  `NSExtensionPrincipalClass = MudThumbnailProvider`,
  `QLSupportedContentTypes = [net.daringfireball.markdown]`,
  `QLThumbnailMinimumDimension = 64` (smaller requests fall through to the
  static `.icns`).
- `Thumbnail.entitlements` / `ThumbnailDirect.entitlements` — sandbox only. No
  network, no app-group, no temporary exceptions: the extension reads the file
  URL the system hands it and its own bundled overlay image.
- `Resources/thumbnail-dynamic.png` — 768×1024 drip overlay: muddy drip with a
  transparent top and sides, exported directly from the design tool. Drawn on
  top of the heading so any wrapped text flowing into the drip's region gets
  visually absorbed.
- `Resources/thumbnail-static.svg` — source for the static `.icns` document
  icon; rasterized by `.claude/tmp/build-document-icon`.

**Resources:**

- `mud.css` — Shared styles and lighting variables
- `mud-up.css` — Up mode styles
- `mud-down.css` — Down mode styles
- `mud.js` — Shared JS: find, scroll, lighting, zoom
- `mud-changes.js` — Change tracking JS: overlays, expand/collapse, navigation
- `mud-up.js` — Up-mode JS
- `mud-down.js` — Down-mode JS
- `emoji.json` — GitHub gemoji shortcode database
- `alert-*.svg` — Octicon alert icons (note, tip, important, warning, caution,
  status)
- `theme-*.css` — Four user-selectable theme files (austere, blues, earthy,
  riot)
- `theme-system.css` — System theme (internal; not user-selectable; used for
  error pages)
- `mermaid.min.js` — Mermaid diagram library (v11, UMD build)
- `mermaid-init.js` — Mermaid init script for Up mode rendering
- `Doc/Guides/command-line.md` — Bundled guide: CLI usage for App Store and
  direct distribution builds

**Scripts and CI:**

- `.github/scripts/update-sparkle` — Download Sparkle framework and CLI tools
  to `Vendor/Sparkle/`
- `.github/scripts/build-appcast` — Sign DMG and generate single-item
  `appcast.xml`
- `.github/scripts/build-release-notes` — Ruby script: extract per-version
  sections from `Doc/RELEASES.md` and render HTML via Mud CLI

**Doc:**

- `Doc/RELEASES.md` — User-facing release notes (hand-written, per-version
  sections)
- `Site/releases/` — Pre-rendered release notes HTML (generated by
  `build-release-notes`)

**Important** — Make sure to update this section of `Doc/AGENTS.md` if you add
or remove key files.


## Rendering pipeline

```
RenderOptions (configuration value type)
  ↓
Markdown string (up mode)
  → MarkdownParser (cmark-gfm) → AST
  → UpHTMLVisitor → rendered HTML body (SlugGenerator adds heading IDs)
  → HTMLTemplate.wrapUp() → full HTML document (CSS + JS inlined)
  → WKWebView

Markdown string (down mode)
  → DownHTMLVisitor → syntax-highlighted HTML table with spans
  → HTMLTemplate.wrapDown() → full HTML document (CSS + JS inlined)
  → WKWebView
```

Both modes render into the same WKWebView; toggling mode swaps the HTML
document.

All public rendering functions accept a `RenderOptions` value that bundles
configuration (theme, baseURL, docCAlertMode, etc.). Call sites build a
`RenderOptions` and pass it through; adding new options requires only a new
field on the struct.

MudCore exposes: `renderUpToHTML(_:options:)`, `renderDownToHTML(_:options:)`,
`renderUpModeDocument(_:options:)`, `renderDownModeDocument(_:options:)`,
`extractHeadings(_:)`.


## State management

Three ObservableObject classes, no nesting:

- **AppState** (singleton) -- `lighting`, `theme`, `modeInActiveTab`,
  `viewToggles`, zoom levels, `sidebarVisible`
- **DocumentState** (per-window) -- `mode`, action triggers (`printID`,
  `reloadID`, `openInBrowserID`), `outlineHeadings`, `scrollTarget`, owns
  `FindState`
- **FindState** -- search text, visibility, match info; Combine subscriber on
  `$searchText` auto-triggers queries

State flows outward via `@ObservedObject`. Combine sinks in
`DocumentWindowController` bridge state → AppKit (window appearance, toolbar
icons). `AppState`'s `@Published` `didSet` observers persist each change by
assigning to the corresponding `MudPreferences.shared.<pref>` property.


## Communication patterns

| Mechanism           | Used for                                         |
| ------------------- | ------------------------------------------------ |
| NotificationCenter  | Menu → views (reload, print, browser, zoom)      |
| Responder chain     | Menu → window controller (toggle, find)          |
| Combine sinks       | State → AppKit side effects                      |
| JS bridge (`Mud.*`) | Swift ↔ WKWebView (find, scroll, lighting, zoom) |
| Direct mutation     | Toolbar buttons → state objects                  |

Menu commands that need the WKWebView use notifications so
`DocumentContentView` can filter by `controlActiveState == .key` (prevents
multi-window conflicts). Toolbar actions use the responder chain reaching
`DocumentWindowController`.


## Key conventions

- **No NSDocument subclass.** `DocumentController` creates
  `DocumentWindowController` instances directly. Documents are just URLs +
  window controllers.
- **Single WebView, HTML swap.** Mode toggle replaces the HTML document (up vs
  down template). Both modes share one `WKWebView` instance.
- **Content identity via string hash.** `WebView` compares content to avoid
  unnecessary reloads.
- **JavaScript namespace.** All JS functions are under `Mud.*` (find, scroll,
  lighting, zoom). Shared code in `mud.js`; mode-specific code in `mud-up.js` /
  `mud-down.js`. Injected as WKUserScript.
- **Lighting = CSS + AppKit.** CSS variables for web content;
  `NSWindow.appearance` for AppKit chrome. Both set from a single Combine sink.
- **Themes.** Four theme files (`theme-*.css`); active theme selected via
  `AppState.theme` and applied as a CSS class.
- **ViewToggle.** Persisted boolean preferences (readable column, line numbers,
  word wrap) mapped to CSS classes on the body element via `bodyClasses`.
- **Extension principal classes.** Quick Look and Thumbnail providers use
  `@objc(ClassName)` so `NSExtensionPrincipalClass` in each `Info.plist`
  resolves without Swift module-name mangling.


### Sandbox-aware features

The app detects sandboxing at runtime via `isSandboxed` (checks
`APP_SANDBOX_CONTAINER_ID`). When sandboxed (Mac App Store build), certain
features are hidden or adapted:

- **CLI installer** — The Command Line settings pane shows manual `ln -s`
  instructions instead of the automatic Install button.
- **Open in Browser** — Hidden entirely. The feature writes a temp HTML file
  for the default browser to open, but sandboxed temp locations aren't readable
  by other apps, so the handoff can't work.

These features use `if !isSandboxed` guards in menus, context menus, and
settings views. No build-time flags are needed — a single binary supports both
distribution channels.


### Deferred mutations in SwiftUI

SwiftUI event handlers (`onKeyPress`, `onChange`, `updateNSView`, Combine sinks
triggered during view updates, etc.) run inside the view-update pipeline.
Setting an `@Published` property there causes:

```
Publishing changes from within view updates is not allowed,
this will cause undefined behavior.
```

Use `deferMutation` (defined in `App/DeferMutation.swift`) to push the mutation
to the next run-loop iteration. Applies to any code path that mutates
`@Published` state and can be reached from a SwiftUI view-update context. Do
**not** use `deferMutation` for unrelated async dispatch such as thread-hopping
from background callbacks or intentional delays.
