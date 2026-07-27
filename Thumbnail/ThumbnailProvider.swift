import AppKit
import CoreGraphics
import CoreText
import Foundation
import MudCore
import OSLog
import QuickLookThumbnailing

private let log = Logger(
    subsystem: "org.josephpearson.Mud.Thumbnail",
    category: "thumbnail"
)

// Geometry on the 768×1024 (3:4 portrait) reference canvas. The canvas
// is filled flat with `cardColor` — no separate page-silhouette layer,
// since Finder wraps the reply in its own paper chrome and we're using
// the whole rect as the card body.
private let canvasSize = CGSize(width: 768, height: 1024)

// The writable interior. Its bottom clears the drip, whose crest peaks at
// y ≈ 784 in the overlay's alpha, so nothing drawn is chopped at the
// canvas edge. Its top sits high enough to reach into the fold curl — see
// `curlLeft`, which shortens the lines that do.
private let textBox = CGRect(x: 72, y: 144, width: 624, height: 640)

// Where the heading starts when it can't wrap around the curl: clear of
// it entirely, which is what 4.0.0 did at every size.
private let textBoxBelowCurl = CGRect(x: 72, y: 210, width: 624, height: 568)

// The fold curl, measured against the overlay's own alpha: its left edge
// is near-vertical — x ≈ 586 at the top, easing to x ≈ 569 by y ≈ 150,
// and x ≈ 556 at its leftmost once the soft shadow is counted — and the
// whole shape is done by y ≈ 190. A line whose top falls in that band is
// shortened to `curlLeft - curlGutter`; the rest run the full box width.
private let curlLeft: CGFloat = 556
private let curlBottom: CGFloat = 190
private let curlGutter: CGFloat = 16

/// Reference-canvas point sizes, largest first — the first that fits
/// wins. A short heading gets display type; a long one steps down.
private let sizeLadder: [CGFloat] = [104, 88, 74, 62, 52]

/// Ceiling on line count. The box height usually binds first; this is
/// generous on purpose, so the fitter prefers stepping down a rung to
/// show the whole heading over truncating it at bigger type.
private let maxLines = 5

/// Multiplier on the font's natural line height (ascent − descent). SF's
/// default leading is airy at display sizes.
private let lineHeightRatio: CGFloat = 0.92

/// Tracking as a fraction of the device font size. SF wants it negative
/// at display sizes and none at text sizes, so it is applied only above
/// the optical-size crossover.
private let trackingRatio: CGFloat = -0.018
private let trackingThreshold: CGFloat = 24

/// Legibility floor, in device points. This is the one lever keeping
/// small replies readable: it trims the bottom rungs off the ladder, so
/// a small card is forced into relatively larger type (and truncation)
/// rather than shrinking to a smudge. It is a preference, not a cut — a
/// reply too small to honor it still gets its heading, at the largest
/// rung there is.
private let minDeviceFontSize: CGFloat = 11

private let headingWeight: NSFont.Weight = .medium

// Matches the `page` fill in thumbnail-static.svg, so the static icon and
// the dynamic thumbnail show the same paper — keep the two in step.
// Deliberately fixed rather than appearance-derived: the system caches
// thumbnails against file content, not appearance, so one rendered in
// Dark mode would persist into Light. Finder's mandatory sheet chrome is
// white in both appearances anyway.
private let cardColor = NSColor(
    red: 0xEF / 255.0, green: 0xEF / 255.0, blue: 0xEF / 255.0, alpha: 1
)

// Heading ink: a darker brown than the app's Earthy `--heading-color`
// (#7A4A2A), which needs the extra contrast to hold up against the light
// card at thumbnail scale.
private let headingColor = NSColor(
    red: 0x60 / 255.0, green: 0x3A / 255.0, blue: 0x21 / 255.0, alpha: 1
)

/// Quick Look thumbnail provider for Markdown files. Fills a 3:4
/// portrait canvas (768×1024 reference) with a flat grey card colour,
/// sets the document's first heading into `textBox`, then composites
/// `thumbnail-dynamic.png` (the muddy-drip overlay) on top. Finder's
/// paper-sheet chrome wraps the reply at the same portrait aspect.
///
/// The heading is fitted rather than drawn at a fixed size: the largest
/// rung of `sizeLadder` whose wrap fits the box wins, the rag is then
/// balanced, and anything still over the line budget is truncated with
/// an ellipsis. A word is never split across two lines — see
/// `firstMidWordBreak`.
///
/// The block starts high on the page and is shaped around the fold curl,
/// its top lines pulled in to clear it. A heading that can't be shaped
/// that way without splitting a word is set below the curl instead, at
/// full width — see `layOutHeading`.
///
/// `@objc(MudThumbnailProvider)` stabilizes the Obj-C class name so
/// `NSExtensionPrincipalClass` in Info.plist resolves without depending
/// on Swift module-name mangling (matches the `MudPreviewProvider`
/// pattern).
@objc(MudThumbnailProvider)
final class MudThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, (any Error)?) -> Void
    ) {
        let url = request.fileURL
        log.info("""
            provideThumbnail: \(url.path, privacy: .public) \
            maximumSize=\(request.maximumSize.width)x\(request.maximumSize.height) \
            scale=\(request.scale)
            """)

        let heading = firstHeading(in: url)
            ?? url.deletingPathExtension().lastPathComponent

        guard let overlay = loadBundledImage(named: "thumbnail-dynamic") else {
            log.error("thumbnail-dynamic.png missing from bundle")
            handler(nil, nil)
            return
        }

        let size = fittedSize(in: request.maximumSize)
        log.info("replying with size=\(size.width)x\(size.height)")
        let reply = QLThumbnailReply(contextSize: size) {
            drawThumbnail(overlay: overlay, heading: heading, size: size)
            return true
        }
        handler(reply, nil)
    }
}

/// Largest 3:4-portrait size that fits inside the system-requested
/// bounding box. `QLFileThumbnailRequest.maximumSize` is a max — the
/// reply bitmap's aspect ratio drives how Finder shapes the paper
/// chrome, so returning a portrait size gets us a portrait thumbnail.
private func fittedSize(in maxSize: CGSize) -> CGSize {
    let aspect = canvasSize.width / canvasSize.height
    if maxSize.width / maxSize.height > aspect {
        return CGSize(
            width: (maxSize.height * aspect).rounded(),
            height: maxSize.height
        )
    } else {
        return CGSize(
            width: maxSize.width,
            height: (maxSize.width / aspect).rounded()
        )
    }
}

private func firstHeading(in url: URL) -> String? {
    guard let source = try? String(contentsOf: url, encoding: .utf8) else {
        return nil
    }
    let trimmed = MudCore.extractHeadings(source)
        .first?.text
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return (trimmed?.isEmpty ?? true) ? nil : trimmed
}

/// The heading as drawn, with the Markdown `#` it would carry in source.
private func displayHeading(_ heading: String) -> String {
    "# " + heading
}

private func loadBundledImage(named name: String) -> CGImage? {
    guard
        let url = Bundle.main.url(forResource: name, withExtension: "png"),
        let source = CGImageSourceCreateWithURL(url as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return image
}

// MARK: - Line breaking

/// UTF-16 units a line may legitimately end on. Anything else means the
/// typesetter ran out of room mid-word and chopped it.
private let breakCharacters: Set<UInt16> = [
    0x20,    // space
    0x09,    // tab
    0x0A,    // newline
    0x2D,    // hyphen-minus
    0x2F,    // solidus
    0x2010,  // hyphen
    0x2013,  // en dash
    0x2014,  // em dash
]

/// Greedy line breaks for `attr`, as typesetter ranges. `width` is asked
/// for each line in turn, so the block can be shaped around the curl
/// rather than run at one width throughout.
private func lineBreaks(
    _ attr: NSAttributedString, width: (Int) -> CGFloat
) -> [CFRange] {
    guard attr.length > 0 else { return [] }
    let typesetter = CTTypesetterCreateWithAttributedString(
        attr as CFAttributedString
    )
    var start = 0
    var out: [CFRange] = []
    while start < attr.length {
        let lineWidth = width(out.count)
        guard lineWidth > 1 else { break }
        let count = CTTypesetterSuggestLineBreak(
            typesetter, start, Double(lineWidth)
        )
        if count <= 0 { break }
        out.append(CFRange(location: start, length: count))
        start += count
        if out.count > 40 { break }
    }
    return out
}

/// Index of the first line that ends mid-word, if any.
/// `CTTypesetterSuggestLineBreak` breaks between characters when no break
/// opportunity fits, so a narrow width can keep the line *count* while
/// shredding the words — this is the guard that catches it.
private func firstMidWordBreak(_ ranges: [CFRange], text: String) -> Int? {
    guard ranges.count > 1 else { return nil }
    let units = Array(text.utf16)
    for (index, range) in ranges.enumerated().dropLast() {
        let end = range.location + range.length
        guard end > 0, end <= units.count else { continue }
        if !breakCharacters.contains(units[end - 1]) { return index }
    }
    return nil
}

private func breaksMidWord(_ ranges: [CFRange], text: String) -> Bool {
    firstMidWordBreak(ranges, text: text) != nil
}

/// Narrowest box width that still wraps to `target` lines without
/// breaking a word — CSS `text-wrap: balance` by binary search. Evens the
/// rag instead of leaving a widow.
///
/// It searches the *box* width; `width` re-applies the curl's own limit
/// on top of each candidate, so balancing can never widen a line past the
/// curl. Only a validated width is ever assigned to `hi`, so whatever
/// comes back satisfies both conditions even though line count isn't
/// strictly monotonic in width.
private func balancedWidth(
    _ attr: NSAttributedString, maxWidth: CGFloat, target: Int,
    width: (Int, CGFloat) -> CGFloat
) -> CGFloat {
    guard target > 1 else { return maxWidth }
    var lo = maxWidth * 0.3
    var hi = maxWidth
    for _ in 0..<20 {
        let mid = (lo + hi) / 2
        let ranges = lineBreaks(attr) { width($0, mid) }
        if ranges.count <= target, !breaksMidWord(ranges, text: attr.string) {
            hi = mid
        } else {
            lo = mid
        }
    }
    return hi
}

// MARK: - Drawing

private func attributes(
    font: NSFont, tracking: CGFloat
) -> [NSAttributedString.Key: Any] {
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: headingColor,
    ]
    if tracking != 0 {
        attrs[NSAttributedString.Key(kCTKernAttributeName as String)] = tracking
    }
    return attrs
}

private struct HeadingLayout {
    let lines: [CTLine]
    let font: NSFont
    let lineHeight: CGFloat
    let box: CGRect
}

/// Sets `heading` into `box`, picking the largest ladder rung that fits.
///
/// With `avoidingCurl`, lines reaching into the curl's band are shortened
/// to clear it — and if even that can't be done without breaking a word,
/// this returns nil so the caller can retry lower down the page. Without
/// it, every line runs the full box width and the layout always succeeds
/// (a mid-word break becomes a truncation instead).
private func layOutHeading(
    _ heading: String, in box: CGRect, avoidingCurl: Bool, size: CGSize
) -> HeadingLayout? {
    let scale = size.height / canvasSize.height
    let boxWidth = box.width * scale
    let boxHeight = box.height * scale

    // Drop ladder rungs that would land below legibility, then treat the
    // last surviving rung as the fallback. Every rung below the floor
    // means a reply that can only ever be suggestive of a title: draw it
    // anyway, at the largest rung there is — a blank card says less.
    var ladder = sizeLadder.filter { $0 * scale >= minDeviceFontSize }
    if ladder.isEmpty, let largest = sizeLadder.first {
        ladder = [largest]
    }

    for (index, refSize) in ladder.enumerated() {
        let deviceSize = refSize * scale
        let font = NSFont.systemFont(ofSize: deviceSize, weight: headingWeight)
        let tracking = deviceSize >= trackingThreshold
            ? trackingRatio * deviceSize : 0
        let attrs = attributes(font: font, tracking: tracking)
        let attr = NSAttributedString(string: heading, attributes: attrs)

        let lineHeight = (font.ascender - font.descender) * lineHeightRatio

        // Width for line `i` given a box limit: while a line's top falls
        // in the curl's band it is pulled in to clear the curl. The band
        // is in reference coordinates, so the line's top converts back
        // through `scale`.
        let width: (Int, CGFloat) -> CGFloat = { i, limit in
            guard avoidingCurl else { return limit }
            let top = box.origin.y + CGFloat(i) * lineHeight / scale
            guard top < curlBottom else { return limit }
            return min(limit, (curlLeft - curlGutter - box.minX) * scale)
        }

        let breaks = lineBreaks(attr) { width($0, boxWidth) }
        guard !breaks.isEmpty else { return nil }

        // How many lines this rung can actually show: the box height is
        // what binds, with `maxLines` only as a ceiling. Deriving it per
        // rung keeps the fit test and the draw cap in agreement.
        let cap = min(
            maxLines, max(1, Int((boxHeight / lineHeight).rounded(.down)))
        )
        // A word too wide for its line gets chopped by the typesetter, so
        // treat that as "doesn't fit" and step down until the longest
        // word lands on one line.
        let fits = breaks.count <= cap && !breaksMidWord(breaks, text: heading)
        let isLast = index == ladder.count - 1

        guard fits || isLast else { continue }

        // Balance only when the text genuinely fits; a truncated block
        // should use every pixel of width it has.
        let limit = fits
            ? balancedWidth(
                attr, maxWidth: boxWidth, target: breaks.count, width: width
            )
            : boxWidth
        let ranges = fits ? lineBreaks(attr) { width($0, limit) } : breaks

        // Out of rungs and still splitting a word: shaping around the
        // curl has failed for this heading. Report it, so it can be set
        // below the curl at full width instead of losing everything after
        // the split to the truncation below.
        if avoidingCurl, breaksMidWord(ranges, text: heading) { return nil }

        // Never render a word split across two lines. Only the fallback
        // rung can produce one — `balancedWidth` rejects such candidates
        // outright — so cut the block at the split and let the ellipsis
        // say there is more.
        var drawCap = cap
        if let split = firstMidWordBreak(ranges, text: heading) {
            drawCap = min(drawCap, split + 1)
        }

        let typesetter = CTTypesetterCreateWithAttributedString(
            attr as CFAttributedString
        )
        var lines: [CTLine] = []
        for (i, range) in ranges.enumerated() {
            if i >= drawCap { break }
            if i == drawCap - 1, ranges.count > drawCap {
                // Typeset to the end of the string so CoreText knows
                // there is more, then truncate that line.
                let rest = CTTypesetterCreateLine(
                    typesetter, CFRange(location: range.location, length: 0)
                )
                let token = CTLineCreateWithAttributedString(
                    NSAttributedString(string: "…", attributes: attrs)
                )
                let truncated = CTLineCreateTruncatedLine(
                    rest, Double(width(i, limit)), .end, token
                )
                lines.append(truncated ?? CTTypesetterCreateLine(typesetter, range))
            } else {
                lines.append(CTTypesetterCreateLine(typesetter, range))
            }
        }
        return HeadingLayout(
            lines: lines, font: font, lineHeight: lineHeight, box: box
        )
    }
    return nil
}

private func drawHeading(
    _ heading: String, size: CGSize, context: CGContext
) {
    // Shape the heading around the curl if it can be done without
    // breaking a word; otherwise set it below the curl at full width.
    let text = displayHeading(heading)
    let layout = layOutHeading(
        text, in: textBox, avoidingCurl: true, size: size
    ) ?? layOutHeading(
        text, in: textBoxBelowCurl, avoidingCurl: false, size: size
    )
    guard let layout, !layout.lines.isEmpty else { return }

    // Align the first line's cap height to the box top, so the box edge
    // reads as the optical top of the text with no ascender gap. CG's
    // origin is bottom-left and reference coordinates are top-down, so a
    // baseline at `y` draws at `size.height - y`.
    let scale = size.height / canvasSize.height
    let left = layout.box.origin.x * scale
    let top = layout.box.origin.y * scale
    context.textMatrix = .identity
    for (i, line) in layout.lines.enumerated() {
        let baseline = top + layout.font.capHeight
            + CGFloat(i) * layout.lineHeight
        context.textPosition = CGPoint(x: left, y: size.height - baseline)
        CTLineDraw(line, context)
    }
}

private func drawThumbnail(
    overlay: CGImage, heading: String, size: CGSize
) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    context.interpolationQuality = .high
    let fullRect = CGRect(origin: .zero, size: size)

    cardColor.setFill()
    context.fill(fullRect)

    // `size` is always 3:4 portrait, so scaling by height is uniform.
    drawHeading(heading, size: size, context: context)

    context.draw(overlay, in: fullRect)
}
