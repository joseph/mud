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
  var PITCH = col.constants.PITCH;

  // New-comment compose state.
  var draft = null;         // { quotation, locator, slot } for the current selection
  var composeNew = null;    // the new-comment compose element (4 slots)
  var composeSlot = 0;

  function zoom() {
    return parseFloat(document.documentElement.style.zoom) || 1;
  }

  function rangeSlot(range) {
    var r = range.getBoundingClientRect();
    var top = (r.top + window.scrollY) / zoom();
    return Math.max(0, Math.round(top / PITCH));
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

  function submit(payload) {
    handlers.mudCommentSubmit.postMessage(payload);
  }

  // -- Locator (selection end → source byte), ported from the anchor path ----

  var LEAF_BLOCK_TAGS = {
    P: 1, LI: 1, TD: 1, TH: 1, H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1,
    BLOCKQUOTE: 1, PRE: 1, DD: 1, DT: 1, FIGCAPTION: 1, CAPTION: 1, SUMMARY: 1
  };
  var LEAF_BLOCK_SELECTOR =
    "p,li,td,th,h1,h2,h3,h4,h5,h6,blockquote,pre,dd,dt,figcaption,caption,summary";

  function normalizeWS(s) { return s.replace(/\s+/g, " "); }

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
  // inside a code block, and resolves to a source byte. (The precise predicate
  // is still being settled; this is the working cut.)
  function commentableDraft() {
    var sel = window.getSelection();
    if (!sel || sel.isCollapsed || sel.rangeCount === 0) return null;
    var range = sel.getRangeAt(0);
    if (!container.contains(range.commonAncestorContainer)) return null;
    var block = leafBlock(range.endContainer);
    if (!block || block.tagName === "PRE") return null;
    var quotation = normalizeWS(sel.toString()).trim();
    if (!quotation) return null;
    var locator = endLocator(range);
    if (!locator) return null;
    return { quotation: quotation, locator: locator, slot: rangeSlot(range) };
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
    actions.appendChild(cancel);
    actions.appendChild(done);
    box.appendChild(ta);
    box.appendChild(actions);

    function trimmed() { return ta.value.trim(); }
    function sync() { done.disabled = trimmed().length === 0; }
    function finish() { onDone(trimmed()); }

    ta.addEventListener("input", sync);
    ta.addEventListener("keydown", function (e) {
      if (e.key === "Escape") { e.preventDefault(); onCancel(); }
      else if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
        e.preventDefault();
        if (!done.disabled) finish();
      }
    });
    cancel.addEventListener("click", function (e) { e.stopPropagation(); onCancel(); });
    done.addEventListener("click", function (e) {
      e.stopPropagation();
      if (!done.disabled) finish();
    });
    sync();
    setComposing(true);
    // Focus after insertion settles.
    requestAnimationFrame(function () { ta.focus(); });
    return box;
  }

  // -- New comment ----------------------------------------------------------

  function openNewCompose() {
    if (!draft) return;
    composeSlot = draft.slot;
    var pending = draft;
    composeNew = buildCompose("", function (body) {
      submit({ action: "add", body: body, locator: pending.locator,
               quotation: pending.quotation });
      closeNewCompose();
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
    document.documentElement.classList.add("is-comments-column");
    col.setVisible();
    openNewCompose();
  }

  // -- Active capsule: reply / edit / delete --------------------------------

  var EDIT_SVG = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" ' +
    'stroke-width="1.4"><path d="M2 11.5V14h2.5l7-7L9 4.5l-7 7z"/>' +
    '<path d="M10 3.5L12.5 6"/></svg>';
  var DELETE_SVG = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" ' +
    'stroke-width="1.4"><path d="M3 4.5h10M6.5 4V2.5h3V4M5 4.5l.6 8h4.8l.6-8"/></svg>';

  function decorateActive(cap, label) {
    if (cap.querySelector(".mud-capsule-actions")) return;
    var thread = cap.querySelector(".mud-capsule-thread");
    if (!thread) return;

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

    var edit = document.createElement("button");
    edit.type = "button";
    edit.className = "mud-icon-button mud-edit";
    edit.title = "Edit";
    edit.innerHTML = EDIT_SVG;
    edit.addEventListener("click", function (e) {
      e.stopPropagation();
      openInlineCompose(cap, label, "edit", lastMessageText(label));
    });
    actions.appendChild(edit);

    var del = document.createElement("button");
    del.type = "button";
    del.className = "mud-icon-button mud-delete";
    del.title = "Delete";
    del.innerHTML = DELETE_SVG;
    del.addEventListener("click", function (e) {
      e.stopPropagation();
      removeComment(cap, label);
    });
    actions.appendChild(del);

    thread.appendChild(actions);
  }

  function undecorateActive(cap) {
    var actions = cap.querySelector(".mud-capsule-actions");
    if (actions) actions.parentNode.removeChild(actions);
    var inline = cap.querySelector(".mud-compose");
    if (inline) inline.parentNode.removeChild(inline);
    setComposing(false);
  }

  // The last message's body text, read from the hidden section (for Edit).
  function lastMessageText(label) {
    var sec = col.section();
    if (!sec) return "";
    var safe = window.CSS && CSS.escape ? CSS.escape(label) : label;
    var li = sec.querySelector('li[data-mud-label="' + safe + '"]');
    if (!li) return "";
    var msgs = li.querySelectorAll(".mud-comment-message .mud-comment-body");
    var last = msgs[msgs.length - 1];
    return last ? last.textContent.trim() : "";
  }

  // Reply / edit: a compose form inside the active capsule. The capsule grows;
  // the read-side solver re-measures it on layout.
  function openInlineCompose(cap, label, action, initial) {
    var thread = cap.querySelector(".mud-capsule-thread");
    if (!thread) return;
    var actions = thread.querySelector(".mud-capsule-actions");
    if (actions) actions.style.display = "none";

    var box = buildCompose(initial, function (body) {
      submit({ action: action, label: label, body: body });
      // Native reprojects on the write echo; just restore controls meanwhile.
      teardownInline();
    }, function () {
      teardownInline();
    });
    box.classList.add("mud-compose-inline");

    function teardownInline() {
      if (box.parentNode) box.parentNode.removeChild(box);
      if (actions) actions.style.display = "";
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

  // Delete the last message. A multi-message thread keeps its capsule and just
  // reprojects with one fewer message; the last remaining message takes the
  // whole comment with it, in a puff.
  function removeComment(cap, label) {
    if (messageCount(label) > 1) {
      submit({ action: "delete", label: label });
      return;
    }
    cap.classList.add("is-removing");
    var fired = false;
    function go() {
      if (fired) return;
      fired = true;
      submit({ action: "delete", label: label });
      col.deactivate();
    }
    cap.addEventListener("animationend", go);
    setTimeout(go, 350); // fallback if the animation event is missed
  }

  // -- Wire the read-side seams --------------------------------------------

  col.addFromSelection = addFromSelection;
  col.hooks.decorateActive = decorateActive;
  col.hooks.undecorateActive = undecorateActive;
  col.hooks.extraItems = function () {
    if (composeNew) return [{ el: composeNew, preferred: composeSlot, slots: 4 }];
    return [];
  };
  col.hooks.ownedNodes = function () {
    return composeNew ? [composeNew] : [];
  };
})();
