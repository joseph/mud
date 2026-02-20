import Foundation

/// Splits an HTML string containing `<span>` tags into per-line
/// strings, closing and reopening open tags at each line boundary
/// so every line is independently well-formed HTML.
enum HTMLLineSplitter {

    /// Split `html` at newline characters, balancing `<span>` tags
    /// across the split.
    static func splitByLine(_ html: String) -> [String] {
        var lines: [String] = []
        var current = ""
        var openTags: [String] = []
        var i = html.startIndex

        while i < html.endIndex {
            if html[i] == "\n" {
                for _ in openTags { current += "</span>" }
                lines.append(current)
                current = ""
                for tag in openTags { current += tag }
                i = html.index(after: i)
            } else if html[i] == "<" {
                if html[i...].hasPrefix("</span>") {
                    current += "</span>"
                    if !openTags.isEmpty { openTags.removeLast() }
                    i = html.index(i, offsetBy: 7)
                } else if html[i...].hasPrefix("<span") {
                    guard let gt = html[i...].firstIndex(of: ">")
                    else {
                        current.append(html[i])
                        i = html.index(after: i)
                        continue
                    }
                    let end = html.index(after: gt)
                    let tag = String(html[i..<end])
                    openTags.append(tag)
                    current += tag
                    i = end
                } else {
                    current.append(html[i])
                    i = html.index(after: i)
                }
            } else {
                current.append(html[i])
                i = html.index(after: i)
            }
        }

        lines.append(current)
        if lines.count > 1, lines.last == "" {
            lines.removeLast()
        }
        return lines
    }
}
