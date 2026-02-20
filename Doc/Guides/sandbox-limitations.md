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

* Local images will not load (alt text is shown instead)
* Links to other local markdown files will not open
* Open In Browser feature is not available
* Install Command Line Tool feature is not available


## Solution

If you are happy with these limitations, continue to use the App Store version!

If these limitations are getting in your way, download the app directly from
<https://apps.josephpearson.org/mud>. It's not sandboxed, but it is notarized.
