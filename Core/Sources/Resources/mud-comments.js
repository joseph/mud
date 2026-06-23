// Mud - Comment helpers (Up mode).
//
// Draws hover-revealed highlights for anchored comments, routes `[⋯]` marker
// clicks to the native editor, and captures the selection for "Add Comment".
//
// The Swift side calls `Mud.comments.setData([{label, quotation}, …])` after
// load (quotations come from the parsed Comment model, not the marker HTML), at
// which point highlights are (re-)anchored. Injected as a WKUserScript in-app
// only: exports keep the static marker, its `#cmt-LABEL` anchor, and the bottom
// Comments section, so no JS is required there.

(function () {
  "use strict";
  if (!document.querySelector(".up-mode-output")) return;

  var container = document.querySelector(".up-mode-output");
  var quotationByLabel = {};

  function normalizeWS(s) {
    return s.replace(/\s+/g, " ");
  }

  function zoom() {
    return parseFloat(document.documentElement.style.zoom) || 1;
  }

  function rectOf(r) {
    var z = zoom();
    return { x: r.left / z, y: r.top / z, width: r.width / z, height: r.height / z };
  }

  // -- Highlight re-anchoring ----------------------------------------------

  // Build a whitespace-collapsed flat text of the body with a parallel
  // char → (textNode, offset) map, plus each marker's flat-index anchor. The
  // bottom comments/footnotes sections and the marker glyphs are skipped so a
  // quotation never matches inside them.
  function buildIndex() {
    var flat = "";
    var map = [];
    var markerAt = {};
    var prevWasSpace = true; // collapse leading whitespace

    function walk(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        var v = node.nodeValue;
        for (var i = 0; i < v.length; i++) {
          if (/\s/.test(v[i])) {
            if (prevWasSpace) continue;
            flat += " ";
            map.push({ node: node, offset: i });
            prevWasSpace = true;
          } else {
            flat += v[i];
            map.push({ node: node, offset: i });
            prevWasSpace = false;
          }
        }
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      if (node.classList) {
        if (node.classList.contains("comments") ||
            node.classList.contains("footnotes")) return;
        if (node.classList.contains("mud-comment-marker")) {
          markerAt[node.getAttribute("data-mud-label")] = flat.length;
          return; // don't descend into the glyph; the marker is a boundary
        }
      }
      for (var c = node.firstChild; c; c = c.nextSibling) walk(c);
    }

    walk(container);
    return { flat: flat, map: map, markerAt: markerAt };
  }

  function clearHighlights() {
    var marks = container.querySelectorAll("mark.mud-comment-highlight");
    for (var i = 0; i < marks.length; i++) {
      var m = marks[i];
      var parent = m.parentNode;
      if (!parent) continue;
      while (m.firstChild) parent.insertBefore(m.firstChild, m);
      parent.removeChild(m);
      parent.normalize();
    }
  }

  // For each marker, the quotation must occupy the `quotation.length` collapsed
  // characters immediately before it (the marker is written at the quotation's
  // end). On a match, wrap each intersected text-node slice in its own
  // <mark data-mud-label>. Different slices live in different text nodes, so the
  // wraps are independent and order-free.
  function anchorAll() {
    clearHighlights();
    var idx = buildIndex();

    Object.keys(idx.markerAt).forEach(function (label) {
      var quote = quotationByLabel[label];
      if (!quote) return;
      quote = normalizeWS(quote).trim();
      if (!quote) return;

      var end = idx.markerAt[label];
      var start = end - quote.length;
      if (start < 0) return;
      if (idx.flat.slice(start, end) !== quote) return; // unanchored: no highlight

      var i = start;
      while (i < end) {
        var node = idx.map[i].node;
        var startOffset = idx.map[i].offset;
        var endOffset = startOffset + 1;
        var j = i + 1;
        while (j < end && idx.map[j].node === node) {
          endOffset = idx.map[j].offset + 1;
          j++;
        }
        wrapSlice(node, startOffset, endOffset, label);
        i = j;
      }
    });
  }

  function wrapSlice(node, startOffset, endOffset, label) {
    try {
      var range = document.createRange();
      range.setStart(node, startOffset);
      range.setEnd(node, endOffset);
      var mark = document.createElement("mark");
      mark.className = "mud-comment-highlight";
      mark.setAttribute("data-mud-label", label);
      range.surroundContents(mark);
    } catch (e) {
      /* a slice that can't be wrapped just goes un-highlighted */
    }
  }

  function setActive(label, on) {
    if (!label) return;
    var safe = window.CSS && CSS.escape ? CSS.escape(label) : label;
    var marks = container.querySelectorAll(
      'mark.mud-comment-highlight[data-mud-label="' + safe + '"]'
    );
    for (var i = 0; i < marks.length; i++) {
      marks[i].classList.toggle("is-active", on);
    }
  }

  // The label whose highlight is held active by a sidebar selection (distinct
  // from transient marker hover). Selecting a thread in the sidebar reveals it
  // in the document; `reveal(null)` clears.
  var revealedLabel = null;

  function reveal(label) {
    if (revealedLabel && revealedLabel !== label) setActive(revealedLabel, false);
    revealedLabel = label || null;
    if (!revealedLabel) return;
    setActive(revealedLabel, true);
    var safe = window.CSS && CSS.escape ? CSS.escape(revealedLabel) : revealedLabel;
    var marker = container.querySelector(
      '.mud-comment-marker[data-mud-label="' + safe + '"]'
    );
    if (marker && marker.scrollIntoView) {
      marker.scrollIntoView({ block: "center", inline: "nearest" });
    }
  }

  // -- Events --------------------------------------------------------------

  container.addEventListener("mouseover", function (e) {
    var marker = e.target.closest(".mud-comment-marker");
    if (marker) setActive(marker.getAttribute("data-mud-label"), true);
  });

  container.addEventListener("mouseout", function (e) {
    var marker = e.target.closest(".mud-comment-marker");
    if (!marker) return;
    var label = marker.getAttribute("data-mud-label");
    // Keep the highlight lit if this thread is held open by the sidebar.
    if (label !== revealedLabel) setActive(label, false);
  });

  // Marker click → native editor (capture phase, ahead of link routing). When
  // the handler is absent (exports) the native `#cmt-LABEL` jump runs instead.
  container.addEventListener("click", function (e) {
    var marker = e.target.closest(".mud-comment-marker");
    if (!marker) return;
    var handlers = window.webkit && window.webkit.messageHandlers;
    if (!handlers || !handlers.mudCommentOpen) return;
    e.preventDefault();
    e.stopPropagation();
    handlers.mudCommentOpen.postMessage({
      label: marker.getAttribute("data-mud-label"),
      rect: rectOf(marker.getBoundingClientRect()),
    });
  }, true);

  // -- Selection capture ("Add Comment") -----------------------------------

  function isMarkerElement(node) {
    return node.nodeType === Node.ELEMENT_NODE && node.classList &&
      (node.classList.contains("mud-comment-marker") ||
       node.classList.contains("footnote-ref"));
  }

  // Block-level elements whose text the source represents as a single leaf block
  // (paragraph, list item, table cell, heading, …). Matching the *innermost*
  // such ancestor — not the top-level container — keeps the captured text free of
  // the whitespace the DOM inserts between a container's children.
  var LEAF_BLOCK_TAGS = {
    P: 1, LI: 1, TD: 1, TH: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1,
    BLOCKQUOTE: 1, PRE: 1, DD: 1, DT: 1, FIGCAPTION: 1, CAPTION: 1, SUMMARY: 1,
  };

  var LEAF_BLOCK_SELECTOR =
    "p,li,td,th,h1,h2,h3,h4,h5,h6,blockquote,pre,dd,dt,figcaption,caption,summary";

  function leafBlock(node) {
    var el = node.nodeType === Node.TEXT_NODE ? node.parentNode : node;
    while (el && el !== container) {
      if (LEAF_BLOCK_TAGS[el.tagName]) return el;
      el = el.parentNode;
    }
    return null;
  }

  // An *innermost* leaf block: a leaf-block element with no leaf-block descendant
  // (so a blockquote wrapping a paragraph is not one, but the paragraph is).
  function isInnermostLeaf(el) {
    return el.nodeType === Node.ELEMENT_NODE && LEAF_BLOCK_TAGS[el.tagName] &&
      !el.querySelector(LEAF_BLOCK_SELECTOR);
  }

  // The marker-free text of an element (skipping `[⋯]` / footnote markers), to
  // compare against the source the same way as the captured block text.
  function markerFreeText(el) {
    var text = "";
    (function walk(n) {
      if (n.nodeType === Node.TEXT_NODE) { text += n.nodeValue; return; }
      if (n.nodeType !== Node.ELEMENT_NODE || isMarkerElement(n)) return;
      for (var c = n.firstChild; c; c = c.nextSibling) walk(c);
    })(el);
    return text;
  }

  // How many innermost leaf blocks with the same collapsed text precede `block`
  // in the rendered body (the bottom comments/footnotes sections excluded). The
  // Swift side counts identically, so identical-text blocks (e.g. a word that
  // appears in a table cell, a list item, and a heading) disambiguate.
  function occurrenceOf(block, blockText) {
    var target = normalizeWS(blockText).trim();
    var count = 0;
    var found = false;
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
    })(container);
    return count;
  }

  // The selection end as a `{blockText, offset}` locator the Swift side maps to a
  // source byte via cmark — the one DOM→source mapping the design needs. Marker
  // glyphs (the `[⋯]` chip, footnote superscripts) are **skipped**: they have no
  // source-text counterpart, so cmark treats the references as zero-width and
  // this must match. `blockText` locates the source block; `offset` is the
  // marker-free char offset of the selection end within it.
  function endLocator(range) {
    var endNode = range.endContainer;
    var endOffset = range.endOffset;
    var block = leafBlock(endNode);
    if (!block) return null;

    var text = "";
    var offset = null;
    (function walk(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        if (node === endNode && offset === null) offset = text.length + endOffset;
        text += node.nodeValue;
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      if (isMarkerElement(node)) {
        if (offset === null && node.contains(endNode)) offset = text.length;
        return;  // skip the marker subtree
      }
      for (var c = node.firstChild; c; c = c.nextSibling) walk(c);
      if (node === endNode && offset === null) offset = text.length;
    })(block);

    if (offset === null) offset = text.length;
    // A task-list item renders its checkbox as `<input …/> ` — that trailing
    // space becomes a synthetic *leading* space on the item's text node that the
    // Markdown source (and so cmark's block text, which strips leading
    // whitespace) doesn't have. Drop leading whitespace and pull the offset back
    // with it, keeping the offset in cmark's source coordinates; otherwise every
    // task-list anchor lands one character too far.
    var lead = text.length - text.replace(/^\s+/, "").length;
    if (lead) { text = text.slice(lead); offset = Math.max(0, offset - lead); }
    // The quotation is whitespace-trimmed, so the marker belongs right after the
    // last non-whitespace character of the selection. When the selection end
    // swept up trailing whitespace (a common drag/double-click overshoot), pull
    // the offset back over it — otherwise the marker lands a byte too far (past
    // the space) and the re-anchored highlight, keyed on the trimmed quotation,
    // no longer lines up. At a block's end the stray offset also overruns the
    // source inline text and the anchor resolves to nothing at all.
    while (offset > 0 && /\s/.test(text[offset - 1])) offset--;
    return { offset: offset, blockText: text, occurrence: occurrenceOf(block, text) };
  }

  function draft() {
    var sel = window.getSelection();
    if (!sel || sel.isCollapsed || sel.rangeCount === 0) return false;
    var range = sel.getRangeAt(0);
    if (!container.contains(range.commonAncestorContainer)) return false;
    var quotation = normalizeWS(sel.toString()).trim();
    if (!quotation) return false;

    var handlers = window.webkit && window.webkit.messageHandlers;
    if (!handlers || !handlers.mudCommentDraft) return false;
    handlers.mudCommentDraft.postMessage({
      quotation: quotation,
      rect: rectOf(range.getBoundingClientRect()),
      locator: endLocator(range),
    });
    return true;
  }

  // -- Selection state (drives the "Add Comment" menu item) ----------------

  // Report whether a non-empty selection exists in the rendered body, so the
  // native Edit-menu "Add Comment…" can enable/disable. Posts only on change to
  // keep IPC quiet; an initial call reports the (empty) starting state.
  var lastHasSelection = null;

  function reportSelection() {
    var sel = window.getSelection();
    var has = !!(sel && !sel.isCollapsed && sel.toString().trim() &&
      sel.anchorNode && container.contains(sel.anchorNode));
    if (has === lastHasSelection) return;
    lastHasSelection = has;
    var handlers = window.webkit && window.webkit.messageHandlers;
    if (handlers && handlers.mudSelection) {
      handlers.mudSelection.postMessage(has);
    }
  }

  document.addEventListener("selectionchange", reportSelection);
  reportSelection();

  // -- Public API ----------------------------------------------------------

  window.Mud = window.Mud || {};
  window.Mud.comments = {
    setData: function (list) {
      quotationByLabel = {};
      (list || []).forEach(function (c) {
        quotationByLabel[c.label] = c.quotation || "";
      });
      anchorAll();
    },
    reanchor: anchorAll,
    draft: draft,
    reveal: reveal,
  };
})();
