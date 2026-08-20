// Mud - Comments column (read side, Up mode).
//
// Projects a capsule per comment from the hidden bottom `<footer
// class="comments">` — the single source of comment HTML — positions each
// beside its quotation, and reveals a quotation's highlight on hover. Bundled
// everywhere, exports included; the write side (selection, compose, submit,
// edit, delete) is mud-comments-edit.js and is bundled in the app only.
//
// The column is built only in column mode (`<html class="comments-column">`)
// with the toggle on (`is-comments-column`). It clones already-rendered nodes
// out of the section — never parsing Markdown — and strips their ids.

(function () {
  "use strict";

  var container = document.querySelector(".up-mode-output");
  if (!container) return;

  var GAP = 15;           // minimum vertical gap between rows
  var INACTIVE_H = 45;    // a collapsed capsule's height
  var COMPOSE_H = 100;    // compose form's starting height (it auto-grows; the
                          // write side measures the real height on every relayout)
  var STUB_H = 5;         // a folded section's stub; the height in the CSS,
                          // pinned to it by CommentResourcesTests

  var capsules = {};          // label -> capsule element
  var quotationByLabel = {};  // label -> quotation text (for anchoring)
  var activeLabel = null;
  var rafPending = 0;
  var lastVisible = null;     // last applied visibility (idempotent setVisible)

  // Shared anchoring primitives (mud-comment-anchor.js, concatenated ahead of
  // this file by HTMLTemplate).
  var anchor = window.Mud.commentAnchor;
  var normalizeWS = anchor.normalizeWS;
  var isMarkerElement = anchor.isMarkerElement;

  // The element's top in layout (pre-zoom) pixels. Robust to the document
  // `zoom`, which scales container and capsules together, so capsule `top`
  // values stay in the same space.
  function layoutTop(el) {
    var y = 0;
    while (el && el !== document.body) {
      y += el.offsetTop;
      el = el.offsetParent;
    }
    return y;
  }

  function section() {
    return document.querySelector("footer.comments[data-comments]");
  }

  // In an export the toggle class is force-included, so the test is uniform.
  function enabled() {
    var root = document.documentElement;
    return root.classList.contains("comments-column") &&
      root.classList.contains("is-comments-column");
  }

  function markersShown() {
    return document.documentElement.classList.contains("show-comment-markers");
  }

  // -- Highlight anchoring (off the hidden quote markers) -------------------

  // Whitespace-collapsed flat text of the body with a parallel char →
  // (textNode, offset) map, plus each marker's flat-index anchor.
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
      if (anchor.isBottomSection(node)) return;
      if (node.classList && node.classList.contains("mud-comment-marker")) {
        var label = node.getAttribute("data-mud-label");
        // A repeated label anchors its quotation at the first reference.
        if (!(label in markerAt)) markerAt[label] = flat.length;
        return;
      }
      // The same exclusions the write side built the quotation under: count
      // them here and it would never match again (`rangeSlices`).
      if (isMarkerElement(node) || anchor.isSkippedSubtree(node)) return;
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

  var ELLIPSIS_SPLIT = /\s+(?:…|\.\.\.)\s+/;

  // The flat-text index where `quote` begins, anchored to end just before the
  // marker at `end`, or -1. Two phases (Doc/Guides/spec-comments.md, "Quotation
  // truncation"): verbatim, then — only if that fails and the quotation carries
  // a spaced ellipsis — anchor the last part at the marker and walk left,
  // matching each earlier part to its nearest occurrence before the one already
  // matched. The returned range covers the elided middle too.
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

  // The native text selection collapses the moment the compose box takes focus,
  // so a provisional highlight + 💬 marker is painted over the live selection
  // under this sentinel label. `.mud-comment-draft` keeps it painted rather than
  // hover-toggled until the comment is saved or dismissed. A real `setData`
  // drops the unknown-label marker, so it is swept up either way.
  var DRAFT_LABEL = "mud-draft";

  // One <mark> per slice: surroundContents needs a single-node range. The draft
  // marker after the last one stands where the saved marker will.
  function showSelectionDraft(range) {
    clearSelectionDraft();
    if (!range) return;
    var slices = anchor.rangeSlices(range, container);
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

  // Scoped to the attribution line: a message body is Markdown and may hold a
  // raw <time> of its own.
  function timeElementOf(el) {
    return el.querySelector(".mud-comment-attribution time[datetime]");
  }

  // `iso` is a floating local date-time, which JS reads in the reader's own
  // zone, matching the bare wall clock the source stores.
  function formatTime(iso, text) {
    var t = iso ? Date.parse(iso) : NaN;
    if (isNaN(t)) return text || "";
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

  // A message's own avatar, or the glyph every attribution carried before
  // avatars existed. Mirrors CommentHTMLRenderer.formatAttribution:
  // data-mud-avatar is present only when the source names one. Takes a missing
  // element, since a comment with no messages still draws a collapsed bar.
  function avatarOf(msg) {
    return (msg && msg.getAttribute("data-mud-avatar")) || "💬";
  }

  function buildMessage(src) {
    var m = document.createElement("div");
    m.className = "mud-comment-message";
    var author = src.getAttribute("data-mud-author") || "";
    var avatar = avatarOf(src);
    var srcTime = timeElementOf(src);
    if (author || srcTime || src.hasAttribute("data-mud-avatar")) {
      var attr = document.createElement("div");
      attr.className = "mud-comment-attribution";
      var a = document.createElement("span");
      a.className = "mud-comment-author";
      a.textContent = author ? avatar + " " + author : avatar;
      attr.appendChild(a);
      if (srcTime) {
        var tm = document.createElement("time");
        tm.className = "mud-comment-time";
        // The stamp rides along, so the relative label can be recomputed.
        var iso = srcTime.getAttribute("datetime");
        tm.setAttribute("datetime", iso);
        tm.textContent = formatTime(iso, srcTime.textContent);
        attr.appendChild(tm);
      }
      m.appendChild(attr);
    }
    var body = src.querySelector(".mud-comment-body");
    if (body) m.appendChild(cloneClean(body));
    return m;
  }

  function refreshTimes(cap) {
    var times = cap.querySelectorAll(
      ".mud-comment-attribution time[datetime]");
    for (var i = 0; i < times.length; i++) {
      times[i].textContent = formatTime(
        times[i].getAttribute("datetime"), times[i].textContent);
    }
  }

  function projectCapsule(li) {
    var label = li.getAttribute("data-mud-label");
    var messages = li.querySelectorAll(".mud-comment-message");
    var first = messages[0];

    var cap = document.createElement("div");
    cap.className = "mud-capsule";
    cap.setAttribute("data-mud-label", label);

    // The opening message's avatar, so a thread is known by who started it.
    var bar = document.createElement("div");
    bar.className = "mud-capsule-bar";
    var emoji = document.createElement("span");
    emoji.className = "mud-bar-emoji";
    emoji.textContent = avatarOf(first);
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

    if (messages.length > 1) {
      var rep = document.createElement("div");
      rep.className = "mud-capsule-replies";
      var n = messages.length - 1;
      rep.textContent = n === 1 ? "1 reply" : n + " replies";
      cap.appendChild(rep);
    }

    // Shown only while active; the quotation is highlighted in the document.
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

  // Created once per column; the arrows and count refresh on every project.
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

  // The `mousedown` that stops propagation keeps the document-level mousedown
  // from deactivating the open comment before the click lands, so `navigate`
  // can still step relative to it.
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

  // With the column closed but the markers shown, a marker still needs its
  // quotation highlight on hover.
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

  function project() {
    if (!enabled()) {
      teardownColumn();
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
    // Keep a comment expanded across a reproject (a reply or edit).
    if (wasActive && capsules[wasActive]) {
      activate(wasActive);
    } else {
      layout();
    }
  }

  // -- Placement pass -------------------------------------------------------

  // What a capsule sits beside: its quotation highlight, or — for a quote-less
  // comment — its hidden inline marker, kept measurable by the visually-hidden
  // CSS. A label should have one marker; if the document holds more, the first
  // with a layout box wins, so a hidden duplicate can't capture the anchor.
  // With none laid out the first still stands: a fold hides the only marker
  // legitimately, and foldOver reads it.
  function anchorFor(label) {
    var mark = container.querySelector(
      'mark.mud-comment-highlight[data-mud-label="' + cssEsc(label) + '"]');
    if (mark) return mark;
    var markers = container.querySelectorAll(
      '.mud-comment-marker[data-mud-label="' + cssEsc(label) + '"]');
    for (var i = 0; i < markers.length; i++) {
      if (markers[i].offsetParent !== null) return markers[i];
    }
    return markers[0] || null;
  }

  // -- Folded quotations ----------------------------------------------------

  // Foldable headings are an app feature and an export doesn't load mud-up.js,
  // so this is the one place the column names them: null wherever folding
  // doesn't exist, which is what makes every branch below fall away in an
  // export. A fold answers with `{ key, top }`. Read per call rather than
  // captured, since the two files' load order isn't this one's to assume.
  function foldOver(anchor) {
    var f = window.Mud && window.Mud.folds;
    return f && anchor && anchor.offsetParent === null
      ? f.hiding(anchor) : null;
  }

  // The placement pass passes the fold it has already looked up; omit it and
  // this looks it up itself.
  function preferredPosition(label, fold) {
    var anchor = anchorFor(label);
    if (!anchor) return 0;
    if (fold === undefined) fold = foldOver(anchor);
    return Math.max(0, fold ? fold.top - STUB_H / 2 : layoutTop(anchor));
  }

  function stubTitle(cap, count) {
    if (count > 1) return count + " comments";
    var who = textOf(cap.querySelector(".mud-bar-author"));
    var what = textOf(cap.querySelector(".mud-bar-text"));
    return who ? who + " " + what : what;
  }

  // Pinned, so the height transition has a pixel target to animate to.
  function sizeActive(cap) {
    cap.style.height = "auto";
    var h = cap.offsetHeight;
    cap.style.height = h + "px";
    return h;
  }

  // Each item sits at its preferred position, or is pushed down to clear the
  // row above. Idempotent: re-running recomputes absolute tops, so a row pushed
  // down by a now-shorter neighbor slides back up on the next pass.
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

    // A comment whose anchor a fold took off screen has nothing to sit beside.
    // One stub stands in for the whole group: a sliver on the line the fold
    // reports, which opens it on a click. So resolve each comment's fold once,
    // up front, and group by it — the first comment of a group carries the
    // stub, and the others leave the column until the fold opens.
    var labels = Object.keys(capsules);
    var folds = Object.create(null);    // label -> { key, top } | null
    var carrier = Object.create(null);  // fold key -> label carrying the stub
    var covered = Object.create(null);  // fold key -> comments it stands for
    labels.forEach(function (label) {
      var fold = foldOver(anchorFor(label));
      folds[label] = fold;
      if (!fold) return;
      if (carrier[fold.key] === undefined) carrier[fold.key] = label;
      covered[fold.key] = (covered[fold.key] || 0) + 1;
    });

    // Hiding the open comment's anchor would leave an expanded thread beside a
    // folded heading.
    if (activeLabel && folds[activeLabel]) clearActive();

    labels.forEach(function (label) {
      var cap = capsules[label];
      var height;
      var fold = folds[label];
      var stub = !!fold && carrier[fold.key] === label;
      var anchor = anchorFor(label);
      // Off screen and not carrying a stub: another comment's stub stands for
      // this one, or its anchor is hidden for some reason of its own — and
      // layoutTop would report 0 and pile the capsule at the top of the column.
      // The ResizeObserver below runs this pass when it is back on screen.
      if (!stub && anchor && anchor.offsetParent === null) {
        // This capsule may have carried a stub on the last pass, and the return
        // skips the reset below.
        cap.classList.remove("is-stub");
        cap.title = "";
        cap.style.display = "none";
        return;
      }
      cap.style.display = "";
      cap.classList.toggle("is-stub", stub);
      // Nothing of the capsule reads at 5px, so its tooltip does the talking.
      cap.title = stub ? stubTitle(cap, covered[fold.key]) : "";
      if (stub) {
        cap.style.height = "";
        height = STUB_H;
      } else if (label === activeLabel) {
        height = sizeActive(cap);
      } else {
        cap.style.height = "";
        height = INACTIVE_H;
      }
      items.push({
        el: cap, preferred: preferredPosition(label, fold), height: height,
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

  // Reproject only when column visibility actually flips: a redundant call must
  // not rebuild the column, or it would wipe an open compose box.
  function syncVisible() {
    var on = enabled();
    if (on === lastVisible) return;
    lastVisible = on;
    // Closing the column cancels an in-progress new comment: let the write side
    // tear its compose box and draft down before `project()` removes the column
    // out from under it.
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
      // `activate` reveals a stub's hidden quotation; the scroll is this
      // handler's, since it may be well below the line the stub sat on.
      var wasStub = cap.classList.contains("is-stub");
      activate(label);
      if (wasStub) scrollToComment(label);
    });
  }

  function activate(label) {
    if (activeLabel && activeLabel !== label) deactivate();
    var cap = capsules[label];
    if (!cap) return;
    // Neither the thread nor its highlight can be read while a fold has the
    // quotation off screen, so open the fold here and the callers — a capsule
    // click, the header arrows, the app after a marker click — needn't repeat
    // it.
    var anchor = anchorFor(label);
    if (foldOver(anchor)) window.Mud.folds.reveal(anchor);
    activeLabel = label;
    cap.classList.add("is-active");
    setHighlight(label, true);
    refreshTimes(cap);
    if (api.hooks.decorateActive) api.hooks.decorateActive(cap, label);
    layout();
  }

  // Close the open comment, leaving the column's geometry to the caller. The
  // placement pass calls this one directly, since it lays out afterwards.
  function clearActive() {
    if (!activeLabel) return;
    var cap = capsules[activeLabel];
    if (cap) {
      cap.classList.remove("is-active");
      if (api.hooks.undecorateActive) api.hooks.undecorateActive(cap, activeLabel);
    }
    setHighlight(activeLabel, false);
    activeLabel = null;
  }

  function deactivate() {
    if (!activeLabel) return;
    clearActive();
    layout();
  }

  document.addEventListener("mousedown", function (e) {
    if (!activeLabel) return;
    var cap = capsules[activeLabel];
    if (cap && !cap.contains(e.target)) deactivate();
  });

  // -- Previous / next navigation -------------------------------------------

  // Compared by DOM position rather than measured position: a folded section's
  // comments all measure at the heading that folded them and would tie.
  function orderedLabels() {
    return Object.keys(capsules).sort(function (a, b) {
      var ea = anchorFor(a), eb = anchorFor(b);
      // An anchor-less comment has no place in document order, so it goes at
      // the end. Ranking those by measured position instead would put two
      // orderings in one comparator, leaving the whole sort undefined.
      if (!ea || !eb) return (ea ? 0 : 1) - (eb ? 0 : 1);
      var rel = ea.compareDocumentPosition(eb);
      if (rel & Node.DOCUMENT_POSITION_FOLLOWING) return -1;
      if (rel & Node.DOCUMENT_POSITION_PRECEDING) return 1;
      return 0;
    });
  }

  function scrollToComment(label) {
    var anchor = anchorFor(label);
    if (anchor) anchor.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  // The app calls this when the window can't be made wide enough for the
  // column: below the Compact tier mud-narrow.css hides the column and reveals
  // this section in its place.
  //
  // The section is revealed by the same class the column is, so switch it on
  // here rather than waiting for the app's class sync — otherwise the scroll
  // measures an element that is still `display: none` and goes nowhere.
  function scrollToSection(label) {
    var sec = section();
    if (!sec) return;
    document.documentElement.classList.add("is-comments-column");
    var item = label && sec.querySelector("#cmt-" + cssEsc(label));
    (item || sec).scrollIntoView({ behavior: "smooth", block: "start" });
  }

  // With none open, +1 lands on the first and -1 on the last, like Find.
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

  // The column needs a window wide enough to hold it, so in the app the
  // decision belongs to Swift, which widens the window (or asks about the
  // sidebar) and calls back into `openToComment`. A read-only export has no app
  // to ask and no window to widen, so it decides for itself.
  function revealComment(label) {
    var handlers = window.webkit && window.webkit.messageHandlers;
    if (handlers && handlers.mudRevealColumn) {
      handlers.mudRevealColumn.postMessage(label);
      return;
    }
    if (columnFits()) openToComment(label);
    else scrollToSection(label);
  }

  // Read off the column's own width rather than restating the breakpoint, since
  // below the Compact tier it is `display: none`. Only the export path asks: in
  // the app the window has room by the time `openToComment` is called, and the
  // page's own view of the new width can lag the resize.
  function columnFits() {
    return !!ensureColumn().offsetWidth;
  }

  function openToComment(label) {
    document.documentElement.classList.add("is-comments-column");
    syncVisible();        // builds the column on an off→on flip
    if (capsules[label]) {
      activate(label);
      scrollToComment(label);
    }
  }

  // Called by mud.js when the `show-comment-markers` class toggles. With the
  // column open the highlights are already anchored and marker visibility is
  // pure CSS, so there is nothing to do.
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

  // The single place the column's width is set: the app pushes a persisted
  // value on load and the drag handle (write side) calls it live, both through
  // the same clamp. Setting the variable rewraps capsule text, so reflow
  // follows. Returns the value applied, which the caller persists.
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

  function cssEsc(s) { return window.CSS && CSS.escape ? CSS.escape(s) : s; }

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

  // The shared walk the write side counted against, so a tight-list segment
  // resolves to its own inline run rather than the whole `<li>`.
  function findBlockByOccurrence(blockText, occurrence) {
    var target = normalizeWS(blockText).trim(), count = 0, result = null;
    anchor.eachLogicalBlock(container, function (lb) {
      if (result) return;
      if (normalizeWS(lb.text).trim() === target) {
        if (count === occurrence) { result = lb; return; }
        count++;
      }
    });
    return result;
  }

  // Skips the same elements as markerFreeText, so the char index the write side
  // computed over its marker-free segment text lands on the right node.
  function blockTextMap(lb) {
    var text = "", map = [];
    function w(n) {
      if (n.nodeType === Node.TEXT_NODE) {
        var v = n.nodeValue;
        for (var i = 0; i < v.length; i++) { text += v[i]; map.push({ node: n, offset: i }); }
        return;
      }
      if (n.nodeType !== Node.ELEMENT_NODE || isMarkerElement(n) ||
          anchor.isSkippedSubtree(n)) return;
      for (var c = n.firstChild; c; c = c.nextSibling) w(c);
    }
    var kids = lb.element.childNodes;
    for (var i = lb.childStart; i < lb.childEnd; i++) w(kids[i]);
    return { text: text, map: map };
  }

  function insertMarkerExact(label, blockText, offset, occurrence) {
    var lb = findBlockByOccurrence(blockText, occurrence);
    if (!lb) return false;
    var bm = blockTextMap(lb);
    var lead = bm.text.length - bm.text.replace(/^\s+/, "").length;
    var k = offset + lead;
    if (k < 0) k = 0;
    var marker = makeMarker(label);
    try {
      if (k >= bm.map.length) {
        // Past the segment's mapped text: land just after it — before whatever
        // follows the segment (a nested list, in a tight item), or appended
        // when the segment runs to the element's end.
        lb.element.insertBefore(marker, lb.element.childNodes[lb.childEnd] || null);
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

  // A section created here goes where the renderer puts it: after the article,
  // not inside it.
  function rebuildSection(list) {
    var sec = section();
    if (!list.length) {
      if (sec && sec.parentNode) sec.parentNode.removeChild(sec);
      return;
    }
    if (!sec) {
      sec = document.createElement("footer");
      sec.className = "comments is-print-only";
      sec.setAttribute("data-comments", "");
      sec.innerHTML = "<h2>Comments</h2>\n<ol></ol>";
      container.parentNode.insertBefore(sec, container.nextSibling);
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
    // Open the column to one comment. Called by the app after a marker click,
    // once it has made room for the column (`CommentColumnFit`).
    openToComment: openToComment,
    // Fallback for a window too narrow to fit the column at all: the bottom
    // Comments section, or with a label that comment within it.
    scrollToSection: scrollToSection,
    activeLabel: function () { return activeLabel; },
    capsuleFor: function (label) { return capsules[label]; },
    section: section,
    column: ensureColumn,
    layout: layout,
    constants: { GAP: GAP, INACTIVE_H: INACTIVE_H, COMPOSE_H: COMPOSE_H },
    layoutTop: layoutTop,
    preferredPosition: preferredPosition,
    // Two-phase quotation matcher. The write side reuses it to confirm a
    // candidate truncation re-anchors to the full text.
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
    },
    // Filled in by the write side; Swift calls this through the bridge. Null
    // until that file loads, so this literal lists the whole Swift-callable
    // surface in one place.
    resolveSubmission: null   // the outcome of the submission in flight
  };
  window.Mud.comments = api;

  lastVisible = enabled();
  if (lastVisible || markersShown()) project();
})();
