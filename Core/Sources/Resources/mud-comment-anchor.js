// Mud - Comment anchoring primitives (shared by the read and write sides).
//
// Maps a rendered-DOM position to a block of source text. CommentAnchor.swift
// computes the same block text, so a comment's marker lands byte-exactly;
// `CommentAnchorParityTests.logicalBlocks` pins the Swift mirror of
// `eachLogicalBlock`. Keep the two in sync.
//
// The same rules decide which rendered text a quotation may hold
// (`rangeSlices`), so the write side stores what the read side searches for.
//
// A **logical block** maps one-to-one to a cmark leaf block. It is either an
// *innermost leaf element* (`<p>`, `<h1>`–`<h6>`, `<td>`, `<th>`, or an `<li>`
// with no nested leaf blocks), or a *segment* — one maximal run of inline
// children directly inside a leaf-block element that also contains nested leaf
// blocks. In Mud's output a segment only arises in a tight `<li>`, where each
// bare run of inline content is one cmark paragraph.

(function () {
  "use strict";

  var LEAF_BLOCK_TAGS = {
    P: 1, LI: 1, TD: 1, TH: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1,
    BLOCKQUOTE: 1, PRE: 1, DD: 1, DT: 1, FIGCAPTION: 1, CAPTION: 1, SUMMARY: 1
  };
  var LEAF_BLOCK_SELECTOR =
    "p,li,td,th,h1,h2,h3,h4,h5,h6,blockquote,pre,dd,dt,figcaption,caption,summary";

  function normalizeWS(s) { return s.replace(/\s+/g, " "); }

  // Elements present in the DOM but absent from the source, so their text is no
  // part of a block's anchor text: comment markers, footnote references, and
  // the `<del>` runs `WordSpanEmitter` writes for a tracked change's removed
  // words. Authored `~~strikethrough~~` renders as `<s>`, so a `<del>` in Up
  // output is always change tracking. Named here rather than in
  // `isSkippedSubtree` because a deletion sits mid-paragraph: it must not break
  // an inline segment, and a selection ending inside one must still anchor.
  function isMarkerElement(node) {
    if (node.nodeType !== Node.ELEMENT_NODE) return false;
    if (node.tagName === "DEL") return true;
    return !!node.classList &&
      (node.classList.contains("mud-comment-marker") ||
       node.classList.contains("footnote-ref"));
  }

  // A subtree with no source byte to anchor to, skipped wholesale. Rendered
  // MathML bears no relation to the TeX source, so a quotation anchored in it
  // could never match. CommentAnchor.swift matches none of these either.
  function isSkippedSubtree(node) {
    if (node.nodeType !== Node.ELEMENT_NODE) return false;
    // localName for math: a MathML element is foreign-namespace, so its
    // tagName stays lowercase and comparing against "MATH" would never match.
    if (node.tagName === "PRE" || node.localName === "math") return true;
    var cl = node.classList;
    return !!cl && (cl.contains("mermaid") || cl.contains("mud-html-block") ||
      cl.contains("mud-change-del") || cl.contains("mud-math-block") ||
      cl.contains("temml-error"));
  }

  // Whether `node` sits anywhere inside a skipped subtree — the ancestor walk
  // the write side uses to reject a selection the anchor rules would refuse.
  function inSkippedSubtree(node, root) {
    var el = node.nodeType === Node.ELEMENT_NODE ? node : node.parentNode;
    while (el && el !== root) {
      if (isSkippedSubtree(el)) return true;
      el = el.parentNode;
    }
    return false;
  }

  function isBottomSection(node) {
    return node.nodeType === Node.ELEMENT_NODE && node.classList &&
      (node.classList.contains("comments") ||
       node.classList.contains("footnotes"));
  }

  function leafBlock(node, root) {
    var el = node.nodeType === Node.TEXT_NODE ? node.parentNode : node;
    while (el && el !== root) {
      if (LEAF_BLOCK_TAGS[el.tagName]) return el;
      el = el.parentNode;
    }
    return null;
  }

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

  // Markers removed, so two blocks differing only in them compare equal.
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

  // A logical block's own text: the half-open child range [start, end).
  function rangeText(element, start, end) {
    var text = "";
    var kids = element.childNodes;
    for (var i = start; i < end; i++) text += markerFreeText(kids[i]);
    return text;
  }

  // No part of a quotation: everything `markerFreeText` leaves out, plus the
  // hidden bottom sections.
  function isUnquotable(node) {
    return isMarkerElement(node) || isSkippedSubtree(node) ||
      isBottomSection(node);
  }

  // Trimmed at both ends, so the slices are exactly the quotation's
  // characters: the provisional highlight then shows what will be stored.
  function trimSlices(slices) {
    while (slices.length) {
      var first = slices[0];
      var head = first.node.nodeValue.slice(first.start, first.end);
      var keptHead = head.replace(/^\s+/, "");
      if (!keptHead) { slices.shift(); continue; }
      first.start += head.length - keptHead.length;
      break;
    }
    while (slices.length) {
      var last = slices[slices.length - 1];
      var tail = last.node.nodeValue.slice(last.start, last.end);
      var keptTail = tail.replace(/\s+$/, "");
      if (!keptTail) { slices.pop(); continue; }
      last.end = last.start + keptTail.length;
      break;
    }
    return slices;
  }

  // The quotable text a DOM range covers: one `{node, start, end}` per
  // intersected text node, in document order, clipped to the range's ends. Not
  // `sel.toString()`, which takes the rendered text whole — a selection across
  // a tracked change would carry the removed words, one across a footnote
  // reference its number, and neither is in the file.
  //
  // An unquotable subtree is descended into rather than skipped, since a range
  // end can sit inside one; it contributes no slice. `range` need only carry
  // the four boundary fields, so this runs outside a browser.
  function rangeSlices(range, root) {
    var slices = [];
    var sc = range.startContainer, so = range.startOffset;
    var ec = range.endContainer, eo = range.endOffset;
    var inside = false, finished = false;

    (function walk(node, quotable) {
      if (finished) return;
      if (node.nodeType === Node.TEXT_NODE) {
        if (node === sc) inside = true;
        if (inside && quotable) {
          var from = node === sc ? so : 0;
          var to = node === ec ? eo : node.nodeValue.length;
          if (to > from) slices.push({ node: node, start: from, end: to });
        }
        if (node === ec) finished = true;
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      var kids = node.childNodes;
      // (node, i) is the boundary before child i, and at kids.length the one
      // after the last child.
      for (var i = 0; i <= kids.length; i++) {
        if (node === sc && so === i) inside = true;
        if (node === ec && eo === i) { finished = true; return; }
        if (i === kids.length) break;
        walk(kids[i], quotable && !isUnquotable(kids[i]));
        if (finished) return;
      }
    })(root, !isUnquotable(root));

    return trimSlices(slices);
  }

  function slicesText(slices) {
    var text = "";
    for (var i = 0; i < slices.length; i++) {
      var s = slices[i];
      text += s.node.nodeValue.slice(s.start, s.end);
    }
    return text;
  }

  // Every logical block under `root` in document order, as
  // `fn({element, childStart, childEnd, text})`. An innermost leaf is one block
  // spanning all its children; a leaf block that also holds nested leaf blocks
  // yields one block per non-empty inline segment and descends in place.
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

  function previousInDocument(n, root) {
    if (n === root) return null;
    var prev = n.previousSibling;
    if (!prev) return n.parentNode === root ? null : n.parentNode;
    while (prev.lastChild) prev = prev.lastChild;
    return prev;
  }

  // No part of any block's anchor text, though the block around it anchors.
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

  // The nearest-ancestor leaf block, narrowed to the segment holding `node`
  // when that block also holds nested leaf blocks.
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
  // logical-block identity stops at the target block — element identity
  // couldn't, since a tight `<li>` with a nested list shares its element with
  // its own segment.
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
    isBottomSection: isBottomSection,
    markerFreeText: markerFreeText,
    rangeSlices: rangeSlices,
    slicesText: slicesText,
    leafBlock: leafBlock,
    anchorableEnd: anchorableEnd,
    eachLogicalBlock: eachLogicalBlock,
    segmentAt: segmentAt,
    occurrenceOf: occurrenceOf
  };
})();
