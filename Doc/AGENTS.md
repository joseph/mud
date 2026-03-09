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


## File quick reference

**App/ key files:**

- `MudApp.swift` — @main, menu commands, AppState

- `AppDelegate.swift` — Lifecycle and document handling

- `DocumentController.swift` — NSDocumentController subclass

- `DocumentWindowController.swift` — Per-window state, toolbar, zoom, lighting

- `DocumentState.swift` — Per-window observable state

- `DocumentContentView.swift` — Main SwiftUI view for a document

- `WebView.swift` — WKWebView wrapper, JS bridge

- `OutlineSidebarView.swift` — Table of contents sidebar

- `OutlineNode.swift` — Sidebar data model

- `FindFeature.swift` — Search state and UI

- `FileWatcher.swift` — DispatchSource file monitoring

- `CommandLineInstaller.swift` — CLI symlink creation with elevation support

- `LocalFileSchemeHandler.swift` — `mud-asset:` URL scheme for local images

- `DeferMutation.swift` — Run-loop deferred state mutation helper

- `Lighting.swift` — auto/bright/dark enum

- `Mode.swift` — up/down enum

- `Theme.swift` — austere/blues/earthy/riot enum

- `ViewToggle.swift` — readableColumn/lineNumbers/wordWrap toggles

- `ErrorPage.swift` — Error-page HTML generator (renders Markdown via MudCore)

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

- `UpModeSettingsView.swift` — Up Mode settings pane (placeholder)

- `DownModeSettingsView.swift` — Down Mode settings pane

- `CommandLineSettingsView.swift` — Command Line settings pane

**Core/ key files:**

- `MudCore.swift` — Public API: renderUpToHTML, renderDownToHTML,
  renderUpModeDocument, renderDownModeDocument, extractHeadings
- `Rendering/UpHTMLVisitor.swift` — AST → rendered HTML
- `Rendering/DownHTMLVisitor.swift` — AST → syntax-highlighted raw HTML
- `Rendering/HTMLTemplate.swift` — Document wrapping and resource loading
- `Rendering/MarkdownParser.swift` — swift-cmark wrapper
- `Rendering/SlugGenerator.swift` — Heading ID generation
- `Rendering/HeadingExtractor.swift` — Heading extraction for sidebar
- `Rendering/CodeHighlighter.swift` — Syntax highlighting via highlight.js
- `Rendering/EmojiShortcodes.swift` — `:shortcode:` → emoji replacement
- `Rendering/ImageDataURI.swift` — Image encoding for browser export
- `OutlineHeading.swift` — Heading model shared between Core and App

**Resources:**

- `mud.css` — Shared styles and lighting variables
- `mud-up.css` — Up mode styles
- `mud-down.css` — Down mode styles
- `mud.js` — Shared JS: find, scroll, lighting, zoom
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

**Important** — Make sure to update this section of `Doc/AGENTS.md` if you add
or remove key files.


## Rendering pipeline

```
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

MudCore exposes: `renderUpToHTML(_:)`, `renderDownToHTML(_:)`,
`renderUpModeDocument(_:)`, `renderDownModeDocument(_:)`,
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
icons, UserDefaults persistence).


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


### Sandbox-aware features

The app detects sandboxing at runtime via `isSandboxed` (checks
`APP_SANDBOX_CONTAINER_ID`). When sandboxed (Mac App Store build), certain
features are hidden or adapted:

- **CLI installer** — The Command Line settings pane shows manual `ln -s`
  instructions instead of the automatic Install button.
- **Open in Browser** — Hidden entirely. The app writes a temp HTML file and
  hands it to the default browser. In the sandbox, temp files live inside the
  app's container directory, which other apps (Safari, Chrome) cannot read. The
  system `/tmp` is readable by other apps but not writable by sandboxed apps.
  No workaround exists, so the feature is hidden.

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
