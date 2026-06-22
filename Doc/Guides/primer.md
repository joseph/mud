Mud primer for coding agents
===============================================================================

Mud (Mark Up & Down) is a macOS Markdown preview app. This primer teaches you
to author and launch documents that use Mud's best features. Read it once, then
write Markdown that takes advantage of everything below.


## Launching

- `mud doc.md` — open in the Mud GUI (rendered "Mark Up" view). This is how you
  show a user a finished document.
- `mud doc.md other.md` — open several files, each in its own tab.
- `command | mud` — preview piped stdin in the GUI.
- `mud -u doc.md > out.html` — render a standalone HTML document to stdout
  (`-d` for the syntax-highlighted source view; `-f` for a body-only fragment;
  `-b` to open in the browser). Add `--standalone` to inline images as data
  URIs.

Prefer `mud doc.md` to show your work — the GUI auto-reloads on save, so you
can edit and the user sees updates live.


## Markdown dialect

Mud renders CommonMark plus GitHub Flavored Markdown, with extras. All of these
work — use them where they make the document clearer:

- **YAML frontmatter**: a `---` block at the very top of the file (line 1),
  closed by `---` or `...`. Mud renders the top-level keys (`title`, `author`,
  `tags: [a, b]`, …) as a collapsible "Frontmatter" table above the document.
- **GFM**: tables, task lists (`- [ ]` / `- [x]`), strikethrough, autolinks,
  fenced code with syntax highlighting (label the language).
- **Alerts** (GitHub style): a blockquote whose first line is `[!NOTE]`,
  `[!TIP]`, `[!IMPORTANT]`, `[!WARNING]`, or `[!CAUTION]` renders as a colored
  callout. DocC asides (`> Note:`, `> Tip:`, …) are also recognized.
- **Mermaid diagrams**: a ```` ```mermaid ```` fenced block renders as a
  diagram (flowcharts, sequence, gantt, etc.). Diagrams are a _great_ way to
  illustrate concepts and flows. Reach for them instead of ASCII art.
- **Footnotes**: `text[^1]` with a `[^1]: definition` block.
- **Math**: not supported yet — don't emit LaTeX or `$…$` math.

Use a clear heading hierarchy: Mud builds a navigable outline sidebar from your
headings, and gives each one a slug ID, so internal links like
`[see above](#markdown-dialect)` jump within the document.


## Comments

A **comment** is Mud's own convention layered on standard Markdown footnotes.
Mud shows comments in a margin column beside the text, anchored to a quotation.
Because a comment is just a footnote, it survives untouched in any other
Markdown tool (on GitHub it shows as a footnote with a `{author @ time}`
byline) — so use comments freely to annotate, review, or leave notes for the
user.

A comment is a footnote whose label matches `comment-<id>` (`<id>` is any run
of `[\w-]`, e.g. `comment-a`, `comment-1`, `comment-intro`). Write it in two
parts:

1. **The reference** `[^comment-a]` — inline, immediately after the word or
   passage it annotates.
2. **The definition** `[^comment-a]: …` — at the **bottom** of the document,
   where Mud keeps all comment definitions. Continuation lines are indented
   **four spaces** (standard footnote structure — this indentation is
   required).

The definition holds:

- A leading **quotation** — a blockquote echoing the document text the thread
  is anchored to. Always open a thread with one, then leave a blank line.
- One or more **messages**. Each opens with an attribution line —
  `💬 {author @ YYYY-MM-DD HH:MM:SS}:` — followed by the message body in the
  paragraph below.


An example thread with a quotation, an opening message, and a reply:

```
The build step[^comment-a] runs before tests.

[^comment-a]: > The build step

    💬 {Claude @ 2026-06-22 14:30:05}:

    Should this be cached? It reruns on every push.

    💬 {Mudder @ 2026-06-22 15:02:31}:

    Good catch — caching it now.
```

Guidelines for commenting:

- Each label must be **unique** and is a stable join key — never renumber or
  reuse one. Pick fresh ids (`comment-a`, `comment-b`, …) as you go.
- To **reply**, add another `💬 {…}:` attribution paragraph to the same
  definition; each one at a paragraph start begins a new message.
- An attribution is recognized only at a **paragraph start** — a `{` or `💬` in
  running prose is ordinary text and never starts a message.
- Put a **blank line** between the quotation and the first message, and no
  space between `}` and `:`.
- Message bodies are full Markdown — they may contain their own lists, code
  blocks, or blockquotes, though you should avoid large or wide tables.
