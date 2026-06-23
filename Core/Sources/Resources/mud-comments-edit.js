// Mud - Comments column (write side, Up mode). App only.
//
// Adds the editing affordances to the read-side column: starting a new comment
// on the current selection (driven from the toolbar, Edit menu, shortcut, or
// context menu), the compose box (new / reply / edit), and the reply / edit /
// delete controls on an active capsule. Each edit is posted to Swift through the
// `mudCommentSubmit` handler; the native side writes the file and reprojects the
// column. Bundled in the app only — exports load just mud-comments.js and so are
// read-only.

(function () {
  "use strict";

  var container = document.querySelector(".up-mode-output");
  if (!container) return;

  var handlers = window.webkit && window.webkit.messageHandlers;
  if (!handlers || !handlers.mudCommentSubmit) return; // read-only context
  if (!window.Mud || !window.Mud.comments) return;

  var col = window.Mud.comments;
  var COMPOSE_H = col.constants.COMPOSE_H;

  // New-comment compose state.
  var draft = null;         // { quotation, locator, position } for the selection
  var composeNew = null;    // the new-comment compose element
  var composePosition = 0;  // its preferred position, in layout pixels
  var pendingResolve = null; // resolver awaiting the native submit ack

  function zoom() {
    return parseFloat(document.documentElement.style.zoom) || 1;
  }

  // The selection's top, in layout pixels — the compose form's preferred
  // position, matching the space the read-side placement pass works in.
  function rangePosition(range) {
    var r = range.getBoundingClientRect();
    return Math.max(0, (r.top + window.scrollY) / zoom());
  }

  function setComposing(on) {
    if (handlers.mudComposing) handlers.mudComposing.postMessage(!!on);
  }

  // Tell the toolbar "Comment" button whether a commentable selection exists.
  // Reported regardless of whether the column is showing, so the button can
  // reveal the column on demand. De-duplicated so a drag posts only on change.
  var lastReportedSelection = null;
  function reportSelection(has) {
    if (has === lastReportedSelection) return;
    lastReportedSelection = has;
    if (handlers.mudSelection) handlers.mudSelection.postMessage(has);
  }

  // Post a submission and remember its resolver. The native side writes the
  // file and calls `resolveCompose` with the outcome: a submission stays
  // "in flight" (its box disabled) until then, so a failed write keeps the box
  // and its text rather than closing on an optimistic assumption of success.
  function submit(payload, onResolve) {
    pendingResolve = onResolve || null;
    handlers.mudCommentSubmit.postMessage(payload);
  }

  // Called from Swift (via WebView) with the submit outcome. True closes the
  // box; false leaves it open for another try.
  col.resolveCompose = function (success) {
    var resolve = pendingResolve;
    pendingResolve = null;
    if (resolve) resolve(!!success);
  };

  // -- Locator (selection end → source byte), ported from the anchor path ----

  var LEAF_BLOCK_TAGS = {
    P: 1, LI: 1, TD: 1, TH: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1,
    BLOCKQUOTE: 1, PRE: 1, DD: 1, DT: 1, FIGCAPTION: 1, CAPTION: 1, SUMMARY: 1
  };
  var LEAF_BLOCK_SELECTOR =
    "p,li,td,th,h1,h2,h3,h4,h5,h6,blockquote,pre,dd,dt,figcaption,caption,summary";

  function normalizeWS(s) { return s.replace(/\s+/g, " "); }

  // -- Quotation truncation -------------------------------------------------

  var TRUNCATE_OVER = 120;  // characters; shorter quotations are stored whole
  var KEEP_WORDS = 6;       // words kept at each end to start
  var WIDEN_STEP = 4;       // words added to each end when a candidate is ambiguous

  // Shorten a long quotation to "head … tail", but only when the shortened form
  // re-anchors to exactly the original text. The read-side matcher, run against
  // the full quotation, must recover the whole of it (start index 0); if a kept
  // part recurs in the elided middle it won't, so widen the kept ends and retry.
  // If no candidate is both unambiguous and shorter, keep the full quotation.
  // See Doc/Plans/2026-05-footnote-comments.md, "Quotation truncation".
  function truncateQuotation(quote) {
    if (quote.length <= TRUNCATE_OVER) return quote;
    if (!col.matchQuotationStart) return quote;
    var words = quote.split(" ");
    for (var keep = KEEP_WORDS; keep * 2 < words.length; keep += WIDEN_STEP) {
      var head = words.slice(0, keep).join(" ");
      var tail = words.slice(words.length - keep).join(" ");
      var candidate = head + " … " + tail;
      if (candidate.length >= quote.length) break; // no saving — keep it whole
      if (col.matchQuotationStart(quote, quote.length, candidate) === 0) {
        return candidate;
      }
    }
    return quote;
  }

  function isMarkerElement(node) {
    return node.nodeType === Node.ELEMENT_NODE && node.classList &&
      (node.classList.contains("mud-comment-marker") ||
       node.classList.contains("footnote-ref"));
  }

  function leafBlock(node) {
    var el = node.nodeType === Node.TEXT_NODE ? node.parentNode : node;
    while (el && el !== container) {
      if (LEAF_BLOCK_TAGS[el.tagName]) return el;
      el = el.parentNode;
    }
    return null;
  }

  function isInnermostLeaf(el) {
    return el.nodeType === Node.ELEMENT_NODE && LEAF_BLOCK_TAGS[el.tagName] &&
      !el.querySelector(LEAF_BLOCK_SELECTOR);
  }

  function markerFreeText(el) {
    var text = "";
    (function walk(n) {
      if (n.nodeType === Node.TEXT_NODE) { text += n.nodeValue; return; }
      if (n.nodeType !== Node.ELEMENT_NODE || isMarkerElement(n)) return;
      for (var c = n.firstChild; c; c = c.nextSibling) walk(c);
    })(el);
    return text;
  }

  function occurrenceOf(block, blockText) {
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
    })(container);
    return count;
  }

  function endLocator(range) {
    var endNode = range.endContainer;
    var endOffset = range.endOffset;
    var block = leafBlock(endNode);
    if (!block) return null;

    var text = "", offset = null;
    (function walk(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        if (node === endNode && offset === null) offset = text.length + endOffset;
        text += node.nodeValue;
        return;
      }
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      if (isMarkerElement(node)) {
        if (offset === null && node.contains(endNode)) offset = text.length;
        return;
      }
      for (var c = node.firstChild; c; c = c.nextSibling) walk(c);
      if (node === endNode && offset === null) offset = text.length;
    })(block);

    if (offset === null) offset = text.length;
    var lead = text.length - text.replace(/^\s+/, "").length;
    if (lead) { text = text.slice(lead); offset = Math.max(0, offset - lead); }
    while (offset > 0 && /\s/.test(text[offset - 1])) offset--;
    return { offset: offset, blockText: text, occurrence: occurrenceOf(block, text) };
  }

  // A selection is commentable when it is non-empty, lives in the body, is not
  // inside a code block or a Mermaid diagram, and resolves to a source byte.
  function commentableDraft() {
    var sel = window.getSelection();
    if (!sel || sel.isCollapsed || sel.rangeCount === 0) return null;
    var range = sel.getRangeAt(0);
    if (!container.contains(range.commonAncestorContainer)) return null;
    var block = leafBlock(range.endContainer);
    if (!block || block.tagName === "PRE") return null;
    // A Mermaid diagram replaces its `<pre>` with a `<div class="mermaid">`;
    // its rendered SVG labels are HTML (a `<p>` in a foreignObject) with no
    // source byte to anchor to, so a selection inside one is not commentable.
    if (block.closest && block.closest(".mermaid")) return null;
    var quotation = normalizeWS(sel.toString()).trim();
    if (!quotation) return null;
    var locator = endLocator(range);
    if (!locator) return null;
    return { quotation: quotation, locator: locator, position: rangePosition(range) };
  }

  // -- Selection reporting --------------------------------------------------

  // The column has no Add Comment button of its own; a comment is started from
  // the toolbar, the Edit menu, the keyboard shortcut, or the context menu. We
  // still watch the selection so those affordances can enable themselves when it
  // is commentable.
  function onSelectionChange() {
    if (composeNew) return; // composing — ignore selection churn
    reportSelection(!!commentableDraft());
  }

  document.addEventListener("selectionchange", onSelectionChange);
  reportSelection(false); // sync initial state (a fresh page has no selection)

  // -- Compose (shared builder) ---------------------------------------------

  function buildCompose(initialText, onDone, onCancel) {
    var box = document.createElement("div");
    box.className = "mud-compose";
    var ta = document.createElement("textarea");
    ta.value = initialText || "";
    var actions = document.createElement("div");
    actions.className = "mud-compose-actions";
    var cancel = document.createElement("button");
    cancel.type = "button";
    cancel.className = "mud-cancel";
    cancel.textContent = "Cancel";
    var done = document.createElement("button");
    done.type = "button";
    done.className = "mud-done";
    done.textContent = "Done";
    var error = document.createElement("div");
    error.className = "mud-compose-error";
    error.style.display = "none";
    actions.appendChild(cancel);
    actions.appendChild(done);
    box.appendChild(ta);
    box.appendChild(error);
    box.appendChild(actions);

    function trimmed() { return ta.value.trim(); }
    function sync() { done.disabled = busy || trimmed().length === 0; }
    function finish() { onDone(trimmed()); }

    // While a submission is in flight, lock the box (its text stays put); a
    // failure unlocks it for another try. Exposed on the element so the submit
    // callbacks below can drive it.
    var busy = false;
    box.setBusy = function (on) {
      busy = !!on;
      ta.disabled = busy;
      cancel.disabled = busy;
      sync();
    };
    box.showError = function (msg) {
      error.textContent = msg || "";
      error.style.display = msg ? "" : "none";
      // With an error showing, dismissing the box discards nothing new — it just
      // drops the held change, refreshing to the version on disk. Say so.
      cancel.textContent = msg ? "Reload" : "Cancel";
      col.relayout();
    };
    box.focusTextarea = function () { ta.focus(); };

    // Grow the textarea to fit its text (CSS clamps it to min/max). The box
    // shrink-wraps, so relayout reflows the capsules below: for a new compose
    // that's the measured offsetHeight; for an inline reply/edit it's the
    // active capsule re-measured.
    function autoGrow() {
      ta.style.height = "auto";
      ta.style.height = ta.scrollHeight + "px";
    }

    ta.addEventListener("input", function () {
      sync();
      autoGrow();
      col.relayout();
    });
    ta.addEventListener("keydown", function (e) {
      if (e.key === "Escape") { e.preventDefault(); onCancel(); return; }
      if (e.key !== "Enter") return;
      // ⌘/⌃-Return always saves. With the "comment-return-saves" preference on,
      // a plain Return saves too and Shift-Return drops to a newline; with it
      // off, a plain Return is an ordinary newline.
      var returnSaves =
        document.documentElement.classList.contains("comment-return-saves");
      var save = e.metaKey || e.ctrlKey || (returnSaves && !e.shiftKey);
      if (!save) return;
      e.preventDefault();
      if (!done.disabled) finish();
    });
    cancel.addEventListener("click", function (e) { e.stopPropagation(); onCancel(); });
    done.addEventListener("click", function (e) {
      e.stopPropagation();
      if (!done.disabled) finish();
    });
    sync();
    setComposing(true);
    // Focus and size after insertion settles (scrollHeight needs the element in
    // the DOM with styles applied; pre-filled edit text sizes the box to fit).
    requestAnimationFrame(function () {
      ta.focus();
      autoGrow();
      col.relayout();
    });
    return box;
  }

  // -- New comment ----------------------------------------------------------

  function openNewCompose() {
    if (!draft) return;
    composePosition = draft.position;
    var pending = draft;
    composeNew = buildCompose("", function (body) {
      composeNew.showError("");
      composeNew.setBusy(true);
      submit({ action: "add", body: body, locator: pending.locator,
               quotation: pending.quotation }, function (success) {
        if (success) { closeNewCompose(); return; }
        // The write couldn't place the marker (native explains why). Keep the
        // box and its text; unlock for another try, or Cancel to refresh.
        composeNew.setBusy(false);
        composeNew.showError("Cannot save: the highlighted text has changed.");
        composeNew.focusTextarea();
      });
    }, function () {
      closeNewCompose();
    });
    col.column().appendChild(composeNew);
    col.layout();
    // We're composing now: disable the Add Comment affordances. Focusing the
    // textarea clears the document selection, but `onSelectionChange` ignores
    // selection churn while composing, so report it explicitly.
    reportSelection(false);
  }

  function closeNewCompose() {
    if (composeNew && composeNew.parentNode) {
      composeNew.parentNode.removeChild(composeNew);
    }
    composeNew = null;
    setComposing(false);
    draft = null;
    col.relayout();
    // Re-evaluate now that compose is closed (the selection is usually gone).
    reportSelection(!!commentableDraft());
  }

  // The "Add Comment" action (toolbar, Edit menu, shortcut, context menu).
  // Capture the selection, reveal the column (native has already persisted the
  // toggle), and open compose — so it works even when the column was hidden.
  function addFromSelection() {
    if (composeNew) return;
    draft = commentableDraft();
    if (!draft) return;
    // Shorten a long quotation now that we're committing to a comment (the
    // marker placement uses the locator, so this only affects the stored text).
    draft.quotation = truncateQuotation(draft.quotation);
    document.documentElement.classList.add("is-comments-column");
    col.setVisible();
    openNewCompose();
  }

  // -- Active capsule: reply / edit / delete --------------------------------

  // Comment-bubble-with-pencil and trash-can icons; see
  // Doc/Plans/2026-06-comments-column-assets/. Filled shapes drawn in
  // currentColor so they pick up the button's color.
  var EDIT_SVG = '<svg viewBox="0 0 64 64" fill="currentColor">' +
    '<path d="M44.6366724,10.536394 L40.5521114,14.6885203 L11.6698684,14.6885203 C6.50868426,14.6885203 4.09335492,17.3246527 4.09335492,22.3643506 L4.09335492,42.1353442 C4.09335492,47.1751303 6.50868426,49.8371983 11.6698684,49.8371983 L14.7716759,49.8371983 C16.1700016,49.8371983 16.678489,50.3797274 16.678489,51.7756002 L16.678489,59.2704405 L24.8144021,51.0519341 C25.7805802,50.0439181 26.5179418,49.8371983 27.9162964,49.8371983 L44.3913673,49.8371983 C49.5271531,49.8371983 51.9423089,47.1751303 51.9423089,42.1353442 L51.9423089,22.3643506 C51.9423089,22.0630338 51.9336306,21.7703034 51.915117,21.4873943 L55.4477416,17.8964107 C55.8417339,19.2143887 56.0358374,20.7104751 56.0358374,22.3643506 L56.0358374,42.1612209 C56.0358374,49.7336914 51.9677651,53.998058 44.3913673,53.998058 L28.0942005,53.998058 L19.2973521,61.9325085 C17.7717454,63.3280873 16.9073343,64 15.636087,64 C13.8818086,64 12.8648339,62.7076341 12.8648339,60.7177728 L12.8648339,53.998058 L11.6444411,53.998058 C4.09335492,53.998058 0,49.7595681 0,42.1612209 L0,22.3643506 C0,14.7660622 4.09335492,10.527543 11.6444411,10.527543 L44.3913673,10.527543 C44.4755463,10.527543 44.559436,10.527543 44.6366724,10.536394 Z"/>' +
    '<path d="M31.9586233,33.2966785 L37.1453214,30.9448372 L59.5189959,8.20151954 L55.9594688,4.60912448 L33.6112505,27.3523833 L31.1451824,32.4436288 C30.9415329,32.882945 31.4755343,33.5033983 31.9586233,33.2966785 Z M61.4256065,6.26317646 L63.3070502,4.29901547 C64.2223158,3.3686002 64.2223158,2.07638128 63.3579625,1.19766066 L62.7478819,0.577383813 C61.9341517,-0.249642176 60.6376218,-0.172100219 59.7984354,0.706620408 L57.8663687,2.61911617 L61.4256065,6.26317646 Z" fill-rule="nonzero"/></svg>';
  var DELETE_SVG = '<svg viewBox="0 0 64 64" fill="currentColor">' +
    '<path d="M24.6662947,52.6944843 C25.6652685,52.6944843 26.322507,52.0556257 26.2962151,51.124285 L25.4812549,22.6502997 C25.454963,21.7189287 24.7977544,21.1068659 23.8513345,21.1068659 C22.8523308,21.1068659 22.1951222,21.7455125 22.2214141,22.6769138 L23.0100824,51.124285 C23.0363743,52.0822701 23.6935829,52.6944843 24.6662947,52.6944843 Z M32.4478694,52.6944843 C33.4468731,52.6944843 34.1566656,52.0556257 34.1566656,51.124285 L34.1566656,22.6769138 C34.1566656,21.7455125 33.4468731,21.1068659 32.4478694,21.1068659 C31.4488956,21.1068659 30.7653651,21.7455125 30.7653651,22.6769138 L30.7653651,51.124285 C30.7653651,52.0556257 31.4488956,52.6944843 32.4478694,52.6944843 Z M40.2558557,52.6944843 C41.2022456,52.6944843 41.8593944,52.0822701 41.8857163,51.124285 L42.6744743,22.6769138 C42.700497,21.7455125 42.0433482,21.1068659 41.0443146,21.1068659 C40.0979246,21.1068659 39.4407759,21.7189287 39.414454,22.6769138 L38.625696,51.124285 C38.5996733,52.0556257 39.2568221,52.6944843 40.2558557,52.6944843 Z M20.9069371,14.1613231 L25.0869357,14.1613231 L25.0869357,8.46652001 C25.0869357,6.9497003 26.1384934,5.96507094 27.7158299,5.96507094 L37.1274447,5.96507094 C38.7046615,5.96507094 39.7563389,6.9497003 39.7563389,8.46652001 L39.7563389,14.1613231 L43.9361281,14.1613231 L43.9361281,8.20040969 C43.9361281,4.34178894 41.465165,2 37.4163867,2 L27.4266486,2 C23.3781395,2 20.9069371,4.34178894 20.9069371,8.20040969 L20.9069371,14.1613231 Z M8.97168561,16.2902359 L55.9502554,16.2902359 C57.0282546,16.2902359 57.895679,15.3588347 57.895679,14.2677794 C57.895679,13.1767241 57.0282546,12.2719369 55.9502554,12.2719369 L8.97168561,12.2719369 C7.92011895,12.2719369 7,13.1767241 7,14.2677794 C7,15.3854487 7.92011895,16.2902359 8.97168561,16.2902359 Z M20.4074502,61.2630608 L44.5146105,61.2630608 C48.2738484,61.2630608 50.7977544,58.788468 50.9817082,54.9828695 L52.8218444,15.7845991 L48.5894114,15.7845991 L46.8279417,54.5305213 C46.7755971,56.1273649 45.6449542,57.2449131 44.0940592,57.2449131 L20.7755073,57.2449131 C19.2770167,57.2449131 18.1465832,56.1007205 18.0677373,54.5305213 L16.2011895,15.7845991 L12.0738047,15.7845991 L13.9403226,55.0095138 C14.1243661,58.8148096 16.5955386,61.2630608 20.4074502,61.2630608 Z" fill-rule="nonzero"/></svg>';

  function decorateActive(cap, label) {
    if (cap.querySelector(".mud-capsule-actions")) return;
    var thread = cap.querySelector(".mud-capsule-thread");
    if (!thread) return;

    // Edit / delete icons go bottom-right inside the last message's box — they
    // act on the last message, the only one that can be edited or deleted.
    var messages = thread.querySelectorAll(".mud-comment-message");
    var last = messages[messages.length - 1];
    if (last && !last.querySelector(".mud-message-actions")) {
      var msgActions = document.createElement("div");
      msgActions.className = "mud-message-actions";

      var edit = document.createElement("button");
      edit.type = "button";
      edit.className = "mud-icon-button mud-edit";
      edit.title = "Edit";
      edit.innerHTML = EDIT_SVG;
      edit.addEventListener("click", function (e) {
        e.stopPropagation();
        openInlineCompose(cap, label, "edit", lastMessageText(label));
      });
      msgActions.appendChild(edit);

      var del = document.createElement("button");
      del.type = "button";
      del.className = "mud-icon-button mud-delete";
      del.title = "Delete";
      del.innerHTML = DELETE_SVG;
      del.addEventListener("click", function (e) {
        e.stopPropagation();
        removeComment(cap, label);
      });
      msgActions.appendChild(del);

      last.appendChild(msgActions);
    }

    // Reply on its own control row below the thread.
    var actions = document.createElement("div");
    actions.className = "mud-capsule-actions";
    var reply = document.createElement("button");
    reply.type = "button";
    reply.className = "mud-reply";
    reply.textContent = "Reply";
    reply.addEventListener("click", function (e) {
      e.stopPropagation();
      openInlineCompose(cap, label, "reply", "");
    });
    actions.appendChild(reply);
    thread.appendChild(actions);
  }

  function undecorateActive(cap) {
    var actions = cap.querySelector(".mud-capsule-actions");
    if (actions) actions.parentNode.removeChild(actions);
    var msgActions = cap.querySelector(".mud-message-actions");
    if (msgActions) msgActions.parentNode.removeChild(msgActions);
    var inline = cap.querySelector(".mud-compose");
    if (inline) inline.parentNode.removeChild(inline);
    // A mid-edit teardown (clicking away, or switching capsules) bypasses the
    // compose box's own teardownInline, which is what restores the message the
    // edit hid. Un-hide it here so it isn't left invisible on the next activate.
    var msgs = cap.querySelectorAll(".mud-capsule-thread .mud-comment-message");
    for (var i = 0; i < msgs.length; i++) {
      if (msgs[i].style.display === "none") msgs[i].style.display = "";
    }
    setComposing(false);
  }

  // The last message's raw Markdown body, read from the hidden section (for
  // Edit). MudCore stashes the original source on the message div as
  // data-mud-body; the rendered .mud-comment-body would be lossy (it has the
  // markdown syntax stripped), so the textarea must use the raw attribute.
  function lastMessageText(label) {
    var sec = col.section();
    if (!sec) return "";
    var safe = window.CSS && CSS.escape ? CSS.escape(label) : label;
    var li = sec.querySelector('li[data-mud-label="' + safe + '"]');
    if (!li) return "";
    var msgs = li.querySelectorAll(".mud-comment-message");
    var last = msgs[msgs.length - 1];
    return last ? (last.getAttribute("data-mud-body") || "") : "";
  }

  // Reply / edit: a compose form on its own row below the thread. The capsule
  // grows; the read-side placement pass re-measures it on layout. While
  // composing, hide the Reply row and the last message's edit/delete icons (a
  // reply means that message is no longer the last one).
  function openInlineCompose(cap, label, action, initial) {
    var thread = cap.querySelector(".mud-capsule-thread");
    if (!thread) return;
    var actions = thread.querySelector(".mud-capsule-actions");
    if (actions) actions.style.display = "none";
    var msgActions = cap.querySelector(".mud-message-actions");
    if (msgActions) msgActions.style.display = "none";

    // Edit replaces the last message in place: hide its box so the compose form
    // stands in for it. (Reply leaves every message showing.)
    var editedMsg = null;
    if (action === "edit") {
      var msgs = thread.querySelectorAll(".mud-comment-message");
      editedMsg = msgs[msgs.length - 1];
      if (editedMsg) editedMsg.style.display = "none";
    }

    var box = buildCompose(initial, function (body) {
      box.showError("");
      box.setBusy(true);
      submit({ action: action, label: label, body: body }, function (success) {
        // Native reprojects on the write echo; just restore controls meanwhile.
        if (success) { teardownInline(); return; }
        box.setBusy(false);
        box.showError("Cannot save: the thread has been changed.");
        box.focusTextarea();
      });
    }, function () {
      teardownInline();
    });
    box.classList.add("mud-compose-inline");

    function teardownInline() {
      if (box.parentNode) box.parentNode.removeChild(box);
      if (actions) actions.style.display = "";
      if (msgActions) msgActions.style.display = "";
      if (editedMsg) editedMsg.style.display = "";
      setComposing(false);
      col.layout();
    }

    thread.appendChild(box);
    col.layout();
  }

  // Messages in the `label` thread, from the hidden section.
  function messageCount(label) {
    var sec = col.section();
    if (!sec) return 0;
    var safe = window.CSS && CSS.escape ? CSS.escape(label) : label;
    var li = sec.querySelector('li[data-mud-label="' + safe + '"]');
    return li ? li.querySelectorAll(".mud-comment-message").length : 0;
  }

  // Delete the last message in a puff. In a multi-message thread only that
  // message box puffs and the capsule reprojects with one fewer message; the
  // last remaining message puffs the whole comment away with it.
  function removeComment(cap, label) {
    var multi = messageCount(label) > 1;
    var target = cap;
    if (multi) {
      var msgs = cap.querySelectorAll(".mud-capsule-thread .mud-comment-message");
      target = msgs[msgs.length - 1] || cap;
    }
    target.classList.add("is-removing");
    var fired = false;
    function go() {
      if (fired) return;
      fired = true;
      submit({ action: "delete", label: label });
      if (!multi) col.deactivate();
    }
    target.addEventListener("animationend", go);
    setTimeout(go, 350); // fallback if the animation event is missed
  }

  // -- Wire the read-side seams --------------------------------------------

  col.addFromSelection = addFromSelection;
  col.hooks.decorateActive = decorateActive;
  col.hooks.undecorateActive = undecorateActive;
  col.hooks.extraItems = function () {
    if (composeNew) {
      // The box auto-grows with its text; measure it so capsules below reflow.
      // COMPOSE_H is the fallback before the box has been laid out.
      var h = composeNew.offsetHeight || COMPOSE_H;
      return [{ el: composeNew, preferred: composePosition, height: h }];
    }
    return [];
  };
  col.hooks.ownedNodes = function () {
    return composeNew ? [composeNew] : [];
  };
})();
