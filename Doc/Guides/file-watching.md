File watching
===============================================================================

How Mud keeps the preview in sync with the file on disk. The app monitors the
opened `.md` file and automatically re-renders whenever an external editor (or
any other process) modifies it.


## Components

Two pieces work together:

- **`FileWatcher`** (`App/FileWatcher.swift`) — a standalone class that wraps
  GCD dispatch sources to monitor a single file for changes.
- **`DocumentContentView`** (`App/DocumentContentView.swift`) — the SwiftUI
  view that creates the watcher and reloads content when it fires.


## How `FileWatcher` works

On init, `FileWatcher` opens the file with `O_EVTONLY` (a read-only descriptor
used purely for event monitoring) and creates a
`DispatchSourceFileSystemObject` on that descriptor. The source listens for
three kernel event types:

| Event     | Meaning                                   |
| --------- | ----------------------------------------- |
| `.write`  | File contents changed in place            |
| `.rename` | File was renamed (half of an atomic save) |
| `.delete` | File was deleted (half of an atomic save) |

**Plain writes** trigger the `onChange` callback immediately.

**Delete or rename events** require special handling because many editors
perform *atomic saves*: they write to a temporary file and then rename it over
the original. After the rename the old file descriptor points at a stale inode,
so `FileWatcher` tears down the current watch, waits 100 ms for the filesystem
to settle, then re-establishes a fresh watch on the same path and fires
`onChange`.

On cancel (or `deinit`), the dispatch source's cancel handler closes the file
descriptor.


## How `DocumentContentView` wires it up

```
.onAppear  → setupFileWatcher()
             → FileWatcher(url: fileURL) { loadFromDisk() }

.onDisappear → fileWatcher = nil   (triggers deinit, cleans up fd)
```

`loadFromDisk()` reads the file as UTF-8 and sets `displayText`, which triggers
SwiftUI to re-render the markdown preview.

A manual reload via `Cmd+R` bypasses the watcher entirely —
`DocumentWindowController` sets `state.reloadID = UUID()`, which
`DocumentContentView` observes via `.onChange(of: state.reloadID)`, calling the
same `loadFromDisk()` path.


## Event flow

```
External editor saves file
  → kernel notices inode change
    → DispatchSource fires event on main queue
      → onChange closure called
        → loadFromDisk() reads new content
          → displayText updated
            → SwiftUI re-renders preview
```


## Edge cases

- **Atomic saves (rename/delete).** Handled by the re-watch-after- delay
  strategy described above.
- **File deleted permanently.** `startWatching()` fails to open the descriptor
  and logs a message. The view keeps showing the last loaded content.
- **Window closed.** `.onDisappear` nils the watcher, closing the file
  descriptor cleanly.
