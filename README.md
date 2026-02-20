Mud: Mark Up or Down
===============================================================================

A Markdown viewer for macOS that shows you both sides of the document.

**Mark Up** renders your Markdown as styled HTML — GitHub-flavored, with
syntax-highlighted code blocks. **Mark Down** shows the raw source,
syntax-highlighted with line numbers. Hit Space to flip between them. Your
scroll position carries over.

Mud doesn't edit your files. It just shows them to you, beautifully, and stays
out of the way. Open a `.md` file, keep it beside your editor, and Mud reloads
automatically every time you save.


## Highlights

- GitHub-flavored Markdown with syntax-highlighted code blocks
- Raw source view with its own syntax highlighting and line numbers
- Space bar flips between views; scroll position preserved
- Four color themes — Austere, Blues, **Earthy** (default), Riot
- Auto / Bright / Dark lighting
- Table of contents sidebar
- Auto-reload on file change
- Find (Cmd+F)
- Print and Open in Browser
- Zoom, readable column, word wrap, and line number toggles


## Command line tool

Install from **Mud > Install Command Line Tool...** to get a `mud` command.

```
mud file.md                    Open a file in the app
mud -u file.md                 Render to HTML (mark-up view)
mud -d file.md                 Render to HTML (mark-down view)
echo "# Hi" | mud -u           Pipe stdin to HTML
mud -u --theme blues file.md   Pick a theme
```


## Build

Open `Mud.xcodeproj` in Xcode and build. 
Requires at least macOS Sequoia (15.6+).


## License

MIT with Commons Clause. See [Doc/LICENSE.md](Doc/LICENSE.md).


## Documents

- [Doc/AGENTS.md](Doc/AGENTS.md) — architecture guide for coding agents
- [Doc/LICENSE.md](Doc/LICENSE.md) — open source license
