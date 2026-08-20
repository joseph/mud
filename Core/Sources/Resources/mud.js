// Mud - Shared client-side helpers (find, scroll, zoom).
// Exposed on window.Mud; called from Swift via evaluateJavaScript.

(function () {
  "use strict";

  // Up mode is two roots: the bottom Comments section is a `<footer>` beside
  // the article rather than inside it, and a reader searches its text too.
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

  function highlightAll(text) {
    clearHighlights();
    if (!text) return;

    var roots = document.querySelectorAll(CONTAINERS());
    if (!roots.length) return;

    var pattern = new RegExp(
      text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"),
      "gi"
    );

    // Collected first: mutating the DOM while walking is unsafe. Roots come
    // back in document order, so the marks do too.
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
    // A folded match has nothing to scroll to until its section opens. Matches
    // stay counted while folded, so Cmd+G still walks the whole document.
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
    var refY = null;
    if (activeIndex >= 0 && activeIndex < marks.length) {
      refY = marks[activeIndex].getBoundingClientRect().top;
    }

    highlightAll(text);

    if (marks.length === 0) return result();

    if (refY !== null) {
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
    if (marks.length === 0) {   // stale or absent — rebuild
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

  // A native popover over `html`, anchored at `rect` (a viewport rect straight
  // from getBoundingClientRect). Swift wraps the fragment in a document carrying
  // the window's theme, lighting and zoom, so callers send a body and no more.
  // False where there is no app to ask, so the caller can fall back.
  //
  // The fragment is loaded as HTML: a caller showing text the document supplied
  // has to escape it first.
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

  // The document `zoom` on <html> scales the whole layout, so
  // getBoundingClientRect reports zoomed viewport pixels while overlays and
  // capsules position in pre-zoom layout pixels; these convert between the two.
  // (mud-comments.js keeps its own layoutTop — it is inlined into exports
  // without mud.js, so it has to stay self-contained.)
  var geometry = {
    zoom: function () {
      return parseFloat(document.documentElement.style.zoom) || 1;
    },
    // The same space mud-comments.js's layoutTop returns, for where an
    // offsetParent walk isn't handy — a selection range, say.
    layoutTopFromRect: function (rect) {
      return (rect.top + window.scrollY) / geometry.zoom();
    },
    viewportToLayout: function (viewportY, containerRect, scrollTop) {
      return (viewportY - containerRect.top) / geometry.zoom() + scrollTop;
    }
  };

  // -- Public namespace ----------------------------------------------------

  // Merged rather than assigned, so injection order is not a silent
  // requirement. mud.js is still injected first: it seeds the shared helpers.
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
