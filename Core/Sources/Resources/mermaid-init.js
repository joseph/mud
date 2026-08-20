// Mermaid diagram renderer for Up mode.
// Injected as a WKUserScript after mermaid.min.js.
//
// The palette comes from the --diagram-* custom properties in mud.css. Mermaid
// computes the rest of its palette from the few colors it is given, so it needs
// resolved values — hence getComputedStyle rather than var() references. Those
// values are baked into the SVG, so a lighting change has to re-render; see the
// media listener at the bottom.

(function () {
  if (!document.querySelector(".up-mode-output")) return;

  // Nodes and clusters take the glaze. A pie slice, a journey section and a
  // timeline block don't: their fill is the datum.
  var WASHABLE_GROUP = "g.node, g.cluster";
  var WASHABLE_SHAPE = "path, rect, polygon, circle, ellipse";

  // An xy chart's bars are one series, so a uniform glaze takes nothing away. A
  // Gantt's are deliberately absent: its three task states have to be told
  // apart, and a glaze costs most of the difference between them.
  var WASHABLE_BAR = "g.plot rect";

  var containers = [];

  // -- Palette ------------------------------------------------------------

  function palette() {
    var css = getComputedStyle(document.documentElement);
    function v(name, fallback) {
      return css.getPropertyValue(name).trim() || fallback;
    }
    var bg = normalizeColor(v("--diagram-bg", "#F5F0E4"));

    // Composite onto the ground first. A theme may write a translucent color
    // (Austere's --code-bg is a green at 3.5% alpha) and Mermaid's color math
    // wants opaque values: it picks some label colors by inverting a fill, and
    // inverting near-nothing gives a label you can't read.
    function over(name, fallback) {
      return flatten(v(name, fallback), bg);
    }

    return {
      bg: bg,
      fg: over("--diagram-fg", "#221E16"),
      surface: over("--diagram-surface", "#EAD9B9"),
      line: over("--diagram-line", "#4D4A44"),
      border: over("--diagram-border", "#5A564E"),
      accent: over("--diagram-accent", "#9A4A24"),
    };
  }

  // Mermaid is given the font name because it measures each label's box with
  // it — a font applied in CSS alone would be laid out in boxes sized for
  // another one.
  function labelFont() {
    var css = getComputedStyle(document.documentElement);
    return (
      css.getPropertyValue("--diagram-font").trim() || "system-ui, sans-serif"
    );
  }

  // Setting a color on an inline style normalizes it to rgb() or rgba(), so two
  // spellings of the same color compare equal. An invalid value leaves the
  // property empty.
  var probe = document.createElement("span");

  function normalizeColor(value) {
    probe.style.color = "";
    probe.style.color = value;
    return probe.style.color;
  }

  function channels(value) {
    var parts = normalizeColor(value).match(/[\d.]+/g);
    return parts && parts.length >= 3 ? parts.map(Number) : null;
  }

  function flatten(value, ground) {
    var c = channels(value);
    if (!c) return value;
    var alpha = c.length > 3 ? c[3] : 1;
    if (alpha >= 1) return normalizeColor(value);

    var g = channels(ground) || [255, 255, 255];
    var mixed = [0, 1, 2].map(function (i) {
      return Math.round(c[i] * alpha + g[i] * (1 - alpha));
    });
    return "rgb(" + mixed.join(", ") + ")";
  }

  // Every color this file builds is hex: Mermaid takes an xy chart's plot
  // colors as one comma-separated string, so an hsl(20, 45%, 43%) in it is torn
  // into three entries naming no color, and the chart falls back to SVG's own
  // defaults — black bars and a line with no stroke.
  function hslHex(h, s, l) {
    var c = (1 - Math.abs(2 * l - 1)) * s;
    var x = c * (1 - Math.abs(((h / 60) % 2) - 1));
    var m = l - c / 2;
    var rgb =
      h < 60 ? [c, x, 0]
      : h < 120 ? [x, c, 0]
      : h < 180 ? [0, c, x]
      : h < 240 ? [0, x, c]
      : h < 300 ? [x, 0, c]
      : [c, 0, x];

    return (
      "#" +
      rgb
        .map(function (v) {
          return Math.round((v + m) * 255)
            .toString(16)
            .padStart(2, "0");
        })
        .join("")
    );
  }

  function toHSL(value) {
    var parts = channels(value);
    if (!parts) return null;

    var r = parts[0] / 255;
    var g = parts[1] / 255;
    var b = parts[2] / 255;
    var max = Math.max(r, g, b);
    var min = Math.min(r, g, b);
    var l = (max + min) / 2;
    if (max === min) return { h: 0, s: 0, l: l };

    var d = max - min;
    var h;
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60;
    if (h < 0) h += 360;

    return { h: h, s: d / (1 - Math.abs(2 * l - 1)), l: l };
  }

  // Asked of the palette rather than of a media query: a theme decides its own
  // ground, and this has to follow the theme.
  function isDarkGround(colors) {
    var ground = toHSL(colors.bg);
    var ink = toHSL(colors.fg);
    return ground && ink ? ground.l < ink.l : false;
  }

  // Mermaid derives every categorical color — pie slices, journey and timeline
  // sections, git branches, chart plots — from its primary, secondary and
  // tertiary colors. Ours are three near-neighbors out of one theme, so a pie
  // chart would come out as four shades of the same thing. Build a set instead:
  // one hue circle walked in twelve steps from the accent's hue.
  function ramp(accent, count, lightness) {
    var base = toHSL(accent) || { h: 20, s: 0.4, l: 0.45 };
    // A grey accent gives the rotation nothing to work with, and a loud one
    // would fight the watercolor, so the saturation is floored and capped.
    var s = Math.min(Math.max(base.s, 0.35), 0.6);
    var colors = [];

    for (var i = 0; i < count; i++) {
      // 5 and 12 share no factor, so stepping by five visits all twelve hues
      // while landing consecutive entries 150° apart.
      var h = (base.h + ((i * 5) % 12) * 30) % 360;
      // Alternate a little either side, so same-hue neighbors still separate.
      colors.push(hslHex(h, s, lightness + (i % 2 ? 0.05 : -0.05)));
    }
    return colors;
  }

  function initialize(colors) {
    var onDark = isDarkGround(colors);
    var font = labelFont();

    // Two sets: a pie slice, timeline section and branch label carry text in
    // --diagram-fg, so those colors are pitched toward the ground. A chart's
    // bars and lines carry no text and take a mid tone to stand out from it.
    var sections = ramp(colors.accent, 12, onDark ? 0.34 : 0.82);
    var plots = ramp(colors.accent, 12, onDark ? 0.62 : 0.48);

    // Gantt bars take no glaze, so each of these is the color as it will be
    // seen rather than one the wash is about to lift.
    var accent = toHSL(colors.accent) || { h: 20, s: 0.4, l: 0.45 };
    var bars = {
      // A done task's border sits away from the ground rather than darker: on a
      // dark page a border darker than its own bar can't be seen.
      doneFill: hslHex(accent.h, 0.12, onDark ? 0.26 : 0.9),
      doneBorder: hslHex(accent.h, 0.15, onDark ? 0.38 : 0.78),
      activeFill: hslHex(accent.h, Math.min(Math.max(accent.s, 0.35), 0.6), onDark ? 0.34 : 0.8),
      // A critical task's fill is pitched to the ground like the others, so the
      // border is thrown the other way: a pale pink alone reads as no warning.
      critFill: hslHex(6, 0.55, onDark ? 0.3 : 0.86),
      critBorder: hslHex(6, 0.6, onDark ? 0.6 : 0.45),
    };

    var seriesVariables = {};
    sections.forEach(function (color, i) {
      seriesVariables["pie" + (i + 1)] = color; // pie1…pie12
      seriesVariables["cScale" + i] = color; // journey, timeline, mindmap
      // Mermaid would work these out from its own light/dark flag, which we
      // never set — name them, and the text on a section stays the page's ink.
      seriesVariables["cScaleLabel" + i] = colors.fg;
      if (i < 8) {
        seriesVariables["git" + i] = color; // gitGraph branches
        seriesVariables["gitBranchLabel" + i] = colors.fg;
      }
    });

    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      theme: "base",
      // Mermaid's failure graphic names neither the line nor the problem. Off,
      // so `showError` can put the block back with the parser's own complaint.
      suppressErrorRendering: true,
      look: "handDrawn",
      // Fixed: Mud re-renders on every content change, and an unseeded wobble
      // would redraw itself differently on each keystroke.
      handDrawnSeed: 1,
      fontFamily: font,
      themeVariables: Object.assign(seriesVariables, {
        background: colors.bg,
        primaryColor: colors.surface,
        mainBkg: colors.surface,
        secondaryColor: colors.surface,
        tertiaryColor: colors.bg,
        primaryTextColor: colors.fg,
        textColor: colors.fg,
        titleColor: colors.fg,
        primaryBorderColor: colors.border,
        nodeBorder: colors.border,
        clusterBkg: colors.bg,
        clusterBorder: colors.border,
        edgeLabelBackground: colors.bg,
        lineColor: colors.line,
        arrowheadColor: colors.accent,
        pieStrokeColor: colors.border,
        pieOuterStrokeColor: colors.border,
        pieTitleTextColor: colors.fg,
        pieSectionTextColor: colors.fg,
        pieLegendTextColor: colors.fg,
        // A git graph's commit label is set at 10px, turned 45°, and colored by
        // inverting the node fill. Name the colors and give it a readable size.
        commitLabelColor: colors.fg,
        commitLabelBackground: colors.bg,
        commitLabelFontSize: "13px",
        tagLabelColor: colors.fg,
        tagLabelBackground: colors.surface,
        tagLabelBorder: colors.border,
        tagLabelFontSize: "12px",
        // A Gantt reads a set of variables of its own, and Mermaid defaults
        // most of them to literal colors no theme can reach (white bands, a
        // grey done bar, a red today line, a navy marker). Name every one.
        // Mermaid cycles four section styles, the first and third taking these
        // two — so the bands alternate rather than running three the same. The
        // bands meant to read as the page are left unpainted rather than filled
        // in --diagram-bg, because the body's ground is a gradient and a solid
        // patch of its top color would show against the rest.
        sectionBkgColor: "transparent",
        sectionBkgColor2: "transparent",
        altSectionBkgColor: colors.surface,
        excludeBkgColor: colors.surface,
        gridColor: colors.line,
        todayLineColor: colors.accent,
        vertLineColor: colors.accent,
        taskBkgColor: colors.surface,
        taskBorderColor: colors.border,
        taskTextColor: colors.fg,
        taskTextDarkColor: colors.fg,
        taskTextLightColor: colors.fg,
        taskTextOutsideColor: colors.fg,
        taskTextClickableColor: colors.accent,
        doneTaskBkgColor: bars.doneFill,
        doneTaskBorderColor: bars.doneBorder,
        // Mermaid's default is lighten(primaryColor, 23), which on any of our
        // surfaces saturates at white — the running task came out the least
        // visible bar. The accent goes on the border instead, where it can be
        // at full strength without taking the label down with it.
        activeTaskBkgColor: bars.activeFill,
        activeTaskBorderColor: colors.accent,
        critBkgColor: bars.critFill,
        critBorderColor: bars.critBorder,
        // An xy chart reads none of the variables above, and the config it does
        // read is built from Mermaid's *default* theme deep-merged with this
        // object, never the base theme the rest of the page uses: anything left
        // unnamed comes out white-on-#131300. Name every color it uses.
        xyChart: {
          // The chart paints this as a rect covering the whole plot; an opaque
          // one shows as a panel with its own edge over the body's gradient.
          backgroundColor: "transparent",
          titleColor: colors.fg,
          xAxisTitleColor: colors.fg,
          xAxisLabelColor: colors.fg,
          xAxisTickColor: colors.line,
          xAxisLineColor: colors.line,
          yAxisTitleColor: colors.fg,
          yAxisLabelColor: colors.fg,
          yAxisTickColor: colors.line,
          yAxisLineColor: colors.line,
          plotColorPalette: plots.join(","),
        },
        fontFamily: font,
      }),
      // Geometry, not color — a second `xyChart` key, read from the config
      // rather than from the theme. Mermaid's 2px axis rules and ticks are
      // heavier than any line the page draws around them.
      xyChart: {
        xAxis: { axisLineWidth: 1, tickWidth: 1 },
        yAxis: { axisLineWidth: 1, tickWidth: 1 },
      },
    });
  }

  // -- The wash -----------------------------------------------------------

  // Everything filled in a node or cluster is glazed except the solid marks
  // drawn in ink: a state diagram's start and end dots are filled in the text
  // or border color, and a 0.3 glaze would all but erase them. An exclusion
  // rather than a list, since Mermaid tints some fills from the given colors
  // rather than using them as-is, and a tinted shape should still be glazed.
  function washable(colors) {
    var ink = [normalizeColor(colors.fg), normalizeColor(colors.border)];
    return function (fill) {
      if (!fill || fill === "none" || fill === "transparent") return false;
      return ink.indexOf(normalizeColor(fill)) === -1;
    };
  }

  function washableShapes(svg) {
    var shapes = [];
    svg.querySelectorAll(WASHABLE_GROUP).forEach(function (group) {
      group.querySelectorAll(WASHABLE_SHAPE).forEach(function (shape) {
        shapes.push(shape);
      });
    });
    svg.querySelectorAll(WASHABLE_BAR).forEach(function (shape) {
      shapes.push(shape);
    });
    return shapes;
  }

  // The fill becomes a translucent glaze, and a copy of the same outline is
  // stroked in the fill color so the pigment pools at the edge. The opacities
  // come from mud-diagram.css; only the per-shape stroke color is set here.
  function wash(svg, isWashable) {
    washableShapes(svg).forEach(function (shape) {
      if (shape.dataset.mudWash) return;

      // The attribute, not the computed style: computed would reach the shapes
      // Mermaid fills from a class — a mindmap above all, whose edges run up to
      // 17px wide under fills that have to stay opaque to cover them.
      var fill = shape.getAttribute("fill");
      if (!isWashable(fill)) return;
      shape.dataset.mudWash = "fill";

      var edge = shape.cloneNode(false);
      edge.removeAttribute("id");
      edge.removeAttribute("fill-opacity");
      edge.dataset.mudWash = "edge";
      // Inline rather than as attributes, keeping the clone's classes: Mermaid
      // scopes its fill and stroke rules under the diagram's id, which outranks
      // both, and the classes carry a milestone's 45° rotation.
      edge.style.fill = "none";
      edge.style.stroke = fill;
      shape.parentNode.insertBefore(edge, shape.nextSibling);
    });
  }

  // -- Rendering ----------------------------------------------------------

  // The source stays on the container for a re-render, and the block itself for
  // a diagram that won't parse.
  function collect() {
    document.querySelectorAll("code.language-mermaid").forEach(function (code) {
      var pre = code.parentElement;
      if (!pre || pre.tagName !== "PRE") return;

      if (pre.classList.contains("mud-change-del")) return;

      var container = document.createElement("div");
      container.className = "mermaid";
      container.textContent = code.textContent;
      container.dataset.mudSource = code.textContent;
      // The <pre> as the document rendered it, held rather than rebuilt, so the
      // block an error puts back is the one turning diagrams off would show.
      container.mudSourceBlock = pre;

      // Change-tracking attributes *move* rather than copy: the <pre> goes back
      // on screen when the diagram won't parse, and two elements carrying one
      // change id would draw that change twice.
      if (pre.dataset.changeId) {
        container.dataset.changeId = pre.dataset.changeId;
        container.dataset.groupId = pre.dataset.groupId;
        container.dataset.groupIndex = pre.dataset.groupIndex;
        var moved = [];
        pre.classList.forEach(function (cls) {
          if (cls.startsWith("mud-change-")) moved.push(cls);
        });
        moved.forEach(function (cls) {
          container.classList.add(cls);
          pre.classList.remove(cls);
        });
        delete pre.dataset.changeId;
        delete pre.dataset.groupId;
        delete pre.dataset.groupIndex;
      }

      pre.parentNode.replaceChild(container, pre);
      containers.push(container);
    });
  }

  // The complaint runs to three or four lines, mostly expected tokens, so it
  // goes in the block below hidden rather than pushing the document down.
  function showError(container, error) {
    container.textContent = "";
    container.classList.add("is-error");

    if (container.mudSourceBlock) {
      container.appendChild(container.mudSourceBlock);
      container.mudSourceBlock.appendChild(badge(container));
    }

    var message = document.createElement("p");
    message.className = "mud-diagram-error";
    message.textContent = messageOf(error);
    container.appendChild(message);
  }

  // With no app to ask, it shows the hidden block below the code instead.
  function badge(container) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "mud-diagram-badge";
    button.textContent = "Invalid";
    button.title = "Show why this diagram could not be drawn";
    button.addEventListener("click", function () {
      var message = container.querySelector(".mud-diagram-error");
      if (!message) return;
      if (showPopover(button, message)) return;
      container.classList.toggle("is-showing-error");
    });
    return button;
  }

  // The element is passed rather than its text, and `outerHTML` read off it, so
  // what crosses the bridge is what `textContent` already escaped — Mermaid's
  // string is never built into HTML. False where there is no app to ask.
  function showPopover(button, message) {
    var popover = window.Mud && window.Mud.popover;
    if (!popover) return false;
    return popover.show(button.getBoundingClientRect(), message.outerHTML);
  }

  // Mermaid rejects with its own wrapper, which carries `message` for a parse
  // error and a thrown Error alike. A parse error's text runs to several lines
  // and draws a caret under the offending column, so it is set as text.
  function messageOf(error) {
    if (!error) return "The diagram could not be drawn.";
    return error.message || error.str || String(error);
  }

  // Back to an undrawn container: Mermaid renders a node once and marks it
  // `data-processed`, and an error block has to come off with that mark.
  function reset(container) {
    container.removeAttribute("data-processed");
    container.classList.remove("is-error", "is-showing-error");
    var stale = container.querySelector(".mud-diagram-badge");
    if (stale) stale.remove();
    container.textContent = container.dataset.mudSource;
  }

  function render() {
    if (containers.length === 0) return;

    var colors = palette();
    initialize(colors);
    var isWashable = washable(colors);

    // One run per container, so a rejection is contained to its own block:
    // handing Mermaid the whole list makes one failure the result of the whole
    // pass, and every diagram that did render loses its wash. Chained rather
    // than started together, because Mermaid ids its temporary render element
    // with `Date.now()` unless `deterministicIds` is set — two runs alive in
    // the same millisecond get the same id and draw over each other.
    containers.reduce(function (chain, container) {
      return chain.then(function () {
        return mermaid
          .run({ nodes: [container] })
          .then(function () {
            var svg = container.querySelector("svg");
            if (svg) wash(svg, isWashable);
          })
          .catch(function (error) {
            showError(container, error);
          });
      });
    }, Promise.resolve());
  }

  collect();
  render();

  // A theme change reloads the document, so diagrams pick up a new theme on
  // their own. A lighting change doesn't: the CSS variables follow the window's
  // appearance, but the diagram keeps the colors baked into its SVG.
  var scheme = window.matchMedia("(prefers-color-scheme: dark)");
  if (scheme.addEventListener) {
    scheme.addEventListener("change", function () {
      containers.forEach(reset);
      render();
    });
  }
})();
