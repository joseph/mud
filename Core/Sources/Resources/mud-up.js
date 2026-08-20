// Mud - Up Mode helpers.
// Auto-detects context via .up-mode-output; no-ops otherwise.

(function () {
  "use strict";
  if (!document.querySelector(".up-mode-output")) return;

  // Route link clicks through the app. Anchor links are left to the browser.
  // No mudOpen handler means no app to route to (browser / CLI / Quick Look).
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

  // Footnote markers: with the mudFootnote handler present, show a native
  // popover; otherwise fall through to the #fn-N anchor jump. Capture phase, to
  // win before the link router above.
  document.addEventListener("click", function (e) {
    var anchor = e.target.closest("a[data-footnote-ref]");
    if (!anchor) return;

    var handlers = window.webkit && window.webkit.messageHandlers;
    if (!handlers || !handlers.mudFootnote) return;

    e.preventDefault();
    e.stopPropagation();

    // The rect already reflects the CSS `zoom` on documentElement, and the
    // WKWebView's AppKit bounds are zoom-independent, so it maps 1:1 to points.
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

// The slugs of the folded headings are the whole state; every change recomputes
// the page's visibility from that set in one pass, since a sub-section folded
// inside an unfolded one has to stay folded. A reload replaces the document, so
// the app holds the set for the window and replays it through `apply`.

(function () {
  "use strict";

  var article = document.querySelector(".up-mode-output");
  if (!article) return;
  // A footnote popover is its own page, rendered with the same options, and has
  // no sections to fold.
  if (document.documentElement.classList.contains("footnote-popover")) return;

  // HTMLTemplate.mudUpJS substitutes fold-arrow.svg for this placeholder.
  var ARROW_SVG = "__MUD_FOLD_ARROW_SVG__";

  // Prototype-less: a slug is document text, and a heading called "Constructor"
  // would otherwise find `Object.prototype.constructor` and read as folded.
  var folded = Object.create(null);

  function enabled() {
    return document.documentElement.classList.contains("is-foldable-headings");
  }

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

  // Only an article child begins a section: a heading nested in a blockquote or
  // a footnote body has no following siblings to fold.
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

  // One walk down the article's children, carrying the folded headings whose
  // sections are still open, outermost first. A block is hidden when that list
  // isn't empty.
  function refresh() {
    var open = [];
    var children = article.children;
    for (var i = 0; i < children.length; i++) {
      var el = children[i];
      // Change overlays are absolutely positioned siblings, and mud-changes.js
      // already hides one whose blocks have all gone.
      if (el.classList.contains("mud-overlay")) continue;
      var level = headingLevel(el);
      if (!level) {
        setHidden(el, open);
        continue;
      }
      // This heading ends every open section of its own rank or deeper.
      while (open.length && open[open.length - 1].level >= level) open.pop();
      setHidden(el, open);
      var isFolded = level > 1 && folded[el.id] === true;
      el.classList.toggle("is-folded", isFolded);
      labelArrow(el, isFolded);
      if (isFolded) open.push({ level: level, id: el.id });
    }
  }

  // While a block is hidden, `data-fold-host` records the outermost hiding
  // heading — the only one still on screen — which is what `hiding` reads back.
  function setHidden(el, open) {
    if (open.length) {
      el.classList.add("is-fold-hidden");
      el.setAttribute("data-fold-host", open[0].id);
    } else {
      el.classList.remove("is-fold-hidden");
      el.removeAttribute("data-fold-host");
    }
  }

  // The whole set, so the app's copy can't drift from the page's.
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

  // Fold / Unfold Headings. Both replace the set rather than adding to it,
  // which drops any slug that is no longer a heading in this document.
  function foldAll() {
    if (!enabled()) return;
    var headings = article.querySelectorAll(FOLDABLE);
    folded = Object.create(null);
    for (var i = 0; i < headings.length; i++) {
      if (headings[i].id) folded[headings[i].id] = true;
    }
    refresh();
    report();
  }

  function unfoldAll() {
    if (!enabled()) return;
    folded = Object.create(null);
    refresh();
    report();
  }

  // -- Revealing ------------------------------------------------------------

  function blockOf(el) {
    while (el && el.parentElement && el.parentElement !== article) {
      el = el.parentElement;
    }
    return el && el.parentElement === article ? el : null;
  }

  // Open every folded section enclosing `el`. Walking back from its block, each
  // heading that outranks the closest one seen so far encloses it. Returns true
  // if anything opened.
  function reveal(el) {
    if (!enabled()) return false;
    var block = blockOf(el);
    if (!block) return false;
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
    if (!opened) return false;
    refresh();
    report();
    return true;
  }

  function revealHeading(slug) {
    return reveal(document.getElementById(slug));
  }

  // The fold hiding `el`, or null when it is on screen. `key` is an opaque
  // grouping string shared by everything one fold hid; `top` is the bottom of
  // that heading, from the document top in layout (pre-zoom) pixels.
  function hiding(el) {
    if (!enabled()) return null;
    var block = blockOf(el);
    var key = block && block.getAttribute("data-fold-host");
    var heading = key ? document.getElementById(key) : null;
    if (!heading) return null;
    // mud.js converts the rect; `offsetHeight` is already in layout pixels.
    var top = Mud.geometry.layoutTopFromRect(heading.getBoundingClientRect());
    return { key: key, top: top + heading.offsetHeight };
  }

  // -- Clicks ---------------------------------------------------------------

  article.addEventListener("click", function (e) {
    if (!enabled()) return;
    var arrow = e.target.closest(".mud-fold-arrow");
    if (!arrow) return;
    var heading = arrow.parentElement;
    if (!heading || !heading.id || heading.parentElement !== article) return;
    toggle(heading.id);
  });

  // In-page links: WebKit can't scroll to a target inside a folded section, so
  // open the section first and do the scroll here. Comment markers and footnote
  // references have their own handlers.
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
      // The hiding rule is scoped to the root class, so everything is already
      // back on screen. The set stays, so turning it on again restores it.
    }
  }

  // The app replays this window's folds on a freshly loaded page. Nothing is
  // reported back: this set came from the app.
  function apply(slugs) {
    folded = Object.create(null);
    for (var i = 0; i < slugs.length; i++) folded[slugs[i]] = true;
    if (enabled()) refresh();
  }

  window.Mud = window.Mud || {};
  window.Mud.folds = {
    setEnabled: setEnabled,
    apply: apply,
    foldAll: foldAll,
    unfoldAll: unfoldAll,
    reveal: reveal,
    revealHeading: revealHeading,
    hiding: hiding
  };

  if (enabled()) addArrows();
})();
