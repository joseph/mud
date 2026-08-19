// Mud - Shared client-side helpers (find, scroll, zoom).
// Exposed on window.Mud; called from Swift via evaluateJavaScript.

(function () {
  "use strict";

  // What Find searches. Up mode is two roots, not one: the bottom Comments
  // section is a `<footer>` beside the article rather than inside it, and its
  // text is still part of the document a reader searches.
  function CONTAINERS() {
    return document.querySelector(".up-mode-output")
        ? ".up-mode-output, footer.comments"
        : ".down-mode-output";
  }
  var MATCH_CLASS = "mud-match";
  var ACTIVE_CLASS = "mud-match-active";

  var marks = [];       // current <mark> elements in DOM order
  var activeIndex = -1; // index of the currently-active match

  // -- Highlight helpers ---------------------------------------------------

  // Walk all text nodes inside the search roots, split at case-insensitive
  // matches, and wrap each match in <mark class="mud-match">.
  function highlightAll(text) {
    clearHighlights();
    if (!text) return;

    var roots = document.querySelectorAll(CONTAINERS());
    if (!roots.length) return;

    var pattern = new RegExp(
      text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
      "gi"
    );

    // Collect text nodes first (mutating the DOM while walking is unsafe).
    // Roots come back in document order, so the marks do too.
    var nodes = [];
    var node;
    for (var r = 0; r < roots.length; r++) {
      var walker = document.createTreeWalker(
        roots[r],
        NodeFilter.SHOW_TEXT,
        null
      );
      while ((node = walker.nextNode())) nodes.push(node);
    }

    for (var i = 0; i < nodes.length; i++) {
      var textNode = nodes[i];
      var value = textNode.nodeValue;
      var match;
      var lastIndex = 0;
      var parts = [];
      pattern.lastIndex = 0;

      while ((match = pattern.exec(value)) !== null) {
        if (match.index > lastIndex) {
          parts.push(document.createTextNode(
            value.slice(lastIndex, match.index)
          ));
        }
        var mark = document.createElement("mark");
        mark.className = MATCH_CLASS;
        mark.textContent = match[0];
        parts.push(mark);
        lastIndex = pattern.lastIndex;
        // Guard against zero-length matches.
        if (match[0].length === 0) pattern.lastIndex++;
      }

      if (parts.length === 0) continue;

      if (lastIndex < value.length) {
        parts.push(document.createTextNode(value.slice(lastIndex)));
      }

      var parent = textNode.parentNode;
      for (var j = 0; j < parts.length; j++) {
        parent.insertBefore(parts[j], textNode);
      }
      parent.removeChild(textNode);
    }

    marks = [];
    for (var k = 0; k < roots.length; k++) {
      marks = marks.concat(Array.prototype.slice.call(
        roots[k].querySelectorAll("mark." + MATCH_CLASS)
      ));
    }
  }

  function activateMatch(n) {
    if (marks.length === 0) return;
    if (activeIndex >= 0 && activeIndex < marks.length) {
      marks[activeIndex].classList.remove(ACTIVE_CLASS);
    }
    activeIndex = ((n % marks.length) + marks.length) % marks.length;
    var el = marks[activeIndex];
    el.classList.add(ACTIVE_CLASS);
    // A match inside a folded section has nothing to scroll to until the
    // section opens. Matches stay counted while folded, so stepping through
    // them with Cmd+G still walks the whole document.
    if (window.Mud.folds) window.Mud.folds.reveal(el);
    el.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  function clearHighlights() {
    for (var i = 0; i < marks.length; i++) {
      var mark = marks[i];
      var parent = mark.parentNode;
      if (!parent) continue;
      parent.replaceChild(document.createTextNode(mark.textContent), mark);
      parent.normalize();
    }
    marks = [];
    activeIndex = -1;
  }

  function result() {
    return { total: marks.length, current: activeIndex + 1 };
  }

  // -- Find API ------------------------------------------------------------

  function findFromTop(text) {
    highlightAll(text);
    if (marks.length > 0) activateMatch(0);
    return result();
  }

  function findRefine(text) {
    // Remember the active match's viewport position so we can pick the
    // nearest match after re-highlighting.
    var refY = null;
    if (activeIndex >= 0 && activeIndex < marks.length) {
      refY = marks[activeIndex].getBoundingClientRect().top;
    }

    highlightAll(text);

    if (marks.length === 0) return result();

    if (refY !== null) {
      // Pick the match closest to the previous active position.
      var best = 0;
      var bestDist = Infinity;
      for (var i = 0; i < marks.length; i++) {
        var d = Math.abs(marks[i].getBoundingClientRect().top - refY);
        if (d < bestDist) { bestDist = d; best = i; }
      }
      activateMatch(best);
    } else {
      activateMatch(0);
    }
    return result();
  }

  function findAdvance(text, direction) {
    // If highlights are stale or absent, rebuild them.
    if (marks.length === 0) {
      highlightAll(text);
      if (marks.length === 0) return result();
      activateMatch(0);
      return result();
    }

    var delta = direction === "backward" ? -1 : 1;
    activateMatch(activeIndex + delta);
    return result();
  }

  function findClear() {
    clearHighlights();
  }

  // -- Scroll --------------------------------------------------------------

  function getScrollY() {
    return window.scrollY;
  }

  function setScrollY(y) {
    window.scrollTo(0, y);
  }

  function getScrollFraction() {
    var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
    if (maxScroll <= 0) return 0;
    return window.scrollY / maxScroll;
  }

  function setScrollFraction(f) {
    var maxScroll = document.documentElement.scrollHeight - window.innerHeight;
    window.scrollTo(0, f * maxScroll);
  }

  // -- Outline navigation ---------------------------------------------------

  function scrollToHeading(slug) {
    var el = document.getElementById(slug);
    if (!el) return;
    // Navigating to a folded heading opens it, and opens whatever it sits in.
    if (window.Mud.folds) window.Mud.folds.revealHeading(slug);
    el.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  function scrollToLine(lineNumber) {
    var lines = document.querySelectorAll(".down-lines .dl");
    var idx = lineNumber - 1;
    if (idx >= 0 && idx < lines.length) {
      lines[idx].scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }

  // -- Body classes ---------------------------------------------------------

  function setClass(name, enabled) {
    if (enabled) {
      document.documentElement.classList.add(name);
    } else {
      document.documentElement.classList.remove(name);
    }
    if (name === "is-auto-expand-changes" && Mud.applyAutoExpandChanges) {
      Mud.applyAutoExpandChanges(enabled);
    }
    if (name === "is-comments-column" && Mud.comments && Mud.comments.setVisible) {
      Mud.comments.setVisible(enabled);
    }
    if (name === "show-comment-markers" && Mud.comments &&
        Mud.comments.setMarkersShown) {
      Mud.comments.setMarkersShown(enabled);
    }
    if (name === "is-foldable-headings" && Mud.folds) {
      Mud.folds.setEnabled(enabled);
    }
  }

  // -- Zoom ----------------------------------------------------------------

  function setZoom(level) {
    document.documentElement.style.zoom = level;
  }

  // -- Popover --------------------------------------------------------------

  // Asks the app for a native popover over `html`, anchored at `rect` — a
  // viewport rect straight from getBoundingClientRect, which is the space
  // WebView.swift's anchorRect converts from. Swift wraps the fragment into a
  // document carrying the window's theme, lighting, and zoom (MudCore's
  // renderPopoverDocument), so callers send a body and nothing more.
  //
  // Returns false where there is no app to ask — an export, Open In Browser,
  // Quick Look — so a caller can fall back to something the page can do on its
  // own. Same check the footnote-marker handler in mud-up.js makes before it
  // falls through to the plain anchor jump.
  //
  // Only Mud's own injected scripts get here: a rendered document is served
  // `script-src 'none'`, so nothing in the Markdown can run and post a message.
  // The fragment is still loaded as HTML — a caller showing text the document
  // supplied has to escape it first.
  var popover = {
    show: function (rect, html) {
      var handlers = window.webkit && window.webkit.messageHandlers;
      if (!handlers || !handlers.mudPopover) return false;
      handlers.mudPopover.postMessage({
        html: html,
        rect: {
          x: rect.left,
          y: rect.top,
          width: rect.width,
          height: rect.height
        }
      });
      return true;
    }
  };

  // -- Geometry ------------------------------------------------------------

  // Shared zoom/position helpers for the app-only overlay and comment-column
  // files (mud-changes.js, mud-comments-edit.js). The document `zoom` on <html>
  // scales the whole layout, so getBoundingClientRect reports zoomed viewport
  // pixels while overlays and capsules position in pre-zoom layout pixels; these
  // convert between the two. (mud-comments.js keeps its own offsetParent-based
  // layoutTop instead of using this — it is inlined into exports without mud.js,
  // so it must stay self-contained.)
  var geometry = {
    // The current document zoom factor (1 when unset).
    zoom: function () {
      return parseFloat(document.documentElement.style.zoom) || 1;
    },
    // A rect's top as an absolute position from the document top, in layout
    // pixels — the same space mud-comments.js's layoutTop returns, via the
    // viewport rect and page scroll (used where an offsetParent walk isn't
    // handy, e.g. a selection range).
    layoutTopFromRect: function (rect) {
      return (rect.top + window.scrollY) / geometry.zoom();
    },
    // A viewport Y coordinate converted to a position relative to a container's
    // scrolled content: subtract the container's viewport top, undo the zoom,
    // then add the container's scrollTop.
    viewportToLayout: function (viewportY, containerRect, scrollTop) {
      return (viewportY - containerRect.top) / geometry.zoom() + scrollTop;
    }
  };

  // -- Public namespace ----------------------------------------------------

  // Merge rather than assign, so the namespace is built the same defensive way
  // in every file and injection order is not a silent requirement. mud.js is
  // still injected first (see WebView.swift), because it seeds the shared
  // helpers the other files call at runtime.
  window.Mud = window.Mud || {};
  Object.assign(window.Mud, {
    findFromTop: findFromTop,
    findRefine: findRefine,
    findAdvance: findAdvance,
    findClear: findClear,
    getScrollY: getScrollY,
    setScrollY: setScrollY,
    getScrollFraction: getScrollFraction,
    setScrollFraction: setScrollFraction,
    setClass: setClass,
    setZoom: setZoom,
    scrollToHeading: scrollToHeading,
    scrollToLine: scrollToLine,
    popover: popover,
    geometry: geometry
  });
})();
