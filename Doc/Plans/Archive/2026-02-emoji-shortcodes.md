Emoji shortcodes
===============================================================================

> Status: Complete


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


## Files created

**`Core/Sources/Core/Resources/emoji.json`** — Trimmed copy of GitHub's gemoji
database (`db/emoji.json`). 83 KB (~1,870 entries, only `emoji` and `aliases`
fields retained).

**`Core/Sources/Core/Rendering/EmojiShortcodes.swift`** —
`enum EmojiShortcodes`:

- `private static let aliasToEmoji: [String: String]` — built lazily on first
  access from the bundled JSON. Swift guarantees thread-safe static `let`
  initialization. ~1,900 entries from the `aliases` arrays.
- `private static let pattern: NSRegularExpression` — `:[a-zA-Z0-9_+\-]+:`
  matching potential shortcodes.
- `static func replaceShortcodes(in text: String) -> String` — fast path
  returns immediately if no colon in text. Matches pattern, looks up each alias
  in the dictionary. Known aliases replaced with emoji; unknown left as-is.

**`Core/Tests/Core/EmojiShortcodesTests.swift`** — 8 unit tests for the
replacement function: known shortcode, special char shortcode, unknown
shortcode, no colons, mixed text, consecutive, empty between colons, time
format.


## Files modified

**`Core/Sources/Core/Rendering/UpHTMLVisitor.swift`** — Changed `visitText` to
pass text through `EmojiShortcodes.replaceShortcodes(in:)` before HTML
escaping.

**`Core/Tests/Core/UpHTMLVisitorTests.swift`** — 6 integration tests added:
shortcode replaced, unknown left as-is, not replaced in inline code, not
replaced in code blocks, consecutive shortcodes, inside strong.

**`Doc/AGENTS.md`** — Added `EmojiShortcodes.swift` to Core key files and
`emoji.json` to Resources.


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

Unit and integration tests as listed above. Manual: open
`Doc/Examples/emoji- shortcodes.md` in Mud, verify emoji rendering in up mode,
verify raw source in down mode, verify inline code and code blocks are
unaffected.
