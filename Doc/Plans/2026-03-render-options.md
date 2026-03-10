Plan: Render Options
===============================================================================

> Status: Underway


## Context

Every new rendering option (e.g. `doccAlertMode`, the upcoming `embedMermaid`)
requires changes to multiple MudCore function signatures,
`HTMLTemplate.wrapUp`, and every call site (`DocumentContentView`, CLI,
open-in-browser). The `stash@{0}` conflict is a direct example: adding
`embedMermaid: Bool` to `renderUpModeDocument` and `wrapUp` touched four files
and conflicted with the `doccAlertMode` parameter that landed on `main`.

The root cause is that rendering options are threaded as individual function
parameters rather than grouped into a value type. This plan introduces a
`RenderOptions` struct in MudCore that bundles all rendering configuration,
making signatures stable across future additions.


## Design

### `RenderOptions` — a value type in Core

A single, flat struct that travels from the call site into MudCore's rendering
pipeline. It is `Sendable` and `Equatable` so it can be compared cheaply
(replacing the manual `displayContentID` string).

```swift
public struct RenderOptions: Sendable, Equatable {
    // Document wrapping
    public var title: String = ""
    public var baseURL: URL? = nil
    public var theme: String = "earthy"
    public var includeBaseTag: Bool = true
    public var blockRemoteContent: Bool = false
    public var embedMermaid: Bool = false

    // Markdown processing
    public var doccAlertMode: DocCAlertMode = .extended

    public init() {}
}
```

The `resolveImageSource` closure stays as a separate function parameter — it is
a rendering _behavior_, not a configuration value, and keeping it out makes the
struct value-friendly.

New options in the future (e.g. emoji shortcodes, syntax highlighting theme)
become new fields on `RenderOptions`. No function signatures change.


### Why one struct, not separate Up/Down structs

Some fields are Up-only (`baseURL`, `includeBaseTag`, `blockRemoteContent`,
`embedMermaid`). Splitting into `UpRenderOptions` / `DownRenderOptions` would
be precise but adds type proliferation for little benefit — unused fields have
harmless defaults, and the struct is small. A single type keeps the API simple
and matches how `AppState` already stores everything together.


### How it flows

```
AppState (App)
  → builds RenderOptions from its @Published properties
  → passed to MudCore.renderUpModeDocument / renderDownModeDocument
  → MudCore unpacks into UpHTMLVisitor, HTMLTemplate, etc.
```

In the CLI, the same struct is built from parsed arguments:

```
CLI argument parsing
  → builds RenderOptions
  → passed to MudCore
```


## Changes

### 1. Add `RenderOptions` to Core

New file `Core/Sources/Core/RenderOptions.swift`:

```swift
public struct RenderOptions: Sendable, Equatable {
    public var title: String = ""
    public var baseURL: URL? = nil
    public var theme: String = "earthy"
    public var includeBaseTag: Bool = true
    public var blockRemoteContent: Bool = false
    public var embedMermaid: Bool = false
    public var doccAlertMode: DocCAlertMode = .extended

    public init() {}
}
```


### 2. Refactor MudCore public API

Replace the parameter lists with `RenderOptions`:

```swift
// Before (9 parameters for Up document):
public static func renderUpModeDocument(
    _ markdown: String, title: String, baseURL: URL?,
    theme: String, includeBaseTag: Bool, blockRemoteContent: Bool,
    embedMermaid: Bool,
    resolveImageSource: ..., doccAlertMode: DocCAlertMode
) -> String

// After (3 parameters):
public static func renderUpModeDocument(
    _ markdown: String,
    options: RenderOptions = .init(),
    resolveImageSource: ((_ source: String, _ baseURL: URL) -> String?)? = nil
) -> String
```

All four public functions adopt the pattern:

| Function                 | Before     | After                            |
| ------------------------ | ---------- | -------------------------------- |
| `renderUpToHTML`         | 4 params   | `options` + `resolveImageSource` |
| `renderUpModeDocument`   | 8→9 params | `options` + `resolveImageSource` |
| `renderDownToHTML`       | 2 params   | `options`                        |
| `renderDownModeDocument` | 4 params   | `options`                        |

Inside each function, fields are unpacked into `UpHTMLVisitor`, `HTMLTemplate`,
etc. as before — the internal wiring doesn't change.


### 3. Refactor `HTMLTemplate.wrapUp` and `wrapDown`

These internal functions also adopt `RenderOptions` to avoid re-spreading the
fields:

```swift
static func wrapUp(body: String, options: RenderOptions) -> String
static func wrapDown(tableHTML: String, options: RenderOptions) -> String
```


### 4. Update `DocumentContentView`

Add a computed `renderOptions` property that builds the struct from `AppState`:

```swift
private var renderOptions: RenderOptions {
    var opts = RenderOptions()
    opts.baseURL = fileURL
    opts.theme = appState.theme.rawValue
    opts.blockRemoteContent = !appState.allowRemoteContent
    opts.doccAlertMode = appState.doccAlertMode
    return opts
}
```

Replace `displayContentID` with a comparison on `RenderOptions`. Since the
struct is `Equatable`, `WebView` can compare directly instead of hashing a
string.

Simplify `modeHTML`:

```swift
private var modeHTML: String {
    guard case .text(let text) = content else { return "" }
    if state.mode == .down {
        return MudCore.renderDownModeDocument(text, options: renderOptions)
    }
    return MudCore.renderUpModeDocument(text, options: renderOptions,
        resolveImageSource: Self.mudAssetResolver)
}
```

The `openInBrowser` method builds its own options with `includeBaseTag: false`
and (later) `embedMermaid: true`.


### 5. Update CLI

Build a `RenderOptions` from parsed arguments:

```swift
var options = RenderOptions()
options.theme = theme

// for browser export:
options.includeBaseTag = false
options.embedMermaid = true
```


### 6. Update tests

Any test that calls MudCore's public API with explicit parameters switches to
building a `RenderOptions`.


### 7. Extract `AppState` into its own file

Move the `AppState` class from `App/MudApp.swift` into a new
`App/AppState.swift`. AppState is ~80 lines (and growing with each new
setting), referenced from ~10 files across the app, and is conceptually
independent of the `@main` entry point. The small extensions at the bottom of
`MudApp.swift` (`isSandboxed`, `URL.isBundleResource`, `UTType.markdown`) stay
put — they're tiny and app-level.

No other types in the codebase meet this threshold. Other co-located types are
either small, private, single-use, or tightly coupled to their host file.


### 8. Update `Doc/AGENTS.md`

Add `RenderOptions.swift` to the Core file reference and `AppState.swift` to
the App file reference. Update the rendering pipeline section to mention
`RenderOptions`.


## What this does NOT change

- **AppState persistence.** The `@Published` properties, UserDefaults keys, and
  `save*()` methods stay as-is. The boilerplate is repetitive but contained in
  one file and works well with SwiftUI's observation. Refactoring persistence
  (e.g. a `@Persisted` property wrapper) is a separate concern that can be
  addressed later if the number of settings grows significantly.

- **ViewToggle.** The CSS-class toggles flow through `bodyClasses` on
  `WebView`, not through MudCore rendering. They remain separate.

- **WebView parameters.** `WebView` already takes its own set of display-state
  parameters (html, mode, theme, bodyClasses, zoomLevel, etc.). These are view
  state, not rendering options, and stay as-is.


## Files changed

| File                                             | Change                             |
| ------------------------------------------------ | ---------------------------------- |
| `Core/Sources/Core/RenderOptions.swift`          | New: `RenderOptions` struct        |
| `Core/Sources/Core/MudCore.swift`                | Adopt `RenderOptions` in all APIs  |
| `Core/Sources/Core/Rendering/HTMLTemplate.swift` | Adopt `RenderOptions` in wrappers  |
| `App/AppState.swift`                             | New: extracted from `MudApp.swift` |
| `App/MudApp.swift`                               | Remove `AppState` class            |
| `App/DocumentContentView.swift`                  | Build + pass `RenderOptions`       |
| `App/CLI/main.swift`                             | Build + pass `RenderOptions`       |
| `Core/Tests/Core/UpHTMLVisitorTests.swift`       | Update test call sites             |
| `Doc/AGENTS.md`                                  | Add file references                |


## Verification

- All existing tests pass with the new API.
- The stashed `embedMermaid` feature can be applied cleanly by adding the field
  to `RenderOptions` and setting it at the two export call sites — no function
  signature conflicts.
- Adding a future option (e.g. `emojiShortcodes: Bool`) requires only: (1) add
  field to `RenderOptions`, (2) use it inside MudCore's implementation. No
  public API signature changes, no call-site churn.
