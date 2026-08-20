---
name: trim-comments
description: Cut the comments in the Core/Sources/Resources CSS and JS back to essentials, verifying that no code changed. Use when asked to trim, thin, or reduce the comments in the stylesheets and scripts, or to tidy the comments a commit added to them.
argument-hint: "[file …]"
---

Trim Resource Comments
===============================================================================

The user has invoked `/trim-comments $ARGUMENTS`.

The stylesheets and scripts in `Core/Sources/Resources` accumulate explanation.
A rule gets a paragraph when it is written, the paragraph is extended when the
rule is amended, and what is left a few releases later documents the history of
our thinking rather than the file in front of us. This sweep cuts that back.

There is no minification step, so every comment ships in the rendered document.
That is not the reason to cut them — the reason is that a dense file is harder
to read — but it does mean the saving is real.

If arguments were given, treat them as the files to sweep. With none, sweep all
of them.


## What this covers

Every `.css` and `.js` file directly in `Core/Sources/Resources`, except:

- `highlight.min.js`, `mermaid.min.js`, `temml.min.js` — vendored bundles, not
  ours to comment. `verify.py` skips these.
- The part of `mud-math.css` below the
  `/* --- Adapted from Temml-Local.css --- */` divider. Those comments came
  with the upstream file; leave them so the next person can diff against Temml.

Swift, Markdown, and everything outside that directory are out of scope.


## The rule

**Keep** a comment that records something the code cannot say:

- An external constraint. WebKit leaving a dragged selection's end in the next
  block; Mermaid deriving its palette from three colors, or id-ing a render
  element with `Date.now()`; a presentation attribute losing to any author
  rule.
- Why a rule is where it is, when it looks arbitrary. The `min-width: 700.02px`
  guards, `@page` sitting outside `@media print`, `mud-print.css` being
  included last.
- A number or name that is stated twice and must agree. `STUB_H` against the
  CSS height, `Layout.compactBreakpoint` against the media query, the JS avatar
  fallback against `CommentAvatar.fallback` — say which test pins the pair.
- A file header: what the file is, when it is loaded, and what loads with it.
  Two or three lines.
- A term of art the code uses without defining it — `mud-comment-anchor.js`'s
  "logical block", say.

**Cut** everything else:

- Narration of what the next line plainly does.
  `// Create one overlay per group.` above a loop that creates one overlay per
  group.
- The history of the change that introduced the code — "the one behavior change
  of extracting this shared file", "(issue #5)", "(Phase 3e)". Git has it.
- Justification of a design choice nobody is about to reverse. Why a collapsed
  capsule shows the author's avatar; why a milestone reads better in the
  accent.
- Restating what `Doc/AGENTS.md` already says about the file.
- A rationale that only defends the code against an alternative that was never
  built.

When a paragraph mixes the two, keep the constraint and drop the rest — usually
three or four lines become one.


### Calibration

Before, in `mud-up.js`:

```
  // Open every folded section enclosing `el` — and `el` itself when it is a
  // folded heading — so a navigation can land on it. Walking back from its
  // block, each heading that outranks the closest one seen so far is a section
  // `el` sits in; the ones in between are sections that have already ended.
  //
  // With the setting off nothing is hidden, so there is nothing to reveal —
  // and dropping slugs from the set would break `setEnabled`'s promise that
  // turning the setting back on restores the same folds.
  //
  // Returns true when something was opened, so a caller knows the document
  // moved under it and may need to scroll again.
```

After:

```
  // Open every folded section enclosing `el`. Walking back from its block, each
  // heading that outranks the closest one seen so far encloses it. Returns true
  // if anything opened.
```

Section banners (`/* -- Comments column ---- */`, `// -- Arrows ---- */`) stay
as they are. They are navigation, not explanation.


## Steps

### 1. Take the baseline

```
  python3 .claude/skills/trim-comments/verify.py snapshot
```

This copies the resource files to `.claude/tmp/trim-comments-baseline/`. It is
a file copy rather than a git ref, so unrelated uncommitted work in the tree is
fine.


### 2. Trim, a file or two at a time

Read the file, then apply the edits **as exact string replacements** — a Python
heredoc that asserts each `old` is present before replacing it:

```
  python3 - <<'PY'
  import pathlib
  p = pathlib.Path("Core/Sources/Resources/mud-up.js")
  s = p.read_text()
  for old, new in [
      ("""  // long comment as it stands …""",
       """  // what it becomes"""),
  ]:
      assert old in s, old[:60]
      s = s.replace(old, new, 1)
  p.write_text(s)
  PY
```

Do **not** rewrite a whole file with `Write` to reshape its comments. On a file
of any size the code gets retyped along with the prose, and a dropped line or a
changed literal is easy to introduce and hard to see. Replacements touch only
what they name, and the assert catches a stale `old` immediately.

Work down the files by comment volume — `verify.py stats` names the heaviest.

Run `verify.py check` after each file or small batch, not once at the end. A
failure then names the file you just touched.


### 3. Verify

```
  python3 .claude/skills/trim-comments/verify.py check
```

`OK` means the two sides are identical once comments and whitespace are gone.
It is a strong check but not a parser — read `git diff` as well and confirm no
line outside a comment moved.


### 4. Check what the tests assert

Several tests read the resource text and assert on substrings, including
negative ones. `Core/Tests/CommentResourcesTests.swift` asserts a read-only
render does _not_ contain `.mud-compose` or `mud-capsule-puff`, so a rewritten
comment mentioning either by name in a read-side file would fail it.

Grep the tests for anything that keys on resource content, and re-check any
negative assertion against the files you edited:

```
  grep -rn 'contains(' Core/Tests/CommentResourcesTests.swift \
      Core/Tests/HTMLTemplateTests.swift
```

Then ask the user to run the suite — they run Swift, we don't:

```
  swift test --package-path Core
```


### 5. Report

Run `verify.py stats` and give the user the totals, the per-file table for the
files that moved most, and the verification result.

Report the real number. If the sweep took less out than the rule suggests it
would, say so and say why — usually because what remains is the constraint
category, which the rule keeps. Do not cut a genuine constraint note to reach a
percentage.

Finish by naming what you deliberately left, so the user can push further if
they disagree: the file headers, an upstream-adapted block, a long note you
judged load-bearing.


## Cleaning up

The baseline directory is scratch. Leave it in place while the user reviews —
they may ask for a second pass — and it will be cleared by the next `snapshot`.
`.claude/tmp/` is git-ignored, so nothing there is ever committed.
