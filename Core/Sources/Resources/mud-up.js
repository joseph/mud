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

    var zoom = parseFloat(document.documentElement.style.zoom) || 1;
    var r = anchor.getBoundingClientRect();
    handlers.mudFootnote.postMessage({
      label: anchor.getAttribute("data-fn-label"),
      num: anchor.getAttribute("data-fn-num"),
      rect: {
        x: r.left / zoom,
        y: r.top / zoom,
        width: r.width / zoom,
        height: r.height / zoom,
      },
    });
  }, true);
})();
