Plan: Mermaid Diagrams Toggle
===============================================================================

> Status: Complete


## Context

Mermaid diagram rendering was always enabled in Up Mode. The `RenderExtension`
system detects `language-mermaid` code blocks and injects mermaid.min.js at
runtime, but there was no way for the user to disable this.

A toggle in the Up Mode settings pane lets users turn off diagram rendering.
When disabled, mermaid code blocks remain as syntax-highlighted `<pre><code>`
blocks.


## Design

`RenderOptions.extensions` is the single source of truth for which extensions
are active. Both HTMLTemplate (embedded export) and WebView (runtime injection)
read from it. `AppState` persists a set of enabled extension names; this set
flows into `renderOptions.extensions` in `DocumentContentView`, and is also
passed directly to `WebView` for runtime injection gating.

Because `extensions` is part of `RenderOptions.contentIdentity`, toggling an
extension in settings automatically triggers a re-render.


## Current flow

```
UpHTMLVisitor
  → <pre><code class="language-mermaid">…</code></pre>

WebView (runtime, WKWebView):
  → filters enabled extensions by marker presence in HTML
  → didFinish injects each extension's runtimeJS() sequentially

HTMLTemplate (export, Open in Browser / CLI --browser):
  → loops over options.extensions, checks marker, embeds scripts + CSP
```


## Changes

### 1. Add `enabledExtensions` to `AppState`

Added `@Published var enabledExtensions: Set<String>` to `AppState`, persisted
via UserDefaults key `"Mud-EnabledExtensions"`. Defaults to all registry keys.
Saved values are intersected with registry keys on load to ignore stale
entries.


### 2. Flow extensions through `RenderOptions`

`DocumentContentView` sets
`renderOptions.extensions = appState.enabledExtensions`. Content identity
includes the extensions set, so toggling triggers a re-render automatically.


### 3. Gate runtime injection in `WebView`

`WebView` accepts an `extensions` set, resolves extensions from the registry by
name, and filters by marker presence in HTML.


### 4. Add toggle to `UpModeSettingsView`

Added a "Generate Diagrams" toggle in `UpModeSettingsView` with a link to the
bundled `mermaid-diagrams.md` example. The binding inserts/removes `"mermaid"`
from `appState.enabledExtensions`.


### 5. Use registry for CLI browser export

`App/CLI/main.swift` sets
`options.extensions = Set(RenderExtension.registry.keys)` so browser export
automatically picks up all registered extensions.


### 6. Update `Doc/AGENTS.md`

Updated the `UpModeSettingsView.swift` description.


## Files changed

| File                                    | Change                                    |
| --------------------------------------- | ----------------------------------------- |
| `App/AppState.swift`                    | Add `enabledExtensions` set + persist     |
| `App/DocumentContentView.swift`         | Flow extensions through `renderOptions`   |
| `App/WebView.swift`                     | Accept `extensions` set, resolve + filter |
| `App/Settings/UpModeSettingsView.swift` | Add Generate Diagrams toggle              |
| `App/CLI/main.swift`                    | Use registry keys for browser export      |
| `Doc/AGENTS.md`                         | Update settings file reference            |
