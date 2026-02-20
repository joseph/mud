Link Handling Test
===============================================================================

Open this file in Mud to test link behavior. Each section contains clickable
links that should behave as described.


## Anchor links

These should scroll within the document without opening anything external.

- [Jump to bottom of this document](#bottom)
- [Back to top](#link-handling-test)
- [Go to external URLs section](#external-urls)


## Local markdown files

These should open in a new Mud window (or focus the window if already open).

- [Stub file - same directory](./Resources/stub.md)
- [This file (should focus current window)](./link-handling.md)
- [Project plan - parent directory](../Plans/2026-02-mud-app.md)


## External URLs

These should open in your default web browser.

- [Example.com](https://example.com)
- [GitHub](https://github.com)
- [Apple](https://apple.com)


## Email links

These should open in your default mail client.

- [Send test email](mailto:test@example.com)
- [Email with subject](mailto:test@example.com?subject=Test%20from%20Mud)


## Other local files

These should open in the default app for that file type (not in Mud).

If you have these files in the same directory, they'll work:

- [Text file](./Resources/example.txt) — opens in TextEdit or default text editor
- [PDF file](./Resources/example.pdf) — opens in Preview or default PDF viewer


## Expected behavior summary

| Link type       | Example            | Action                                     |
| --------------- | ------------------ | ------------------------------------------ |
| Anchor          | `#section`         | Scroll within WebView                      |
| Local .md       | `./other.md`       | Open in Mud (new window or focus existing) |
| Local .markdown | `./other.markdown` | Open in Mud (new window or focus existing) |
| HTTPS           | `https://...`      | Open in default browser                    |
| HTTP            | `http://...`       | Open in default browser                    |
| Mailto          | `mailto:...`       | Open in default mail client                |
| Other files     | `./file.pdf`       | Open in default app for that type          |


## Bottom

You've reached the bottom. [Back to top](#link-handling-test)
