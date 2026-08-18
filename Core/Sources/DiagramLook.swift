/// How a Mermaid diagram's labels are lettered.
///
/// Only the face differs. Both looks take the page's palette, Mermaid's rough
/// outlines, and the watercolor wash — see `mermaid-init.js`. The name reaches
/// the page as the `--diagram-font` custom property, which the init script
/// reads and hands to Mermaid: Mermaid measures each label's box with the font
/// it was given, so a face applied in CSS alone would be laid out in boxes
/// sized for another one.
public enum DiagramLook: String, CaseIterable, Sendable {
    /// The page's own sans stack. The default, and the only look that ships no
    /// font of its own.
    case simplicity = "simplicity"
    /// Caveat, embedded as a data URI by `mud-diagram-font.css`. Roughly 100 KB
    /// on top of every document that draws a diagram, which is why the
    /// stylesheet is added for this look alone.
    case handwritten = "handwritten"
}
