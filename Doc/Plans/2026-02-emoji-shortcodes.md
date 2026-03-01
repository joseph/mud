Emoji shortcodes
===============================================================================

> Status: Planning


## Context

GitHub and many markdown tools support `:shortcode:` syntax for emoji
(`:smile:` → 😄). Currently these render as literal text. This change replaces
known shortcodes with Unicode emoji in up mode, using GitHub's gemoji database
(~1,800 shortcodes).


## Approach

Replace shortcodes in `UpHTMLVisitor.visitText` before HTML escaping. Unicode
emoji pass through `HTMLEscaping.escape` unchanged (they contain none of the
four escaped characters). Down mode is unaffected (shows raw source). Inline
code and code blocks are unaffected (separate visit methods).


## Files to create

**`Core/Sources/Core/Resources/emoji.json`** — Download GitHub's gemoji
database (`db/emoji.json`). ~170 KB. Only the `emoji` and `aliases` fields are
used.

**`Core/Sources/Core/Rendering/EmojiShortcodes.swift`** — New module:

- `private static let aliasToEmoji: [String: String]` — built lazily on first
  access from the bundled JSON. Swift guarantees thread-safe static `let`
  initialization. ~1,800 entries from the `aliases` arrays.
- `private static let pattern: NSRegularExpression` — `:[a-zA-Z0-9_+\-]+:`
  matching potential shortcodes.
- `static func replaceShortcodes(in text: String) -> String` — fast path
  returns immediately if no colon in text. Matches pattern, looks up each alias
  in the dictionary. Known aliases replaced with emoji; unknown left as-is.


## Files to modify

**`Core/Sources/Core/Rendering/UpHTMLVisitor.swift`** — Change `visitText`:

```swift
mutating func visitText(_ text: Text) {
    result += HTMLEscaping.escape(
        EmojiShortcodes.replaceShortcodes(in: text.string)
    )
}
```

**`Doc/AGENTS.md`** — Add `EmojiShortcodes.swift` to the Core key files section
and `emoji.json` to Resources.


## Files not modified

- `DownHTMLVisitor.swift` — down mode shows raw source.
- `Package.swift` — `.process("Resources")` picks up `emoji.json`.


## Edge cases

| Input           | Output          | Reason                             |
| --------------- | --------------- | ---------------------------------- |
| `:smile:`       | 😄               | Standard shortcode                 |
| `:+1:`          | 👍               | Special char in shortcode          |
| `:not_real:`    | `:not_real:`    | Unknown alias, left as-is          |
| `10:30:00`      | `10:30:00`      | `30` not in dictionary, left as-is |
| `:smile::+1:`   | 😄👍              | Consecutive, each replaced         |
| `**:rocket:**`  | `<strong>🚀`...  | Text node inside Strong            |
| `` `:smile:` `` | `<code>:smile:` | Inline code, separate visit method |


## Verification

**`Core/Tests/Core/EmojiShortcodesTests.swift`** (new) — Unit tests for the
replacement function: known shortcode, unknown shortcode, no colons, mixed
text, consecutive, empty between colons, time format.

**`Core/Tests/Core/UpHTMLVisitorTests.swift`** — Integration tests: shortcode
replaced, unknown left as-is, not replaced in inline code, not replaced in code
blocks, consecutive shortcodes, inside strong.

Manual: open a file with shortcodes in Mud, verify emoji rendering in up mode,
verify raw source in down mode, verify inline code and code blocks are
unaffected.
