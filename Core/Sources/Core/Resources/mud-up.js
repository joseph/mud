// Mud - Up Mode helpers.
// Auto-detects context via .up-mode-output; no-ops otherwise.

(function () {
  "use strict";
  if (!document.querySelector(".up-mode-output")) return;

  // Route link clicks through the native app.  Anchor links are left
  // to the browser; everything else is resolved to an absolute URL and
  // posted to the mudOpen message handler registered in WebView.swift.
  // The handler check doubles as a guard: in Open in Browser (or any
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
})();
