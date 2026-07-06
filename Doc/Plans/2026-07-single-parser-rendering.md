Plan: Single-Parser Rendering
===============================================================================

> Status: Planning

Whether and how to consolidate Mud's rendering on one Markdown parser. Today
every Up-mode render parses the document twice: once with cmark-gfm (via
`FootnoteProcessor`, for footnote detection with byte positions), then — after
rewriting the source bytes — again with swift-markdown (for the actual render).
This investigation answers: is dropping swift-markdown feasible, what does it
buy, what does it cost, and in what order should the work land.

**Verdict: feasible, worth doing, and lower-risk than it looks — because
swift-markdown is a wrapper around the exact same parser we would move to.**
The recommended path is a staged port with a differential test harness,
scheduled after Phases 2–3 of
[2026-07-architecture-improvements.md](./2026-07-architecture-improvements.md).


## Why this is not a parser swap

The decisive fact, verified in the pinned sources: **swift-markdown 0.8.0 is a
Swift layer over the same swift-cmark 0.8.0 package Mud already links
directly.** SwiftPM resolves both to one pin (`Core/Package.swift` matches
swift-markdown's version range for exactly this reason). swift-markdown's
converter calls `cmark_parse_document` with
`CMARK_OPT_SMART | CMARK_OPT_SOURCEPOS | CMARK_OPT_TABLE_SPANS` and attaches
three extensions — `table`, `strikethrough`, `tasklist` (its
`Parser/CommonMarkConverter.swift`). Every source range Mud reads off a
swift-markdown node is a copy of the cmark sourcepos fields.

So consolidating does not change the parser, the parse options, or the position
model. It removes the wrapper — and with it, the need to rewrite the source
between the two parses. Rendering differences reduce to Mud's own visitor
logic, which is exactly what the parity harness below tests.

```mermaid
flowchart LR
  subgraph today [Today]
    S1[source bytes] --> C1[cmark parse<br/>FOOTNOTES + SOURCEPOS]
    C1 -->|rewrite refs to HTML,<br/>delete definitions| S2[transformed source]
    S2 --> M1[swift-markdown parse<br/>= cmark + Swift layer]
    M1 --> V1[UpHTMLVisitor]
  end
  subgraph target [Target]
    S3[source bytes] --> C2[one cmark parse<br/>FOOTNOTES + SMART + SOURCEPOS]
    C2 --> V2[UpHTMLVisitor<br/>footnote refs are AST nodes]
  end
```


## What consolidation deletes

The two-parser seam is where the recent comment bugs landed (the anchoring and
failed-write fixes in the last several commits). Each item below is code or a
coordinate system that exists only to reconcile the two parses:

1. **The source-rewriting layer.** `FootnoteProcessor.process` injects marker
   HTML into the source and deletes definition blocks so swift-markdown never
   sees footnote syntax. With `CMARK_OPT_FOOTNOTES` on the render parse,
   references and definitions arrive as AST nodes; the visitor emits the same
   marker HTML when it visits a reference node. The byte-edit machinery, the
   orphan-definition scan, and the "transformed source" coordinate system all
   go away.
2. **Waypoint reprocessing.** `processingWaypoint` (`MudCore.swift:88-95`)
   exists so the diff compares transformed source against transformed source.
   With no transformation, it is deleted — and with it the easy-to-forget
   requirement that every new entry point call it.
3. **Half of comment invisibility.** `stripCommentTokens` must today recognize
   _two_ token forms — raw `[^comment-x]` refs and the baked marker HTML —
   because the Up path diffs transformed source while the sidebar diffs raw
   source (`FootnoteProcessor.swift:737-758`). With one representation, the
   regex drops to one form; better, comment nodes can be skipped structurally
   during leaf collection instead of stripped textually.
4. **Down-mode definition blanking.** Down mode blanks footnote-definition
   lines with spaces before parsing (swift-markdown would misparse them as code
   blocks), then remaps coordinates from a sub-parse of each body
   (`DownHTMLVisitor.swift:73-84, 153-194`). Parsing with `CMARK_OPT_FOOTNOTES`
   deletes both mechanisms.
5. **The `Aside` crash workaround.** `AlertDetector` replicates
   swift-markdown's internal column arithmetic to dodge an upstream trap (smart
   typography makes decoded strings longer than their source spans; unfixed as
   of 0.8.0) — `AlertDetector.swift:142-174`. Our own DocC tag parser replaces
   `Aside` and the workaround together.
6. **The `isLooseList` range hack.** `UpHTMLVisitor.swift:1044-1078` infers
   list looseness from range arithmetic (with a workaround for swift-markdown
   extending item ranges past trailing blanks). cmark exposes it directly:
   `cmark_node_get_list_tight`.
7. **One parse per render instead of two.** This also simplifies Phase 3c of
   the architecture plan: the "footnote scan cache" reconciling five
   `FootnoteProcessor` entry points shrinks, because the render itself no
   longer needs a separate detection parse. (If we commit to this plan, build
   3c as a minimal memo, not an elaborate cache.)

What does _not_ go away: `CommentAnchor.fold()`. Smart typography happens at
parse time (curly quotes land in the text-node literals), so rendered DOM text
still differs from raw source bytes regardless of parser count. The fold stays,
unchanged.


## What consolidation costs

### The port surface

Thirteen files import swift-markdown. Most are mechanical ports onto a typed
cmark wrapper; the full inventory (per-file API surface) is summarized here by
what the replacement needs:

| File                        | Port difficulty | Notes                                                     |
| --------------------------- | --------------- | --------------------------------------------------------- |
| `MarkdownParser`            | trivial         | same pattern as `FootnoteProcessor.makeFootnoteParser`    |
| `ParsedMarkdown`            | moderate        | owning wrapper class; see lifetime, below                 |
| `HeadingExtractor`          | easy, exacting  | `plainText` must be byte-identical (slug stability)       |
| `AlertDetector`             | easy            | own DocC tag parser; deletes the `Aside` workaround       |
| `UpHTMLVisitor`             | large           | 24 visit methods; table/tasklist accessors exist in cmark |
| `DownHTMLVisitor`           | large, exacting | inline sourcepos + column conventions; deletes blanking   |
| `BlockMatcher`              | moderate        | fingerprints already slice raw source by sourcepos        |
| `DiffContext`               | moderate        | `SourceKey` range join survives as-is                     |
| `LineDiffMap`, `ChangeList` | trivial         | follow `LeafBlock`                                        |
| `WordDiff.inlineText`       | small, exacting | counts must match the Up visitor's cursor arithmetic      |
| `CommentSerialization`      | **hardest**     | `format()` output is written into users' files; see below |
| `CommentAnchor`             | none            | already cmark-only                                        |


### The three exacting parts

1. **Smart typography is a cross-cutting contract.** Four subsystems are
   calibrated to smart-typographed text-node literals: Up-mode text emission,
   the word-span cursor counts (which must equal `WordDiff.inlineText`'s
   counts), heading slugs, and `CommentAnchor`'s fold. Passing
   `CMARK_OPT_SMART` preserves all four byte-for-byte — verified:
   swift-markdown passes this exact flag to this exact library, so the
   substituted literals are identical. Forgetting the flag would silently
   change rendered output, slugs, word diffs, and comment anchoring. The
   wrapper should hard-code it (with sourcepos) rather than accept options.
2. **Down mode's column conventions.** The event collector emits spans from
   node ranges for seven inline types and all block containers. Two conventions
   must be reproduced exactly: swift-markdown's upper bound is cmark's
   inclusive end column **plus one**, and columns are UTF-8 byte columns within
   the line. The existing multi-line strikethrough workaround
   (`DownHTMLVisitor.swift:491-504`) papers over a cmark _extension_ sourcepos
   bug, so it survives the port unchanged.
3. **`CommentSerialization.format()`.** The one true Markdown re-serialization
   of a subtree, whose output `CommentEditor` writes back into the user's file
   under a `parse(serialize(x)) == x` invariant. `cmark_render_commonmark`
   formats differently (escaping, wrapping, list markers), so a drop-in swap
   would churn bytes in users' documents. Mitigation: this file parses tiny,
   de-indented comment bodies, not the document — it has **no position coupling
   to the render parse**. So it can keep swift-markdown after everything else
   has moved (the seam is gone even if the dependency lingers), and be ported
   last with a hand-rolled serializer for the four block kinds comment bodies
   use, or not at all.


### Node lifetime

swift-markdown nodes are immutable ref-counted Swift values; cmark nodes are
raw pointers into a manually-freed C tree. `LeafBlock.markup` handles flow out
of `BlockMatcher` and are read later by `DiffContext` — including nodes from
the _old_ document's tree. The wrapper must make this safe by construction: a
`ParsedMarkdown`-owned root (freed in `deinit`) and node handles that retain
their owning document, so a live handle can never outlive its tree. This is the
main design work in the wrapper, not the visit methods.


### Verified sourcepos limits (and the existing defense)

Inline sourcepos in the pinned swift-cmark fork is real and complete — verified
in `src/inlines.c`: every inline constructor sets positions, emphasis/links
copy positions from their delimiter text nodes, nested inlines included;
footnote references have a dedicated sourcepos block (the one Mud already
reads). It is exactly as good as what swift-markdown consumes, because
swift-markdown consumes these same fields. Known inaccuracies, from the
position math itself:

- Continuation lines with a different prefix width than the block's first line
  (lazy blockquote continuations, ragged list indents) get columns off by the
  prefix delta; line numbers stay correct.
- A paragraph whose opening lines are link-reference definitions reports inline
  lines too small by the number of dropped lines (the classic upstream bug).
- Entity references keep source columns but store decoded literals, so column
  span ≠ literal length across an entity.

Mud already defends against exactly this class of error: `FootnoteProcessor`
verifies every position against the raw bytes before trusting it
(`delimitsFootnoteRef`). The wrapper should generalize that pattern — a
`verifiedRange(of:)` that checks the sliced source against the node before any
byte surgery, falling back gracefully (as comment insertion already falls back
to block-end placement).


### Extension parity

For byte-identical output, the render parse attaches the same three extensions
swift-markdown does (`table`, `strikethrough`, `tasklist`) plus
`CMARK_OPT_FOOTNOTES`. Two deliberate follow-up choices, made separately from
the port so parity stays testable:

- **autolink**: swift-markdown never attaches it, so bare-URL autolinking is
  off in Up mode today (the detection parse attaches it, but that parse doesn't
  render). Turning it on afterward is a small, user-visible improvement — as
  its own commit.
- **`CMARK_OPT_TABLE_SPANS`**: swift-markdown always passes it. Match it during
  the port; decide afterward whether Mud wants cell spans at all.

The extension node types (`table`, `strikethrough`, `tasklist`) are not
exported constants in the public module map; identify them by
`cmark_node_get_type_string`, as swift-markdown itself does.


## Migration plan

Strangler-style: both pipelines coexist behind a differential harness until the
last stage; every stage lands independently and keeps the app shipping.

**Stage 0 — the harness.** A corpus (start from `Doc/Examples/` plus the
rendering tests' fixtures; add documents exercising every node type, smart
typography, footnotes, comments, alerts, tables, task lists) and a test that
renders each document through both pipelines and asserts byte-identical HTML.
This is also Phase 3e of the architecture plan doing double duty.

**Stage 1 — the wrapper.** `CMarkDocument` in Core: owning class over the
parsed tree, typed node enum (by type string for extension nodes), a walker
with default-descend behavior, and a range API that reproduces swift-markdown's
conventions (exclusive upper bound, UTF-8 byte columns) so consumers port
without changing their range math. Includes `verifiedRange(of:)`. Unit tests
against known documents.

**Stage 2 — leaf consumers.** `HeadingExtractor` (with a slug-parity test over
the corpus), `WordDiff.inlineText` (with a count-parity test against the old
implementation), `AlertDetector` (own DocC tag parser). Each is small,
independently revertible, and proves the wrapper.

**Stage 3 — UpHTMLVisitor.** Port the 24 visit methods; footnote and comment
references become visit cases emitting the existing marker HTML (numbering
logic moves from `FootnoteProcessor`'s rewrite pass into the render). The
harness gates the switch: byte-identical output on the corpus, no deliberate
changes in this stage.

**Stage 4 — the diff layer.** `BlockMatcher`, `DiffContext`, `LineDiffMap`,
`ChangeList`. Sequence this after architecture Phase 2 (one diff pass) if
possible — porting one shared pass is less work than porting three consumers.
`SourceKey` joins survive because both sides still parse the same string with
the same parser.

**Stage 5 — DownHTMLVisitor.** Port the event collector onto verified inline
sourcepos; delete the definition blanking and the sub-parse remap. Down mode's
output is raw-source-faithful, so the harness comparison is exact here too.

**Stage 6 — collapse FootnoteProcessor.** `process` shrinks to an AST walk
producing `FootnoteEntry` / `Comment` models (no edits); `scan` and the render
share one parse. The byte-geometry functions (`locateComments`,
`SourceGeometry`) stay — the comment **write** path still does byte surgery by
design — but now read positions from the same single parse. Delete the
swift-markdown pipeline and the harness's old side.

**Stage 7 (optional, separable) — CommentSerialization.** Hand-rolled
serializer for comment bodies with round-trip tests, then drop the
swift-markdown dependency from `Package.swift`. Until then the dependency
remains for this one leaf use, with zero position coupling.


## Recommendation

Do it, in the order above, after Phases 2–3 of the architecture plan:

- Phase 2 first (one diff pass) so Stage 4 ports one implementation, not three.
- Phase 3's renderer extraction and entry-point consolidation first, so Stage 3
  ports one pipeline, not two spellings of it.
- Build Phase 3c (the footnote-scan cache) as a minimal memo, since Stage 6
  removes most of what it would cache.

The risk profile is unusual for a "replace the parser" project: the parser does
not change, the options do not change, the maintained C library (BSD 2-clause,
near-frozen except security work) is already a direct dependency, and the team
already operates its C API in the two most position-sensitive files in the
codebase. The work is real — roughly 4,000 lines of visitors and collectors
plus the parity corpus — but it is mechanical under a harness that fails
loudly, and each stage is useful on its own. The alternative (waiting for
swift-markdown to gain footnotes) has no timeline: the request has been open
upstream since 2022 with no in-flight work as of July 2026.
