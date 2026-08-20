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
- GFM math: TeX rendered to MathML server-side (Temml), three delimiter forms
  (```` ```math ````, `$$…$$`, inline `` $`…`$ ``); no client-side JS
- Two modes: Mark Up (rendered) and Mark Down (raw, syntax-highlighted)
- Space bar toggles modes; scroll position preserved
- Auto-reload on file change (DispatchSource); manual reload (Cmd+R)
- Four themes: Austere, Blues, Earthy (default), Riot
- Lighting: Auto/Bright/Dark cycle
- Zoom In/Out/Actual Size (per-mode, persisted)
- Readable Column, Line Numbers, Word Wrap toggles
- Foldable Headings: an arrow on every h2-or-deeper heading folds its section
  for as long as the window is open. The View menu adds Fold / Unfold Headings
  (Ctrl+Cmd+H, Shift+Cmd+H) for the whole document
- Table of contents sidebar
- Comments: select text and attach threaded comments, stored in-file as GFM
  footnotes (`[^💬-a]`, or the older equivalent `[^comment-a]`); hover-revealed
  highlights and a Comments Column (Up mode only; GUI authoring writes the
  `.md` file)
- Find (Cmd+F), Find Next/Previous (Cmd+G, Cmd+Shift+G)
- Print / Save as PDF (Cmd+P)
- Open In Browser (Cmd+Shift+B) with image data-URI embedding
- Local images via custom `mud-asset:` URL scheme; remote images allowed. When
  the sandbox denies one, the info bar offers a folder grant, kept as a
  security-scoped bookmark and revocable in Settings → Up Mode
- Info bar: a one-at-a-time notice below the tab bar for what the document
  can't say itself — an open that failed, a held external change, a comment
  write that failed, a folder with no Markdown, blocked local images
- Link handling: anchors, local .md, external URLs
- Opening a folder does one of two things, per the `folder-open-behavior`
  setting: builds an index of every Markdown file in the tree below it, as one
  document of links (the default), or opens the files directly inside it, one
  tab each. A folder with nothing to list gets a blank page and an info-bar
  warning
- Quit on last window close
- CLI tool: `mud -u` / `-d` for HTML output, `-f` for fragment output, stdin
  support, theme and view-option flags, `--primer` for the agent authoring
  guide


## Targets

- **Mud** (App/) -- macOS app, SwiftUI + AppKit hybrid
- **Mud CLI** (App/CLI/) -- standalone Swift CLI tool (`mud`), bundled in
  Mud.app. Its Swift module is `MudCLI` (`PRODUCT_MODULE_NAME`) so its
  swiftmodule can't collide case-insensitively with the app's; the binary is
  still `mud`.
- **MudCore** (Core/) -- Swift Package, platform-independent rendering and
  syntax highlighting
- **MudPreferences** (Preferences/) -- Swift Package for preference
  persistence, shared between the app and the Quick Look extension. Depends on
  MudCore for the types its snapshot maps into `RenderOptions`.
- **QuickLook** (QuickLook/) -- `.appex` preview extension, bundled in
  `Mud.app/Contents/PlugIns/`. Renders via MudCore, reads preferences from the
  app-group mirror.
- **Thumbnail** (Thumbnail/) -- `.appex` thumbnail extension, also in
  `PlugIns/`. Sandboxed; no app-group entitlement.
- **Mud Tests** (App/Tests/) -- unit-test bundle hosted in Mud.app
  (`@testable import Mud`). Swift Testing, like the Core and Preferences
  suites. The folder is file-system-synchronized, so new test files need no
  project edit.


## File quick reference

**App/ key files:**

- `MudApp.swift` — @main, menu commands
- `AppState.swift` — Singleton observable state; persistence delegated to
  `MudPreferences.shared`
- `Pref.swift` — `@Pref` property wrapper: live read/write of a
  `MudPreferences` value on an `ObservableObject`, firing `objectWillChange` on
  set
- `ActiveDocument.swift` — `ActiveDocumentSnapshot` (the key document window's
  menu-relevant facts) and `ActiveDocumentObserver`, which publishes it
- `AppDelegate.swift` — Lifecycle and document handling
- `DocumentController.swift` — NSDocumentController subclass. Owns the modeless
  open panel (`canChooseDirectories`, plus the "Enable:" popup). A folder URL
  takes the route `folderOpenBehavior` names: under `.index` one window on the
  folder itself, which `DocumentModel` makes a document of; under `.tabs`
  `openFolderAsTabs`, one window per `MarkdownFolder.markdownFiles` entry,
  tabbed with an explicit `addTabbedWindow`. An already-open document is
  surfaced where it is; a folder with no Markdown gets a window on itself
- `MarkdownFolder.swift` — What a folder open yields under `.tabs`: the
  Markdown files directly inside, top level only, name-ordered — nil when the
  URL isn't a folder (packages included, read as one document), empty when it
  holds none. `displayName(for:)` names windows and tabs (a folder's gets a
  trailing "/"). Its `isFolder` / `isMarkdown` rules are shared with the walk
- `FolderIndex.swift` — What a folder open yields under `.index`: a walk of the
  whole tree (hidden entries and symlinks skipped, empty branches dropped,
  `fileLimit` files at most) and the document written from it — one nested list
  of links, relative to the folder. The walk and the writing are separate calls
  so the source can be checked against a tree built by hand
- `OpenPanelFilter.swift` — The open panel's "Enable:" cases: Markdown and
  Text, or All Files (empty `allowedContentTypes`). Not persisted; each panel
  is built fresh on the Markdown case
- `DocumentWindowController.swift` — Per-window state, toolbar, zoom, lighting.
  Cmd+R re-reads the file — except on the `.tabs` empty-folder window, which
  re-runs the folder open and closes itself if the folder gained a document,
  since a folder gets no watcher. Under `.index` the plain re-read walks the
  tree again, so Cmd+R needs nothing special
- `DocumentState.swift` — Per-window observable state, the `WebCommand` enum,
  and the `webCommands` channel
- `DocumentModel.swift` — Per-window document data: loaded content, disk reads,
  the file watcher and its hold/echo policy, `renderOptions` (shared with
  exports), and the cached render (`display()`). A folder URL is read through
  `FolderIndex` instead of the file system; `baseURL` is what makes that
  document's relative links resolve — a folder's ends in a slash, so the page's
  `<base href>` names it as a folder
- `DocumentContentView.swift` — Main SwiftUI view for a document: layout, key
  handling, and the plumbing between the model/state objects and `WebView`
- `DocumentExporter.swift` — Writes `MudCore.exportDocument` output to a temp
  file and hands it to a browser or editor via `NSWorkspace`
- `WebView.swift` — WKWebView wrapper: declarative state diffing, the
  `WebCommand` sink, navigation delegate. Its coordinator holds what a reload
  would lose — scroll fraction and folded-heading slugs; per window, never
  persisted
- `MudJSBridge.swift` — The one Swift ↔ page JS bridge: outbound `Mud.*` calls
  (JSON-encoded arguments, namespace guards, error logging), typed inbound
  messages (`MudJSMessage`, with the full message table), the shared
  `WKWebViewConfiguration` factory and link `navigationPolicy`
- `HTMLPopover.swift` — Transient `NSPopover` hosting a `WKWebView` that
  renders a self-contained Up-mode document; shares `MudJSBridge` with the main
  view. Two callers, one instance on `WebView.Coordinator`, so two popovers
  can't be open at once: a footnote body, which Swift rendered before the page
  loaded and looks up by label, and HTML the page sent over `mudPopover`
- `CommentController.swift` — `CommentDraft` plus the comment write path
  (re-read from disk, byte-surgical edit via `CommentEditor`, atomic
  security-scoped write). Add / reply / edit-last / delete
- `CommentSubmissionHandler.swift` — Routes a page `CommentSubmission` to
  `CommentController`, answers the page, and raises `commentWriteFailed`
- `CommentColumnFit.swift` — Whether the Comments column fits at the window's
  current width, and `makeRoom`: widen silently, ask before collapsing the
  sidebar, or report that neither is possible. `remedy` is pure geometry, so
  the branches are testable
- `OutlineSidebarView.swift` — Table of contents sidebar
- `OutlineNode.swift` — Sidebar data model
- `FindFeature.swift` — Search state and UI
- `ChangesFeature.swift` — Floating Changes bar and overlay
- `GitProvider.swift` — Git history queries for external waypoints, conforming
  as `GitWaypointProvider` (`#if GIT_PROVIDER`)
- `WaypointProvider.swift` — `WaypointProvider` protocol, its no-op default,
  and the build's provider factory — the one `#if GIT_PROVIDER` outside the
  whole-file-guarded git files
- `FileWatcher.swift` — DispatchSource file monitoring
- `CommandLineInstaller.swift` — CLI symlink creation with elevation support
- `LocalFileSchemeHandler.swift` — `mud-asset:` URL scheme for local images
- `LocalAssetProbe.swift` — Whether a local file can actually be read, by
  `open(2)` and `errno`: readable / missing / denied. `FileManager.fileExists`
  can't tell the last two apart — the sandbox denies the content read while
  permitting `stat`. Opens `O_NONBLOCK`, since this runs on the main thread
  inside a render
- `BlockedAssetLog.swift` — The images one render couldn't read. Vends the
  resolver closure `DocumentModel` hands `MudCore`, since a bare closure has
  nowhere to report to. Denials only: a missing file is the document's problem,
  not a permission Mud can ask for
- `AssetAccessStore.swift` — The folders the reader has let Mud read local
  content from, held as security-scoped bookmarks so a grant outlives the app's
  run: launch resolution, the grant panel, revocation, and the pure
  `reduce(grants:adding:)` (a covered folder adds no row, a covering folder
  replaces what it covers). A `Grant` whose bookmark won't resolve is kept as
  an unavailable row — an unplugged disk is not a revocation. Windows watch
  `accessChanged`, not `$grants`
- `DeferMutation.swift` — Run-loop deferred state mutation helper
- `Lighting+AppKit.swift` — AppKit/SwiftUI behavior on the bare `Lighting` enum
  (which lives in MudPreferences)
- `ErrorPage.swift` — Error-page HTML generator; `empty()` is the blank page
  the empty-folder window shows, where the notice says everything
- `ChangesSidebarView.swift` — Changes pane listing tracked changes
- `SidebarView.swift` — Sidebar tab container (outline / changes)
- `ReselectMonitor.swift` — Detects clicks on already-selected List rows
- `TabReloadBadgeView.swift` — Brown-dot badge on a tab whose document reloaded
  while the window was not key
- `DocumentNotice.swift` — A short, non-blocking message about the document
  (kind, level, optional action, dismissibility), plus the notices themselves —
  `openFailed`, `externalChangeHeld`, `commentWriteFailed`,
  `folderHasNoMarkdown`, `folderIndexTruncated`, `localAssetsBlocked`. An
  action's effect is a value, not a closure, so the notice keeps a synthesized
  `Equatable`; `DocumentNoticeBar` performs it. One at a time in
  `DocumentState.notice`; `clear(_:)` matches on kind
- `DocumentNoticeBar.swift` — The info bar, attached with
  `.safeAreaInset(edge: .top)` so it takes space from the WebView instead of
  covering it. Deliberately not an `NSTitlebarAccessoryViewController` — AppKit
  puts the tab bar below app-supplied accessories
- `View+Modify.swift` — SwiftUI `modify(_:)` view modifier helper
- `Date+Formatting.swift` — `shortTimestamp` formatting extension
- `CheckForUpdatesView.swift` — Sparkle updater owner, KVO observer, and menu
  button (`#if SPARKLE`)
- `OpenInEditor.swift` — Backs the "Open In…" submenu and toolbar button
  (`NSMenuToolbarItem`): registered-handler model, `NSMenu` builder,
  `NSOpenPanel` chooser, launch via
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
- `UpModeSettingsView.swift` — Up Mode settings pane (remote content, foldable
  headings, diagrams). Its Diagrams list is one control over two preferences:
  `DiagramSetting` maps Simplicity / Handwritten onto `upModeDiagramLook` and
  Disabled onto dropping `mermaid` from `enabledExtensions`. Turning diagrams
  off leaves the look alone, so switching them back on returns the reader to
  the look they picked
- `DownModeSettingsView.swift` — Down Mode settings pane
- `ChangesSettingsView.swift` — Changes settings pane (inline deletions, git
  waypoints)
- `CommentsSettingsView.swift` — Comments settings pane (`comment-author`,
  `comment-avatar`, `comment-return-saves`, `comments-show-markers`,
  `comments-include-in-export`)
- `AvatarPicker.swift` — The `comment-avatar` control: a button showing the
  current avatar, opening a popover grid of `AvatarChoices` (forty-nine emoji,
  seven to a row, grouped by kind). No text field, so nothing invalid can be
  entered and the preference needs no validation on the way in. The list is an
  offering rather than the rule — `CommentAvatar.isValid` still takes any
  single emoji, so a `defaults write comment-avatar` value outside the list
  shows on the button with no cell highlighted and survives until the reader
  picks one
- `CommandLineSettingsView.swift` — Command Line settings pane
- `UpdateSettingsView.swift` — Updates pane (`#if SPARKLE`)
- `SettingsWindowController.swift` — Settings window lifecycle (singleton)
- `CSSColors.swift` — CSS hex color parsing extension on `Color`
- `LightingPreviewCard.swift` — Lighting selection preview card
- `DebuggingSettingsView.swift` — Debugging pane (debug builds only); includes
  the Notice Bar testers

**Preferences/ key files:**

- `MudPreferences.swift` — Struct with `.shared`. Source of truth is
  `UserDefaults.standard`, mirrored into the Team-ID-prefixed app-group suite
  `XVL2AFNXH5.org.josephpearson.Mud` so the Quick Look extension can read a
  snapshot. Holds `Keys`, per-key accessors, `reset()`.
- `MudPreferencesObserver.swift` — Syncs `defaults` into the app-group mirror
  at launch and watches them via KVO thereafter.
- `MudPreferencesSnapshot.swift` — Value-type prefs snapshot feeding
  `RenderOptions`; consumed by the Quick Look extension.
- `Lighting.swift` — auto/bright/dark enum (bare; AppKit behavior in
  `App/Lighting+AppKit.swift`)
- `ViewToggle.swift` — readableColumn/lineNumbers/wordWrap/codeHeader/
  autoExpandChanges/foldableHeadings toggles
- `SidebarPane.swift` — outline/changes enum
- `FloatingControlsPosition.swift` — Floating-bar placement enum
- `FolderOpenBehavior.swift` — index/tabs enum: what Mud makes of a folder it
  is handed
- `EditorFormat.swift` — markdown/html enum for the "Open In" handoff

**Core/ key files:**

- `ParsedMarkdown.swift` — Parse-once handle: owns the one footnote-aware
  `CMarkDocument` parse and exposes headings, title, and the frontmatter split.
  Every consumer reads this one tree.
- `FrontMatterExtractor.swift` — Detects and extracts YAML frontmatter and
  parses its top-level keys for the frontmatter table.
- `RenderExtension.swift` — Client-side rendering extension type and registry
- `RenderOptions.swift` — Rendering configuration value type
- `Theme.swift` — austere/blues/earthy/riot enum (plus internal `.system`)
- `DiagramLook.swift` — simplicity/handwritten enum: the face a diagram's
  labels are lettered in. Only the font differs; both looks take the page's
  palette, the rough outlines, and the wash
- `Mode.swift` — up/down enum (Mark Up / Mark Down)
- `MudCore.swift` — Public API facade: the Up- and Down-mode entry points
  (dispatch only — HTML emission lives in `Rendering/`), `renderUpPipeline`,
  `exportDocument` (the one self-contained export recipe), `computeChanges`,
  `renderPopoverDocument` (body HTML → a themed popover document, for content
  only the page has), and the extractHeadings / parseComments / removeComments
  calls
- `CMark/CMarkDocument.swift` — Owning wrapper over the one footnote-aware
  cmark-gfm parse: hard-coded parse options, range APIs in swift-markdown's
  byte conventions (exclusive upper bound, UTF-8 byte columns, backtick
  widening), and the `verifiedRange(of:)` delimiter defense. `correctInline`
  fixes inline positions inside footnote and comment definitions, where cmark
  reports a column against the prefix stripped from the block's _first_ line.
  Also trims a link's leading whitespace (GFM autolink matches from the
  boundary character). Frees the tree in `deinit`; every `CMarkNode` retains it
- `CMark/CMarkNode.swift` — Document-retaining node handle: `CMarkNodeKind`
  (extension nodes identified by type string), content and structure accessors.
  Accessors stay read-only — the `@unchecked Sendable` conformance depends on
  the tree being immutable after parsing
- `CMark/CMarkWalker.swift` — Depth-first walker: one visit method per node
  kind, descending into children by default
- `CMark/SourceGeometry.swift` — Byte/line geometry over a UTF-8 source (line
  starts, byte offsets, blank-line and `[^…]`-delimiter checks). Shared by
  `CMarkDocument`, `FootnoteProcessor`, and `CommentAnchor`
- `Rendering/UpHTMLVisitor.swift` — AST → rendered Up-mode HTML. `renderBody`
  (visitor plus frontmatter prefix) is the core every Up-mode render goes
  through; it emits footnote and comment markers from the AST and skips
  definitions structurally. With a waypoint set, it wires change annotations
  and inline deletions through `DiffContext`
- `Rendering/DownHTMLVisitor.swift` — AST → syntax-highlighted raw-source HTML
  table. `highlightWithChanges` projects a `ChangePlan` onto the source lines
  when a waypoint is set
- `Rendering/WordSpanEmitter.swift` — Word-level `<ins>` / `<del>` cursor
  machine; advances through a block's `[WordSpan]` in step with the visitor's
  character stream (aligned with `WordDiff.inlineText`)
- `Rendering/DeletionPlacer.swift` — Places pre-rendered deletions into the
  Up-mode stream: exactly-once bookkeeping, `<tr>` wrapping, deferral around
  `</table>`
- `Rendering/DeletionRenderer.swift` — Renders deleted blocks for the Up-mode
  overlay; injected into `DiffContext` so `Diff/` never calls rendering code.
  Seeds deletion visitors with the old document's footnote numbering, and runs
  them with `isDeletionRender` set so a deleted copy never emits a comment
  marker. Hosts the `DiffContext(old:new:)` convenience initializer
- `Rendering/FootnoteProcessor.swift` — Scans a source's footnotes and comments
  through one memoized `FootnoteScan`. Builds the models for the bottom
  sections, classifies comment labels (via `CommentLabel`) apart from authorial
  ones, and supplies the comment byte geometry (`CommentLocation`),
  `removeComments`, and `stripCommentTokens`. It rewrites no source
- `Rendering/FootnoteHTMLRenderer.swift` — Bottom footnotes section and the
  per-footnote popover documents
- `Rendering/CommentHTMLRenderer.swift` — Bottom comments section, single
  comment `<li>` items, thread popover documents
- `Rendering/FrontMatterHTMLRenderer.swift` — Frontmatter for both modes: Up's
  collapsible table, Down's highlighted source lines
- `Rendering/HTMLDocument.swift` — Structured HTML document builder
- `Rendering/HTMLTemplate.swift` — Document wrapping and resource loading (CSS
  and JS inlined into the final document)
- `Rendering/SlugGenerator.swift` — Heading ID generation
- `Rendering/HeadingExtractor.swift` — Heading extraction for the sidebar (a
  `CMarkWalker`)
- `Rendering/CodeHighlighter.swift` — Syntax highlighting via highlight.js
- `Rendering/MathRenderer.swift` — TeX → MathML via Temml in a JSContext
  (server-side, no client JS); same pattern as `CodeHighlighter`
- `Rendering/BundledJSContext.swift` — Shared bootstrap loading a bundled JS
  library (highlight.js, Temml) into a fresh `JSContext`
- `Rendering/EmojiShortcodes.swift` — `:shortcode:` → emoji replacement
- `Rendering/AlertDetector.swift` — GFM alert and DocC aside detection
- `Rendering/HTMLEscaping.swift` — Shared HTML entity escaping
- `Rendering/HTMLLineSplitter.swift` — Splits HTML by line preserving `<span>`
  balance (for diff display)
- `Rendering/ImageDataURI.swift` — Image encoding for browser export
- `OutlineHeading.swift` — Heading model shared between Core and App
- `Layout.swift` — `Layout.compactBreakpoint`, the Compact tier width from
  `mud-narrow.css`. A media query can only live in CSS, so the number is stated
  in both places and `HTMLTemplateTests` checks they agree
- `Comments/Comment.swift` — `Comment` / `CommentMessage` models and the
  `CommentMode` enum
- `Comments/CommentGrammar.swift` — The two parts of the on-disk form that are
  values rather than structure: `CommentLabel` (which footnote labels are
  comments — `💬-` and the older `comment-`, equivalent — and which prefix Mud
  writes) and `CommentAvatar` (the single emoji that may lead a message
  attribution: what Mud writes, what a message without one is shown with, and
  what counts as one)
- `Comments/CommentSerialization.swift` — Read/write codec for a comment body
- `Comments/CommentEditor.swift` — Pure source rewriting (no IO):
  insert/rewrite/delete with stable, never-renumbered alpha labels
- `Comments/CommentAnchor.swift` — Maps a rendered-DOM selection end to a
  source UTF-8 byte (via the cmark footnote AST) so the marker lands where the
  quotation ends
- `Diff/BlockMatcher.swift` — Block-level diff over two `CMarkDocument` trees:
  leaf collection, fingerprint matching, gap ordering. `DefinitionDiffPolicy`
  handles definitions (Up skips every one; Down descends plain footnote
  definitions so their edits stay diffable; comment definitions always
  skipped). Feeds `ChangePlan`
- `Diff/ChangePlan.swift` — The single diff pass every consumer projects from:
  change-ID minting, gap pairing, code-block pairs, word spans, grouping.
  Memoized per (source text, policy); every join keys on a source position
  (`SourceKey`), never node identity, so the cache can return nodes from a
  textually identical tree
- `Diff/DiffContext.swift` — Up-mode change tracking: projects `ChangePlan`
  into annotation lookups and rendered deletions
- `Diff/LineDiffMap.swift` — Down-mode change tracking: projects `ChangePlan`
  onto line numbers
- `Diff/ChangeList.swift` — Sidebar change list projected from `ChangePlan`
- `Diff/ChangeGroup.swift` — Groups consecutive changes by `groupID`
- `Diff/CodeBlockDiff.swift` — Line-level diff within paired code blocks (Up
  mode)
- `Diff/LineLevelDiff.swift` — Shared line-level diff algorithm
- `Diff/WordDiff.swift` — Word-level diff and inline text extraction
- `Diff/WordPairing.swift` — Greedy best-match pairing of deleted / inserted
  lines
- `ChangeTracker.swift` — Waypoint history and active-waypoint selection

**QuickLook/ key files:**

- `PreviewProvider.swift` — `MudPreviewProvider`, a view-based
  `QLPreviewingController` (not data-based — required for Finder's column-view
  pane to live-render) hosting a `WKWebView`. Renders self-contained HTML via
  `MudCore.exportDocument`. It is the one export path passing
  `commentsColumn: false`: a preview pane is not the reader's to widen, so
  comments always render as the bottom section. For the same reason it
  overrides the snapshot's `zoomLevel` (`lockZoom`: 100% above
  `Layout.compactBreakpoint`, 80% at or below) and sets `is-zoom-locked` so the
  Tight tier's 14px type rule doesn't compound with it
- `Info.plist` — Preview extension point; principal class `MudPreviewProvider`;
  supports `net.daringfireball.markdown`.
- `QuickLook.entitlements` / `QuickLookDirect.entitlements` — Sandboxed; MAS
  variant carries app-group, Direct variant adds a temporary read exception for
  inlining sibling images. Selected via `CODE_SIGN_ENTITLEMENTS`.

**Thumbnail/ key files:**

- `ThumbnailProvider.swift` — `MudThumbnailProvider`, a `QLThumbnailProvider`.
  Draws the file's first heading (via `MudCore.extractHeadings`) on the card
  grey, then composites the bundled drip overlay on top.
- `Info.plist` — Thumbnail extension point; principal class
  `MudThumbnailProvider`; `QLThumbnailMinimumDimension = 64`.
- `Thumbnail.entitlements` / `ThumbnailDirect.entitlements` — Sandbox only; no
  network, app-group, or temporary exceptions.
- `Resources/thumbnail-dynamic.png` — 768×1024 drip overlay drawn over the
  heading.
- `Resources/thumbnail-static.svg` — Source for the static `.icns` document
  icon.

**App/Tests/ key files:**

- `TestSupport.swift` — Async pumping helpers (`pump`, `pumpUntil`), the
  temp-directory fixture, and the `MudComment` alias
- `FindStateTests.swift` — The find state machine: origin classification,
  navigation, reset behavior
- `DocumentModelTests.swift` — The self-write dedup policy, the watcher
  hold/echo policy against real temp files, the folder window in both behaviors
  (the `.tabs` blank page with its notice and no watcher, the `.index` document
  and its re-walk), and the waypoint-provider seam
- `CommentControllerTests.swift` — Comment mutations on disk and the
  `anchorFailed` / `writeFailed` matrix
- `CommentSubmissionHandlerTests.swift` — What the handler answers the column
  over `resolveSubmission`, for every action including the ones with no compose
  box
- `OpenInFormatTests.swift` — The Open In `.auto` format truth table
- `OpenPanelFilterTests.swift` — The open panel's Enable filter: type lists and
  the raw-value-to-menu-index contract
- `DocumentNoticeTests.swift` — Raising and clearing the info bar's notice
- `MarkdownFolderTests.swift` — Which files a folder open yields (top level
  only, hidden files and packages excluded) and the nil / empty distinction
- `FolderIndexTests.swift` — The tree walk (depth, pruning, order, symlinks,
  the file limit) and the document written from it (nesting, relative paths,
  escaping)
- `LocalAssetProbeTests.swift` — The probe's three answers against real temp
  files; the denied case uses mode `000` and is skipped when running as root
- `AssetAccessStoreTests.swift` — `reduce` and `covers`: the de-duplication
  truth table, that a shared name prefix isn't containment, and what an
  unavailable `Grant` still knows about itself
- `BlockedAssetLogTests.swift` — The resolver's three answers against real temp
  files: only a denial reaches the log
- `AvatarChoicesTests.swift` — Every curated avatar passes
  `CommentAvatar.isValid`, the entries are distinct, and they fill whole rows
- `CommentColumnFitTests.swift` — `CommentColumnFit.remedy` truth table
- `AddCommentRuleTests.swift` — `ActiveDocumentSnapshot.canAddComment` truth
  table: the one rule every Add Comment affordance applies
- `WebViewParsingTests.swift` — `parseMatchInfo` and `commentSignature`
- `MudJSBridgeTests.swift` — Outbound script building (escaping) and inbound
  message decoding, including the `mudPopover` payload
- `GitProviderTests.swift` — Waypoint assembly and git-output parsing over a
  scripted runner (`#if GIT_PROVIDER`)

**Resources:**

- `mud.css` — Shared styles and lighting variables
- `mud-up.css` — Up mode styles. Its foldable-headings block sits inside
  `@media screen` — paper always gets the whole document, so `mud-print.css`
  only hides the arrows
- `mud-down.css` — Down mode styles
- `mud-comments.css` — Comments column styles (read side, bundled everywhere):
  markers, quotation highlights, the bottom Comments section, and the projected
  column. The bottom section is a `<footer>` beside the article, not inside it,
  so these rules give it a matching Up-mode page box (`--up-page-inset` /
  `--up-page-clearance`, published by `mud-up.css`). It sets no background, so
  it sits on `--body-bg`. The `is-stub` capsule is a folded section's stand-in:
  5px tall and empty, its `title` carrying the text
- `mud-comments-edit.css` — Comments column styles (write side, app only): the
  compose box, the add / reply / edit / delete controls, and the delete puff.
  Embedded only when `RenderOptions.commentsEditable` is set, so exports omit
  it. Mirrors the `mud-comments.js` / `mud-comments-edit.js` split
- `mud-narrow.css` — Every width-based rule for both modes, in two tiers:
  Compact (≤ 700px) and Tight (≤ 420px, Finder's column-view pane). Both scoped
  to `@media screen`, since a printed page is narrower than 700 CSS px.
  Included second-to-last, before `mud-print.css`. Below Compact the Comments
  column stands down in favor of the bottom section — the column's own blocks
  carry a matching `min-width: 700.02px` guard, so they stop applying rather
  than being undone here. The Tight tier's 14px type rule is the one a document
  can opt out of, via `html:not(.is-zoom-locked)`
- `mud-print.css` — Every `@media print` rule, gathered out of the mode and
  comments stylesheets. Included last in both modes so it wins
- `mud-find.css` — Find highlight styles, themed via the lighting variables in
  `mud.css`. Appended only when `!options.standalone`, so exports never carry
  it
- `mud-math.css` — MathML styles: display-block layout plus per-engine spacing
  and accent rules adapted from Temml-Local.css. Appended to an Up document
  only when its body contains math, so a math-free document never carries it.
  No matching JS — MathML renders natively
- `mud-diagram.css` — Diagram styles: the `.mermaid` layout rules, the wash
  opacities `mermaid-init.js` marks shapes for, and `--diagram-font`, the label
  face the init script reads and hands to Mermaid — here the Simplicity look's
  stack, the page's own sans. Two more concerns are covered here:
  `foreignObject` gets `overflow: visible`, since Caveat's letters trail past
  the advance width Mermaid sized the box to; and every label sitting on a line
  is made readable — SVG text (`.messageText`, `.relationshipLabel`) takes a
  halo in the page's ground, and the plates Mermaid draws half-transparent
  (`.labelBkg` on a state transition, `.relationshipLabelBox` on an ER
  relationship) are made opaque in that same ground. Three Gantt rules live
  here because no theme variable reaches them: the grid's vertical rules are
  `<line stroke="currentColor">`, and that attribute beats the `stroke` the
  `.tick` group around it inherits — which is all `gridColor` sets — so they
  come out black however the page is lit; a milestone takes the accent, held
  off the wash rim by name so the rim keeps its own color; and the section
  bands are forced opaque, since `mermaid-init.js` already names them at the
  strength they should be seen at and Mermaid's own 0.2 left the banding
  invisible. The INVALID badge and the parse message it opens are here too; the
  message rule is unscoped and carries no margin, because it is also the whole
  body of the popover. `wrapUp` appends this file when the body holds a Mermaid
  block _and_ the extension is on — or when it holds a `mud-diagram-error`,
  which is how the popover document gets these rules with no block to draw
- `mud-diagram-font.css` — The Handwritten look's label font: the Caveat
  `@font-face` (variable weight, Latin subset, embedded as a data URI so the
  labels need no second request and no swap up from the fallback face — an
  export still loads `mermaid.min.js` from a CDN, so it is not offline), and
  `--diagram-font` named again over the Simplicity stack — this file is
  appended after `mud-diagram.css`, so the second declaration is what switches
  the look. `wrapUp` adds it only for
  `RenderOptions.diagramLook == .handwritten`, and gives that document
  `font-src data:` along with it — without the directive `default-src 'none'`
  blocks the font and the labels quietly fall back to system-ui. Roughly 100
  KB, which is why the Simplicity look ships none of it
- `mud.js` — Shared JS: find, scroll, lighting, zoom. Find and outline
  navigation unfold their target first (`Mud.folds`); `setClass` routes
  `is-foldable-headings` to `folds.setEnabled`. `Mud.popover.show(rect, html)`
  is the one way to ask the app for a native popover over page-built HTML; it
  returns false where there is no app to ask, so the caller can fall back to
  something the page does itself
- `mud-changes.js` — Change tracking JS: overlays, expand/collapse, navigation
- `mud-comment-anchor.js` — Shared comment-anchoring primitives
  (`Mud.commentAnchor`): the leaf-block and marker-free-text rules that map a
  rendered-DOM position to a block of source text. `anchorableEnd` comes first:
  WebKit ends a selection dragged past a line at a boundary in the block
  _below_, so the end is walked back to the last text it really covers.
  `HTMLTemplate.mudCommentsJS` concatenates it ahead of `mud-comments.js`, so
  it ships wherever the read side does. Its skip rules (comment markers,
  footnote references, math, and the inline `<del>` a tracked change's removed
  words render as) match `CommentAnchor.swift`, mirrored in
  `CommentAnchorParityTests`
- `mud-comments.js` — Comments column (read side, bundled everywhere): projects
  a capsule per comment from the hidden bottom section, anchors quotation
  highlights off the hidden markers, runs the slot solver, and on `setData`
  rebuilds and reprojects in place (no reload). A marker click doesn't open the
  column itself: it posts `mudRevealColumn` and waits for the app to make room
  and call `openToComment`. An export has no app to ask, so it picks on the
  column's own width. `foldOver` asks `Mud.folds.hiding` — null wherever
  folding doesn't exist, so an export takes no fold branch; comments hidden by
  one fold collapse to a single stub
- `mud-comments-edit.js` — Comments column (write side, app only): the Add
  Comment button on a commentable selection, the compose box, and the
  submit/reply/edit/delete bridge (`mudCommentSubmit`)
- `mud-up.js` — Up-mode JS: link routing, footnote-marker clicks, and
  `Mud.folds`. Folds keeps the folded headings' slugs and recomputes every
  block's visibility from that set in one walk, stamping each hidden block with
  `data-fold-host` — which is what keeps a sub-section folded when its parent
  opens. The app replays the set through `folds.apply` after a reload; the page
  reports it back over `mudFolds`. Every navigation that scrolls calls
  `folds.reveal` first, since WebKit can't scroll to a hidden target
- `mud-down.js` — Down-mode JS
- `emoji.json` — GitHub gemoji shortcode database
- `alert-*.svg` — Octicon alert icons
- `fold-arrow.svg` — The foldable-headings arrow, drawn pointing down (folded
  rotates it -90°). `HTMLTemplate.mudUpJS` substitutes it into `mud-up.js`
- `theme-*.css` — Four user-selectable theme files (austere, blues, earthy,
  riot)
- `theme-system.css` — System theme (internal; used for error pages)
- `mermaid.min.js` — Mermaid diagram library (v11, UMD build)
- `mermaid-init.js` — Mermaid init and render for Up mode. Reads the page's
  `--diagram-*` variables through `getComputedStyle` (Mermaid computes the rest
  of its palette from them, so it needs resolved values) and hands them over as
  theme variables, flattened onto the ground first (a theme may write a
  translucent color — Austere's `--code-bg` is a green at 3.5% alpha — and
  Mermaid picks some label colors by inverting a fill, which on a near-
  transparent one yields a label you can't read). It runs with
  `look: handDrawn` and a fixed `handDrawnSeed` — an unseeded wobble would
  redraw differently on every content change. `labelFont` reads
  `--diagram-font` the same way and passes it to Mermaid as `fontFamily`, since
  Mermaid measures each label's box with the font it is given: that one
  property is the whole difference between the Simplicity and Handwritten
  looks. Mermaid derives every categorical color (pie slices, journey and
  timeline sections, git branches) from its primary/secondary/tertiary colors,
  which for us are three near-neighbors out of one theme — so `ramp` supplies
  them instead, one hue circle walked in twelve steps from the accent's hue. It
  is called twice, because the two jobs want opposite lightness: colors that
  carry text (`pie1`…`pie12`, `cScale0`…`cScale11`, `git0`…`git7`, with
  `cScaleLabel*` and `gitBranchLabel*` named as the page's ink) are pitched
  toward the ground so that ink reads over them, while a chart's bars and lines
  (`xyChart.plotColorPalette`, the one list an xy chart reads) take a mid tone
  so they stand out from it. `isDarkGround` decides which way by comparing
  `--diagram-bg` against `--diagram-fg`, not by a media query. Every ramp color
  is written as hex by `hslHex`, because `plotColorPalette` is one
  comma-separated string and an `hsl(20, 45%, 43%)` in it is torn into three
  entries that name no color — which draws the bars in SVG's default black and
  the line with no stroke at all. Gantt and xy charts each read a set of
  variables of their own, so both sets are named in full: Mermaid otherwise
  defaults a Gantt to literal colors no theme reaches (white alternating bands,
  a grey done bar, a red today line) and builds an xy chart's config from its
  _default_ theme, not the base one the rest of the page uses. The `bars` block
  holds the Gantt's three task states, and unlike everything else here those
  are final colors — a Gantt takes no glaze, so each is named at the strength
  it is seen at. None of the fills is a color at full strength, since every bar
  carries a label in the page's ink; the accent goes on the active bar's border
  instead. After the run it applies the watercolor wash: node and cluster fills
  become a glaze, and a clone of each outline, stroked in the fill color, pools
  the pigment at the edge. Only shapes filled in a palette color are glazed,
  which leaves a state diagram's start and end dots alone. `WASHABLE_BAR` adds
  an xy chart's bars, which are one series and lose nothing to a uniform glaze;
  a Gantt's don't take one, because its three states have to be told apart at a
  glance and the glaze costs most of the difference between them. Only a shape
  that names its own `fill` is glazed, which is what keeps the wash off the
  families Mermaid fills from a class — a mindmap above all, whose every shape
  is filled by a `.section-N` rule and which draws its edges up to 17px wide
  underneath them, so an opaque fill is the point. It keeps each diagram's
  source on the container, because a lighting change has to draw them all again
  — the colors are baked into the SVG, and only a theme change reloads the
  document. Each container is run on its own and chained, not handed to Mermaid
  as one list: a rejection would otherwise be the whole pass's result and every
  diagram that did draw would lose its wash, and two runs alive in the same
  millisecond would be given the same temporary id. A diagram that won't parse
  takes the path in `showError` — Mermaid's own bomb graphic is off
  (`suppressErrorRendering`), so the block goes back as the reader wrote it
  with an INVALID badge in its corner.
- `temml.min.js` — Temml TeX-to-MathML library (v0.13.3, MIT). Loaded into a
  `JSContext` by `MathRenderer`; renders server-side, never shipped in exports
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
- `Doc/Local/site-maintenance-guide.md` — How `Site/` works: the magic numbers
  in the header CSS, which stylesheets track which app stylesheet, and what the
  inline JS in `index.html` does. `Site/` ships with no build step and its CSS
  and JS carry **no comments**, so explanations go in this guide

**Important** — Keep this section in sync when you add or remove key files.


## Rendering pipeline

Both modes start from one `ParsedMarkdown`, which holds a single footnote-aware
cmark parse (`CMarkDocument`) of the source. Every consumer — the visitors,
heading extraction, and the diff layer — reads that one tree; no one re-parses.

```
RenderOptions (configuration value type)
  ↓
Markdown string (up mode)
  → MudCore.renderUpPipeline
    → FootnoteProcessor.process  (footnote + comment models; no rewriting)
    → ParsedMarkdown             (one footnote-aware cmark parse)
    → UpHTMLVisitor.renderBody   (AST → HTML body; markers emitted from the AST,
                                  SlugGenerator adds heading IDs,
                                  MathRenderer converts TeX to MathML,
                                  DiffContext adds change overlays)
    → FootnoteHTMLRenderer + CommentHTMLRenderer  (bottom sections appended)
  → HTMLTemplate.wrapUp()        → full HTML document (CSS + JS inlined)
  → WKWebView

Markdown string (down mode)
  → ParsedMarkdown               (the same parse)
  → DownHTMLVisitor              → syntax-highlighted raw-source table
                                  (highlightWithChanges projects a ChangePlan
                                  when a waypoint is set)
  → HTMLTemplate.wrapDown()      → full HTML document (CSS + JS inlined)
  → WKWebView
```

Both modes render into the same WKWebView; toggling mode swaps the HTML
document. All public rendering functions take a `RenderOptions` value bundling
configuration (theme, baseURL, docCAlertMode, commentMode, waypoint, …); adding
an option means adding a field on the struct.

Footnotes and comments are **not** rewritten into the source.
`FootnoteProcessor` scans the source once to build the models for the bottom
sections, and the Up visitor emits every marker straight from the AST. The
bottom `<section class="footnotes">` is always emitted; in `.popover` mode it
is hidden on screen (`is-print-only`, shown under `@media print`) and
`renderUpModeDocumentWithFootnotes` also returns each footnote body as a
self-contained document for the in-app `NSPopover`.


### Comments

A footnote whose label `CommentLabel` recognizes — `💬-a`, or the older
equivalent `comment-a` — is a comment. Its reference renders as a `[⋯]` marker
(consuming no footnote number) and its definition parses into a quotation plus
threaded messages. `RenderOptions.commentMode` selects the output: `.section`
emits a visible bottom Comments section with visible `💬` markers, while
`.interactive` keeps that section `is-print-only` and instead draws
hover-revealed highlights and feeds the Comments Column. The live app and
exports are always `.interactive` (`exportDocument` upgrades a commented source
through `showingReadOnlyComments`) — except Quick Look, which passes
`commentsColumn: false` and stays on `.section`. Without `.interactive` the
document carries neither the `comments-column` class nor the column script, so
there is nothing to project and nothing for a media query to hide.

Each message may carry an **avatar** — one emoji leading its attribution, kept
on `CommentMessage.avatar` so a thread rewrite puts every message's own back.
Mud writes the `comment-avatar` preference (`👤` unless the reader changes it,
resolved once in `CommentSubmissionHandler`); a message with none is drawn with
`CommentAvatar.fallback`. `CommentHTMLRenderer` writes the resolved glyph into
the attribution and the raw one as `data-mud-avatar`, present only when the
source names one — which is how `mud-comments.js` tells an explicit avatar from
the fallback when it projects a capsule.

The section is emitted as a `<footer class="comments">` **outside** the
`<article>`, as its next sibling, always after any footnotes section. Being a
sibling, it can't inherit the article's page box, so `mud-up.css` publishes
that box as `--up-page-inset` / `--up-page-clearance` and `mud-comments.css`
gives the footer a matching one.

Comments are **invisible to change tracking**, through two mechanisms in the
leaf-block collector (`BlockMatcher`):

- Comment **definitions** never become leaf blocks. `visitFootnoteDefinition`
  drops any definition whose label is a comment label, on either policy.
- Inline comment **references** are stripped from each block's fingerprint
  (`FootnoteProcessor.stripCommentTokens`), so a paragraph that only gains or
  loses a `[^comment-x]` marker produces no change.

Rendering keeps the same promise: a deletion render emits no comment marker
(`UpHTMLVisitor.isDeletionRender`), so the surviving block's marker stays the
label's only `data-mud-label` anchor in the DOM — otherwise the Comments column
would anchor the capsule to a hidden deleted copy and drop it.

So a comment-only edit yields zero changes and no new waypoint across all three
diff consumers (sidebar, Up overlay, Down highlighting). The sidebar picks its
policy from the on-screen mode (`MudCore.computeChanges(old:new:mode:)`: `.up`
→ `.skipAll`, `.down` and waypoint dedup → `.descendPlainFootnotes`), because
change IDs are a running counter — a definition edit that one mode draws and
the other doesn't must not renumber the visible list. Correspondingly, the
Up-mode `contentID` is **comment-invariant**
(`DocumentContentView.displayContentID` hashes `MudCore.removeComments(...)`),
so a comment add/remove updates the live Up view in place with no reload; Down
mode keeps the full markdown so its raw source stays current.


### Math

Math is rendered in the Up visitor by `MathRenderer` (Temml in a `JSContext`,
server-side, no client JS). Three GFM forms are recognized: a ```` ```math ````
fenced block (`visitCodeBlock`), a paragraph that is exactly `$$…$$`
(`visitParagraph`), and inline `` $`…`$ `` (`visitInlineCode`). For the `$$…$$`
form the visitor reads the paragraph's **raw source bytes** rather than its
children, because cmark has already inline-parsed the interior (turning `_`
into emphasis); a bare `$…$` is deliberately not math. Math-bearing blocks take
whole-block change annotations and never word-level spans (like code blocks),
so `WordSpanEmitter` can't desync; inline math renders only when the emitter is
inactive. Comment anchoring skips math on both sides.


## State management

Five ObservableObject classes, no nesting:

- **AppState** (singleton) -- persisted preferences as `@Published` mirrors:
  `lighting`, `theme`, `viewToggles`, `sidebarEnabled`, …
- **ActiveDocumentObserver** (singleton) -- publishes an
  `ActiveDocumentSnapshot?` of the key document window (mode, editable,
  commentable, column visibility) for app-menu labels and enablement; `nil`
  when no document window is key
- **DocumentState** (per-window) -- `mode`, per-window zoom levels and
  sidebar-pane selection (each seeded from `MudPreferences` at window creation,
  re-persisted on change so the next window opens at the last-used value), the
  `webCommands` channel, `outlineHeadings`, `contentTitle`, comments-column
  state, the info bar's `notice`, owns `FindState`
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
`updateNSView` diffs only declarative state (contentID, mode, zoom, classes,
comments, search — the theme rides in the contentID). Cmd+R calls
`DocumentModel.load(forced:)`, whose bumped load token changes the contentID so
the page reloads even when the file's text hasn't.

All Swift ↔ page traffic goes through `MudJSBridge` (`App/MudJSBridge.swift`):
outbound `bridge.call("comments.setData", …)` JSON-encodes every argument and
logs JS errors; inbound `window.webkit.messageHandlers` posts decode into the
typed `MudJSMessage` enum (the message table is documented on that enum). The
popover uses the same bridge type for its `mudOpen` link routing.

`mudPopover` is the one inbound message whose payload is HTML rather than a
label, a number, or a flag, so it is worth knowing what bounds it. Only Mud's
own injected `WKUserScript`s can post it: a rendered document is served
`script-src 'none'`, so nothing in the Markdown can run script and reach a
message handler at all. It is still not a place for anything a document
supplies verbatim — a caller showing document text escapes it first.


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


### The Comments column and narrow widths

Every command that needs the column — Add Comment, Show Comments, and a marker
click (`mudRevealColumn`) — routes through `CommentColumnFit` first, which
widens the window, else offers to collapse the sidebar, else turns the toggle
on anyway and scrolls to the bottom section (`WebCommand.scrollToComments`,
taking the clicked comment's label when there is one). Below
`Layout.compactBreakpoint` the column stands down in favor of that section; see
`mud-narrow.css`.


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


#### Local content

Opening a document grants the sandboxed build that one file, so an image beside
it can't be read and renders broken. Three pieces answer that:

- `LocalAssetProbe` tells a denial from a wrong path, so only the first is
  reported. `DocumentModel.resolve` runs it in place of the old file-exists
  check and hands each denied file to a `BlockedAssetLog`.
- `DocumentModel.reportBlockedAssets` raises
  `DocumentNotice.localAssetsBlocked` from what the render found — through
  `deferMutation`, since the render runs inside SwiftUI's `body`, and only
  `if isSandboxed`.
- The notice's button carries `Action.Effect.grantFolderAccess`, which
  `DocumentNoticeBar` performs by asking `AssetAccessStore` for a folder. The
  bookmark taken with the grant
  (`com.apple.security.files.bookmarks.app-scope`, resolved by `AppDelegate` at
  launch) is what makes it survive a quit. Every window runs
  `reloadForAssetAccessChange` on a grant, since it can unblock a document in
  any of them.

This is the only notice re-derived on every render, so it carries two rules the
others don't need. `lastBlockedReport` ignores an answer matching the last one,
which keeps a dismissed bar down across the re-renders a mode toggle or theme
change causes; `blockedAssetsMayRaise` stops it taking the bar from another
notice, which would otherwise lose `externalChangeHeld` for good. Only Up mode
probes an image, so `reloadForAssetAccessChange` clears the notice outright in
Down mode.

The reader sees and takes back these grants in Settings → Up Mode → Content
permissions, beside "Allow remote content": both decide what a rendered
document may load, and neither applies in Down mode.

Quick Look reaches none of this: it renders through `ImageDataURI` in its own
extension process, which can use neither the app's sandbox extensions nor its
bookmarks.


### Deferred mutations in SwiftUI

Setting an `@Published` property from inside the view-update pipeline
(`onKeyPress`, `onChange`, `updateNSView`, Combine sinks fired during updates)
triggers SwiftUI's "Publishing changes from within view updates is not allowed"
warning and undefined behavior. Use `deferMutation` (`App/DeferMutation.swift`)
to push the mutation to the next run-loop iteration. Don't use it for unrelated
async dispatch such as background thread-hops or intentional delays.
