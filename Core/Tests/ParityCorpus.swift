import Testing

/// One shared, reusable markdown corpus for the single-parser-rendering
/// migration (Doc/Plans/2026-07-single-parser-rendering.md, Stage 0). Each
/// document isolates one feature or node type so a failure names what broke.
/// `CommentAnchorParityTests` draws its anchoring corpus from here today; the
/// planned Stage 1+ dual-pipeline comparison will render this same set
/// through both parsers and assert byte-identical HTML.
enum ParityCorpus {
  struct Document: Sendable, CustomTestStringConvertible {
    let name: String
    let markdown: String

    var testDescription: String { name }
  }

  static let paragraphsWithInlineSyntax = Document(
    name: "paragraphsWithInlineSyntax",
    markdown: """
      The quick *brown* **fox** jumps over the `lazy` dog.

      A [link](https://example.org) and an image ![drip](drip.png) inline.

      Ampersand & angle < bracket > text with "quotes" and it's fine.

      Emoji :tada: shortcode and ~~struck~~ text.

      A paragraph that continues
      across two source lines.

      A footnote[^1] and a comment[^comment-a] reference.

      [^1]: The footnote body.

      [^comment-a]: A comment body.
      """)

  static let hardBreakParagraph = Document(
    name: "hardBreakParagraph",
    markdown: "Line one  \nLine two continues.\n")

  static let headings = Document(
    name: "headings",
    markdown: """
      # Top heading

      ## Second *level* heading

      ### Third with `code`

      #### Fourth

      ##### Fifth

      ###### Sixth
      """)

  static let listItems = Document(
    name: "listItems",
    markdown: """
      - First tight item
      - Second tight item with **bold**
        - Nested item

      1. Ordered one
      2. Ordered two

      - Loose item one

        Second paragraph of the loose item.

      - Loose item two
      """)

  static let taskListItems = Document(
    name: "taskListItems",
    markdown: """
      - [ ] Unchecked task
      - [x] Checked task
      """)

  static let blockquoteParagraphs = Document(
    name: "blockquoteParagraphs",
    markdown: """
      > A quoted paragraph.
      >
      > A second quoted paragraph.

      Plain text after.
      """)

  static let alertBodyParagraphs = Document(
    name: "alertBodyParagraphs",
    markdown: """
      > [!NOTE]
      > The note body paragraph.

      > Warning: This DocC aside body is long enough that the renderer keeps it
      > roman in its own paragraph instead of bolding it on the title line.
      """)

  static let tableCells = Document(
    name: "tableCells",
    markdown: """
      | Name | Value |
      | ----- | ------ |
      | alpha | **one** |
      | beta | two |
      """)

  static let duplicateBlocks = Document(
    name: "duplicateBlocks",
    markdown: """
      Repeated text.

      Unique middle.

      Repeated text.
      """)

  /// Straight quotes, an apostrophe, an en dash, an em dash, and an ellipsis —
  /// every literal `CMARK_OPT_SMART` rewrites. Absent from the rest of the
  /// corpus on purpose, so this document is the one place a lost `SMART` flag
  /// would show up.
  static let smartTypography = Document(
    name: "smartTypography",
    markdown: """
      "Curly double quotes" and 'curly single quotes' surround this sentence.

      It's a contraction, and the dog's bone -- separated by an en dash, or a
      sentence---separated by an em dash.

      Wait for it... the ellipsis converts too.
      """)

  static let frontMatter = Document(
    name: "frontMatter",
    markdown: """
      ---
      title: Front-matter corpus document
      tags: [markdown, yaml]
      nested:
        depth: 1
      ---

      # Body heading

      Body paragraph after front matter.
      """)

  static let codeBlockAndThematicBreak = Document(
    name: "codeBlockAndThematicBreak",
    markdown: """
      ```swift
      let value = 1
      ```

      -------------------------------------------------------------------------------

      Text after a thematic break.
      """)

  static let all: [Document] = [
    paragraphsWithInlineSyntax, hardBreakParagraph, headings, listItems,
    taskListItems, blockquoteParagraphs, alertBodyParagraphs, tableCells,
    duplicateBlocks, smartTypography, frontMatter, codeBlockAndThematicBreak,
  ]
}
