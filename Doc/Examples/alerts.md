Alerts and asides
===============================================================================

This document exercises both GFM alert syntax (`[!TYPE]`) and DocC aside syntax
(`Tag: content`), plus several blockquotes that should render as plain
blockquotes.

Six common alert categories exist: Note, Tip, Important, Status, Warning, and
Caution. Each has a GFM form and a DocC form. DocC also has extended aliases
that map to one of these six categories.


## GFM alerts

> [!NOTE]
> Highlights information that users should take into account, even when
> skimming.

> [!TIP]
> Optional information to help a user be more successful.

> [!IMPORTANT]
> Crucial information necessary for users to succeed.

> [!STATUS]
> Indicates the current state of a document or task.

> [!WARNING]
> Critical content demanding immediate user attention due to
> potential risks.

> [!CAUTION]
> Negative potential consequences of an action.


## GFM alerts with rich content

> [!NOTE]
> Alerts can contain **bold**, _italic_, `inline code`, and
> [links](https://example.com).
>
> They can also have multiple paragraphs.

> [!TIP]
> Here is a code block inside an alert:
>
> ```swift
> let x = 42
> ```

> [!WARNING]
>
> - First item
> - Second item
> - Third item


## DocC asides — common forms

DocC asides are written as a blockquote whose first line is `Tag: content`.
Short same-line content (under 60 characters) is bolded inline; longer content
falls to the paragraph below.

> Note: Short same-line content is bolded.
>
> A second paragraph follows when a blank line separates it.

> Tip: DocC tip with _formatted_ content.

> Important: This is important information.

> Status: Planning

> Status: Underway
>
> X and Y have been implemented. Implementation of Z is underway.

> Status: Complete. All features shipped.

> Status: Complete
>
> All features shipped. No outstanding issues.

> Warning: Careful with this operation. It may have side effects that are
> difficult to reverse.

> Caution: Contents hot!


## DocC asides — extended forms

By default, Mud also recognises these DocC alias blockquote prefixes. Extended
aliases render as their mapped common category (same color and icon). They can
be disabled in Up Mode settings.


### Note

> Remark: An observation worth calling out.

> Complexity: O(n log n) in the worst case.

> Author: Jane Doe

> Authors: Jane Doe, John Smith

> Copyright: 2026 Example Corp.

> Date: 2026-02-28

> Since: Version 2.0

> Version: 3.1.4

> SeeAlso: `relatedMethod()` for an alternative approach.

> MutatingVariant: Use `sort()` to sort in place.

> NonMutatingVariant: Use `sorted()` to get a new sorted array.


### Status

> ToDo: Refactor this to use the new API.


### Tip

> Experiment: Try changing the value to see what happens.


### Important

> Attention: Pay close attention to this detail.


### Warning

> Precondition: The array must be sorted in ascending order.

> Postcondition: The return value is always non-negative.

> Requires: Swift 5.9 or later.

> Invariant: The count property is always equal to the number of elements.


### Caution

> Bug: This method crashes when passed an empty array.

> Throws: `InvalidArgumentError` if the input is nil.

> Error: An unrecoverable failure occurred.


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
