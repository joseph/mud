Plan: Mermaid Diagrams Toggle
===============================================================================

> Status: Underway


## Context

Mermaid diagram rendering is always enabled in Up Mode. The `RenderExtension`
system (introduced in f16f2d6) detects `language-mermaid` code blocks and
injects mermaid.min.js at runtime, but there is no way for the user to disable
this.

A toggle in the Up Mode settings pane lets users turn off diagram rendering.
When disabled, mermaid code blocks remain as syntax-highlighted `<pre><code>`
blocks (same as Down Mode shows them).


## Design

`RenderOptions.extensions` is the single source of truth for which extensions
are active. Both HTMLTemplate (embedded export) and WebView (runtime injection)
read from it. `AppState` persists a set of enabled extension names; this set
flows into `renderOptions.extensions` in `DocumentContentView`, and is also
passed directly to `WebView` for runtime injection gating.

Because `extensions` is part of `RenderOptions.contentIdentity`, toggling an
extension in settings automatically triggers a re-render — no separate content
ID hack is needed.


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

In `App/AppState.swift`:

- Add `@Published var enabledExtensions: Set<String>`.
- UserDefaults key: `"Mud-EnabledExtensions"` (persisted as `[String]`).
- Default: all keys from `RenderExtension.registry`.
- Intersect saved values with registry keys on load (ignores stale entries).
- Add `saveEnabledExtensions()` method.


### 2. Flow extensions through `RenderOptions`

In `App/DocumentContentView.swift`:

- Set `renderOptions.extensions = appState.enabledExtensions`.
- Remove the separate `disabledExtensions` computed property.
- `displayContentID` uses `renderOptions.contentIdentity` (which already
  includes `extensions.sorted()`), so no extra content ID logic is needed.
- Export (Open in Browser) inherits the same extensions from `renderOptions`
  instead of hard-coding `"mermaid"`.


### 3. Gate runtime injection in `WebView`

In `App/WebView.swift`:

- Replace `disabledExtensions: Set<String>` with `extensions: Set<String>`.

- `updateNSView` resolves extensions from the registry by name, then filters by
  marker presence:

  ```swift
  context.coordinator.activeExtensions = extensions.compactMap {
          RenderExtension.registry[$0]
      }
      .filter { html.contains($0.marker) }
  ```


### 4. Add toggle to `UpModeSettingsView`

In `App/Settings/UpModeSettingsView.swift`, add a section with a "Mermaid
Diagrams" toggle. The binding inserts/removes `"mermaid"` from
`appState.enabledExtensions`. Place it after the "Allow Remote Content"
section.


### 5. Use registry for CLI browser export

In `App/CLI/main.swift`, replace `options.extensions.insert("mermaid")` with
`options.extensions = Set(RenderExtension.registry.keys)` so browser export
automatically picks up all registered extensions.


### 6. Update `Doc/AGENTS.md`

Add setting names to the `UpModeSettingsView.swift` bullet.


## Files changed

| File                                    | Change                                    |
| --------------------------------------- | ----------------------------------------- |
| `App/AppState.swift`                    | Add `enabledExtensions` set + persist     |
| `App/DocumentContentView.swift`         | Flow extensions through `renderOptions`   |
| `App/WebView.swift`                     | Accept `extensions` set, resolve + filter |
| `App/Settings/UpModeSettingsView.swift` | Add Mermaid Diagrams toggle               |
| `App/CLI/main.swift`                    | Use registry keys for browser export      |
| `Doc/AGENTS.md`                         | Update settings file reference            |


## Verification

- Settings → Up Mode shows a "Mermaid Diagrams" toggle (default: on).
- With toggle on: mermaid code blocks render as diagrams.
- With toggle off: mermaid code blocks render as syntax-highlighted source.
- Toggling triggers an immediate re-render of the current document.
- Down Mode is unaffected regardless of toggle state.
- Open in Browser respects the toggle (disabled = no mermaid scripts embedded).
- CLI `--browser` embeds all registered extensions.
