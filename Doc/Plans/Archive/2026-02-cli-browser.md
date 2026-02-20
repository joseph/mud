Plan: --browser flag for CLI
===============================================================================

_STATUS: COMPLETE_


## Summary

Add a `--browser` (`-b`) flag to the `mud` CLI that renders the HTML output to
a temporary file and opens it in the user's default browser, instead of writing
to stdout. This mirrors the app's Cmd+Shift+B "Open in Browser" feature.

Example usage:

```
mud -u -b README.md
mud -d -b --theme riot README.md
cat README.md | mud -u -b
```


## Design decisions

### 1. Mode requirement

`--browser` requires a mode flag (`-u` or `-d`). If neither is given, error
out with the existing message. Rationale: the current CLI already requires a
mode, and `--browser` is a delivery mechanism, not a mode.


### 2. Image embedding (up mode only)

When `--browser` is used with `-u`, pass `ImageDataURI.encode` as the
`resolveImageSource` callback and set `includeBaseTag: false`. This makes the
HTML self-contained — local images are base64-encoded inline, and anchor links
work correctly. This matches the app's Cmd+Shift+B behavior exactly.

Down mode does not reference images, so no special handling needed there.


### 3. Temp file naming

- File input: `{NSTemporaryDirectory()}/mud-{basename}.html` (e.g. `README.md`
  becomes `mud-README.html`)
- Stdin input: `{NSTemporaryDirectory()}/mud-stdin.html`

Single predictable path per source file. Repeat invocations overwrite the
previous temp file, which is fine — the browser will reload.


### 4. Opening the browser

Use `/usr/bin/open {tempPath}`. The `open` command delegates to the system's
default browser. This avoids importing `NSWorkspace` in the CLI code path and
works even with `setActivationPolicy(.prohibited)`.


### 5. Multiple files

When multiple files are given, render each to its own temp file and open all of
them. The `open` command accepts multiple paths.


### 6. Stdout suppression

When `--browser` is active, nothing is written to stdout. The HTML goes to the
temp file. Stderr still receives errors.


## Changes

### `CommandLineInterface.swift`

1. **Add `--browser` / `-b` to `cliFlags`** so that `looksLikeCLI` recognizes
   it.
2. **Add a `browser` boolean to the argument parser** (in the `run` method's
   `while` loop).
3. **Branch on `browser` after rendering.** Currently, rendered HTML is passed
   to `printToStdout`. When `browser` is true, instead:
   - Write HTML to a temp file.
   - Invoke `/usr/bin/open` on the temp file path.
4. **Adjust the `render` method** to accept a `browser` flag:
   - When `browser && mode == .up`: call `renderUpModeDocument` with
     `includeBaseTag: false` and `resolveImageSource: ImageDataURI.encode`.
   - Otherwise: render as before.
5. **Add two private helpers:**
   - `writeTempFile(html:name:) -> URL?` — writes to
     `NSTemporaryDirectory()/mud-{name}.html`, returns URL or nil.
   - `openInBrowser(_ urls: [URL])` — runs `/usr/bin/open` with the paths.
6. **Update `printUsage`** to document `-b, --browser`.


### No changes to MudCore

All necessary APIs already exist: `includeBaseTag`, `resolveImageSource`,
`ImageDataURI.encode`. The CLI already imports `MudCore`.


## Updated help text

```
mud — Markdown preview and HTML renderer

Usage:
  mud                           Launch the Mud app
  mud [file ...]                Open files in the Mud app
  command | mud                 Preview stdin in the Mud app
  mud -u [options] [file ...]   Render to HTML (mark-up view)
  mud -d [options] [file ...]   Render to HTML (mark-down view)
  command | mud -u [options]    Render stdin to HTML

Modes:
  -u, --html-up      Full HTML document (rendered Markdown)
  -d, --html-down    Full HTML document (syntax-highlighted source)

Options:
  -b, --browser      Open in default browser instead of stdout
  --line-numbers     Show line numbers (with -d)
  --word-wrap        Enable word wrapping (with -d)
  --readable-column  Limit content width (with -d or -u)
  --theme NAME       Theme: austere, blues, earthy (default), riot
  -v, --version      Print version and exit
  -h, --help         Print this help and exit

Without -u or -d, files open in the GUI. With -u or -d, HTML is
written to stdout; if no file is given, reads from stdin. Add -b
to open the result in your default browser instead.
```


## Testing

- `mud -u -b file.md` — opens rendered HTML in browser with embedded images
- `mud -d -b file.md` — opens syntax-highlighted source in browser
- `echo "# Hi" | mud -u -b` — stdin renders and opens in browser
- `mud -u -b a.md b.md` — opens two tabs/windows
- `mud -b file.md` — errors (no mode flag)
- `mud -u -b` with no stdin — reads stdin, opens result
