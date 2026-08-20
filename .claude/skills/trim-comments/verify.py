#!/usr/bin/env python3
"""Guard rail for a comment-trimming pass over Core/Sources/Resources.

    verify.py snapshot        copy the resource files aside as the baseline
    verify.py check           baseline vs working tree, comments ignored
    verify.py stats           comment-line counts, baseline vs working tree

`check` strips comments and collapses whitespace on both sides and compares
what is left. Any difference means an edit touched something other than a
comment. The baseline is a file copy rather than `git show HEAD:`, so the pass
can start from a working tree that already has unrelated edits in it.

Caveat: the stripper does not parse JS regex literals, so a regex containing
`//` or `/*` would be misread — the same way on both sides, but it could mask a
real change nearby. Read `git diff` for non-comment lines as well, and run the
test suite.
"""

import re
import shutil
import sys
from pathlib import Path

RES = Path("Core/Sources/Resources")
BASELINE = Path(".claude/tmp/trim-comments-baseline")

# Vendored bundles: not ours to comment, never trimmed.
SKIP = {"highlight.min.js", "mermaid.min.js", "temml.min.js"}


def targets():
    if not RES.is_dir():
        sys.exit(f"{RES} not found — run from the repository root.")
    return sorted(
        p for p in RES.iterdir()
        if p.suffix in {".css", ".js"} and p.name not in SKIP
    )


def strip(text, is_js):
    """The file with every comment removed and whitespace collapsed."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'`":                       # string / template literal
            j = i + 1
            while j < n:
                if text[j] == "\\":
                    j += 2
                    continue
                if text[j] == c:
                    break
                j += 1
            out.append(text[i:j + 1])
            i = j + 1
            continue
        if text.startswith("/*", i):
            i = text.find("*/", i + 2)
            i = n if i < 0 else i + 2
            continue
        if is_js and text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        out.append(c)
        i += 1
    return re.sub(r"\s+", " ", "".join(out)).strip()


def comment_lines(text):
    """How many lines of the file are comment."""
    count, in_block = 0, False
    for line in text.split("\n"):
        t = line.strip()
        if in_block:
            count += 1
            if "*/" in t:
                in_block = False
        elif t.startswith("/*"):
            count += 1
            in_block = "*/" not in t
        elif t.startswith("//"):
            count += 1
    return count


def baseline_for(path):
    saved = BASELINE / path.name
    if not saved.exists():
        sys.exit(f"No baseline for {path.name} — run `verify.py snapshot` first.")
    return saved.read_text()


def snapshot():
    if BASELINE.exists():
        shutil.rmtree(BASELINE)
    BASELINE.mkdir(parents=True)
    files = targets()
    for path in files:
        shutil.copy2(path, BASELINE / path.name)
    print(f"Baseline: {len(files)} files copied to {BASELINE}")


def check():
    bad = 0
    for path in targets():
        is_js = path.suffix == ".js"
        before = strip(baseline_for(path), is_js)
        after = strip(path.read_text(), is_js)
        if before == after:
            continue
        bad += 1
        print(f"CODE CHANGED: {path.name}")
        for k in range(min(len(before), len(after))):
            if before[k] != after[k]:
                lo = max(0, k - 60)
                print(f"  was: …{before[lo:k + 60]}…")
                print(f"  now: …{after[lo:k + 60]}…")
                break
        else:
            print(f"  length {len(before)} -> {len(after)} (one is a prefix)")
    print("FAIL" if bad else "OK: code identical, comments only")
    return 1 if bad else 0


def stats():
    was = now = was_all = now_all = 0
    rows = []
    for path in targets():
        old, new = baseline_for(path), path.read_text()
        a, b = comment_lines(old), comment_lines(new)
        was, now = was + a, now + b
        was_all += old.count("\n")
        now_all += new.count("\n")
        if a != b:
            rows.append((a - b, path.name, a, b))
    for _, name, a, b in sorted(rows, reverse=True):
        print(f"  {name:28} {a:4} -> {b:4}   -{a - b}")
    cut = was - now
    print(f"\ncomment lines {was} -> {now}  (-{cut}, {cut * 100 // max(was, 1)}%)")
    print(f"file lines    {was_all} -> {now_all}  (-{was_all - now_all})")
    print(f"comment share {was * 100 // max(was_all, 1)}%"
          f" -> {now * 100 // max(now_all, 1)}%")
    return 0


COMMANDS = {"snapshot": snapshot, "check": check, "stats": stats}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in COMMANDS:
        sys.exit(f"usage: {sys.argv[0]} {{{'|'.join(COMMANDS)}}}")
    sys.exit(COMMANDS[sys.argv[1]]() or 0)
