// Mermaid diagram renderer for Up mode.
// Injected as a WKUserScript after mermaid.min.js.
//
// The palette is the page's own: every color comes from the --diagram-*
// custom properties in mud.css, which each theme derives from its own
// variables. Mermaid computes the rest of its palette from the few colors it
// is given, so it needs resolved values — hence getComputedStyle rather than
// var() references. Those values are baked into the SVG, so a lighting change
// has to re-render; see the media listener at the bottom.
//
// The look is rough outlines, a translucent glaze with pigment pooled at its
// edge, and labels in whichever face --diagram-font names. Mermaid draws the
// outlines (look: handDrawn); the glaze and the pooling are the wash pass
// below.

(function () {
  if (!document.querySelector(".up-mode-output")) return;

  // Nodes and clusters take the glaze. A pie slice, a journey section and a
  // timeline block don't: their fill is the datum, and washing them out would
  // misreport it.
  var WASHABLE_GROUP = "g.node, g.cluster";
  var WASHABLE_SHAPE = "path, rect, polygon, circle, ellipse";

  // An xy chart's bars are one series, so the same glaze over every one of
  // them takes nothing away — and it is what makes the chart read as part of a
  // drawn document rather than as a panel pasted into one.
  //
  // A Gantt's bars are deliberately not here. Its three task states have to be
  // told apart at a glance, and a glaze costs most of the difference between
  // them; they are drawn solid instead, in colors already named at the
  // strength they should be seen at.
  var WASHABLE_BAR = "g.plot rect";

  var containers = [];

  // -- Palette ------------------------------------------------------------

  function palette() {
    var css = getComputedStyle(document.documentElement);
    function v(name, fallback) {
      return css.getPropertyValue(name).trim() || fallback;
    }
    var bg = normalizeColor(v("--diagram-bg", "#F5F0E4"));

    // Every other color is composited onto the ground first. A theme is free
    // to write a translucent one — Austere's --code-bg is a green at 3.5%
    // alpha — and Mermaid's color math wants opaque values: it picks some
    // label colors by inverting a fill, and inverting near-nothing gives
    // near-nothing, which is a label you can't read.
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

  // The label font, named by the stylesheets rather than by this file: the
  // page's own sans under the Simplicity look (mud-diagram.css), Caveat under
  // Handwritten (mud-diagram-font.css, the only one that ships a font). Mermaid
  // is given the name because it measures each label's box with it — a font
  // applied in CSS alone would be laid out in boxes sized for another one.
  function labelFont() {
    var css = getComputedStyle(document.documentElement);
    return (
      css.getPropertyValue("--diagram-font").trim() || "system-ui, sans-serif"
    );
  }

  // Setting a color on an inline style normalizes it to rgb() or rgba(), so
  // two spellings of the same color compare equal, and a color named in any
  // CSS syntax can be taken apart. An invalid value leaves the property empty.
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

  // The color as it actually looks over `ground`, with any alpha resolved.
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

  // Mermaid takes an xy chart's plot colors as one comma-separated string, so
  // a color spelled with commas inside it — hsl(20, 45%, 43%) — is torn into
  // three entries that name no color at all, and the chart falls back to SVG's
  // own defaults: black bars, and a line with no stroke. Every color this file
  // builds is hex for that reason.
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

  // Whether the page is dark, asked of the palette rather than of a media
  // query: a theme decides its own ground, and this has to follow the theme.
  function isDarkGround(colors) {
    var ground = toHSL(colors.bg);
    var ink = toHSL(colors.fg);
    return ground && ink ? ground.l < ink.l : false;
  }

  // Mermaid derives every categorical color — pie slices, journey and timeline
  // sections, git branches, chart plots — from its primary, secondary and
  // tertiary colors. Ours are three near-neighbors out of one theme, so a pie
  // chart comes out as four shades of the same thing. Build a set instead: one
  // hue circle, walked in twelve steps from the accent's own hue, at a fixed
  // saturation and a lightness the caller picks for where the color is going.
  function ramp(accent, count, lightness) {
    var base = toHSL(accent) || { h: 20, s: 0.4, l: 0.45 };
    // A grey accent gives the rotation nothing to work with, and a loud one
    // would fight the watercolor, so the saturation is floored and capped.
    var s = Math.min(Math.max(base.s, 0.35), 0.6);
    var colors = [];

    for (var i = 0; i < count; i++) {
      // 5 and 12 share no factor, so stepping by five visits all twelve hues
      // while landing consecutive entries 150° apart — adjacent slices of a
      // pie read as different colors, not as neighbors on the wheel.
      var h = (base.h + ((i * 5) % 12) * 30) % 360;
      // Alternate a little either side, so same-hue neighbors still separate.
      colors.push(hslHex(h, s, lightness + (i % 2 ? 0.05 : -0.05)));
    }
    return colors;
  }

  function initialize(colors) {
    var onDark = isDarkGround(colors);
    var font = labelFont();

    // Two sets, because the two jobs want opposite things. A pie slice, a
    // timeline section and a branch label all have text sitting on top of
    // them, and that text is --diagram-fg — so those colors are pitched away
    // from the ink and toward the ground: pale on a light page, deep on a
    // dark one. A chart's bars and lines carry no text and have to stand out
    // *from* the ground instead, so they take a mid tone either way.
    var sections = ramp(colors.accent, 12, onDark ? 0.34 : 0.82);
    var plots = ramp(colors.accent, 12, onDark ? 0.62 : 0.48);

    // The Gantt bars take no glaze, so each of these is the color as it will
    // be seen rather than one the wash is about to lift. Every bar carries a
    // label in the page's own ink, which is why none of the fills is a color
    // at full strength: they are pitched toward the ground the way a pie slice
    // is, and it is the borders that carry the weight.
    var accent = toHSL(colors.accent) || { h: 20, s: 0.4, l: 0.45 };
    var bars = {
      // A completed task is the accent drained of its saturation — a warm grey
      // in Earthy and Riot, a cool one in Austere and Blues, rather than a
      // neutral belonging to no page. Its border sits a dozen points from the
      // fill, and away from the ground rather than darker: on a dark page a
      // border darker than its own bar is a border you can't see.
      doneFill: hslHex(accent.h, 0.12, onDark ? 0.26 : 0.9),
      doneBorder: hslHex(accent.h, 0.15, onDark ? 0.38 : 0.78),
      activeFill: hslHex(accent.h, Math.min(Math.max(accent.s, 0.35), 0.6), onDark ? 0.34 : 0.8),
      // A critical task keeps the hue the convention gives it. Its fill is
      // pitched to the ground like the others, so the border is thrown the
      // other way — a pale pink on its own doesn't read as a warning.
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
      look: "handDrawn",
      // Fixed, because Mud re-renders on every content change: an unseeded
      // wobble would redraw itself differently on each keystroke.
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
        // A git graph's commit label is set at 10px and turned 45°, which a
        // handwriting face can't carry, and Mermaid colors it by inverting the
        // node fill. Name the colors, and give both labels a readable size.
        commitLabelColor: colors.fg,
        commitLabelBackground: colors.bg,
        commitLabelFontSize: "13px",
        tagLabelColor: colors.fg,
        tagLabelBackground: colors.surface,
        tagLabelBorder: colors.border,
        tagLabelFontSize: "12px",
        // A Gantt chart is drawn from a set of variables of its own, and
        // Mermaid defaults most of them to literal colors no theme can reach:
        // white alternating bands, a grey done bar, a red today line, a navy
        // vertical marker. Name every one. The three task states run from the
        // ground outward — a done task is the accent drained of its saturation
        // and sits nearest the page, a plain one sits on the node surface, and
        // the active one is the only bar drawn in the accent itself.
        // Mermaid cycles four section styles: the first and third take these
        // two, the second and fourth take the alternate — so the bands come
        // out alternating rather than three the same. The bands that are meant
        // to read as the page are left unpainted rather than filled in
        // --diagram-bg, because the body's ground is a gradient and a solid
        // patch of its top color would show against the rest of it.
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
        // Mermaid's own default here is lighten(primaryColor, 23), which on
        // any of our surfaces saturates at pure white, bordered in the plain
        // task's fill — the running task came out the least visible bar. The
        // accent goes on the border, where it can be at full strength without
        // taking the label down with it.
        activeTaskBkgColor: bars.activeFill,
        activeTaskBorderColor: colors.accent,
        critBkgColor: bars.critFill,
        critBorderColor: bars.critBorder,
        // An xy chart reads none of the variables above. Worse, the config it
        // does read is built from Mermaid's *default* theme deep-merged with
        // this object, so it never sees the base theme the rest of the page is
        // drawn from: anything left unnamed comes out white-on-#131300 in all
        // four themes and both lightings. Name every color it uses.
        xyChart: {
          // The page already has a ground, and the chart paints this as a rect
          // covering the whole plot — an opaque one shows as a panel with its
          // own edge where the body's gradient runs.
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

  // Every filled shape in a node or cluster takes the glaze except the solid
  // marks drawn in ink: a state diagram's start and end dots are filled in the
  // text or border color, and a 0.3 glaze would all but erase them. Stated as
  // an exclusion on purpose — Mermaid derives some body fills from the colors
  // it was given rather than using them as-is, and a shape it tinted should
  // still be glazed.
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

      // Only a shape that names its own fill is glazed. Reading the computed
      // style instead would reach the families Mermaid fills from a class —
      // a mindmap above all, whose every shape is filled by a `.section-N`
      // rule and which draws its edges up to 17px wide underneath them. Those
      // want an opaque fill covering the line, not a wash letting it through.
      var fill = shape.getAttribute("fill");
      if (!isWashable(fill)) return;
      shape.dataset.mudWash = "fill";

      var edge = shape.cloneNode(false);
      edge.removeAttribute("id");
      edge.removeAttribute("fill-opacity");
      edge.dataset.mudWash = "edge";
      // Set inline rather than as attributes, and keep the clone's classes:
      // Mermaid scopes its own fill and stroke rules under the diagram's id,
      // which outranks both, but the classes are also what carry a milestone's
      // 45° rotation — a rim drawn square around a diamond is worse than none.
      edge.style.fill = "none";
      edge.style.stroke = fill;
      shape.parentNode.insertBefore(edge, shape.nextSibling);
    });
  }

  // -- Rendering ----------------------------------------------------------

  // Replaces each mermaid code block with the container Mermaid renders into,
  // keeping the source on the container so a re-render has something to read.
  function collect() {
    document.querySelectorAll("code.language-mermaid").forEach(function (code) {
      var pre = code.parentElement;
      if (!pre || pre.tagName !== "PRE") return;

      // Skip deleted mermaid blocks (change tracking).
      if (pre.classList.contains("mud-change-del")) return;

      var container = document.createElement("div");
      container.className = "mermaid";
      container.textContent = code.textContent;
      container.dataset.mudSource = code.textContent;

      // Preserve change-tracking attributes through the replacement.
      if (pre.dataset.changeId) {
        container.dataset.changeId = pre.dataset.changeId;
        container.dataset.groupId = pre.dataset.groupId;
        container.dataset.groupIndex = pre.dataset.groupIndex;
        pre.classList.forEach(function (cls) {
          if (cls.startsWith("mud-change-")) container.classList.add(cls);
        });
      }

      pre.parentNode.replaceChild(container, pre);
      containers.push(container);
    });
  }

  function render() {
    if (containers.length === 0) return;

    var colors = palette();
    initialize(colors);

    mermaid
      .run({ nodes: containers })
      .then(function () {
        var isWashable = washable(colors);
        containers.forEach(function (container) {
          var svg = container.querySelector("svg");
          if (svg) wash(svg, isWashable);
        });
      })
      .catch(function (error) {
        console.error("Mud: mermaid render failed", error);
      });
  }

  collect();
  render();

  // A theme change reloads the document, so diagrams pick up a new theme on
  // their own. A lighting change doesn't: it flips the window's appearance,
  // the CSS variables follow, and the diagram keeps the colors baked into its
  // SVG. So put each diagram back to its source and draw it again.
  var scheme = window.matchMedia("(prefers-color-scheme: dark)");
  if (scheme.addEventListener) {
    scheme.addEventListener("change", function () {
      containers.forEach(function (container) {
        container.removeAttribute("data-processed");
        container.textContent = container.dataset.mudSource;
      });
      render();
    });
  }
})();
