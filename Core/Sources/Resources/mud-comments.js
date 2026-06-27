// Mud - Comments column (read side, Up mode).
//
// Projects a capsule per comment from the hidden bottom `<section
// class="comments">` (the single source of comment HTML), positions each
// capsule beside its quotation with the placement pass below, and reveals a
// quotation's highlight on hover / activate. This file is bundled everywhere,
// exports
// included; the write side (selection, compose, submit, edit, delete) lives in
// mud-comments-edit.js and is bundled in the app only.
//
// The column is built only in column mode (`<html class="comments-column">`,
// set by MudCore) with the toggle on (`is-comments-column`). It clones
// already-rendered nodes out of the section — it never parses Markdown — and
// strips their ids so the page holds no duplicates.

(function () {
  "use strict";

  var container = document.querySelector(".up-mode-output");
  if (!container) return;

  var GAP = 15;           // minimum vertical gap between rows
  var INACTIVE_H = 45;    // a collapsed capsule's height
  var COMPOSE_H = 100;    // compose form's starting height (it auto-grows; the
                          // write side measures the real height on every relayout)

  var capsules = {};          // label -> capsule element
  var quotationByLabel = {};  // label -> quotation text (for anchoring)
  var activeLabel = null;
  var rafPending = 0;
  var lastVisible = null;     // last applied visibility (idempotent setVisible)

  function normalizeWS(s) {
    return s.replace(/\s+/g, " ");
  }

  // The element's top in layout (pre-zoom) pixels, summed up the offsetParent
  // chain to the body. Robust to the document `zoom`, which scales container and
  // capsules together, so capsule `top` values stay in the same space.
  function layoutTop(el) {
    var y = 0;
    while (el && el !== document.body) {
      y += el.offsetTop;
      el = el.offsetParent;
    }
    return y;
  }

  function section() {
    return document.querySelector("section.comments[data-comments]");
  }

  // Visible when the render is in column mode and the column is toggled on. In
  // an export the toggle class is force-included, so the test is uniform.
  function enabled() {
    var root = document.documentElement;
    return root.classList.contains("comments-column") &&
      root.classList.contains("is-comments-column");
  }

  // The "Show comment markers" preference: the inline 💬 markers are visible
  // on screen and interactive (hover highlights the quotation; click opens the
  // column to the comment). Independent of whether the column is showing.
  function markersShown() {
    return document.documentElement.classList.contains("show-comment-markers");
  }

  // -- Highlight anchoring (off the hidden quote markers) -------------------

  // Build a whitespace-collapsed flat text of the body with a parallel char →
  // (textNode, offset) map, plus each marker's flat-index anchor. The bottom
  // sections and the marker glyphs are skipped so a quotation never matches
  // inside them.
  function buildIndex() {
    var flat = "";
    var map = [];
    var markerAt = {};
    var prevWasSpace = true;

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
          return;
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

  function wrapSlice(node, startOffset, endOffset, label) {
    try {
      var range = document.createRange();
      range.setStart(node, startOffset);
      range.setEnd(node, endOffset);
      var mark = document.createElement("mark");
      mark.className = "mud-comment-highlight";
      mark.setAttribute("data-mud-label", label);
      range.surroundContents(mark);
      return mark;
    } catch (e) {
      /* a slice that can't be wrapped goes un-highlighted */
      return null;
    }
  }

  // A truncation marker: an ellipsis (the `…` character or three dots) with
  // whitespace on both sides. Splitting `flat` on it yields the kept parts.
  var ELLIPSIS_SPLIT = /\s+(?:…|\.\.\.)\s+/;

  // The flat-text index where `quote` begins, anchored to end just before the
  // marker at `end` — or -1 if it doesn't anchor. Two phases (see
  // Doc/Spec/comments.md, "Quotation truncation"):
  //   1. Verbatim — the whole quotation sits immediately before the marker.
  //   2. Truncated — only when phase 1 fails and the quotation carries a spaced
  //      ellipsis. Split into parts; anchor the last part at the marker, then
  //      walk left, matching each earlier part to its nearest occurrence before
  //      the part already matched. The returned range (first part's start →
  //      marker) covers the elided middle too.
  function matchQuotationStart(flat, end, quote) {
    var start = end - quote.length;
    if (start >= 0 && flat.slice(start, end) === quote) return start;

    var parts = quote.split(ELLIPSIS_SPLIT);
    if (parts.length < 2) return -1;
    for (var i = 0; i < parts.length; i++) {
      parts[i] = parts[i].trim();
      if (!parts[i]) return -1;
    }

    var last = parts[parts.length - 1];
    var s = end - last.length;
    if (s < 0 || flat.slice(s, end) !== last) return -1;
    for (var k = parts.length - 2; k >= 0; k--) {
      var at = flat.lastIndexOf(parts[k], s - parts[k].length);
      if (at < 0) return -1;
      s = at;
    }
    return s;
  }

  // For each marker, find where its quotation anchors (verbatim, or truncated).
  // On a match, wrap each intersected text-node slice in its own
  // <mark data-mud-label>.
  function anchorAll() {
    clearHighlights();
    var idx = buildIndex();

    Object.keys(idx.markerAt).forEach(function (label) {
      var quote = quotationByLabel[label];
      if (!quote) return;
      quote = normalizeWS(quote).trim();
      if (!quote) return;

      var end = idx.markerAt[label];
      var start = matchQuotationStart(idx.flat, end, quote);
      if (start < 0) return;

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

  function setHighlight(label, on) {
    if (!label) return;
    var safe = window.CSS && CSS.escape ? CSS.escape(label) : label;
    var marks = container.querySelectorAll(
      'mark.mud-comment-highlight[data-mud-label="' + safe + '"]');
    for (var i = 0; i < marks.length; i++) {
      marks[i].classList.toggle("is-active", on);
    }
  }

  // -- Selection draft (write side, while composing) ------------------------

  // While a new comment is being written, the native text selection collapses
  // the moment the compose box takes focus. To keep the quoted span visible we
  // paint our own provisional highlight + 💬 marker over the live selection,
  // under a sentinel label. The highlight carries `.mud-comment-draft` so it
  // stays painted (not hover-toggled like a real one) until the comment is
  // saved or dismissed; that styling is app-only (mud-comments-edit.css). A
  // real `setData` on save drops the unknown-label marker and reprojects the
  // highlights, so it is swept up even without the explicit clear.
  var DRAFT_LABEL = "mud-draft";

  // True when a text node sits inside a marker glyph or the hidden bottom
  // sections — never part of a quotable selection, so it isn't highlighted.
  function inSkippedRegion(node) {
    var el = node.parentNode;
    while (el && el !== container) {
      if (el.classList && (el.classList.contains("mud-comment-marker") ||
          el.classList.contains("comments") ||
          el.classList.contains("footnotes"))) return true;
      el = el.parentNode;
    }
    return false;
  }

  // The text-node slices a range covers, clipped to its end points: one
  // {node, start, end} per intersected text node (skipped regions excluded).
  function collectRangeTextSlices(range) {
    var slices = [];
    var common = range.commonAncestorContainer;
    if (common.nodeType === Node.TEXT_NODE) {
      if (!inSkippedRegion(common) && range.endOffset > range.startOffset) {
        slices.push({
          node: common, start: range.startOffset, end: range.endOffset
        });
      }
      return slices;
    }
    var walker = document.createTreeWalker(common, NodeFilter.SHOW_TEXT, {
      acceptNode: function (n) {
        return range.intersectsNode(n) && !inSkippedRegion(n)
          ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_REJECT;
      }
    });
    var n;
    while ((n = walker.nextNode())) {
      var s = n === range.startContainer ? range.startOffset : 0;
      var e = n === range.endContainer ? range.endOffset : n.nodeValue.length;
      if (e > s) slices.push({ node: n, start: s, end: e });
    }
    return slices;
  }

  // Paint the provisional highlight + marker over `range`: each text-node slice
  // wrapped in its own <mark> (surroundContents needs a single-node range), then
  // the marker just after the last slice — the quotation's end, where the saved
  // marker will land. CSS reveals the marker only when markers are shown.
  function showSelectionDraft(range) {
    clearSelectionDraft();
    if (!range) return;
    var slices = collectRangeTextSlices(range);
    var lastMark = null;
    for (var i = 0; i < slices.length; i++) {
      var mark = wrapSlice(
        slices[i].node, slices[i].start, slices[i].end, DRAFT_LABEL);
      if (mark) { mark.classList.add("mud-comment-draft"); lastMark = mark; }
    }
    if (lastMark && lastMark.parentNode) {
      var marker = makeMarker(DRAFT_LABEL);
      lastMark.parentNode.insertBefore(marker, lastMark.nextSibling);
    }
  }

  // Remove the provisional highlight + marker (Cancel / Escape, or after a save
  // — where `setData` would also have swept the sentinel).
  function clearSelectionDraft() {
    var safe = cssEsc(DRAFT_LABEL);
    var marker = container.querySelector(
      '.mud-comment-marker[data-mud-label="' + safe + '"]');
    if (marker && marker.parentNode) marker.parentNode.removeChild(marker);
    var marks = container.querySelectorAll(
      'mark.mud-comment-highlight[data-mud-label="' + safe + '"]');
    for (var i = 0; i < marks.length; i++) {
      var mk = marks[i], parent = mk.parentNode;
      if (!parent) continue;
      while (mk.firstChild) parent.insertBefore(mk.firstChild, mk);
      parent.removeChild(mk);
      parent.normalize();
    }
  }

  // -- Projection: build capsules from the section --------------------------

  function textOf(el) {
    return el ? normalizeWS(el.textContent || "").trim() : "";
  }

  function stripIds(el) {
    if (el.removeAttribute) el.removeAttribute("id");
    if (!el.querySelectorAll) return;
    var ided = el.querySelectorAll("[id]");
    for (var i = 0; i < ided.length; i++) ided[i].removeAttribute("id");
  }

  function cloneClean(node) {
    var c = node.cloneNode(true);
    stripIds(c);
    return c;
  }

  // Relative within a day ("Just now", "11 hours ago"); a locale-ordered short
  // date ("Jun 16" / "16 Jun") beyond. Falls back to the preformatted absolute
  // string only when the epoch is missing.
  function formatTime(ms, abs) {
    var t = parseInt(ms, 10);
    if (!ms || isNaN(t)) return abs || "";
    var diff = Date.now() - t;
    if (diff < 0) diff = 0;
    if (diff >= 24 * 3600 * 1000) {
      return new Date(t).toLocaleDateString(undefined, {
        month: "short", day: "numeric"
      });
    }
    var s = Math.floor(diff / 1000);
    if (s < 60) return "Just now";
    var m = Math.floor(s / 60);
    if (m < 60) return m === 1 ? "1 minute ago" : m + " minutes ago";
    var h = Math.floor(m / 60);
    return h === 1 ? "1 hour ago" : h + " hours ago";
  }

  function buildMessage(src) {
    var m = document.createElement("div");
    m.className = "mud-comment-message";
    var author = src.getAttribute("data-mud-author") || "";
    var ms = src.getAttribute("data-mud-time");
    var abs = src.getAttribute("data-mud-time-abs");
    var time = formatTime(ms, abs);
    if (author || time) {
      var attr = document.createElement("div");
      attr.className = "mud-comment-attribution";
      var a = document.createElement("span");
      a.className = "mud-comment-author";
      a.textContent = author ? "💬 " + author : "";
      var tm = document.createElement("span");
      tm.className = "mud-comment-time";
      // Keep the raw time so the relative label can be recomputed on expand.
      if (ms) tm.setAttribute("data-mud-time", ms);
      if (abs) tm.setAttribute("data-mud-time-abs", abs);
      tm.textContent = time;
      attr.appendChild(a);
      attr.appendChild(tm);
      m.appendChild(attr);
    }
    var body = src.querySelector(".mud-comment-body");
    if (body) m.appendChild(cloneClean(body));
    return m;
  }

  // Recompute each message's relative time from its stored epoch — the projected
  // label is a snapshot, so it goes stale until the thread is reopened.
  function refreshTimes(cap) {
    var spans = cap.querySelectorAll(".mud-comment-time[data-mud-time]");
    for (var i = 0; i < spans.length; i++) {
      spans[i].textContent = formatTime(
        spans[i].getAttribute("data-mud-time"),
        spans[i].getAttribute("data-mud-time-abs"));
    }
  }

  function projectCapsule(li) {
    var label = li.getAttribute("data-mud-label");
    var messages = li.querySelectorAll(".mud-comment-message");
    var first = messages[0];

    var cap = document.createElement("div");
    cap.className = "mud-capsule";
    cap.setAttribute("data-mud-label", label);

    // Collapsed bar: "💬 Author: first message…".
    var bar = document.createElement("div");
    bar.className = "mud-capsule-bar";
    var emoji = document.createElement("span");
    emoji.className = "mud-bar-emoji";
    emoji.textContent = "💬";
    var author = document.createElement("span");
    author.className = "mud-bar-author";
    var firstAuthor = first ? (first.getAttribute("data-mud-author") || "") : "";
    author.textContent = firstAuthor ? firstAuthor + ":" : "";
    var text = document.createElement("span");
    text.className = "mud-bar-text";
    text.textContent = first ? textOf(first.querySelector(".mud-comment-body")) : "";
    bar.appendChild(emoji);
    if (firstAuthor) bar.appendChild(author);
    bar.appendChild(text);
    cap.appendChild(bar);

    // "N replies" label for a collapsed thread.
    if (messages.length > 1) {
      var rep = document.createElement("div");
      rep.className = "mud-capsule-replies";
      var n = messages.length - 1;
      rep.textContent = n === 1 ? "1 reply" : n + " replies";
      cap.appendChild(rep);
    }

    // Expanded thread (shown only while active). The quotation is not shown
    // here — it is highlighted in the document instead.
    var thread = document.createElement("div");
    thread.className = "mud-capsule-thread";
    for (var i = 0; i < messages.length; i++) {
      thread.appendChild(buildMessage(messages[i]));
    }
    cap.appendChild(thread);

    wireCapsule(cap, label);
    return cap;
  }

  function ensureColumn() {
    var col = document.getElementById("mud-comments-column");
    if (!col) {
      col = document.createElement("div");
      col.id = "mud-comments-column";
      document.body.appendChild(col);
    }
    return col;
  }

  // The "Comments" header pinned at the top of the column: a "Comments" title,
  // previous / next navigation arrows, and a running count badge. Created once
  // per column; the arrows and `count` are refreshed on every project. The
  // arrows show whenever there is at least one comment.
  function ensureHeader(col, count) {
    var header = col.querySelector("#mud-comments-header");
    if (!header) {
      header = document.createElement("div");
      header.id = "mud-comments-header";
      var title = document.createElement("span");
      title.className = "mud-comments-title";
      title.textContent = "Comments";

      var nav = document.createElement("div");
      nav.className = "mud-comments-nav";
      var prev = makeNavButton("mud-comments-prev", "Previous comment", "‹", -1);
      var next = makeNavButton("mud-comments-next", "Next comment", "›", 1);
      var badge = document.createElement("span");
      badge.className = "mud-comments-count";
      nav.appendChild(prev);
      nav.appendChild(badge);
      nav.appendChild(next);

      header.appendChild(title);
      header.appendChild(nav);
      col.appendChild(header);
    }
    var badgeEl = header.querySelector(".mud-comments-count");
    badgeEl.textContent = String(count);
    badgeEl.style.display = count > 0 ? "" : "none";
    var showArrows = count > 0 ? "" : "none";
    header.querySelector(".mud-comments-prev").style.display = showArrows;
    header.querySelector(".mud-comments-next").style.display = showArrows;
    return header;
  }

  // A header arrow button. A `mousedown` that stops propagation keeps the
  // document-level mousedown from deactivating the open comment before the
  // click lands, so `navigate` can still step relative to it.
  function makeNavButton(cls, label, glyph, direction) {
    var btn = document.createElement("button");
    btn.type = "button";
    btn.className = cls;
    btn.setAttribute("aria-label", label);
    btn.textContent = glyph;
    btn.addEventListener("mousedown", function (e) { e.stopPropagation(); });
    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      navigate(direction);
    });
    return btn;
  }

  function teardownColumn() {
    var col = document.getElementById("mud-comments-column");
    if (col && col.parentNode) col.parentNode.removeChild(col);
    capsules = {};
    activeLabel = null;
  }

  // Populate quotationByLabel from the bottom section and (re)wrap the highlight
  // marks, independent of the column. With the column closed but the markers
  // shown, a marker still needs its quotation highlight on hover.
  function anchorHighlightsOnly() {
    var sec = section();
    quotationByLabel = {};
    if (sec) {
      var lis = sec.querySelectorAll("li[data-mud-label]");
      for (var i = 0; i < lis.length; i++) {
        var q = lis[i].getAttribute("data-mud-quotation");
        if (q) quotationByLabel[lis[i].getAttribute("data-mud-label")] = q;
      }
    }
    anchorAll();
  }

  // (Re)build every capsule from the section, then lay out.
  function project() {
    if (!enabled()) {
      teardownColumn();
      // Keep the marks alive for marker hover when the column is closed but the
      // markers are shown; otherwise drop them.
      if (markersShown()) anchorHighlightsOnly();
      else clearHighlights();
      return;
    }
    var sec = section();
    var col = ensureColumn();
    var wasActive = activeLabel;

    // Keep the header and any write-side items (Add button, compose) the hooks
    // manage; remove the projected capsules so they rebuild from the section.
    var header = col.querySelector("#mud-comments-header");
    var keep = api.hooks.ownedNodes ? api.hooks.ownedNodes() : [];
    var child = col.firstChild;
    while (child) {
      var next = child.nextSibling;
      if (child !== header && keep.indexOf(child) === -1) col.removeChild(child);
      child = next;
    }

    capsules = {};
    quotationByLabel = {};
    activeLabel = null;

    if (sec) {
      var lis = sec.querySelectorAll("li[data-mud-label]");
      for (var i = 0; i < lis.length; i++) {
        var li = lis[i];
        var label = li.getAttribute("data-mud-label");
        var quote = li.getAttribute("data-mud-quotation");
        if (quote) quotationByLabel[label] = quote;
        var cap = projectCapsule(li);
        col.appendChild(cap);
        capsules[label] = cap;
      }
    }

    ensureHeader(col, Object.keys(capsules).length);
    anchorAll();
    if (api.hooks.afterProject) api.hooks.afterProject();
    // Keep a comment expanded across a reproject (e.g. after a reply or edit).
    if (wasActive && capsules[wasActive]) {
      activate(wasActive);
    } else {
      layout();
    }
  }

  // -- Placement pass -------------------------------------------------------

  // A comment's preferred position, in layout pixels: the top of its quotation
  // highlight, or — for a quote-less comment with no highlight — the position of
  // its hidden inline marker (kept measurable by the visually-hidden CSS).
  function preferredPosition(label) {
    var safe = window.CSS && CSS.escape ? CSS.escape(label) : label;
    var anchor = container.querySelector(
        'mark.mud-comment-highlight[data-mud-label="' + safe + '"]') ||
      container.querySelector(
        '.mud-comment-marker[data-mud-label="' + safe + '"]');
    if (!anchor) return 0;
    return Math.max(0, layoutTop(anchor));
  }

  // Let the active capsule take its natural height, pin it there (so the height
  // transition has a pixel target to animate to), and return that height.
  function sizeActive(cap) {
    cap.style.height = "auto";
    var h = cap.offsetHeight;
    cap.style.height = h + "px";
    return h;
  }

  // Lay the items out top to bottom: each sits at its preferred position, or is
  // pushed down to clear the row above plus the minimum gap. Sort by preferred
  // position, breaking ties by build order. Idempotent — re-running from the
  // current heights always recomputes absolute tops, so a row pushed down by a
  // now-shorter neighbor slides back up on the next pass.
  function solve(items, startTop) {
    items.sort(function (a, b) {
      return a.preferred - b.preferred || a.order - b.order;
    });
    var nextFree = startTop || 0;
    for (var i = 0; i < items.length; i++) {
      var it = items[i];
      it.top = Math.max(it.preferred, nextFree);
      nextFree = it.top + it.height + GAP;
    }
  }

  function layout() {
    if (!enabled()) return;
    var items = [];
    var order = 0;

    Object.keys(capsules).forEach(function (label) {
      var cap = capsules[label];
      var height;
      if (label === activeLabel) {
        height = sizeActive(cap);
      } else {
        cap.style.height = "";
        height = INACTIVE_H;
      }
      items.push({
        el: cap, preferred: preferredPosition(label), height: height,
        order: order++
      });
    });

    if (api.hooks.extraItems) {
      var extra = api.hooks.extraItems();
      for (var i = 0; i < extra.length; i++) {
        extra[i].order = order++;
        items.push(extra[i]);
      }
    }

    // Reserve the header's band at the top so no row sits under it.
    var header = document.getElementById("mud-comments-header");
    var startTop = header ? layoutTop(header) + header.offsetHeight + GAP : 0;

    solve(items, startTop);
    for (var k = 0; k < items.length; k++) {
      items[k].el.style.top = items[k].top + "px";
    }
  }

  function scheduleLayout() {
    if (rafPending) return;
    rafPending = requestAnimationFrame(function () {
      rafPending = 0;
      layout();
    });
  }

  // Reproject only when column visibility actually flips. A redundant call (same
  // value) must not rebuild the column, or it would wipe an open inline compose
  // box. Called by mud.js on every `is-comments-column` `setClass`, and by the
  // marker-click reveal below.
  function syncVisible() {
    var on = enabled();
    if (on === lastVisible) return;
    lastVisible = on;
    // Closing the column cancels an in-progress new comment: let the write side
    // tear down the compose box and its provisional draft (highlight + marker)
    // before `project()` removes the column out from under it.
    if (!on && api.hooks.onHide) api.hooks.onHide();
    project();
  }

  // -- Hover / activate -----------------------------------------------------

  function wireCapsule(cap, label) {
    cap.addEventListener("mouseenter", function () {
      if (label !== activeLabel) setHighlight(label, true);
    });
    cap.addEventListener("mouseleave", function () {
      if (label !== activeLabel) setHighlight(label, false);
    });
    cap.addEventListener("click", function (e) {
      if (cap.classList.contains("is-active")) return;
      e.stopPropagation();
      activate(label);
    });
  }

  function activate(label) {
    if (activeLabel && activeLabel !== label) deactivate();
    var cap = capsules[label];
    if (!cap) return;
    activeLabel = label;
    cap.classList.add("is-active");
    setHighlight(label, true);
    refreshTimes(cap);
    if (api.hooks.decorateActive) api.hooks.decorateActive(cap, label);
    layout();
  }

  function deactivate() {
    if (!activeLabel) return;
    var cap = capsules[activeLabel];
    if (cap) {
      cap.classList.remove("is-active");
      if (api.hooks.undecorateActive) api.hooks.undecorateActive(cap, activeLabel);
    }
    setHighlight(activeLabel, false);
    activeLabel = null;
    layout();
  }

  document.addEventListener("mousedown", function (e) {
    if (!activeLabel) return;
    var cap = capsules[activeLabel];
    if (cap && !cap.contains(e.target)) deactivate();
  });

  // -- Previous / next navigation -------------------------------------------

  // Comment labels in document order — sorted by the same preferred position
  // the placement pass uses, so navigation follows the order the capsules read
  // down the column.
  function orderedLabels() {
    return Object.keys(capsules).sort(function (a, b) {
      return preferredPosition(a) - preferredPosition(b);
    });
  }

  function scrollToComment(label) {
    var safe = cssEsc(label);
    var anchor = container.querySelector(
        'mark.mud-comment-highlight[data-mud-label="' + safe + '"]') ||
      container.querySelector(
        '.mud-comment-marker[data-mud-label="' + safe + '"]');
    if (anchor) anchor.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  // Step to the previous (-1) or next (+1) comment, wrapping around the ends.
  // The step is relative to the open comment; with none open, +1 lands on the
  // first comment and -1 on the last, like the Find bar.
  function navigate(direction) {
    var order = orderedLabels();
    if (!order.length) return;
    var current = activeLabel ? order.indexOf(activeLabel) : -1;
    var n = current + direction;
    n = ((n % order.length) + order.length) % order.length;
    var label = order[n];
    activate(label);
    scrollToComment(label);
  }

  // -- Inline marker interactions (when shown) ------------------------------

  // With "Show comment markers" on, the inline 💬 chips are visible and
  // interactive. Handlers are delegated off the container, so the same ones
  // cover markers from the initial render and from live edits. Hovering previews
  // the quotation highlight; clicking opens the column to the comment.
  function markerLabelFor(target) {
    if (!target || !target.closest) return null;
    var m = target.closest(".mud-comment-marker");
    return m && container.contains(m) ? m.getAttribute("data-mud-label") : null;
  }

  container.addEventListener("mouseover", function (e) {
    var label = markerLabelFor(e.target);
    if (label && label !== activeLabel) setHighlight(label, true);
  });

  container.addEventListener("mouseout", function (e) {
    var label = markerLabelFor(e.target);
    if (label && label !== activeLabel) setHighlight(label, false);
  });

  container.addEventListener("click", function (e) {
    var label = markerLabelFor(e.target);
    if (!label) return;
    e.preventDefault();   // don't follow the marker's #cmt- anchor jump
    e.stopPropagation();
    revealComment(label);
  });

  // Open the column (and tell Swift so it persists the per-window toggle — a
  // later class sync would otherwise tear the column back down), then expand and
  // scroll to the comment. With the column already open, this just activates and
  // scrolls. In a read-only export there is no handler, so the post is skipped.
  function revealComment(label) {
    document.documentElement.classList.add("is-comments-column");
    syncVisible();        // builds the column on an off→on flip
    var handlers = window.webkit && window.webkit.messageHandlers;
    if (handlers && handlers.mudRevealColumn) {
      handlers.mudRevealColumn.postMessage(true);
    }
    if (capsules[label]) {
      activate(label);
      scrollToComment(label);
    }
  }

  // Called by mud.js when the `show-comment-markers` class toggles. With the
  // column open the highlights are already anchored and marker visibility is
  // pure CSS, so there is nothing to do; with it closed, (re)anchor or clear the
  // highlights so the now-shown markers can light their quotation on hover.
  function setMarkersShown() {
    if (enabled()) return;
    project();   // routes to anchorHighlightsOnly() / clearHighlights()
  }

  // -- Reflow ---------------------------------------------------------------

  if (window.ResizeObserver) {
    var ro = new ResizeObserver(scheduleLayout);
    ro.observe(container);
  }
  window.addEventListener("resize", scheduleLayout);

  // The column's inner content width, clamped to its bounds. The single place
  // the width is set: the app pushes a persisted value on load and the drag
  // handle (write side) calls it live; both go through the same clamp. Setting
  // the CSS variable rewraps capsule text, so reflow follows. Returns the value
  // actually applied, which the caller persists.
  var MIN_WIDTH = 200, MAX_WIDTH = 400;

  function setColumnWidth(px) {
    var w = Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, Math.round(px)));
    document.documentElement.style.setProperty(
      "--comment-column-width", w + "px");
    scheduleLayout();
    return w;
  }

  // -- Live updates: rebuild the hidden section, sync body markers ----------

  // The app calls setData on a comment add / reply / edit / delete (no reload).
  // Each entry carries the rendered `<li>` HTML plus, for a just-added comment,
  // the locator that places its body marker byte-exactly. Exports never call it.

  var LEAF_BLOCK_TAGS = {
    P: 1, LI: 1, TD: 1, TH: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1,
    BLOCKQUOTE: 1, PRE: 1, DD: 1, DT: 1, FIGCAPTION: 1, CAPTION: 1, SUMMARY: 1
  };
  var LEAF_BLOCK_SELECTOR =
    "p,li,td,th,h1,h2,h3,h4,h5,h6,blockquote,pre,dd,dt,figcaption,caption,summary";

  function cssEsc(s) { return window.CSS && CSS.escape ? CSS.escape(s) : s; }

  function isInnermostLeaf(el) {
    return el.nodeType === Node.ELEMENT_NODE && LEAF_BLOCK_TAGS[el.tagName] &&
      !el.querySelector(LEAF_BLOCK_SELECTOR);
  }

  function markerFreeText(el) {
    var t = "";
    (function w(n) {
      if (n.nodeType === Node.TEXT_NODE) { t += n.nodeValue; return; }
      if (n.nodeType !== Node.ELEMENT_NODE) return;
      if (n.classList && n.classList.contains("mud-comment-marker")) return;
      for (var c = n.firstChild; c; c = c.nextSibling) w(c);
    })(el);
    return t;
  }

  function hasMarker(label) {
    return !!container.querySelector(
      '.mud-comment-marker[data-mud-label="' + cssEsc(label) + '"]');
  }

  function makeMarker(label) {
    var a = document.createElement("a");
    a.className = "mud-comment-marker";
    a.id = "cmtref-" + label;
    a.setAttribute("data-mud-label", label);
    a.setAttribute("href", "#cmt-" + label);
    a.textContent = "💬";
    return a;
  }

  function findBlockByOccurrence(blockText, occurrence) {
    var target = normalizeWS(blockText).trim(), count = 0, result = null;
    (function w(node) {
      if (result || node.nodeType !== Node.ELEMENT_NODE) return;
      if (node.classList && (node.classList.contains("comments") ||
          node.classList.contains("footnotes"))) return;
      if (isInnermostLeaf(node)) {
        if (normalizeWS(markerFreeText(node)).trim() === target) {
          if (count === occurrence) { result = node; return; }
          count++;
        }
        return;
      }
      for (var c = node.firstChild; c && !result; c = c.nextSibling) w(c);
    })(container);
    return result;
  }

  function blockTextMap(block) {
    var text = "", map = [];
    (function w(n) {
      if (n.nodeType === Node.TEXT_NODE) {
        var v = n.nodeValue;
        for (var i = 0; i < v.length; i++) { text += v[i]; map.push({ node: n, offset: i }); }
        return;
      }
      if (n.nodeType !== Node.ELEMENT_NODE) return;
      if (n.classList && n.classList.contains("mud-comment-marker")) return;
      for (var c = n.firstChild; c; c = c.nextSibling) w(c);
    })(block);
    return { text: text, map: map };
  }

  function insertMarkerExact(label, blockText, offset, occurrence) {
    var block = findBlockByOccurrence(blockText, occurrence);
    if (!block) return false;
    var bm = blockTextMap(block);
    var lead = bm.text.length - bm.text.replace(/^\s+/, "").length;
    var k = offset + lead;
    if (k < 0) k = 0;
    var marker = makeMarker(label);
    try {
      if (k >= bm.map.length) {
        block.appendChild(marker);
      } else {
        var pos = bm.map[k];
        var after = pos.offset > 0 ? pos.node.splitText(pos.offset) : pos.node;
        after.parentNode.insertBefore(marker, after);
      }
    } catch (e) { return false; }
    return true;
  }

  function insertMarkerBySearch(label, quote) {
    var idx = buildIndex(), claimed = {};
    Object.keys(idx.markerAt).forEach(function (l) { claimed[idx.markerAt[l]] = true; });
    var from = 0, pos, end = -1;
    while ((pos = idx.flat.indexOf(quote, from)) !== -1) {
      var e = pos + quote.length;
      if (!claimed[e]) { end = e; break; }
      from = pos + 1;
    }
    if (end < 0) return false;
    var ref = idx.map[end - 1];
    if (!ref) return false;
    var marker = makeMarker(label);
    try {
      var node = ref.node, splitAt = ref.offset + 1;
      if (splitAt < node.nodeValue.length) {
        var after = node.splitText(splitAt);
        after.parentNode.insertBefore(marker, after);
      } else {
        node.parentNode.insertBefore(marker, node.nextSibling);
      }
    } catch (e2) { return false; }
    return true;
  }

  function syncMarkers(list) {
    var labelSet = {};
    list.forEach(function (c) { labelSet[c.label] = true; });
    var markers = container.querySelectorAll(".mud-comment-marker");
    for (var i = 0; i < markers.length; i++) {
      var l = markers[i].getAttribute("data-mud-label");
      if (!labelSet[l] && markers[i].parentNode) {
        markers[i].parentNode.removeChild(markers[i]);
      }
    }
    container.normalize();
    list.forEach(function (c) {
      if (hasMarker(c.label)) return;
      var quote = normalizeWS(c.quotation || "").trim();
      if (!quote) return;
      var placed = false;
      if (c.blockText != null && c.offset != null) {
        placed = insertMarkerExact(c.label, c.blockText, c.offset, c.occurrence || 0);
      }
      if (!placed) insertMarkerBySearch(c.label, quote);
    });
    container.normalize();
  }

  // Replace the hidden section's items with the freshly rendered `<li>`s (the
  // single source the capsules project from), creating or removing the section
  // as the comment count crosses zero.
  function rebuildSection(list) {
    var sec = section();
    if (!list.length) {
      if (sec && sec.parentNode) sec.parentNode.removeChild(sec);
      return;
    }
    if (!sec) {
      sec = document.createElement("section");
      sec.className = "comments is-print-only";
      sec.setAttribute("data-comments", "");
      sec.innerHTML = "<h2>Comments</h2>\n<ol></ol>";
      container.appendChild(sec);
    }
    var ol = sec.querySelector("ol");
    if (ol) ol.innerHTML = list.map(function (c) { return c.html || ""; }).join("");
  }

  function setData(list) {
    list = list || [];
    quotationByLabel = {};
    list.forEach(function (c) { quotationByLabel[c.label] = c.quotation || ""; });
    rebuildSection(list);
    syncMarkers(list);
    project();
  }

  // -- Public API -----------------------------------------------------------

  window.Mud = window.Mud || {};
  var api = {
    // Rebuild capsules from the section (initial load and live updates).
    refresh: project,
    // Geometry-only re-solve (zoom, toggle of an unrelated class, etc.).
    relayout: scheduleLayout,
    // Called by mud.js on every `is-comments-column` `setClass`.
    setVisible: syncVisible,
    // Called by mud.js on every `show-comment-markers` `setClass`.
    setMarkersShown: setMarkersShown,
    activate: activate,
    deactivate: deactivate,
    // Step to the previous (-1) or next (+1) comment, wrapping at the ends.
    navigate: navigate,
    isEnabled: enabled,
    activeLabel: function () { return activeLabel; },
    capsuleFor: function (label) { return capsules[label]; },
    section: section,
    column: ensureColumn,
    layout: layout,
    constants: { GAP: GAP, INACTIVE_H: INACTIVE_H, COMPOSE_H: COMPOSE_H },
    layoutTop: layoutTop,
    preferredPosition: preferredPosition,
    // Two-phase quotation matcher (verbatim, then truncated). The write side
    // reuses it to confirm a candidate truncation re-anchors to the full text.
    matchQuotationStart: matchQuotationStart,
    // Live update from the app: rebuild section + markers + reproject.
    setData: setData,
    // Provisional highlight + marker over the live selection while a new
    // comment is composed (the write side drives these).
    showSelectionDraft: showSelectionDraft,
    clearSelectionDraft: clearSelectionDraft,
    // Live width change (app load + the write side's drag handle). Clamps to
    // 200–400px, sets the CSS variable, reflows, and returns the applied width.
    setColumnWidth: setColumnWidth,
    // Seams the write side fills in (all default to no-op / empty).
    hooks: {
      afterProject: null,     // build the Add button machinery
      decorateActive: null,   // add reply/edit/delete to the active capsule
      undecorateActive: null, // remove them
      extraItems: null,       // [{el, preferred, height}] for the compose form
      ownedNodes: null,       // nodes project() must not remove
      onHide: null            // column closing: cancel an in-progress compose
    }
  };
  window.Mud.comments = api;

  lastVisible = enabled();
  if (lastVisible || markersShown()) project();
})();
