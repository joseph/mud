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
- Comments: select text and attach threaded comments, stored in-file as GFM
  footnotes (`^comment-[\w-]+$`); hover-revealed highlights and a Comments
  Column (Up mode only; GUI authoring writes the `.md` file)
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
  Mud.app. Its Swift module is named `MudCLI` (`PRODUCT_MODULE_NAME`) so its
  products-dir swiftmodule can't collide case-insensitively with the app's
  `Mud.swiftmodule` — the binary is still `mud`.
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
- **MudTests** (MudTests/) -- unit-test bundle for the App target, hosted in
  Mud.app (`@testable import Mud`). Swift Testing, like the Core and
  Preferences suites; Cmd+U on either scheme runs it. The folder is a
  file-system-synchronized group, so new test files need no project edit.


## File quick reference

**App/ key files:**

- `MudApp.swift` — @main, menu commands
- `AppState.swift` — Singleton observable state; persistence delegated to
  `MudPreferences.shared`
- `ActiveDocument.swift` — `ActiveDocumentSnapshot` (the key document window's
  menu-relevant facts) and `ActiveDocumentObserver`, the key-window watcher
  that publishes it
- `AppDelegate.swift` — Lifecycle and document handling
- `DocumentController.swift` — NSDocumentController subclass
- `DocumentWindowController.swift` — Per-window state, toolbar, zoom, lighting
- `DocumentState.swift` — Per-window observable state, the `WebCommand` enum,
  and the `webCommands` channel
- `DocumentModel.swift` — Per-window document data: the loaded content, disk
  reads, the file watcher with its hold/echo policy, the render configuration
  (`renderOptions`, shared with exports), and the cached render (`display()`)
- `DocumentContentView.swift` — Main SwiftUI view for a document: layout, key
  handling, and the plumbing between the model/state objects and `WebView`
- `DocumentExporter.swift` — App side of the export path: writes
  `MudCore.exportDocument` output to a temp file and hands it to a browser or
  editor via `NSWorkspace` (created on demand by `DocumentWindowController`)
- `WebView.swift` — WKWebView wrapper: declarative state diffing, the
  `WebCommand` sink, navigation delegate
- `MudJSBridge.swift` — The one Swift ↔ page JS bridge: outbound `Mud.*` calls
  (JSON-encoded arguments, namespace guards, error logging), typed inbound
  messages (`MudJSMessage`, with the full message table), the shared
  `WKWebViewConfiguration` factory and link `navigationPolicy`
- `FootnotePopover.swift` — Transient `NSPopover` hosting a `WKWebView` that
  renders a footnote body; shares `MudJSBridge` with the main view
- `CommentController.swift` — `CommentDraft` model plus `CommentController`:
  the comment write path (re-read from disk, byte-surgical edit via
  `CommentEditor`, atomic security-scoped write). Add / reply / edit-last /
  delete
- `CommentSubmissionHandler.swift` — Routes a page `CommentSubmission` to
  `CommentController`, resolves the compose box (`resolveCompose`), and
  presents the failure alert
- `OutlineSidebarView.swift` — Table of contents sidebar
- `OutlineNode.swift` — Sidebar data model
- `FindFeature.swift` — Search state and UI
- `ChangesFeature.swift` — Floating Changes bar and overlay
- `GitProvider.swift` — Git history queries for external waypoints, conforming
  as `GitWaypointProvider` (`#if GIT_PROVIDER`)
- `WaypointProvider.swift` — `WaypointProvider` protocol, its no-op default,
  and the build's provider factory (`WaypointProviders`) — the one
  `#if GIT_PROVIDER` outside the whole-file-guarded git files
- `FileWatcher.swift` — DispatchSource file monitoring
- `CommandLineInstaller.swift` — CLI symlink creation with elevation support
- `LocalFileSchemeHandler.swift` — `mud-asset:` URL scheme for local images
- `DeferMutation.swift` — Run-loop deferred state mutation helper
- `Lighting+AppKit.swift` — AppKit/SwiftUI behavior on the bare `Lighting` enum
  (which lives in MudPreferences)
- `ErrorPage.swift` — Error-page HTML generator
- `ChangesSidebarView.swift` — Changes pane listing tracked changes
- `SidebarView.swift` — Sidebar tab container (outline / changes)
- `ReselectMonitor.swift` — Detects clicks on already-selected List rows
- `TabReloadBadgeView.swift` — Brown-dot badge on a tab whose document reloaded
  while the window was not key
- `View+Modify.swift` — SwiftUI `modify(_:)` view modifier helper
- `Date+Formatting.swift` — `shortTimestamp` formatting extension
- `CheckForUpdatesView.swift` — Sparkle updater owner, KVO observer, and menu
  button (`#if SPARKLE`)
- `OpenInEditor.swift` — Backs the "Open In…" submenu and the Open In toolbar
  button (`NSMenuToolbarItem`): registered-handler model, `NSMenu` builder
  (`NSMenuDelegate`), `NSOpenPanel` chooser, launch via
  `DocumentWindowController.openInEditor(with:format:)`

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
  `comment-return-saves`, `comments-show-markers`, and
  `comments-include-in-export` preferences)
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
- `ViewToggle.swift` — readableColumn/lineNumbers/wordWrap/codeHeader/
  autoExpandChanges toggles
- `SidebarPane.swift` — outline/changes enum
- `FloatingControlsPosition.swift` — Floating-bar placement enum
- `EditorFormat.swift` — markdown/html enum for the "Open In" handoff

**Core/ key files:**

- `ParsedMarkdown.swift` — Parse-once handle: AST, headings, title
- `RenderExtension.swift` — Client-side rendering extension type and registry
- `RenderOptions.swift` — Rendering configuration value type
- `Mode.swift` — up/down enum (Mark Up / Mark Down)
- `MudCore.swift` — Public API facade: rendering entry points (dispatch only —
  HTML emission lives in `Rendering/`), the shared Up-mode pipeline,
  `exportDocument` (the one self-contained export recipe), extractHeadings /
  parseComments / removeComments convenience
- `Rendering/UpHTMLVisitor.swift` — AST → rendered HTML; `renderBody` is the
  visitor + frontmatter-prefix core every Up-mode fragment render goes through
- `Rendering/DownHTMLVisitor.swift` — AST → syntax-highlighted raw HTML
- `Rendering/WordSpanEmitter.swift` — Word-level `<ins>`/ `<del>` cursor
  machine; advances through a block's `[WordSpan]` in step with the visitor's
  character stream (aligned with `WordDiff.inlineText`)
- `Rendering/DeletionPlacer.swift` — Places pre-rendered deletions into the
  Up-mode stream: exactly-once bookkeeping, `<tr>` wrapping, deferral around
  `</table>`
- `Rendering/DeletionRenderer.swift` — Renders deleted blocks to HTML for the
  Up-mode overlay; injected into `DiffContext` so `Diff/` never calls rendering
  code
- `Rendering/FootnoteHTMLRenderer.swift` — Bottom footnotes section and the
  per-footnote popover documents
- `Rendering/CommentHTMLRenderer.swift` — Bottom comments section, single
  comment `<li>` items, thread popover documents
- `Rendering/FrontMatterHTMLRenderer.swift` — Frontmatter for both modes: Up's
  collapsible table, Down's highlighted source lines
- `Rendering/HTMLDocument.swift` — Structured HTML document builder
- `Rendering/HTMLTemplate.swift` — Document wrapping and resource loading
- `Rendering/MarkdownParser.swift` — swift-cmark wrapper
- `Rendering/FootnoteProcessor.swift` — Pre-parses footnotes via cmark;
  classifies `^comment-[\w-]+$` labels as comments (diverted to `[⋯]` markers,
  authorial footnotes renumbered to skip them). All entry points derive from
  one memoized `FootnoteScan` per source
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
- `Diff/BlockMatcher.swift` — Block-level diff: leaf collection, fingerprint
  matching, and gap ordering between two parsed documents
- `Diff/ChangePlan.swift` — The single diff pass every consumer projects from:
  change-ID minting, gap pairing, code-block pairs, word spans, and grouping;
  memoized per (waypoint, content) pair
- `Diff/LineLevelDiff.swift` — Shared line-level diff algorithm
- `Diff/LineDiffMap.swift` — Down mode change tracking (projects `ChangePlan`
  onto line numbers)
- `Diff/CodeBlockDiff.swift` — Line-level diff within paired code blocks (Up
  mode)
- `Diff/DiffContext.swift` — Up mode change tracking (projects `ChangePlan`
  into annotation lookups and rendered deletions)
- `Diff/WordDiff.swift` — Word-level diff and inline text extraction
- `Diff/WordPairing.swift` — Greedy best-match pairing of deleted/inserted
  lines
- `Diff/ChangeList.swift` — Sidebar change list projected from `ChangePlan`
- `Diff/ChangeGroup.swift` — Groups consecutive changes by `groupID`
- `ChangeTracker.swift` — Waypoint history and active-waypoint selection

**QuickLook/ key files:**

- `PreviewProvider.swift` — `MudPreviewProvider`, a view-based
  `QLPreviewingController` (not data-based — required for Finder's column-view
  pane to live-render) hosting a `WKWebView`. Renders self-contained HTML via
  `MudCore.exportDocument` (images inlined as data URIs, read-only Comments
  column for commented files).
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

**MudTests/ key files:**

- `TestSupport.swift` — Async pumping helpers (`pump`, `pumpUntil`), the
  temp-directory fixture, and the `MudComment` alias
- `FindStateTests.swift` — The find state machine: origin classification,
  navigation, reset behavior
- `DocumentModelTests.swift` — The self-write dedup policy, the watcher
  hold/echo policy against real temp files, and the waypoint-provider seam
- `CommentControllerTests.swift` — Comment mutations on disk and the
  `anchorFailed` / `writeFailed` matrix
- `OpenInFormatTests.swift` — The Open In `.auto` format truth table
- `WebViewParsingTests.swift` — `parseMatchInfo` and `commentSignature`
- `MudJSBridgeTests.swift` — Outbound script building (escaping) and inbound
  message decoding
- `GitProviderTests.swift` — Waypoint assembly and git-output parsing over a
  scripted runner (`#if GIT_PROVIDER`)

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
- `mud-print.css` — Print styles: every `@media print` rule, gathered out of
  the mode and comments stylesheets. Included last in both Up and Down
  documents so its rules win over the on-screen defaults.
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

Footnotes are preprocessed at the **String** boundary (sourcepos needs raw
bytes): `FootnoteProcessor` rewrites `[^ref]` to inline-HTML markers and strips
definitions before `ParsedMarkdown` parsing. The bottom
`<section class="footnotes">` is always emitted; in `.popover` mode it is
hidden on screen (`is-print-only`, shown under `@media print`) and
`renderUpModeDocumentWithFootnotes` additionally returns each footnote body as
a self-contained document for the in-app `NSPopover`.

Comments ride the same preprocessing pass. A footnote whose label matches
`^comment-[\w-]+$` is classified as a comment: its reference renders as a `[⋯]`
marker (consuming no footnote number) and its definition is parsed into a
quotation + threaded messages. `RenderOptions.commentMode` (added to
`contentIdentity`) selects the output: `.section` emits a visible bottom
`<section class="comments">` for every export path, while `.interactive` (the
live app) keeps that section `is-print-only` and instead draws hover-revealed
highlights and feeds the Comments Column. The bottom section always follows any
footnotes section.

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

Five ObservableObject classes, no nesting:

- **AppState** (singleton) -- persisted preferences as `@Published` mirrors:
  `lighting`, `theme`, `viewToggles`, `sidebarEnabled`, …
- **ActiveDocumentObserver** (singleton) -- publishes an
  `ActiveDocumentSnapshot?` of the key document window (mode, editable,
  commentable, column visibility) for app-menu labels and enablement; `nil`
  when no document window is key
- **DocumentState** (per-window) -- `mode`, per-window zoom levels (seeded from
  `MudPreferences` at window creation, re-persisted on change so the next
  window opens at the last-used zoom), the `webCommands` channel,
  `outlineHeadings`, `contentTitle`, comments-column state, owns `FindState`
- **DocumentModel** (per-window) -- the loaded content, disk reads, the file
  watcher with its hold/echo policy, and the cached render; renders run only
  when the content or the content-affecting options change, never per view
  update
- **FindState** -- search text, visibility, match info; Combine subscriber on
  `$searchText` auto-triggers queries

State flows outward via `@ObservedObject`. Combine sinks in
`DocumentWindowController` bridge state → AppKit (window appearance, toolbar
icons). `AppState`'s `@Published` `didSet` observers persist each change to the
corresponding `MudPreferences.shared` property. Nothing writes per-window facts
into globals: `ActiveDocumentObserver` watches
`NSWindow.didBecomeKeyNotification` and subscribes to the key window's state
itself.


## Communication patterns

| Mechanism            | Used for                                         |
| -------------------- | ------------------------------------------------ |
| Responder chain      | Menu and toolbar → window controller             |
| `WebCommand` channel | One-shot page actions via `state.webCommands`    |
| Combine sinks        | State → AppKit side effects                      |
| `MudJSBridge`        | Swift ↔ WKWebView (find, scroll, lighting, zoom) |
| Direct mutation      | Toolbar buttons → state objects                  |

Menu and toolbar commands travel the responder chain (`NSApp.sendAction`) to
the key window's `DocumentWindowController`, which mutates its `DocumentState`
— for page actions (print, scroll, add comment), it sends a `WebCommand` over
`state.webCommands`, which the `WebView` coordinator executes as it arrives.
`updateNSView` diffs only declarative state (contentID, mode, theme, zoom,
classes, comments, search). Cmd+R calls `DocumentModel.load(forced:)`, whose
bumped load token changes the contentID so the page reloads even when the
file's text hasn't.

All Swift ↔ page traffic goes through `MudJSBridge` (`App/MudJSBridge.swift`):
outbound `bridge.call("comments.setData", …)` JSON-encodes every argument and
logs JS errors; inbound `window.webkit.messageHandlers` posts decode into the
typed `MudJSMessage` enum (the message table is documented on that enum). The
footnote popover uses the same bridge type for its `mudOpen` link routing.


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

Comment authoring is the one **write** path (the app is otherwise read-only)
and is **not** hidden under sandboxing. The MAS build writes the user-opened
`.md` file via the read-write file entitlement (`App/Mud.entitlements`) plus
security-scoped access (start/stop around an atomic write); the direct build is
unsandboxed and writes freely (`CommentController`).


### Deferred mutations in SwiftUI

Setting an `@Published` property from inside the view-update pipeline
(`onKeyPress`, `onChange`, `updateNSView`, Combine sinks fired during updates)
triggers SwiftUI's "Publishing changes from within view updates is not allowed"
warning and undefined behavior. Use `deferMutation` (`App/DeferMutation.swift`)
to push the mutation to the next run-loop iteration. Don't use it for unrelated
async dispatch such as background thread-hops or intentional delays.
