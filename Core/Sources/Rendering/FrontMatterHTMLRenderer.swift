import Foundation

/// Renders YAML frontmatter for both modes: the collapsible table block that
/// precedes an Up-mode body, and the syntax-highlighted source lines that
/// Down mode's layout builder consumes.
enum FrontMatterHTMLRenderer {
    /// Renders YAML frontmatter as a collapsible HTML block for
    /// Up mode. Parses top-level keys into a table; falls back to
    /// a raw code block if no keys are found.
    static func upModeHTML(_ yaml: String) -> String {
        let keys = FrontMatterExtractor.parseTopLevelKeys(yaml)

        var html = "<details class=\"mud-frontmatter\">"
        html += "<summary>Frontmatter</summary>"

        if keys.isEmpty {
            html += "<pre><code class=\"language-yaml\">"
            html += HTMLEscaping.escape(yaml)
            html += "</code></pre>"
        } else {
            html += "<table class=\"mud-frontmatter-table\">"
            for kv in keys {
                html += "<tr>"
                html += "<th class=\"fm-key\">"
                html += HTMLEscaping.escape(kv.key)
                html += "</th><td>"
                switch kv.value {
                case .scalar(let v):
                    html += HTMLEscaping.escape(v)
                case .inlineArray(let items):
                    html += HTMLEscaping.escape(items.joined(separator: ", "))
                case .block(let raw):
                    html += "<pre>"
                    html += HTMLEscaping.escape(raw)
                    html += "</pre>"
                }
                html += "</td></tr>"
            }
            html += "</table>"
        }

        html += "</details>"
        return html
    }

    /// Renders frontmatter lines from the original source with YAML
    /// syntax highlighting via `CodeHighlighter`.
    ///
    /// Returns an array of HTML content strings (one per
    /// frontmatter source line) ready for use in `CMarkDownHTMLVisitor`'s
    /// `buildLayout`. The input `markdown` should already be
    /// `\r\n`-normalized (see `ParsedMarkdown.init`).
    static func downModeLines(
        markdown: String, lineCount: Int
    ) -> [String] {
        guard lineCount > 0 else { return [] }

        let allLines = markdown.split(
            separator: "\n", omittingEmptySubsequences: false)
        guard allLines.count >= lineCount else { return [] }

        var rendered = [String]()
        rendered.reserveCapacity(lineCount)

        // First and last lines are the `---` delimiters.
        let openingDelimiter = HTMLEscaping.escape(String(allLines[0]))
        rendered.append(
            "<span class=\"md-code-fence\">\(openingDelimiter)</span>")

        // YAML content lines (between delimiters).
        if lineCount > 2 {
            let yamlLines = allLines[1..<(lineCount - 1)]
            let yamlText = yamlLines.joined(separator: "\n")

            if let highlighted = CodeHighlighter.highlight(
                yamlText, language: "yaml")
            {
                rendered += HTMLLineSplitter.splitByLine(highlighted)
            } else {
                for line in yamlLines {
                    rendered.append(HTMLEscaping.escape(String(line)))
                }
            }
        }

        // Closing delimiter.
        let closingDelimiter = HTMLEscaping.escape(
            String(allLines[lineCount - 1]))
        rendered.append(
            "<span class=\"md-code-fence\">\(closingDelimiter)</span>")

        return rendered
    }
}
