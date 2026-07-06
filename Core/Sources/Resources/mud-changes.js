// Mud - Change tracking: overlays, expand/collapse, navigation.
// Extends window.Mud; called from Swift via evaluateJavaScript.
// Injected only in WKWebView (not in HTML exports).

(function () {
  "use strict";

  // -- Overlays ---------------------------------------------------------------

  var _overlays = {};       // groupID → overlay element
  var _expandedGroups = {}; // groupID → true when expanded
  var _groupTypes = {};     // groupID → "ins" | "del" | "mix"

  // Sub-overlays: temporary red/green overlays created when a mixed
  // (blue) group is expanded. Each entry: { overlay, els, groupId }.
  var _subOverlays = [];
  // Group IDs whose original overlay is suppressed (replaced by sub-overlays).
  var _suppressedGroups = {};

  function buildOverlays() {
    var container = document.querySelector(".up-mode-output");
    if (!container) return;

    // Remove any existing overlays.
    var old = container.querySelectorAll(".mud-overlay");
    for (var i = 0; i < old.length; i++) old[i].remove();
    _overlays = {};
    _expandedGroups = {};
    _groupTypes = {};
    _subOverlays = [];
    _suppressedGroups = {};

    // Discover groups from data-group-id attributes. The group's type
    // (ins | del | mix) is computed in Swift and carried on each member
    // as data-group-type, so members hidden from the DOM (e.g. a
    // suppressed deletion) still count toward the type.
    var els = container.querySelectorAll("[data-group-id]");
    var groups = {};  // groupID → { index, type }
    for (var j = 0; j < els.length; j++) {
      var gid = els[j].dataset.groupId;
      if (!groups[gid]) {
        groups[gid] = { index: "", type: "" };
      }
      if (!groups[gid].index && els[j].dataset.groupIndex) {
        groups[gid].index = els[j].dataset.groupIndex;
      }
      if (!groups[gid].type && els[j].dataset.groupType) {
        groups[gid].type = els[j].dataset.groupType;
      }
    }

    // Create one overlay per group.
    for (var gid in groups) {
      var g = groups[gid];
      var type = g.type || "ins";
      var typeClass = "mud-overlay-" + type;
      _groupTypes[gid] = type;

      var div = document.createElement("div");
      div.className = "mud-overlay " + typeClass;
      div.dataset.groupId = gid;
      div.dataset.groupIndex = g.index;

      // Add expando button to every group.
      var btn = document.createElement("button");
      btn.className = "mud-expando";
      btn.textContent = g.index;
      div.appendChild(btn);

      if (type === "ins") {
        // Ins-only groups are always expanded; button is non-interactive.
        btn.classList.add("mud-expando-expanded");
        btn.disabled = true;
        btn.setAttribute("aria-expanded", "true");
      } else {
        btn.setAttribute("aria-expanded", "false");
        btn.addEventListener("click", (function (id) {
          return function () { toggleGroup(id); };
        })(gid));
      }

      // Del-only and mix groups start collapsed unless auto-expand is on.
      if (type === "del" || type === "mix") {
        if (!document.documentElement.classList.contains("is-auto-expand-changes")) {
          if (type === "del") {
            div.classList.add("mud-overlay-collapsed");
          }
        }
      }

      container.appendChild(div);
      _overlays[gid] = div;
    }

    // Auto-expand collapsible groups when the preference is set.
    if (document.documentElement.classList.contains("is-auto-expand-changes")) {
      for (var gid in _overlays) {
        if (_groupTypes[gid] === "del" || _groupTypes[gid] === "mix") {
          expandGroup(gid);
        }
      }
    }

    positionOverlays();
  }

  /// Position an overlay element to span from the first to last
  /// visible element in `els`, relative to `container`.
  function positionOverlay(overlay, els, containerRect, scrollTop) {
    var visible = [];
    for (var i = 0; i < els.length; i++) {
      if (els[i].offsetParent !== null) visible.push(els[i]);
    }
    if (visible.length === 0) {
      overlay.style.display = "none";
      return;
    }
    var zoom = parseFloat(document.documentElement.style.zoom) || 1;
    var firstRect = visible[0].getBoundingClientRect();
    var lastRect = visible[visible.length - 1].getBoundingClientRect();
    overlay.style.display = "";
    overlay.style.top = ((firstRect.top - containerRect.top) / zoom + scrollTop) + "px";
    overlay.style.height = ((lastRect.bottom - firstRect.top) / zoom) + "px";
  }

  /// Position a collapsed del-only overlay at the gap where its
  /// hidden deletions would appear.
  function positionCollapsedOverlay(overlay, gid, container, containerRect, scrollTop) {
    var els = container.querySelectorAll(
      "[data-group-id='" + gid + "']:not(.mud-overlay)"
    );
    if (els.length === 0) {
      overlay.style.display = "none";
      return;
    }
    // Walk backwards from the first del element to find a visible sibling.
    var first = els[0];
    var prev = first.previousElementSibling;
    while (prev && prev.offsetParent === null) {
      prev = prev.previousElementSibling;
    }
    var zoom = parseFloat(document.documentElement.style.zoom) || 1;
    var top;
    if (prev) {
      var prevRect = prev.getBoundingClientRect();
      top = (prevRect.bottom - containerRect.top) / zoom + scrollTop;
    } else {
      // No previous visible sibling — find the next visible sibling instead
      // and position at its top edge.
      var next = els[els.length - 1].nextElementSibling;
      while (next && next.offsetParent === null) {
        next = next.nextElementSibling;
      }
      if (next) {
        var nextRect = next.getBoundingClientRect();
        top = (nextRect.top - containerRect.top) / zoom + scrollTop;
      } else {
        // No visible siblings at all — use the parent's top edge.
        var parentRect = first.parentElement.getBoundingClientRect();
        top = (parentRect.top - containerRect.top) / zoom + scrollTop;
      }
    }
    overlay.style.display = "";
    overlay.style.top = top + "px";
  }

  function positionOverlays() {
    var container = document.querySelector(".up-mode-output");
    if (!container) return;
    var containerRect = container.getBoundingClientRect();
    var scrollTop = container.scrollTop;

    for (var gid in _overlays) {
      if (_suppressedGroups[gid]) continue;
      var overlay = _overlays[gid];

      if (overlay.classList.contains("mud-overlay-collapsed")) {
        positionCollapsedOverlay(overlay, gid, container, containerRect, scrollTop);
        continue;
      }

      var els = container.querySelectorAll(
        "[data-group-id='" + gid + "']:not(.mud-overlay)"
      );
      positionOverlay(overlay, els, containerRect, scrollTop);
    }

    for (var i = 0; i < _subOverlays.length; i++) {
      var sub = _subOverlays[i];
      positionOverlay(sub.overlay, sub.els, containerRect, scrollTop);
    }

    // Make consecutive sub-overlays for the same group continuous:
    // extend each overlay's bottom to meet the next overlay's top.
    // Mark non-last overlays as "cont" and last overlays as "tail".
    for (var i = 0; i < _subOverlays.length; i++) {
      var cur = _subOverlays[i];
      var next = _subOverlays[i + 1];
      var isLast = !next || next.groupId !== cur.groupId;
      cur.overlay.classList.toggle("mud-overlay-cont", !isLast);
      cur.overlay.classList.toggle("mud-overlay-tail", isLast);
      if (isLast) continue;
      if (cur.overlay.style.display === "none") continue;
      if (next.overlay.style.display === "none") continue;
      var curTop = parseFloat(cur.overlay.style.top);
      var nextTop = parseFloat(next.overlay.style.top);
      if (nextTop > curTop) {
        cur.overlay.style.height = (nextTop - curTop) + "px";
      }
    }
  }

  // Build overlays on load; reposition on resize.
  buildOverlays();
  var _upContainer = document.querySelector(".up-mode-output");
  if (_upContainer) {
    new ResizeObserver(positionOverlays).observe(_upContainer);
  }

  // -- Expand / collapse ------------------------------------------------------

  function expandGroup(gid) {
    _expandedGroups[gid] = true;
    var overlay = _overlays[gid];
    if (!overlay) return;
    var container = document.querySelector(".up-mode-output");
    var type = _groupTypes[gid];

    // Mark all elements in group as revealed.
    var els = container.querySelectorAll(
      "[data-group-id='" + gid + "']:not(.mud-overlay)"
    );
    for (var i = 0; i < els.length; i++) {
      els[i].classList.add("mud-change-revealed");
    }

    if (type === "del") {
      overlay.classList.remove("mud-overlay-collapsed");
      overlay.classList.add("mud-change-revealed");
    } else if (type === "mix") {
      // Hide blue overlay and create red/green sub-overlays.
      overlay.style.display = "none";
      _suppressedGroups[gid] = true;

      // Split group elements into consecutive runs by type.
      var runs = [];
      var cur = null;
      for (var k = 0; k < els.length; k++) {
        var t = (els[k].classList.contains("mud-change-del")
                 || els[k].classList.contains("cl-del")) ? "del" : "ins";
        if (cur && cur.type === t) {
          cur.els.push(els[k]);
        } else {
          cur = { type: t, els: [els[k]] };
          runs.push(cur);
        }
      }

      // Create a sub-overlay for each run, starting invisible.
      var firstSub = null;
      for (var r = 0; r < runs.length; r++) {
        var run = runs[r];
        var typeClass = run.type === "del"
          ? "mud-overlay-del" : "mud-overlay-ins";
        var div = document.createElement("div");
        div.className = "mud-overlay " + typeClass;
        div.dataset.groupId = gid;
        div.dataset.groupIndex = overlay.dataset.groupIndex;
        div.style.opacity = "0";
        div.setAttribute("aria-hidden", "true");
        container.appendChild(div);
        _subOverlays.push({
          overlay: div, els: run.els, groupId: gid
        });
        if (!firstSub) firstSub = div;
      }

      // Move button to first sub-overlay.
      var btn = overlay.querySelector(".mud-expando");
      if (btn && firstSub) {
        firstSub.appendChild(btn);
      }
    }

    // Mark button as expanded.
    var btn = overlay.querySelector(".mud-expando")
           || (container && container.querySelector(
                ".mud-overlay[data-group-id='" + gid + "'] .mud-expando"));
    if (btn) {
      btn.classList.add("mud-expando-expanded");
      btn.setAttribute("aria-expanded", "true");
    }

    positionOverlays();

    // Fade in sub-overlays on next frame.
    if (type === "mix") {
      requestAnimationFrame(function () {
        for (var i = 0; i < _subOverlays.length; i++) {
          if (_subOverlays[i].groupId === gid) {
            _subOverlays[i].overlay.style.opacity = "";
          }
        }
      });
    }
  }

  function collapseGroup(gid) {
    delete _expandedGroups[gid];
    var overlay = _overlays[gid];
    if (!overlay) return;
    var container = document.querySelector(".up-mode-output");
    var type = _groupTypes[gid];

    // Remove revealed class from all elements in group.
    var els = container.querySelectorAll(
      "[data-group-id='" + gid + "']:not(.mud-overlay)"
    );
    for (var i = 0; i < els.length; i++) {
      els[i].classList.remove("mud-change-revealed");
    }

    if (type === "del") {
      overlay.classList.add("mud-overlay-collapsed");
      overlay.classList.remove("mud-change-revealed");
    } else if (type === "mix") {
      // Move button back from sub-overlay, then remove sub-overlays.
      var remaining = [];
      for (var i = 0; i < _subOverlays.length; i++) {
        if (_subOverlays[i].groupId === gid) {
          var movedBtn = _subOverlays[i].overlay.querySelector(".mud-expando");
          if (movedBtn) overlay.appendChild(movedBtn);
          _subOverlays[i].overlay.remove();
        } else {
          remaining.push(_subOverlays[i]);
        }
      }
      _subOverlays = remaining;
      delete _suppressedGroups[gid];
      overlay.style.display = "";
    }

    // Unmark button.
    var btn = overlay.querySelector(".mud-expando");
    if (btn) {
      btn.classList.remove("mud-expando-expanded");
      btn.setAttribute("aria-expanded", "false");
    }

    positionOverlays();
  }

  function toggleGroup(gid) {
    if (_expandedGroups[gid]) {
      collapseGroup(gid);
    } else {
      expandGroup(gid);
    }
  }

  function collapseAllChanges() {
    for (var gid in _expandedGroups) {
      collapseGroup(gid);
    }
  }

  // -- Scroll to change -------------------------------------------------------

  function scrollToChange(ids) {
    if (!ids.length) return;
    var first = document.querySelector(
      '[data-change-id="' + ids[0] + '"]'
    );
    if (!first) return;
    var gid = first.dataset.groupId;

    // For collapsed del-only groups, scroll to the overlay button.
    if (first.offsetParent === null && gid && _overlays[gid]) {
      var btn = _overlays[gid].querySelector(".mud-expando");
      if (btn) {
        btn.scrollIntoView({ behavior: "smooth", block: "center" });
      }
    } else {
      first.scrollIntoView({ behavior: "smooth", block: "center" });
    }

    // Ripple the expando button for the group.
    if (!gid) return;

    // Clear any leftover active state from a previous navigation.
    var stale = document.querySelectorAll(".mud-expando.mud-change-active");
    for (var s = 0; s < stale.length; s++) {
      stale[s].classList.remove("mud-change-active");
    }

    var btn = null;
    if (_overlays[gid]) {
      btn = _overlays[gid].querySelector(".mud-expando");
    }
    if (!btn) {
      for (var i = 0; i < _subOverlays.length; i++) {
        if (_subOverlays[i].groupId === gid) {
          btn = _subOverlays[i].overlay.querySelector(".mud-expando");
          if (btn) break;
        }
      }
    }
    if (btn) {
      void btn.offsetWidth;
      btn.classList.add("mud-change-active");
      btn.addEventListener("animationend", function () {
        btn.classList.remove("mud-change-active");
      }, { once: true });
    }
  }

  // -- Extend public namespace ------------------------------------------------

  function applyAutoExpandChanges(enabled) {
    for (var gid in _overlays) {
      var type = _groupTypes[gid];
      if (type === "del" || type === "mix") {
        if (enabled && !_expandedGroups[gid]) {
          expandGroup(gid);
        } else if (!enabled && _expandedGroups[gid]) {
          collapseGroup(gid);
        }
      }
    }
  }

  window.Mud.scrollToChange = scrollToChange;
  window.Mud.collapseAllChanges = collapseAllChanges;
  window.Mud.applyAutoExpandChanges = applyAutoExpandChanges;
})();
