import Foundation

/// Watches a file for changes using GCD dispatch sources.
///
/// Handles atomic saves (write-to-temp-then-rename) by re-establishing
/// the watch when the file is deleted or renamed.
final class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let url: URL
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        startWatching()
    }

    deinit {
        stopWatching()
    }

    private func startWatching() {
        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("FileWatcher: Failed to open file descriptor for \(url.path)")
            return
        }

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source?.setEventHandler { [weak self] in
            guard let self else { return }
            let events = self.source?.data ?? []

            // File was replaced (atomic save) - re-establish watch
            if events.contains(.delete) || events.contains(.rename) {
                self.stopWatching()
                // Brief delay to let file system settle after rename
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.startWatching()
                    self?.onChange()
                }
            } else {
                self.onChange()
            }
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
            self?.fileDescriptor = -1
        }

        source?.resume()
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
    }
}
