Limitations of the App Store version
===============================================================================

Mud is really easy to install via the Mac App Store. And if you trust Apple's
vetting of apps that are published to the store, then you can feel more
confident about the safety of Mud.

But the version of Mud we publish to the App Store is somewhat limited, because
it is _sandboxed_.

The main implication of sandboxing is that Mud is prevented from accessing any
part of the filesystem other than the document you open.

That's reasonable. But if, say, your document contains image references with
local paths, Mud will not be able to render those images, because it only has
permission to access the file you chose to open, not other files in nearby
directories.


## What's affected

- Local images will not load (alt text is shown instead)
- Links to other local markdown files will not open
- Open in Browser is not available
- Command Line Tool installation is manual (no Install button)
- No automatic updates (the App Store handles updates instead)


## Solution

If you are happy with these limitations, continue to use the App Store version!

If these limitations are getting in your way, download the app directly from
[GitHub](https://github.com/joseph/mud/releases). The direct version is not
sandboxed, and it is notarized and includes automatic updates via Sparkle.
