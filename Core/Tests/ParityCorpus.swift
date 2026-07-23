import Testing

/// One shared, reusable markdown corpus. Each document isolates one feature
/// or node type so a failure names what broke. `GoldenRenderingTests` renders
/// this set to checked-in HTML fixtures, `CommentAnchorParityTests` draws its
/// anchoring corpus from here, and several diff suites reuse the documents.
/// It began as the Stage 0 corpus for the single-parser-rendering migration
/// (Doc/Plans/Archive/2026-07-single-parser-rendering.md).
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

  /// A setext heading's raw cmark end position is (line after the underline,
  /// column 0) — the one node shape whose end column is 0 — so this document
  /// pins the blind end-position conversion `CMarkDocument.range(of:)` shares
  /// with swift-markdown. The frontMatter document below also hits it, but
  /// only by accident (its YAML block parses as a setext heading).
  static let setextHeadings = Document(
    name: "setextHeadings",
    markdown: """
      Top-level setext heading
      ========================

      Second-level *setext* heading
      -----------------------------

      A paragraph between the setext headings.
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

  /// Footnote numbering is assigned Mud-side in first-reference order over
  /// authorial references only, in the render visitor. References
  /// arrive out of definition order; a repeated reference exercises the
  /// occurrence-suffixed back-link ids; the interleaved comment consumes no
  /// number; the undefined reference stays literal text; and the orphan
  /// definition renders nothing.
  static let footnoteNumbering = Document(
    name: "footnoteNumbering",
    markdown: """
      Second-defined[^beta] then a comment[^comment-note] then
      first-defined[^alpha] and beta again[^beta].

      An undefined reference[^missing] stays literal text.

      [^alpha]: Alpha body, defined first.

      [^beta]: Beta body, defined second.

      [^unrefd]: Never referenced; renders nothing.

      [^comment-note]: > then a comment

          💬 {Tester @ 2026-07-08 12:00:00}:

          A comment thread body.
      """)

  /// A GFM alert with content on the tag line (the `after` path in the
  /// alert-content emitter) and one with multiple body paragraphs.
  static let gfmAlertVariants = Document(
    name: "gfmAlertVariants",
    markdown: """
      > [!TIP] Same-line content after the tag.
      > A second line in the first paragraph.

      > [!CAUTION]
      > First body paragraph.
      >
      > Second body paragraph.
      """)

  /// DocC asides beyond the long-roman case in `alertBodyParagraphs`: a
  /// short same-line body (bolded on the title line) with a continuation, a
  /// two-word display name (`SeeAlso` → "See Also"), and the `Don't:` input
  /// whose smart-typography apostrophe makes the tag unrecognized, so it
  /// renders as a plain blockquote.
  static let docCAsideVariants = Document(
    name: "docCAsideVariants",
    markdown: """
      > Note: Short note bolded on the title line.
      > Continuing body after the soft break.

      > SeeAlso: The two-word display name.

      > Don't: the smart-typography apostrophe makes this tag unrecognized,
      > so the blockquote renders plain.
      """)

  static let rawHTML = Document(
    name: "rawHTML",
    markdown: """
      <div class="wrapper">
        <p>A raw HTML block passes through verbatim.</p>
      </div>

      A paragraph with <em>inline HTML</em> and <br/> tags.

      <!-- an HTML comment block -->

      Closing paragraph.
      """)

  static let linkVariants = Document(
    name: "linkVariants",
    markdown: """
      A [titled link](https://example.org "The title") in prose.

      An angle autolink <https://example.org/auto> in prose.

      A [reference link][ref] and a [shortcut ref] in prose.

      An image with a title ![drip](drip.png "Drip title") inline.

      [ref]: https://example.org/ref "Ref title"
      [shortcut ref]: https://example.org/shortcut
      """)

  /// Bare, extended autolinks — the GFM `autolink` extension's job. Angle
  /// autolinks and bracketed links live in `linkVariants`; these are the bare
  /// forms only the extension detects: a naked URL, a `www.` host, and a bare
  /// email. The code span is a negative case — autolink must not fire inside
  /// code.
  static let autolinkVariants = Document(
    name: "autolinkVariants",
    markdown: """
      Visit https://example.org/bare for the details.

      Or start at www.example.org instead.

      Mail hi@example.org with questions.

      Not a link in `https://example.org/code` inside a code span.
      """)

  /// Code blocks beyond the plain `swift` fence in
  /// `codeBlockAndThematicBreak`: a multi-word info string, an indented code
  /// block (no info string at all), and a bare fence. The closing paragraph
  /// keeps the document from being all code blocks, so the diff and anchor
  /// suites that reuse it have at least one text inline to collect.
  static let codeBlockVariants = Document(
    name: "codeBlockVariants",
    markdown: """
      ```swift attributes=here
      let fenced = "with a multi-word info string"
      ```

          an indented code block line
          a second indented line

      ```
      a bare fence with no info string
      ```

      Prose after the code blocks.
      """)

  static let orderedListStart = Document(
    name: "orderedListStart",
    markdown: """
      3. Starts at three
      4. Continues at four
      """)

  /// Definition bodies for Down mode: inline constructs across a lazy
  /// continuation line, a reference *inside* a body (Down highlights nothing
  /// there — an in-body reference renders as plain text), a blockquote body,
  /// and a two-line GFM alert body (the alert `>` markers take a different
  /// column offset on the opener line than on continuation lines). Every
  /// definition is referenced: cmark unlinks orphan definitions, whose Down
  /// rendering deliberately diverges — pinned in `DownRenderingTests`.
  static let footnoteDefBodyVariants = Document(
    name: "footnoteDefBodyVariants",
    markdown: """
      Ref one[^inline] and two[^nested] and three[^quoted] and
      four[^alerted].

      [^inline]: A body with **bold**, `code`, and a [link](https://example.org),
          continuing on an indented line.

      [^nested]: This body references[^inline] the first note.

      [^quoted]: > A quoted line inside the body.

      [^alerted]: > [!NOTE]
          > A second alert line inside the body.
      """)

  /// Code blocks inside definition bodies: span-colored but never
  /// highlight.js-rendered and never given `dc-*` line roles. The fence's
  /// last content line is blank — the one shape where the close-column
  /// arithmetic can't be simplified to the raw line width.
  static let footnoteDefCodeBlocks = Document(
    name: "footnoteDefCodeBlocks",
    markdown: """
      Code refs[^fenced] and[^indented].

      [^fenced]: A body opening paragraph.

          ```swift
          let inDefBody = true

          ```

      [^indented]: An opener paragraph.

              an indented code line in the body
              a second indented line
      """)

  /// A definition in the middle of the document. cmark parses it as a real
  /// definition node between two paragraphs — the one surrounding shape that
  /// renders identically in both modes. A definition between two *lists*
  /// splits them (cmark ends the first list at the definition), so that
  /// shape lives in `DownRenderingTests` (where Down's spanless list
  /// rendering keeps the bytes equal) and is excluded here, where it would
  /// fail the Up sweep.
  static let footnoteDefMidDocument = Document(
    name: "footnoteDefMidDocument",
    markdown: """
      Opening ref[^mid] paragraph.

      [^mid]: A definition between two paragraphs.

      A middle paragraph after the definition.

      A closing paragraph.
      """)

  /// Whitespace after a DocC aside's colon: the tag span must cover `Note:`
  /// only, excluding the trailing spaces — `docCTagSpanWidth` measures the
  /// literal through the colon, not `detectDocCAlert`'s whitespace-inclusive
  /// `tagByteLength`.
  static let docCAsideTrailingSpaces = Document(
    name: "docCAsideTrailingSpaces",
    markdown: """
      > Note:   Three spaces follow the colon before this content.

      > Warning:  Two spaces after the colon on the core-map path.
      """)

  /// The documents whose rendered output depends on `DocCAlertMode` —
  /// blockquotes that may parse as DocC asides. `GoldenRenderingTests` sweeps
  /// these across the non-default alert modes; every other corpus document
  /// renders identically regardless of mode and is pinned at the default mode
  /// only. Keep this in sync when adding a document with an aside-shaped
  /// blockquote.
  static let docCVariants: [Document] = [
    alertBodyParagraphs, gfmAlertVariants, docCAsideVariants,
    docCAsideTrailingSpaces,
  ]

  static let all: [Document] = [
    paragraphsWithInlineSyntax, hardBreakParagraph, headings, listItems,
    taskListItems, blockquoteParagraphs, alertBodyParagraphs, tableCells,
    duplicateBlocks, smartTypography, setextHeadings, frontMatter,
    codeBlockAndThematicBreak, footnoteNumbering, gfmAlertVariants,
    docCAsideVariants, rawHTML, linkVariants, autolinkVariants,
    codeBlockVariants, orderedListStart, footnoteDefBodyVariants,
    footnoteDefCodeBlocks, footnoteDefMidDocument, docCAsideTrailingSpaces,
  ]
}
