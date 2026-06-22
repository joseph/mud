AGENTS Guide to Mud
===============================================================================

## Project overview

Mud (Mark Up & Down) is a macOS Markdown preview app targeting macOS Sonoma
(14.0+). Built with SwiftUI and AppKit. Opens .md files and offers two views:
"Mark Up" (rendered GFM with syntax highlighting) and "Mark Down"
(syntax-highlighted raw source with line numbers). Auto-reloads on file change.
The user-facing `mud` command is a shell script (`mud.sh`) bundled in the app
that dispatches to a standalone `mud` Swift executable (also bundled) for
rendering, or to `open -a Mud.app` for GUI use.

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
- Comments: attach threaded comments to selected text, written to the document
  as GFM footnotes
- Find (Cmd+F), Find Next/Previous (Cmd+G, Cmd+Shift+G)
- Print / Save as PDF (Cmd+P)
- Open In Browser (Cmd+Shift+B) with image data-URI embedding
- Local images via custom `mud-asset:` URL scheme; remote images allowed
- Link handling: anchors, local .md, external URLs
- Quit on last window close
- CLI tool: `mud -u` / `-d` for HTML output, `-f` for fragment output, stdin
  support, theme and view-option flags, `--primer` for the agent authoring
  guide


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
  file's first heading. Sandboxed; no app-group entitlement.


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
- `FootnotePopover.swift` — Transient `NSPopover` hosting a `WKWebView` that
  renders a footnote body
- `CommentController.swift` — The comment write path: re-read from disk,
  byte-surgical edit via `CommentEditor`, atomic security-scoped write
  (add/reply/edit-last/delete)
- `CommentsSidebarView.swift` — Comments sidebar pane: thread list, rendered
  messages, and the native compose box.
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
- `Lighting+AppKit.swift` — AppKit/SwiftUI behavior on the bare `Lighting` enum
  (which lives in MudPreferences)
- `ErrorPage.swift` — Error-page HTML generator
- `ChangesSidebarView.swift` — Changes pane listing tracked changes
- `SidebarView.swift` — Sidebar tab container (outline / changes / comments)
- `ReselectMonitor.swift` — Detects clicks on already-selected List rows
- `TabReloadBadgeView.swift` — Brown-dot badge on a tab whose document reloaded
  while the window was not key
- `View+Modify.swift` — SwiftUI `modify(_:)` view modifier helper
- `Date+Formatting.swift` — `shortTimestamp` formatting extension
- `CheckForUpdatesView.swift` — Sparkle updater owner, KVO observer, and menu
  button (`#if SPARKLE`)
- `OpenInEditor.swift` — Backs the "Open In…" submenu: registered-handler
  model, `NSOpenPanel` chooser, launch via `DocumentState.openInEditorRequest`

**App/CLI/ key files:**

- `main.swift` — `mud` CLI: argument parsing, rendering via MudCore,
  stdout/browser output. No AppKit or SwiftUI.
- `mud.sh` — Shell dispatcher: routes to the bundled `mud` CLI for rendering
  flags, else opens the GUI via `open -a`. The CLI binary lives at
  `Contents/Helpers/mud` (not `MacOS/`, to avoid a case-insensitive collision
  with the `Mud` app executable).

**App/Settings/ key files:**

- `SettingsView.swift` — Settings window root with NavigationSplitView sidebar
- `GeneralSettingsView.swift` — General settings pane
- `ThemeSettingsView.swift` — Theme selection pane with preview cards
- `ThemePreviewCard.swift` — Theme color constants and preview card view
- `MarkdownSettingsView.swift` — Markdown settings pane (DocC alert mode)
- `UpModeSettingsView.swift` — Up Mode settings pane (remote content, Mermaid)
- `DownModeSettingsView.swift` — Down Mode settings pane
- `ChangesSettingsView.swift` — Changes settings pane (inline deletions, git
  waypoints)
- `CommentsSettingsView.swift` — Comments settings pane (`comment-author`,
  `comment-return-saves`, and `comments-include-in-export` preferences)
- `CommandLineSettingsView.swift` — Command Line settings pane
- `UpdateSettingsView.swift` — Updates pane (`#if SPARKLE`)
- `SettingsWindowController.swift` — Settings window lifecycle (singleton)
- `CSSColors.swift` — CSS hex color parsing extension on `Color`
- `LightingPreviewCard.swift` — Lighting selection preview card
- `DebuggingSettingsView.swift` — Debugging pane (debug builds only)

**Preferences/ key files:**

- `MudPreferences.swift` — Struct with `.shared`. Source of truth is
  `UserDefaults.standard`, mirrored into the Team-ID-prefixed app-group suite
  `XVL2AFNXH5.org.josephpearson.Mud` so the Quick Look extension can read a
  snapshot. Holds `Keys`, per-key accessors, `reset()`.
- `MudPreferencesObserver.swift` — Syncs `defaults` into the app-group mirror
  at launch and watches them via KVO thereafter.
- `MudPreferencesSnapshot.swift` — Value-type prefs snapshot feeding
  `RenderOptions`; consumed by the Quick Look extension.
- `Theme.swift` — austere/blues/earthy/riot enum
- `Lighting.swift` — auto/bright/dark enum (bare; AppKit behavior in
  `App/Lighting+AppKit.swift`)
- `Mode.swift` — up/down enum
- `ViewToggle.swift` — readableColumn/lineNumbers/wordWrap/codeHeader/
  autoExpandChanges toggles
- `SidebarPane.swift` — outline/changes/comments enum
- `FloatingControlsPosition.swift` — Floating-bar placement enum
- `EditorFormat.swift` — markdown/html enum for the "Open In" handoff

**Core/ key files:**

- `ParsedMarkdown.swift` — Parse-once handle: AST, headings, title
- `RenderExtension.swift` — Client-side rendering extension type and registry
- `RenderOptions.swift` — Rendering configuration value type
- `MudCore.swift` — Public API: rendering functions, `extractHeadings`,
  `parseComments`, comment thread / bottom-section rendering
- `Rendering/UpHTMLVisitor.swift` — AST → rendered HTML
- `Rendering/DownHTMLVisitor.swift` — AST → syntax-highlighted raw HTML
- `Rendering/HTMLDocument.swift` — Structured HTML document builder
- `Rendering/HTMLTemplate.swift` — Document wrapping and resource loading
- `Rendering/MarkdownParser.swift` — swift-cmark wrapper
- `Rendering/FootnoteProcessor.swift` — Pre-parses footnotes; classifies
  `^comment-[\w-]+$` labels as comments
- `Rendering/SlugGenerator.swift` — Heading ID generation
- `Rendering/HeadingExtractor.swift` — Heading extraction for sidebar
- `Rendering/CodeHighlighter.swift` — Syntax highlighting via highlight.js
- `Rendering/EmojiShortcodes.swift` — `:shortcode:` → emoji replacement
- `Rendering/AlertDetector.swift` — GFM alert and DocC aside detection
- `Rendering/HTMLEscaping.swift` — Shared HTML entity escaping
- `Rendering/HTMLLineSplitter.swift` — Splits HTML by line preserving `<span>`
  balance (for diff display)
- `Rendering/ImageDataURI.swift` — Image encoding for browser export
- `OutlineHeading.swift` — Heading model shared between Core and App
- `Comments/Comment.swift` — `Comment` / `CommentMessage` models and the
  `CommentMode` enum
- `Comments/CommentSerialization.swift` — Read/write codec for a comment body
- `Comments/CommentEditor.swift` — Pure source rewriting (no IO):
  insert/rewrite/delete with stable, never-renumbered alpha labels
- `Comments/CommentAnchor.swift` — Maps a rendered-DOM selection end to a
  source UTF-8 byte (via the cmark footnote AST) so the marker lands where the
  quotation ends
- `Diff/BlockMatcher.swift` — Block-level diff: leaf collection,
  fingerprinting, `CollectionDifference` matching
- `Diff/LineLevelDiff.swift` — Shared line-level diff algorithm
- `Diff/LineDiffMap.swift` — Down mode change tracking
- `Diff/CodeBlockDiff.swift` — Line-level diff within paired code blocks (Up
  mode)
- `Diff/DiffContext.swift` — Up mode change tracking
- `Diff/WordDiff.swift` — Word-level diff and inline text extraction
- `Diff/WordPairing.swift` — Greedy best-match pairing of deleted/inserted
  lines
- `Diff/ChangeList.swift` — Sidebar change list computed from `DiffContext`
- `Diff/ChangeGroup.swift` — Groups consecutive changes by `groupID`
- `ChangeTracker.swift` — Waypoint history and active-waypoint selection

**QuickLook/ key files:**

- `PreviewProvider.swift` — `MudPreviewProvider`, a view-based
  `QLPreviewingController` (not data-based — required for Finder's column-view
  pane to live-render) hosting a `WKWebView`. Renders self-contained HTML via
  MudCore, inlining local images as data URIs.
- `Info.plist` — Quick Look preview extension point; principal class
  `MudPreviewProvider`; supports `net.daringfireball.markdown`.
- `QuickLook.entitlements` / `QuickLookDirect.entitlements` — Sandboxed; MAS
  variant carries app-group, Direct variant adds a temporary read exception for
  inlining sibling images. Selected per build config via
  `CODE_SIGN_ENTITLEMENTS`.

**Thumbnail/ key files:**

- `ThumbnailProvider.swift` — `MudThumbnailProvider`, a `QLThumbnailProvider`.
  Draws the file's first heading (via `MudCore.extractHeadings`) on the card
  grey, then composites the bundled drip overlay on top.
- `Info.plist` — Quick Look thumbnail extension point; principal class
  `MudThumbnailProvider`; `QLThumbnailMinimumDimension = 64`.
- `Thumbnail.entitlements` / `ThumbnailDirect.entitlements` — Sandbox only; no
  network, app-group, or temporary exceptions.
- `Resources/thumbnail-dynamic.png` — 768×1024 drip overlay drawn over the
  heading.
- `Resources/thumbnail-static.svg` — Source for the static `.icns` document
  icon.

**Resources:**

- `mud.css` — Shared styles and lighting variables
- `mud-up.css` — Up mode styles
- `mud-down.css` — Down mode styles
- `mud-comments.css` — Comments column styles (read side, bundled everywhere):
  markers, quotation highlights, the bottom Comments section, and the projected
  column (capsules, header, threads). Inlined into every Up document via
  `wrapUp`, exports included.
- `mud-comments-edit.css` — Comments column styles (write side, app only): the
  compose box and the add / reply / edit / delete controls, plus the delete
  puff. Embedded only when `RenderOptions.commentsEditable` is set, so exports
  omit it. Mirrors the `mud-comments.js` / `mud-comments-edit.js` split.
- `mud.js` — Shared JS: find, scroll, lighting, zoom
- `mud-changes.js` — Change tracking JS: overlays, expand/collapse, navigation
- `mud-comments.js` — Comments column (read side, bundled everywhere): projects
  a capsule per comment from the hidden bottom section, anchors quotation
  highlights off the hidden markers, runs the slot solver, and on `setData`
  rebuilds the section + syncs body markers + reprojects in place (no reload)
- `mud-comments-edit.js` — Comments column (write side, app only): the Add
  Comment button on a commentable selection, the compose box, and the
  submit/reply/edit/delete bridge (`mudCommentSubmit`)
- `mud-up.js` — Up-mode JS
- `mud-down.js` — Down-mode JS
- `emoji.json` — GitHub gemoji shortcode database
- `alert-*.svg` — Octicon alert icons
- `theme-*.css` — Four user-selectable theme files (austere, blues, earthy,
  riot)
- `theme-system.css` — System theme (internal; used for error pages)
- `mermaid.min.js` — Mermaid diagram library (v11, UMD build)
- `mermaid-init.js` — Mermaid init script for Up mode rendering
- `Doc/Guides/command-line.md` — Bundled guide: CLI usage
- `Doc/Guides/primer.md` — Bundled guide: dense Markdown authoring primer for
  coding agents, printed by `mud --primer`

**Scripts and CI:**

- `.github/scripts/update-sparkle` — Download Sparkle framework and CLI tools
  to `Vendor/Sparkle/`
- `.github/scripts/build-appcast` — Sign DMG and generate single-item
  `appcast.xml`
- `.github/scripts/build-release-notes` — Ruby: extract per-version sections
  from `Doc/RELEASES.md` and render HTML via Mud CLI

**Doc:**

- `Doc/RELEASES.md` — User-facing release notes (hand-written, per-version)
- `Site/releases/` — Pre-rendered release notes HTML (generated by
  `build-release-notes`)

**Important** — Keep this section in sync when you add or remove key files.


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
document. All public rendering functions accept a `RenderOptions` value
bundling configuration (theme, baseURL, docCAlertMode, commentMode, etc.);
adding an option means adding a field on the struct.

Footnotes and comments are preprocessed at the **String** boundary (sourcepos
needs raw bytes): `FootnoteProcessor` rewrites references to inline-HTML
markers and strips definitions before parsing. A footnote labelled
`^comment-[\w-]+$` is diverted to a `[⋯]` marker (consuming no footnote number)
and parsed into a quotation + threaded messages; `RenderOptions.commentMode`
selects whether the bottom comments section is visible (`.section`, for export)
or hidden in favor of live highlights and the Comments sidebar
(`.interactive`).

Comments are **invisible to change tracking**: `BlockMatcher.collectLeafBlocks`
excludes comment-definition blocks (via
`FootnoteProcessor.commentDefinitionLineRanges`) and strips comment tokens from
block fingerprints (`stripCommentTokens`), so a comment-only edit produces zero
changes and no new waypoint across all three diff consumers (sidebar, Up
overlay, Down highlighting). Both are gated to a strict no-op on comment-free
input. Correspondingly, the Up-mode `contentID` is **comment-invariant**
(`DocumentContentView.displayContentID` hashes `MudCore.removeComments(...)`),
so a comment add/remove updates the live Up view in place (`mud-comments.js`
marker sync) with no reload; Down mode keeps the full markdown so its raw
source stays current.


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
icons). `AppState`'s `@Published` `didSet` observers persist each change to the
corresponding `MudPreferences.shared` property.


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
- **Single WebView, HTML swap.** Mode toggle replaces the HTML document; both
  modes share one `WKWebView`.
- **Content identity via string hash.** `WebView` compares content to avoid
  unnecessary reloads.
- **JavaScript namespace.** All JS functions live under `Mud.*`. Shared code in
  `mud.js`; mode-specific code in `mud-up.js` / `mud-down.js`. Injected as
  WKUserScript.
- **Lighting = CSS + AppKit.** CSS variables for web content;
  `NSWindow.appearance` for AppKit chrome. Both set from a single Combine sink.
- **Themes.** Four theme files (`theme-*.css`); active theme applied as a CSS
  class.
- **ViewToggle.** Persisted boolean preferences mapped to CSS classes on the
  body element via `bodyClasses`.
- **Extension principal classes.** Quick Look and Thumbnail providers use
  `@objc(ClassName)` so `NSExtensionPrincipalClass` resolves without Swift
  module-name mangling.


### Sandbox-aware features

The app detects sandboxing at runtime via `isSandboxed` (checks
`APP_SANDBOX_CONTAINER_ID`). When sandboxed (Mac App Store build),
`if !isSandboxed` guards in menus, context menus, and settings adapt two
features — no build-time flags, one binary for both channels:

- **CLI installer** — shows manual `ln -s` instructions instead of the Install
  button.
- **Open In Browser** — hidden entirely (sandboxed temp files aren't readable
  by other apps).

Comment authoring is the one **write** path and is **not** hidden under
sandboxing: the MAS build writes the user-opened `.md` via the read-write file
entitlement plus security-scoped access; the direct build is unsandboxed and
writes freely (`CommentController`).


### Deferred mutations in SwiftUI

Setting an `@Published` property from inside the view-update pipeline
(`onKeyPress`, `onChange`, `updateNSView`, Combine sinks fired during updates)
triggers SwiftUI's "Publishing changes from within view updates is not allowed"
warning and undefined behavior. Use `deferMutation` (`App/DeferMutation.swift`)
to push the mutation to the next run-loop iteration. Don't use it for unrelated
async dispatch such as background thread-hops or intentional delays.
