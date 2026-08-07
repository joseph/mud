import Foundation

// MARK: - Local Asset Probe

/// Whether Mud can read a local file, and if not, why not.
///
/// The distinction that matters is `denied` versus `missing`. Both leave the
/// reader looking at a broken image, but only one of them is Mud's to fix: a
/// denied read means the sandbox is holding a folder back and the reader can
/// grant it (`AssetAccessStore`), while a missing file is a wrong path in the
/// document and nothing Mud can offer to do anything about.
enum LocalAssetAccess: Equatable {
    /// The file is there and Mud can read its bytes.
    case readable
    /// Nothing at that path.
    case missing
    /// The file is there and Mud isn't allowed to read it. In the sandboxed
    /// build this is the ordinary case for any file the reader hasn't handed
    /// Mud — which is every file except the one they opened.
    case denied
}

/// Asks whether a local file can actually be read, by opening it.
///
/// `FileManager.fileExists` won't answer this. The macOS sandbox denies the
/// content read while generally permitting `stat`, so a file Mud can't read
/// still reports as existing — and a denial and a typo become the same
/// answer. `open(2)` is the operation the sandbox actually adjudicates, and
/// the one `LocalFileSchemeHandler` will attempt later, so its `errno` is the
/// same verdict the WebView would eventually get.
enum LocalAssetProbe {

    /// Opens `path` for reading and closes it again, reporting what happened.
    ///
    /// `O_NONBLOCK` is there so the open itself can't hang. A regular file is
    /// unaffected by it, but a FIFO opened for reading with no writer at the
    /// other end blocks until one arrives — and this runs on the main thread,
    /// inside a render, so that would be the whole app stopped by a document
    /// that named a pipe `diagram.png`.
    static func probe(path: String) -> LocalAssetAccess {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK)
        if descriptor >= 0 {
            close(descriptor)
            return .readable
        }
        switch errno {
        case EACCES, EPERM:
            return .denied
        default:
            // ENOENT and ENOTDIR are the ordinary "not there" answers; anything
            // else (a broken symlink loop, a device that went away) is equally
            // not something a folder grant would fix, so it reads the same way.
            return .missing
        }
    }

    static func probe(_ url: URL) -> LocalAssetAccess {
        return probe(path: url.path)
    }
}
