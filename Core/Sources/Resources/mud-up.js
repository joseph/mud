// Mud - Up Mode helpers.
// Auto-detects context via .up-mode-output; no-ops otherwise.

(function () {
  "use strict";
  if (!document.querySelector(".up-mode-output")) return;

  // Route link clicks through the native app.  Anchor links are left
  // to the browser; everything else is resolved to an absolute URL and
  // posted to the mudOpen message handler registered in WebView.swift.
  // The handler check doubles as a guard: in Open In Browser (or any
  // non-Mud context) window.webkit doesn't exist, so we return early
  // and let the browser handle links normally.
  document.addEventListener("click", function (e) {
    var anchor = e.target.closest("a");
    if (!anchor) return;

    var href = anchor.getAttribute("href");
    if (!href || href.startsWith("#")) return;

    var handlers = window.webkit && window.webkit.messageHandlers;
    if (!handlers || !handlers.mudOpen) return;

    e.preventDefault();
    var resolved = new URL(href, document.baseURI).href;
    handlers.mudOpen.postMessage(resolved);
  });

  // Footnote markers: when the mudFootnote handler is present (the live app),
  // intercept the click and show a native popover anchored at the marker.
  // Otherwise (browser / CLI / Quick Look) fall through to the native #fn-N
  // anchor jump to the visible footnotes section. Capture phase so we win
  // before the link-routing listener above.
  document.addEventListener("click", function (e) {
    var anchor = e.target.closest("a[data-footnote-ref]");
    if (!anchor) return;

    var handlers = window.webkit && window.webkit.messageHandlers;
    if (!handlers || !handlers.mudFootnote) return;

    e.preventDefault();
    e.stopPropagation();

    // `getBoundingClientRect()` already reflects the CSS `zoom` on
    // `documentElement`, returning viewport coordinates in the visual (zoomed)
    // space. The WKWebView's AppKit bounds are the viewport in points and are
    // zoom-independent, so these values map 1:1 to AppKit points — no scaling.
    var r = anchor.getBoundingClientRect();
    handlers.mudFootnote.postMessage({
      label: anchor.getAttribute("data-fn-label"),
      num: anchor.getAttribute("data-fn-num"),
      rect: {
        x: r.left,
        y: r.top,
        width: r.width,
        height: r.height,
      },
    });
  }, true);
})();

// -- Foldable headings -------------------------------------------------------

// With the "Foldable headings" setting on (the `is-foldable-headings` root
// class), every h2-and-deeper heading gets an arrow button at its right edge,
// and clicking that button folds the heading's section away: the blocks that
// follow it, up to the next heading of the same or higher rank, sub-sections
// included.
//
// The slugs of the folded headings are the whole state. Every change recomputes
// the page's visibility from that set in one pass, because "unfold this
// section" is not "show these blocks" — a sub-section folded inside it has to
// stay folded.
//
// A reload replaces the document, so the app holds the set for the window
// (WebView.Coordinator) and replays it through `apply` on the new page.

(function () {
  "use strict";

  var article = document.querySelector(".up-mode-output");
  if (!article) return;
  // A footnote popover is its own page, rendered with the document's options —
  // this class included. Nothing in a popover is a section to fold.
  if (document.documentElement.classList.contains("footnote-popover")) return;

  // The arrow, drawn pointing down (the open state). HTMLTemplate.mudUpJS
  // substitutes the contents of fold-arrow.svg for this placeholder, so the
  // shape is drawn in one file rather than restated here.
  var ARROW_SVG = "__MUD_FOLD_ARROW_SVG__";

  // The folded headings, one `slug: true` entry each. Prototype-less, because
  // a slug is document text: a heading called "Constructor" would otherwise
  // find `Object.prototype.constructor` and read as already folded.
  var folded = Object.create(null);

  function enabled() {
    return document.documentElement.classList.contains("is-foldable-headings");
  }

  // 2–6 for a foldable heading, 1 for an h1 (the document title, not a section
  // anyone folds), 0 for everything else.
  function headingLevel(el) {
    var tag = el.tagName;
    if (!tag || tag.length !== 2 || tag.charAt(0) !== "H") return 0;
    var level = +tag.charAt(1);
    return level >= 1 && level <= 6 ? level : 0;
  }

  // -- Arrows ---------------------------------------------------------------

  function arrowIn(heading) {
    return heading.querySelector(".mud-fold-arrow");
  }

  // Only a heading that is the article's own child begins a section: one
  // nested in a blockquote, a list item, or a footnote body has no following
  // siblings to fold, so it gets no arrow either.
  var FOLDABLE = ":scope > h2, :scope > h3, :scope > h4, :scope > h5," +
    " :scope > h6";

  function addArrows() {
    var headings = article.querySelectorAll(FOLDABLE);
    for (var i = 0; i < headings.length; i++) {
      if (arrowIn(headings[i])) continue;
      var button = document.createElement("button");
      button.type = "button";
      button.className = "mud-fold-arrow";
      button.innerHTML = ARROW_SVG;
      headings[i].appendChild(button);
    }
  }

  function removeArrows() {
    var arrows = article.querySelectorAll(".mud-fold-arrow");
    for (var i = 0; i < arrows.length; i++) {
      arrows[i].parentNode.removeChild(arrows[i]);
    }
  }

  function labelArrow(heading, isFolded) {
    var arrow = arrowIn(heading);
    if (!arrow) return;
    arrow.setAttribute("aria-expanded", isFolded ? "false" : "true");
    arrow.setAttribute(
      "aria-label", isFolded ? "Unfold section" : "Fold section");
  }

  // -- The visibility pass --------------------------------------------------

  // Recompute what is on screen from the folded set: one walk down the
  // article's children carrying the ranks of the folded headings whose sections
  // are still open. A block is hidden when that list isn't empty.
  function refresh() {
    var open = [];
    var children = article.children;
    for (var i = 0; i < children.length; i++) {
      var el = children[i];
      // Change overlays are absolutely positioned siblings rather than part of
      // the flow, and mud-changes.js already hides one whose blocks have all
      // gone. Leave them to it.
      if (el.classList.contains("mud-overlay")) continue;
      var level = headingLevel(el);
      if (!level) {
        setHidden(el, open.length > 0);
        continue;
      }
      // This heading ends every open section of its own rank or deeper.
      while (open.length && open[open.length - 1] >= level) open.pop();
      setHidden(el, open.length > 0);
      var isFolded = level > 1 && folded[el.id] === true;
      el.classList.toggle("is-folded", isFolded);
      labelArrow(el, isFolded);
      if (isFolded) open.push(level);
    }
  }

  function setHidden(el, hidden) {
    el.classList.toggle("is-fold-hidden", hidden);
  }

  // Tell the app the whole set rather than the one heading that changed, so its
  // copy — the one that survives the next reload — can't drift from the page's.
  function report() {
    var handlers = window.webkit && window.webkit.messageHandlers;
    if (!handlers || !handlers.mudFolds) return;
    handlers.mudFolds.postMessage(Object.keys(folded));
  }

  function toggle(slug) {
    if (folded[slug]) {
      delete folded[slug];
    } else {
      folded[slug] = true;
    }
    refresh();
    report();
  }

  // -- Revealing ------------------------------------------------------------

  // The article child holding `el` (`el` itself when it is one), or null when
  // `el` is outside the article — the bottom Comments section, say.
  function blockOf(el) {
    while (el && el.parentElement && el.parentElement !== article) {
      el = el.parentElement;
    }
    return el && el.parentElement === article ? el : null;
  }

  // Open every folded section enclosing `el` — and `el` itself when it is a
  // folded heading — so a navigation can land on it. Walking back from its
  // block, each heading that outranks the closest one seen so far is a section
  // `el` sits in; the ones in between are sections that have already ended.
  function reveal(el) {
    var block = blockOf(el);
    if (!block) return;
    var rank = 7;
    var opened = false;
    for (var node = block; node; node = node.previousElementSibling) {
      var level = headingLevel(node);
      if (!level || level >= rank) continue;
      rank = level;
      if (folded[node.id]) {
        delete folded[node.id];
        opened = true;
      }
      if (level === 1) break;   // nothing encloses an h1
    }
    if (!opened) return;
    refresh();
    report();
  }

  function revealHeading(slug) {
    reveal(document.getElementById(slug));
  }

  // -- Clicks ---------------------------------------------------------------

  // A click on the arrow folds or unfolds its section.
  article.addEventListener("click", function (e) {
    if (!enabled()) return;
    var arrow = e.target.closest(".mud-fold-arrow");
    if (!arrow) return;
    var heading = arrow.parentElement;
    if (!heading || !heading.id || heading.parentElement !== article) return;
    toggle(heading.id);
  });

  // In-page links, which the link router above leaves to the page: WebKit can't
  // scroll to a target inside a folded section, so open the section first and
  // do the scroll here. Comment markers and footnote references have their own
  // handlers and are left alone.
  article.addEventListener("click", function (e) {
    if (!enabled()) return;
    var link = e.target.closest('a[href^="#"]');
    if (!link) return;
    if (link.classList.contains("mud-comment-marker") ||
        link.hasAttribute("data-footnote-ref")) return;
    var id = decodeURIComponent(link.getAttribute("href").slice(1));
    var target = id ? document.getElementById(id) : null;
    if (!target) return;
    e.preventDefault();
    reveal(target);
    target.scrollIntoView({ behavior: "smooth", block: "start" });
  });

  // -- Public namespace -----------------------------------------------------

  function setEnabled(on) {
    if (on) {
      addArrows();
      refresh();
    } else {
      removeArrows();
      // The hiding rule is scoped to the root class, so everything is back on
      // screen already. The set stays, so turning the setting on again restores
      // the same folds.
    }
  }

  // The app replays this window's folds on a freshly loaded page. Nothing is
  // reported back: this set came from the app in the first place.
  function apply(slugs) {
    folded = Object.create(null);
    for (var i = 0; i < slugs.length; i++) folded[slugs[i]] = true;
    if (enabled()) refresh();
  }

  window.Mud = window.Mud || {};
  window.Mud.folds = {
    setEnabled: setEnabled,
    apply: apply,
    reveal: reveal,
    revealHeading: revealHeading
  };

  if (enabled()) addArrows();
})();
