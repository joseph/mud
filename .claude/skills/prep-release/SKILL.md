---
name: prep-release
description: Prepare a new Mud release — bump version, freshen the guides, and draft release notes.
disable-model-invocation: true
argument-hint: <version>
---

Prepare a release for Mud
===============================================================================

The user has invoked `/prep-release $ARGUMENTS`.

The argument is the new version number (e.g. `1.3.0`). If no argument was
provided, ask for the version number before proceeding.


## Steps

### 1. Validate

- Confirm the argument looks like a version number (X.Y.Z).
- Read `Mud.xcodeproj/project.pbxproj` and find the current
  `MARKETING_VERSION`. Confirm the new version is higher.
- Check `Doc/RELEASES.md` to make sure a section for this version doesn't
  already exist.

If any check fails, stop and explain.


### 2. Bump the versions

Run `.github/scripts/prep-release-version X.Y.Z` from the project root. The
script updates `MARKETING_VERSION` across every build configuration in the
pbxproj and increments `CURRENT_PROJECT_VERSION` by one across every build
configuration. App Store and Direct distribution share a single monotonic
`CFBundleVersion` stream — Sparkle compares the new value against the installed
app's `CFBundleVersion` to decide whether to offer an update — so the build
bump runs unconditionally regardless of channel.

The script validates state before writing (version format, pbxproj presence,
consistent current values, new marketing version strictly higher than the old).
If any precondition fails, it exits non-zero with a message; surface the
failure and stop.

After a successful run, verify the diff touches only the pbxproj and only the
`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` lines.


### 3. Gather the changes

Everything from here on works from the same picture of what changed since the
last release:

- Run `git log --oneline <last-tag>..HEAD` (get the tag with
  `git tag --list 'v*' --sort=-v:refname | head -1`).
- Read any plan files in `Doc/Plans/` marked Underway, and any completed since
  the last tag.

Read that list once, and note which changes are user-facing: a new feature, a
new keyboard shortcut, a new piece of Markdown syntax, or a change to how an
existing one behaves. Those are what steps 4 and 5 need.


### 4. Freshen the guides

Four documents describe Mud to its readers, and each has its own job. Bring
each one up to date with the changes from step 3 — nothing more. Most releases
should touch one or two of these, and some should touch none. Making no edit is
a valid outcome; say so and move on.

**`README.md`** — the pitch. The **Highlights** checklist names the reasons
someone would install Mud. Add a bullet only for a feature big enough to sit
beside "Change tracking!" and "Comments!" — a new mode, a new document type it
can open, a whole capability. Match the existing form: one line, the feature
name in bold, no explanation of how it works. A release that only refines an
existing feature gets no new bullet; reword the existing one if it now claims
too little. Check the Quick start distribution list and the `mud` command
examples still describe the shipping app.

**`Doc/HUMANS.md`** — the manual, shown in the Help menu. Two things to check:

- The shortcut tables must match the app's menus. Read the `.keyboardShortcut`
  declarations in `App/MudApp.swift`, and the `keyEquivalent` assignments in
  `App/WebView.swift` and `App/OpenInEditor.swift` for anything outside the
  menu bar. Every shortcut a reader can press belongs in one of the tables;
  correct any that moved and delete any that are gone.
- The document directory lists every file in `Doc/Guides/` and `Doc/Examples/`.
  Add new ones, drop deleted ones.

**`Doc/Examples/feature-showcase.md`** — a demonstration of Mud's Markdown
rendering, not a feature list. It gets a new section only when the release
taught Mud a new piece of Markdown syntax, or changed how it renders an
existing one. App behavior — folder opening, the sidebar, themes, preferences —
does not belong here, however good it is. A new section shows the syntax and
its rendered result in the same voice as the sections around it: a sentence or
two of prose, then the example.

**`Doc/AGENTS.md`** — the architecture guide for coding agents. Its worth is in
being scannable, so keep it under pressure:

- **File quick reference** — add files the release introduced and remove ones
  it deleted. One entry, one line of what the file is for. Entries drift into
  paragraphs over successive releases; when you find one that has grown past
  three or four lines, cut it back to what an agent needs before opening the
  file. The design reasoning it accumulated belongs in the file's own comments
  or a plan document, not here.
- **Features** — the summary list near the top. Same rule as the README's
  Highlights, at a lower bar: it lists what the app does, one line each.
- The prose sections (rendering pipeline, state management, conventions) —
  check the ones the release touched still describe the code. Rewrite rather
  than append; a correction bolted onto a stale sentence reads worse than
  either.

Run `odmarkdown -w` on each file you edit, in the same tool call batch as the
edit.

Two things in `Site/` follow from the same list, and neither has a build step
to derive it:

- **The download link** — the GitHub card in `Site/index.html` points straight
  at one release's DMG, and the version is in that URL twice:
  `releases/download/vX.Y.Z/Mud-vX.Y.Z.dmg`. Bump both, every release. Left
  alone, the site hands out the previous version.
- **The site copy** — if the release changed the README's Highlights or any
  other copy the landing page repeats, `Doc/Local/site-maintenance-guide.md`
  says what else has to change with it. The copy lives in three places, and the
  Down article's line numbers are literal text.


### 5. Draft release notes

Draft a new section for `Doc/RELEASES.md`, working from the same change list.
Follow the existing style:

- Insert the new section at the top, after the `===` heading rule.
- Heading format: `## vX.Y.Z`
- Bulleted list of user-facing changes.
- Concise, compelling prose — these are user-facing notes, not a changelog.
  Lead each bullet with the feature or fix, not the file or module.
- Don't mention internal refactors, code cleanup, or implementation details
  unless they have user-visible impact.
- Omit changes that are only relevant to developers (CI, build scripts, etc).
- Wrap lines at 78 characters.

Present the draft to the user for review. Incorporate any feedback.


### 6. Finalize

Use `AskUserQuestion` to block while the user reviews the guide edits and the
notes, and renders the HTML:

- Question: "Review the guide edits and `Doc/RELEASES.md`, then run
  `.github/scripts/build-release-notes` to render the HTML. Continue when
  ready."

- Header: "Finalize"

- Options:

  - `Done` (description: "Reviewed and HTML rendered — commit, merge, and
    tag.")
  - `Cancel` (description: "I'll finish the remaining steps by hand.")

**On `Done`**, run these commands in sequence. Stop and surface any error
instead of continuing past it. The guide edits are a commit of their own, and
it comes first — skip it if step 4 changed nothing:

```
git add README.md Doc/HUMANS.md Doc/AGENTS.md Doc/Examples/feature-showcase.md
git commit -m "Doc: freshening guides for vX.Y.Z."
git add Mud.xcodeproj/project.pbxproj Doc/RELEASES.md Site/releases/ Site/index.html
git commit -m "VERSION: X.Y.Z."
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
  git checkout main
  git merge --ff-only "$BRANCH"
fi
git tag vX.Y.Z
```

Then tell the user (in chat) that everything local is ready, and to push with:

```
git push origin main vX.Y.Z
```

Do **not** run the push yourself — pushing the tag triggers the release
workflow, which is a shared-state action the user authorizes explicitly.

**On `Cancel`**, instead print the list of remaining steps for the user to
perform:

1. Review the guide edits and edit `Doc/RELEASES.md` if needed.
2. Run `.github/scripts/build-release-notes` to render the HTML.
3. Commit the guide edits with message `Doc: freshening guides for vX.Y.Z.`.
4. Commit the bump, notes, and rendered HTML with message `VERSION: X.Y.Z.`.
5. If on a feature branch, merge to `main` (`--ff-only` preferred).
6. Tag as `vX.Y.Z`.
7. Push with `git push origin main vX.Y.Z` to trigger the release workflow.
