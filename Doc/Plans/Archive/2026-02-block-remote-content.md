Block remote content setting for Up Mode
===============================================================================

> Status: Complete


## Context

The Up Mode settings pane is currently a placeholder with no options. Markdown
documents can reference remote images via HTTPS URLs, which the WKWebView loads
automatically. A security-conscious user may want to prevent this -- remote
images can leak IP addresses, track document opens, or serve unwanted content.

The existing Content Security Policy in Up Mode already controls image loading:

```
img-src mud-asset: data: https:
```

Removing `https:` from this directive blocks all remote images while still
allowing local images (`mud-asset:`) and inline data URIs (`data:`). This is
the simplest and most robust mechanism since the CSP is enforced by WebKit
itself.


## Plan

### 1. AppState -- add `blockRemoteContent` property

**File:** `App/MudApp.swift`

Add a `@Published var blockRemoteContent: Bool` property to `AppState`,
persisted to UserDefaults under the key `Mud-blockRemoteContent`. Default:
`false` (remote content loads normally).

Follow the existing pattern for `quitOnClose`:

```swift
@Published var blockRemoteContent: Bool {
    didSet { UserDefaults.standard.set(blockRemoteContent, forKey: "Mud-blockRemoteContent") }
}
```

Initialize from UserDefaults in `init()`.


### 2. HTMLTemplate -- accept `blockRemoteContent` parameter

**File:** `Core/Sources/Core/Rendering/HTMLTemplate.swift`

Add `blockRemoteContent: Bool = false` to `wrapUp()`. When `true`, emit the CSP
with `img-src mud-asset: data:` (no `https:`). When `false`, keep the current
CSP unchanged.


### 3. MudCore -- thread the parameter through

**File:** `Core/Sources/Core/MudCore.swift`

Add `blockRemoteContent: Bool = false` to `renderUpModeDocument()`. Pass it
through to `HTMLTemplate.wrapUp()`.


### 4. DocumentContentView -- pass the setting, trigger reload on change

**File:** `App/DocumentContentView.swift`

- Pass `appState.blockRemoteContent` to `MudCore.renderUpModeDocument()` in the
  `modeHTML` computed property.
- Include the setting in `contentID` so the WebView detects the change and
  performs a full HTML reload (the CSP is baked into the document, so a
  JavaScript-only update is insufficient).


### 5. UpModeSettingsView -- replace placeholder with a toggle

**File:** `App/Settings/UpModeSettingsView.swift`

Replace the placeholder text with a `Form` containing a toggle, following the
`DownModeSettingsView` pattern:

```
[x] Block remote content
    Prevents loading of remote images and other external
    resources. Only local images will be displayed.
```


## Files to modify

| File                                             | Change                         |
| ------------------------------------------------ | ------------------------------ |
| `App/MudApp.swift`                               | Add property to AppState       |
| `Core/Sources/Core/Rendering/HTMLTemplate.swift` | CSP parameter                  |
| `Core/Sources/Core/MudCore.swift`                | Thread parameter               |
| `App/DocumentContentView.swift`                  | Pass setting, update contentID |
| `App/Settings/UpModeSettingsView.swift`          | Toggle UI                      |


## Verification

1. Open a markdown file that references a remote HTTPS image.
2. Confirm the image loads by default.
3. Open Settings > Up Mode, enable "Block remote content".
4. The preview should reload and the remote image should not appear.
5. Local images (relative paths) should still display.
6. Toggle the setting off -- the remote image should reappear.
7. Quit and relaunch -- the setting should persist.
