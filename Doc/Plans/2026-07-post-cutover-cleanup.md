Plan: Post-Cutover Cleanup
===============================================================================

> Status: Underway

The single-parser rendering plan
([archived](./Archive/2026-07-single-parser-rendering.md)) cut every render
over to the cmark pipeline and deleted the legacy swift-markdown pipeline. The
cutover itself is done and correct, but the codebase still describes itself as
if the migration were in flight, and a few pieces of migration scaffolding were
left behind. A July 2026 architecture review of the branch found six concrete
leftovers:

1. Five source headers claim the cmark code is "parallel and unwired" and that
   the legacy pipeline is still in production. The legacy files are deleted;
   these headers are now false.
2. `Doc/AGENTS.md` lists ten deleted files as current, and its rendering
   pipeline description still routes through `UpHTMLVisitor` and a
   source-rewriting `FootnoteProcessor` — neither exists anymore.
3. `FootnoteLayout` and `FootnoteProcessor.scan(_:)` (~90 lines) have no
   callers. They fed the deleted Down pipeline.
4. Twelve types keep a `CMark` prefix that existed only to distinguish them
   from swift-markdown counterparts that no longer exist.
5. `FootnoteProcessor.SourceGeometry` is used by the `CMark/` wrapper layer —
   the one place a lower layer reads from `Rendering/`.
6. The deleted `UpHTMLVisitorTests` (508 lines) and `DownHTMLVisitorTests` (338
   lines) pinned exact HTML per construct. Their "parity" replacements lost
   their comparison baseline when legacy was deleted and now mostly assert
   output is non-empty.

This plan is the finishing sweep. Slices 2–6 must not change any rendered byte;
Slice 1 adds the tests that prove it.


## Goals

- Every comment and doc describes the codebase in present tense, as it is.
- No dead code from the migration.
- Type and file names read as "the one pipeline", not "the experimental copy".
- Layering runs downward only: `CMark/` depends on nothing above it.
- Per-construct rendering output is pinned again, without a legacy referent.


## Non-goals

These stay deferred, tracked by their own plans' closing notes:

- The `mud-comments.js` split (js-resource-layer Slice 6, deferred twice).
- The `DiffRequest` split (architecture-improvements Phase 3d, closed out as a
  standing deferral).
- AppState test coverage and a JS unit-test harness.
- The `CMarkDownHTMLVisitor` phase-split (inherited from the old Phase 3f
  deferral on `DownHTMLVisitor`; do it when the file is next touched for a
  feature).
- Behavior changes in Slices 2–6. The two parser decisions in Slice 7 do change
  output: autolink is now on (bare URLs and emails become links), and
  `CMARK_OPT_TABLE_SPANS` is now off. Both are recorded in Slice 7 and have
  shipped — autolink as its own commit (it regenerated the goldens),
  table-spans folded in with its decision (byte-neutral against every golden,
  since no corpus table uses span syntax).


## Slice 1 — golden rendering tests

Restore per-construct output coverage by freezing the current pipeline's
output, so the mechanical slices that follow have a safety net.

- Add golden-file tests over the existing 24-document `ParityCorpus`: render
  each document through the public Up and Down entry points (plain, plus one
  diffed case per document where the corpus defines an edit) and compare
  byte-for-byte against checked-in `.html` fixtures under `Core/Tests/Golden/`.
- Regeneration: a `MUD_REGENERATE_GOLDENS=1` environment variable makes the
  suite rewrite the fixtures instead of asserting. Document this in the test
  file header. Regenerating is a deliberate act; a golden diff in review is the
  point of the mechanism.
- Keep the genuinely contract-shaped suites as they are (`ChangeIDParityTests`,
  `CommentAnchorParityTests`, the String-vs- `ParsedMarkdown` overload checks
  in `UpRenderingParityTests`). Retire the `!isEmpty` smoke sweeps that the
  goldens supersede.
- Rename test files whose "Parity" name now misleads: parity against deleted
  legacy code is gone, so e.g. `UpRenderingParityTests` → `UpRenderingTests`,
  `DownRenderingParityTests` → `DownRenderingTests`. `ChangeIDParityTests` and
  `CommentAnchorParityTests` keep their names — they test parity between live
  consumers.
- Fix the stale future tense in `ParityCorpus.swift` and
  `ParityCorpusTests.swift` headers ("the planned Stage 1+ dual-pipeline
  comparison will…" — that comparison happened and was dismantled). Fold
  `ParityCorpusTests` into the golden suite if nothing distinct remains.


## Slice 2 — truthful headers and comments

Rewrite every comment that is phrased relative to the deleted pipeline. No code
changes.

- The five false headers: `CMarkUpHTMLVisitor.swift`,
  `CMarkDownHTMLVisitor.swift`, `CMarkBlockMatcher.swift`,
  `CMarkChangePlan.swift`, `CMarkLineDiffMap.swift`. Each currently says the
  legacy type "remains the production renderer" or that consumers stay on the
  legacy plan "until Stage 6". Rewrite each as a present-tense statement of
  what the type does. Use the already-updated headers
  (`CMarkDiffContext.swift`, `CMarkDeletionRenderer.swift`,
  `CMarkChangeList.swift`) as the model.
- The ~48 inline "legacy" comparisons across the Core sources (heaviest in
  `CMarkDownHTMLVisitor.swift` and `CMarkUpHTMLVisitor.swift`). Each justifies
  a byte against an implementation that no longer exists. Rewrite each as a
  statement of current behavior — "the remainder is escaped without emoji
  replacement, so `[!NOTE] :tada:` stays literal" — or delete it where the code
  now speaks for itself. Where a quirk exists only to match frozen output and
  has no independent rationale, say exactly that: "kept for output stability;
  no other requirement."
- Fix the 13 source references that point at
  `Doc/Plans/2026-07-single-parser-rendering.md`; the file now lives in
  `Doc/Plans/Archive/`.


## Slice 3 — delete dead code

- Delete `FootnoteLayout` and `FootnoteProcessor.scan(_:)` from
  `FootnoteProcessor.swift` (~90 lines, zero callers). Update the two comments
  in `CMarkDownHTMLVisitor.swift` that still mention them.
- Deduplicate the identical `registerGFMExtensions` definitions in
  `CMarkDocument.swift` and `FootnoteProcessor.swift` into one internal helper.


## Slice 4 — drop the migration prefix

Rename the twelve `CMark`-prefixed types whose non-CMark twin was deleted at
the cutover. The wrapper layer keeps its prefix — `CMarkDocument`, `CMarkNode`,
`CMarkWalker`, `CMarkNodeKind` genuinely wrap cmark.

| Current                     | New                    |
| --------------------------- | ---------------------- |
| `CMarkUpHTMLVisitor`        | `UpHTMLVisitor`        |
| `CMarkDownHTMLVisitor`      | `DownHTMLVisitor`      |
| `CMarkBlockMatcher`         | `BlockMatcher`         |
| `CMarkChangePlan`           | `ChangePlan`           |
| `CMarkDiffContext`          | `DiffContext`          |
| `CMarkLineDiffMap`          | `LineDiffMap`          |
| `CMarkChangeList`           | `ChangeList`           |
| `CMarkDeletionPlacer`       | `DeletionPlacer`       |
| `CMarkDeletionRenderer`     | `DeletionRenderer`     |
| `CMarkLeafBlock`            | `LeafBlock`            |
| `CMarkBlockMatch`           | `BlockMatch`           |
| `CMarkDefinitionDiffPolicy` | `DefinitionDiffPolicy` |
| `CMarkSourceKey`            | `SourceKey`            |

- Rename the files to match with `git mv`, including the test files
  (`CMarkBlockMatcherTests` → `BlockMatcherTests`, `CMarkChangePlanParityTests`
  → `ChangePlanParityTests`). `CMarkDocumentTests` stays.
- Blast radius is Core-only: the App, CLI, and extensions call the `MudCore`
  facade and never name these types (verified by search). No `.pbxproj` edits —
  Core is a file-system-synchronized package.
- The old names appear in prose across `Doc/` plans; archived plans stay as
  written (they describe the past accurately). Only `Doc/AGENTS.md` (Slice 6)
  and any non-archived doc get the new names.


## Slice 5 — hoist SourceGeometry

`SourceGeometry` (byte/line geometry over the raw source) lives inside
`FootnoteProcessor` but is used by `CMarkDocument`, `FootnoteProcessor`, and
`CommentAnchor`. The `CMark/` wrapper reading a type from `Rendering/` is the
one upward dependency in Core.

- Move it to its own file, `Core/Sources/CMark/SourceGeometry.swift`, as a
  top-level type. `CMark/` is the right home: the wrapper is its lowest-level
  consumer, and the type is about source bytes, not rendering.
- Renaming call sites is mechanical (`FootnoteProcessor.SourceGeometry` →
  `SourceGeometry`).
- This also shrinks `FootnoteProcessor.swift` toward one job (footnote and
  comment classification plus the scan cache). A fuller split of that file is
  not in scope; this slice only moves the geometry type.
- While here, add the one-line rule the review asked for to `CMarkNode`'s
  header: accessors must remain read-only cmark calls — the
  `@unchecked Sendable` conformances depend on it.


## Slice 6 — rewrite AGENTS.md

Bring `Doc/AGENTS.md` back in line with its own "keep this section in sync"
rule, after Slices 3–5 have settled the final names.

- File quick reference: remove the ten deleted legacy entries, fold each "Stage
  N port … parallel and unwired" bullet into a plain description of the
  (renamed) production file, add `SourceGeometry.swift`, and correct the
  test-file names from Slice 1.
- Rendering pipeline section: replace the `MarkdownParser → UpHTMLVisitor`
  diagram and the "FootnoteProcessor rewrites `[^ref]` … before parsing"
  paragraph with the real flow — one footnote-aware cmark parse,
  `ParsedMarkdown` retaining the `CMarkDocument`, markers emitted by the
  visitor, no source rewriting, no waypoint reprocessing.
- Comment-invariance paragraph: describe the `DefinitionDiffPolicy` mechanism
  (Up skips all definitions, Down descends plain footnote definitions, comments
  always skipped) instead of the deleted `stripCommentTokens` fingerprint
  story, and name the mode-aware sidebar policy.
- Fix the contradiction in the MudPreferences target description
  ("Foundation-only … depends on MudCore" — it links a package that bundles
  cmark and web resources; say what's true).


## Slice 7 — record the two open parser decisions

Two decisions from the single-parser plan were left unrecorded. Both are now
made and shipped: autolink on, table-spans off.

- **autolink.** The port kept autolink off in the render parse to hold byte
  parity, with "turn it on afterward as its own commit" noted. **Decided: turn
  it on, and done.** The `autolink` extension is attached to the render parse,
  so bare URLs and emails now render as links — a small user-visible win. That
  commit regenerated the Slice 1 goldens (the first exercise of the mechanism).
- **`CMARK_OPT_TABLE_SPANS`.** Matched during the port "decide afterward" and
  never decided. **Decided: drop it.** The option computes MultiMarkdown
  colspan/rowspan metadata on table cells, but nothing in Mud reads it — the Up
  visitor emits every cell as a plain `<td>`/ `<th>` with alignment only, and
  Down mode renders the raw source. So it produced no spanning tables. Its one
  visible effect was a footgun: a body cell whose whole text is `^` (the
  rowspan marker) got blanked, so a lone caret in a table silently vanished.
  Dropping it removes that surprise and gives up nothing. The corpus has no
  `||` or `^` table cells and no golden carries `colspan`/ `rowspan`, so the
  removal changed no fixture — it shipped in this slice rather than as separate
  work.
- Both parse configurations are now documented at their sites. The render parse
  (`CMarkDocument`) sets `SMART | SOURCEPOS | FOOTNOTES` with the `table`,
  `strikethrough`, `tasklist`, and `autolink` extensions; `FootnoteScan`'s
  parse sets `FOOTNOTES | SOURCEPOS` with the same four extensions. After the
  autolink and table-spans decisions, the only option difference is `SMART`
  (the scan renders nothing, so it needs no smart typography). The divergence
  is deliberate and now stated in both headers.


## Testing

I can't run the suites here; each slice ends with a request to run them in the
VM.

- Slice 1: `swift test` in `Core/` — new goldens pass twice in a row
  (regenerate, then assert).
- Slices 2–6: `swift test` in `Core/` must pass with **no golden changes**
  (byte-neutral guarantee), plus Cmd+U on the Mud scheme after Slice 6 for the
  app suite.
- Slice 7: autolink's commit regenerated the goldens (review that diff);
  dropping table-spans left every golden unchanged, so `swift test` in `Core/`
  should still pass with no golden changes.


## Order and size

Slices land in numbered order — goldens first so everything after is provably
byte-neutral. Each slice is one commit. Slices 2, 3, and 5 are small; Slice 4
is wide but mechanical; Slices 1 and 6 are the substantive ones.
