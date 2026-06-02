Footnotes
===============================================================================

This document exercises GFM footnote syntax. A footnote has two parts: a
**reference** like `[^label]` in running text, and a **definition** like
`[^label]: text` somewhere in the document. Definitions can appear anywhere;
they are collected and rendered at the bottom of the document in the order they
were first referenced.


## Basic numeric labels

Here is a sentence with a single footnote reference.[^1] And here is another
sentence with a different footnote.[^2]

[^1]: This is the first footnote definition.

[^2]: This is the second footnote definition.


## Named labels

Footnote labels need not be numeric. They can be words[^named], hyphenated
phrases[^long-name], snake_case[^under_score], or mixed alphanumerics[^abc123].

[^named]: A footnote with a plain word label.

[^long-name]: A footnote with a hyphenated label.

[^under_score]: A footnote with an underscored label.

[^abc123]: A footnote with a mixed alphanumeric label.


## Case sensitivity

Labels match case-insensitively in GFM. A footnote defined as `[^Hello]` can be
referenced as `[^hello]`, `[^HELLO]`, or `[^Hello]` — all three should resolve
to the same definition.[^Hello]

[^Hello]: A footnote whose label resolves regardless of reference casing.


## Multiple references to the same footnote

The same footnote can be referenced more than once.[^repeat] When the user
clicks the link in the rendered footnote, they should be returned to whichever
reference they came from. Here is a second reference to the same
definition.[^repeat] And a third one[^repeat] for good measure.

[^repeat]: A single definition referenced three times.


## Forward references

A footnote can be referenced before its definition appears in source
order.[^forward] The renderer should still resolve it.

Earlier we also used `[^1]` and `[^2]`, which were defined immediately after
the reference — that is the common case. This section demonstrates the
opposite: the definition for `[^forward]` is far below, in the **Definitions
out of order** section.


## Definitions out of order

Definitions can appear anywhere in the document; the rendered output orders
them by first reference.

[^forward]: Defined later in the source than its first reference.

[^orphan]: This definition is never referenced. It should not appear in the
    rendered footnotes section, or it should appear marked as unused,
    depending on the renderer's policy.


## Multi-paragraph footnotes

A footnote definition can span multiple paragraphs. Continuation lines are
indented by four spaces (or one tab).[^multipara]

[^multipara]: This is the first paragraph of a multi-paragraph footnote.

    This is the second paragraph. It is part of the same footnote
    because it is indented under the definition.

    And a third paragraph, just to confirm the pattern holds.


## Footnotes with inline formatting

Footnote bodies are full Markdown, so they can contain **bold**, _italic_,
`inline code`, [links](https://example.com), and ~~strikethrough~~.[^rich]

[^rich]: A footnote with **bold**, _italic_, `inline code`, a
    [link](https://example.com), and ~~strikethrough~~ all in one body.


## Footnotes with block content

A footnote can contain block-level constructs — lists, code blocks, and
blockquotes — when continuation lines are indented.[^blocks]

[^blocks]: A footnote with a list and a code block:

    - first item
    - second item
    - third item

    ```swift
    let answer = 42
    ```

    > And a blockquote at the end.


## Footnotes in headings

### A heading with a footnote[^in-heading]

A footnote referenced inside a heading should still resolve, and the heading
should remain navigable from the outline sidebar.

[^in-heading]: Footnote referenced from a heading.


## Footnotes in lists

- First list item with a footnote.[^in-list-1]
- Second list item with a footnote.[^in-list-2]
- Third list item with no footnote.

[^in-list-1]: Footnote referenced from inside a list item.

[^in-list-2]: A second footnote, also inside a list item.


## Footnotes in blockquotes

> A blockquote that contains a footnote reference.[^in-quote] The reference
> should still resolve and the back-link should return the reader here.

[^in-quote]: Footnote referenced from inside a blockquote.


## Footnotes in tables

| Feature   | Notes                                 |
| --------- | ------------------------------------- |
| Cell ref  | Reference inside a cell.[^in-table-1] |
| Multi-ref | Same footnote twice.[^in-table-2]     |

[^in-table-1]: Footnote referenced from inside a table cell.

[^in-table-2]: Footnote referenced from inside a table cell, twice in the same
    table.


## Footnotes inside emphasis

A footnote reference inside _italic text[^in-em]_ and inside **bold
text[^in-strong]** should still resolve cleanly.

[^in-em]: Reference inside emphasis.

[^in-strong]: Reference inside strong.


## Empty definition body

A definition with no body[^empty-body] — the colon is present but nothing
follows.

[^empty-body]:


## Dangling reference

This sentence references a footnote that has no definition.[^missing] A
sensible renderer either leaves the reference as literal text or renders it
with a warning marker — but does not crash, and does not create an empty
footnote at the bottom.


## Should NOT be footnotes

These constructs look like footnote syntax but should render literally.

Inline code containing the syntax: `[^1]` and `[^1]: definition`.

```
[^1]
[^1]: This is inside a fenced code block and should render as raw text, not as
a footnote definition.
```

Escaped reference: \[^1\] should appear as bracketed text, not as a footnote
link.

Reference with an empty label: [^] — not a valid footnote.

Reference with whitespace in the label: [^foo bar] — not a valid footnote.

A definition must start at column zero. A line that begins indented under a
paragraph is treated as continuation text, not a definition — so a renderer
should not pick `[^buried]` out of a paragraph just because the line beneath it
reads like `    [^buried]: ...`.
