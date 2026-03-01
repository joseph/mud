Emoji shortcodes
===============================================================================

This document exercises emoji shortcode replacement. Before implementation, all
shortcodes appear as literal `:name:` text. After implementation, known
shortcodes render as Unicode emoji in up mode; down mode always shows raw
source.


## Common shortcodes

:smile: :wave: :+1: :-1: :heart: :rocket: :star: :fire: :tada: :sparkles:


## Shortcodes in context

I gave this a :+1: because it was :fire:

Welcome to the team :wave: we're glad you're here :heart:


## Inline formatting

**:rocket: Launch plan** — shortcode inside strong

_:memo: Notes_ — shortcode inside emphasis

Check out [:link: the docs](https://example.com) — shortcode inside a link


## Headings with shortcodes

### :bug: Known issues

### :sparkles: What's new

## Shortcodes in lists

- :white_check_mark: Tests pass
- :construction: Work in progress
- :x: Blocked


## Should NOT be replaced

`:smile:` — shortcode inside inline code, should stay as literal text

```
:rocket: — shortcode inside a code block, should stay as literal text
```

:not_a_real_shortcode: — unknown shortcode, should stay as literal text

10:30:00 — time format, not a shortcode

C:\Users\name — backslash path, not a shortcode

:::: — empty between colons, not a shortcode
