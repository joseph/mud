Alerts and asides
===============================================================================

This document exercises both GFM alert syntax (`[!TYPE]`) and DocC aside syntax
(`Tag: content`), plus several blockquotes that should render as plain
blockquotes.


## GFM alerts

> [!NOTE]
> Highlights information that users should take into account, even when
> skimming.

> [!TIP]
> Optional information to help a user be more successful.

> [!IMPORTANT]
> Crucial information necessary for users to succeed.

> [!WARNING]
> Critical content demanding immediate user attention due to
> potential risks.

> [!CAUTION]
> Negative potential consequences of an action.


## GFM alerts with rich content

> [!NOTE] Alerts can contain **bold**, _italic_, `inline code`, and
> [links](https://example.com).
>
> They can also have multiple paragraphs.

> [!TIP] Here is a code block inside an alert:
>
> ```swift
> let x = 42
> ```

> [!WARNING]
>
> - First item
> - Second item
> - Third item


## DocC asides

> Note: This is a DocC-style note aside.

> Tip: DocC tip with **formatted** content.

> Important: This is important information.

> Warning: Careful with this operation. It may have side effects that are
> difficult to reverse.

> Remark: An observation worth calling out.

> Experiment: Try changing the value to see what happens.

> Attention: Pay close attention to this detail.

> Bug: This method crashes when passed an empty array.

> Throws: `InvalidArgumentError` if the input is nil.

> Precondition: The array must be sorted in ascending order.

> Postcondition: The return value is always non-negative.

> Requires: Swift 5.9 or later.

> Invariant: The count property is always equal to the number of elements.

> Complexity: O(n log n) in the worst case.

> Author: Jane Doe

> Authors: Jane Doe, John Smith

> Copyright: 2026 Example Corp.

> Date: 2026-02-28

> Since: Version 2.0

> Version: 3.1.4

> SeeAlso: `relatedMethod()` for an alternative approach.

> ToDo: Refactor this to use the new API.


## Plain blockquotes (should NOT render as alerts)

> This is a regular blockquote. It has no alert tag at all and should look like
> an ordinary blockquote with a gray border.

> "To be, or not to be, that is the question." — Shakespeare

> Summary: this looks like a tag but "Summary" is not a recognised alert kind,
> so it should render as a plain blockquote.

> Hello: same idea here. An unknown word before a colon should not trigger
> alert styling.

> 42: a number followed by a colon is not a tag.

> [https://example.com](https://example.com): a URL is not a tag.

> The note about performance is important, but this blockquote does not start
> with a recognised tag word followed by a colon.
