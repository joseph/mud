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

  // A block's text with the marker glyphs and footnote references removed, so
  // two blocks that differ only in their markers compare equal.
  function markerFreeText(el) {
    var text = "";
    (function walk(n) {
      if (n.nodeType === Node.TEXT_NODE) { text += n.nodeValue; return; }
      if (n.nodeType !== Node.ELEMENT_NODE || isMarkerElement(n)) return;
      for (var c = n.firstChild; c; c = c.nextSibling) walk(c);
    })(el);
    return text;
  }

  // How many earlier innermost leaves under root share block's marker-free
  // text: the occurrence index that disambiguates identical blocks.
  function occurrenceOf(block, blockText, root) {
    var target = normalizeWS(blockText).trim();
    var count = 0, found = false;
    (function walk(node) {
      if (found || node.nodeType !== Node.ELEMENT_NODE) return;
      if (node.classList && (node.classList.contains("comments") ||
          node.classList.contains("footnotes"))) return;
      if (isInnermostLeaf(node)) {
        if (node === block) { found = true; return; }
        if (normalizeWS(markerFreeText(node)).trim() === target) count++;
        return;
      }
      for (var c = node.firstChild; c && !found; c = c.nextSibling) walk(c);
    })(root);
    return count;
  }

  window.Mud = window.Mud || {};
  window.Mud.commentAnchor = {
    normalizeWS: normalizeWS,
    isMarkerElement: isMarkerElement,
    isInnermostLeaf: isInnermostLeaf,
    markerFreeText: markerFreeText,
    leafBlock: leafBlock,
    occurrenceOf: occurrenceOf
  };
})();
