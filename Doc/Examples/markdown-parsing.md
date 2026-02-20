Heading 1
===============================================================================

## Heading 2

### Heading 3 with `inline code`

#### Heading 4 with **bold** and *italic*

##### Heading 5

###### Heading 6

## Emphasis

*single asterisk italic* _single underscore italic_ **double asterisk bold**
__double underscore bold__ ***bold and italic*** ___bold and italic___ **bold
with *nested italic* inside** *italic with **nested bold** inside*


## Strikethrough

~~deleted text~~ ~~strikethrough with **bold** inside~~ **bold with
~~strikethrough~~ inside**


## Inline code

Use `printf()` to print. Backtick escaping: `` `literal backtick` `` Empty
backticks: `` (not code) Code with special chars: `<div class="foo">&amp;</div>`


## Code blocks

```swift
func greet(_ name: String) -> String {
    return "Hello, \(name)!"
}
```

```
Plain code block with no language tag.
    Indented content here.
```

    Indented code block (four spaces).
    Second line.


## Links and images

[simple link](https://example.com)
[link with title](https://example.com "Example")
[link with **bold** text](https://example.com) ![alt text](image.png)
![](empty-alt.png) [reference link][ref] [![image inside link](icon.png)
](https://example.com)

[ref]: https://example.com


## Block quotes

> Simple block quote.

> Multi-line block
  quote spanning two lines.

> > Nested block quote.

> Block quote with **bold**, *italic*, and `code`.

> Block quote with a list:
    - item one
    - item two


## Lists

- unordered dash
- second item
  - nested item - deeply nested
* unordered asterisk
* second item
+ unordered plus
1. ordered
2. second
3. third
1. ordered with **bold** item
2. item with `code`
3. item with [a link](https://example.com)
100. large number marker
101. next item
- [ ] unchecked task
- [x] checked task


## Thematic breaks


---


***


___


## Mixed / edge cases

A paragraph with **bold**, *italic*, `code`, [link](url), ~~struck~~, and
![img](i.png) all on one line.

**bold at start** and at **end of line**

*italic at start* and at *end of line*

Bare URL: https://example.com/path?q=1&r=2

Adjacent markers: **bold***italic*`code`

> > > Triple-nested block quote with **bold**.

- list with > not a blockquote
- `code` at start of list item
1. First
   - Mixed 1. Nesting - Deep

*Emphasis across
two lines* is tricky.

**Bold across
two lines** likewise.


## Unicode stress

**日本語の太字** *émphasis with àccénts* `코드 인라인` [링크](https://example.com)
~~зачёркнутый~~

Emoji in **bold 🎉** and *italic 🚀* and `code 💻`.

CJK: 你好世界。**粗体**和*斜体*混合。


## Empty / degenerate

#

##

- * 1.

>

```

```

[](empty-link) ![](empty-image)
