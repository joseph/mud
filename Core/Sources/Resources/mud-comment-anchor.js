// Mud - Comment anchoring primitives (shared by the read and write sides).
//
// The leaf-block and marker-text rules that map a rendered-DOM position to a
// block of source text. Both comment scripts and CommentAnchor.swift compute
// the same block text so a comment's marker lands byte-exactly; keeping the JS
// rules in one place stops the two scripts from drifting apart.
//
// HTMLTemplate concatenates this file ahead of mud-comments.js (the read side),
// so it is present wherever the read side is — the app and every HTML export.
// The write side (mud-comments-edit.js), injected separately in the app, runs
// after and sees `Mud.commentAnchor` too.
//
// A **logical block** is the DOM-side unit that maps one-to-one to a cmark leaf
// block (paragraph, heading, table cell). It is either:
//
//   - an *innermost leaf element* — `<p>`, `<h1>`–`<h6>`, `<td>`, `<th>`, or a
//     `<li>` with no nested leaf blocks; the whole element is one block; or
//   - a *segment* — one maximal run of inline children directly inside a
//     leaf-block element that *also* contains nested leaf blocks. In Mud's own
//     output this only happens in a tight `<li>`, where each bare run of inline
//     content is one cmark paragraph. (A change-annotated tight paragraph is
//     wrapped in an inline `<span>`, which stays inside its segment.)
//
// Swift needs no matching change: a segment's text equals the text of the cmark
// paragraph it renders, which CommentAnchor already matches, and Swift's
// occurrence walk already counts every matching paragraph — those inside tight
// list items included — in document order. This file makes the JS compute the
// same things: `eachLogicalBlock` enumerates blocks in document order,
// `segmentAt` maps a selection end to its block, and `occurrenceOf` counts by
// logical-block identity (element + child range).
//
// `anchorableEnd` runs before all of those: WebKit ends a selection dragged
// past a line at a boundary in the block *below* it, so the end is first walked
// back to the last text the selection really covers.
//
// The skip rules match CommentAnchor.swift: comment markers and footnote
// references contribute no text (`isMarkerElement`); the bottom `.comments` /
// `.footnotes` sections, code blocks (`<pre>`), Mermaid diagrams, raw-HTML
// blocks (`.mud-html-block`), and change-tracking deletion overlays
// (`.mud-change-del`) are skipped entirely — none has a source byte the anchor
// could match. `CommentAnchorParityTests.logicalBlocks` is the pinned Swift
// mirror of `eachLogicalBlock`; keep the two in sync.

(function () {
  "use strict";

  var LEAF_BLOCK_TAGS = {
    P: 1, LI: 1, TD: 1, TH: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1,
    BLOCKQUOTE: 1, PRE: 1, DD: 1, DT: 1, FIGCAPTION: 1, CAPTION: 1, SUMMARY: 1
  };
  var LEAF_BLOCK_SELECTOR =
    "p,li,td,th,h1,h2,h3,h4,h5,h6,blockquote,pre,dd,dt,figcaption,caption,summary";

  function normalizeWS(s) { return s.replace(/\s+/g, " "); }

  // The elements whose text is not part of a block's anchor text: the comment
  // markers (💬) and authorial footnote references (the superscript number).
  // Skipping the footnote reference is the one behavior change of extracting
  // this shared file: the read side used to skip only the comment marker, so
  // exact marker placement missed in a block that also held a footnote
  // reference and fell back to a quotation search (Phase 3e).
  function isMarkerElement(node) {
    return node.nodeType === Node.ELEMENT_NODE && node.classList &&
      (node.classList.contains("mud-comment-marker") ||
       node.classList.contains("footnote-ref"));
  }

  // A subtree with no source byte to anchor a comment to, skipped wholesale
  // when enumerating logical blocks and computing their text: code blocks, a
  // Mermaid diagram's rendered SVG, a raw-HTML block passed through verbatim,
  // a change-tracking deletion overlay (text that is not in the current
  // source), and rendered math (a `<math>` element or a `temml-error` span —
  // the rendered MathML text bears no relation to the TeX source, so a
  // quotation anchored there could never match). CommentAnchor.swift never
  // matches any of these.
  function isSkippedSubtree(node) {
    if (node.nodeType !== Node.ELEMENT_NODE) return false;
    // localName for math, not tagName: a MathML element is foreign-namespace,
    // so its tagName stays lowercase "math" (tagName is uppercased only for
    // HTML elements) and comparing against "MATH" would never match.
    if (node.tagName === "PRE" || node.localName === "math") return true;
    var cl = node.classList;
    return !!cl && (cl.contains("mermaid") || cl.contains("mud-html-block") ||
      cl.contains("mud-change-del") || cl.contains("mud-math-block") ||
      cl.contains("temml-error"));
  }

  // Whether `node` sits anywhere inside a skipped subtree — the ancestor walk
  // the write side uses to reject a selection the anchor rules would refuse.
  // Keeping it here means the skip list lives in exactly one place.
  function inSkippedSubtree(node, root) {
    var el = node.nodeType === Node.ELEMENT_NODE ? node : node.parentNode;
    while (el && el !== root) {
      if (isSkippedSubtree(el)) return true;
      el = el.parentNode;
    }
    return false;
  }

  // The bottom sections, never the selection's source.
  function isBottomSection(node) {
    return node.nodeType === Node.ELEMENT_NODE && node.classList &&
      (node.classList.contains("comments") ||
       node.classList.contains("footnotes"));
  }

  // The nearest enclosing leaf block of a node, up to (not including) root.
  function leafBlock(node, root) {
    var el = node.nodeType === Node.TEXT_NODE ? node.parentNode : node;
    while (el && el !== root) {
      if (LEAF_BLOCK_TAGS[el.tagName]) return el;
      el = el.parentNode;
    }
    return null;
  }

  // A leaf block with no leaf-block descendant: the innermost text container.
  function isInnermostLeaf(el) {
    return el.nodeType === Node.ELEMENT_NODE && LEAF_BLOCK_TAGS[el.tagName] &&
      !el.querySelector(LEAF_BLOCK_SELECTOR);
  }

  // A child of a leaf block that breaks an inline run: a nested leaf block, any
  // element holding one, or a skipped subtree. Inline children (text nodes,
  // `<em>`, `<a>`, `<code>`, comment markers, …) don't break the run.
  function breaksSegment(node) {
    if (node.nodeType !== Node.ELEMENT_NODE) return false;
    if (isSkippedSubtree(node)) return true;
    return !!LEAF_BLOCK_TAGS[node.tagName] ||
      node.querySelector(LEAF_BLOCK_SELECTOR) != null;
  }

  // A block's text with the marker glyphs and footnote references removed, so
  // two blocks that differ only in their markers compare equal.
  function markerFreeText(el) {
    var text = "";
    (function walk(n) {
      if (n.nodeType === Node.TEXT_NODE) { text += n.nodeValue; return; }
      if (n.nodeType !== Node.ELEMENT_NODE || isMarkerElement(n) ||
          isSkippedSubtree(n)) return;
      for (var c = n.firstChild; c; c = c.nextSibling) walk(c);
    })(el);
    return text;
  }

  // The marker-free text of `element`'s children in the half-open child range
  // [start, end) — a logical block's own text.
  function rangeText(element, start, end) {
    var text = "";
    var kids = element.childNodes;
    for (var i = start; i < end; i++) text += markerFreeText(kids[i]);
    return text;
  }

  // Enumerate every logical block under `root` in document order, calling
  // `fn({element, childStart, childEnd, text})` for each. An innermost leaf is
  // one block spanning all its children; a leaf block that also holds nested
  // leaf blocks yields one block per non-empty inline segment and descends into
  // the nested blocks in place, so the document order is preserved.
  function eachLogicalBlock(root, fn) {
    // `inLeaf` is true while iterating the children of a leaf-block element:
    // its inline runs are segments. In a plain container (a list, a table, the
    // body) an inline run is stray whitespace between tags and is ignored.
    (function walk(node, inLeaf) {
      var kids = node.childNodes;
      var runStart = -1;
      for (var i = 0; i <= kids.length; i++) {
        var child = i < kids.length ? kids[i] : null;
        var isBreak = !child || breaksSegment(child) || isBottomSection(child);
        if (!isBreak) {
          if (runStart < 0) runStart = i;
          continue;
        }
        // Close the pending inline run: a segment, if we're in a leaf block.
        if (inLeaf && runStart >= 0) {
          var text = rangeText(node, runStart, i);
          if (normalizeWS(text).trim() !== "") {
            fn({ element: node, childStart: runStart, childEnd: i, text: text });
          }
        }
        runStart = -1;
        if (!child) break;
        // Descend into the block child (unless skipped or a bottom section).
        if (isSkippedSubtree(child) || isBottomSection(child)) continue;
        if (LEAF_BLOCK_TAGS[child.tagName]) {
          if (isInnermostLeaf(child)) {
            fn({
              element: child, childStart: 0,
              childEnd: child.childNodes.length,
              text: rangeText(child, 0, child.childNodes.length)
            });
          } else {
            walk(child, true);   // leaf block with nested leaf blocks
          }
        } else {
          walk(child, false);    // plain container
        }
      }
    })(root, false);
  }

  // The node before `n` in a backward document-order walk. Stops at `root`.
  function previousInDocument(n, root) {
    if (n === root) return null;
    var prev = n.previousSibling;
    if (!prev) return n.parentNode === root ? null : n.parentNode;
    while (prev.lastChild) prev = prev.lastChild;
    return prev;
  }

  // Whether a text node sits inside a marker (💬, a footnote number): no part
  // of any block's anchor text, but the block around it still anchors.
  function inMarker(node, root) {
    for (var el = node.parentNode; el && el !== root; el = el.parentNode) {
      if (isMarkerElement(el)) return true;
    }
    return false;
  }

  // The last position at or before (node, offset) holding text a comment can
  // anchor to: `{node: <a text node>, offset, crossedSkipped}`, or null.
  //
  // WebKit doesn't leave a dragged selection's end on the last character it
  // covers: drag past the end of a line and the range ends at a boundary in the
  // block below — `(nextLi, 0)`, or the whitespace between the two — with
  // nothing of that block selected. Taken at face value it anchors the comment
  // in the wrong block, so walk back to the text the selection really covers.
  //
  // `crossedSkipped` says the walk crossed real text in a skipped subtree: the
  // quotation would carry text `markerFreeText` leaves out, which the read side
  // could never match, so the write side refuses the selection.
  function anchorableEnd(node, offset, root) {
    var n = node, head = null, crossedSkipped = false;
    if (node.nodeType === Node.TEXT_NODE) {
      head = node.nodeValue.slice(0, offset);
    } else if (offset > 0) {
      // (element, k) is the boundary before childNodes[k].
      n = node.childNodes[offset - 1];
      while (n.lastChild) n = n.lastChild;
      if (n.nodeType === Node.TEXT_NODE) head = n.nodeValue;
    }
    while (n) {
      if (n.nodeType === Node.TEXT_NODE && !inMarker(n, root)) {
        // The first node counts only as far as the end; the rest count whole.
        var text = (head === null ? n.nodeValue : head).replace(/\s+$/, "");
        if (text !== "") {
          if (!inSkippedSubtree(n, root)) {
            return { node: n, offset: text.length, crossedSkipped: crossedSkipped };
          }
          crossedSkipped = true;
        }
      }
      n = previousInDocument(n, root);
      head = null;
    }
    return null;
  }

  // The logical block a selection end sits in: the nearest-ancestor leaf block,
  // narrowed to the segment whose child range contains `node` when that block
  // also holds nested leaf blocks. Returns {element, childStart, childEnd, text}
  // or null.
  function segmentAt(node, root) {
    var block = leafBlock(node, root);
    if (!block) return null;
    if (isInnermostLeaf(block)) {
      var end = block.childNodes.length;
      return {
        element: block, childStart: 0, childEnd: end,
        text: rangeText(block, 0, end)
      };
    }
    // Find the direct child of `block` that is (or contains) `node`.
    var directChild = node;
    while (directChild && directChild.parentNode !== block) {
      directChild = directChild.parentNode;
    }
    if (!directChild) return null;
    var kids = block.childNodes;
    var idx = Array.prototype.indexOf.call(kids, directChild);
    if (idx < 0) return null;
    var start = idx, stop = idx + 1;
    while (start > 0 && !breaksSegment(kids[start - 1]) &&
           !isBottomSection(kids[start - 1])) start--;
    while (stop < kids.length && !breaksSegment(kids[stop]) &&
           !isBottomSection(kids[stop])) stop++;
    return {
      element: block, childStart: start, childEnd: stop,
      text: rangeText(block, start, stop)
    };
  }

  function sameLogicalBlock(a, b) {
    return a.element === b.element && a.childStart === b.childStart &&
      a.childEnd === b.childEnd;
  }

  // How many earlier logical blocks under `root` share `block`'s marker-free
  // text: the occurrence index that disambiguates identical blocks. Counting by
  // logical-block identity (element + child range) stops at the target block —
  // a plain element-identity check couldn't, because a tight `<li>` with a
  // nested list is never an innermost leaf and its segment shares the element.
  function occurrenceOf(block, blockText, root) {
    var target = normalizeWS(blockText).trim();
    var count = 0, found = false;
    eachLogicalBlock(root, function (lb) {
      if (found) return;
      if (sameLogicalBlock(lb, block)) { found = true; return; }
      if (normalizeWS(lb.text).trim() === target) count++;
    });
    return count;
  }

  window.Mud = window.Mud || {};
  window.Mud.commentAnchor = {
    normalizeWS: normalizeWS,
    isMarkerElement: isMarkerElement,
    isInnermostLeaf: isInnermostLeaf,
    isSkippedSubtree: isSkippedSubtree,
    inSkippedSubtree: inSkippedSubtree,
    markerFreeText: markerFreeText,
    leafBlock: leafBlock,
    anchorableEnd: anchorableEnd,
    eachLogicalBlock: eachLogicalBlock,
    segmentAt: segmentAt,
    occurrenceOf: occurrenceOf
  };
})();
