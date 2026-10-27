import Darwin
import Foundation

/// Watches one file or folder through kqueue.
///
/// `DispatchSourceFileSystemObject` is the per-file equivalent of Node's
/// `fs.watch`: it reports unlink, rename and volume revocation for the exact
/// vnode without scanning a directory tree. FSEvents is directory-oriented
/// and coalesced; this is both more direct and immediate for a shelf item.
///
/// After a rename or move, the descriptor still refers to the same inode, so
/// `F_GETPATH` can return the new path. That is what lets the shelf follow a
/// moved file instead of losing it. When the file is unlinked (or moved to the
/// Trash), the path is gone and the item should be removed.
final class FileWatcher {
    enum Resolution {
        /// The same file is still at the watched path.
        case unchanged
        /// The path now holds a different inode, e.g. after an atomic save.
        case replaced
        /// The same inode was renamed or moved to a new path.
        case moved(String)
        /// The file was unlinked, moved to the Trash, or left the volume.
        case gone
        /// The volume was unmounted. Keep the item, but stop watching.
        case revoked
    }

    private struct FileIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    /// Shared with the cancel handler so the descriptor is closed even if the
    /// watcher is released before the handler runs.
    private final class Descriptor {
        let fd: Int32
        var isCancelled = false

        init(_ fd: Int32) {
            self.fd = fd
        }
    }

    let path: String

    private let descriptor: Descriptor
    private let source: DispatchSourceFileSystemObject
    private let handler: (Resolution) -> Void

    /// Opens `path` for event-only access. `handler` runs on `queue`.
    init?(path: String,
          queue: DispatchQueue,
          handler: @escaping (Resolution) -> Void) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }

        self.path = path
        self.descriptor = Descriptor(fd)
        self.handler = handler

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.delete, .rename, .revoke],
            queue: queue
        )
        self.source = source

        source.setEventHandler { [weak self] in
            guard let self else { return }
            if self.source.data.contains(.revoke) {
                self.handler(.revoked)
            } else {
                self.handler(self.resolve())
            }
        }
        let descriptor = self.descriptor
        source.setCancelHandler {
            descriptor.isCancelled = true
            close(descriptor.fd)
        }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    func cancel() {
        source.cancel()
    }

    /// Classifies the event. Must run on the watcher's queue, like the event
    /// and cancel handlers, so the descriptor cannot be closed underneath it.
    func resolve() -> Resolution {
        guard !descriptor.isCancelled else { return .gone }

        let pathExists = FileManager.default.fileExists(atPath: path)
        let descriptorIdentity = Self.identity(of: descriptor.fd)

        if pathExists {
            guard let descriptorIdentity else { return .replaced }
            guard let pathIdentity = Self.identity(at: path) else { return .gone }
            return pathIdentity == descriptorIdentity ? .unchanged : .replaced
        }

        guard let descriptorIdentity,
              let current = Self.currentPath(of: descriptor.fd),
              current != Self.canonicalPath(path),
              !Self.isInTrash(current),
              let currentIdentity = Self.identity(at: current),
              currentIdentity == descriptorIdentity else {
            return .gone
        }
        return .moved(current)
    }

    /// Resolves `/var` and `/tmp` prefixes so paths can be compared.
    static func canonicalPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    // MARK: - Descriptor helpers

    private static func currentPath(of fd: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard fcntl(fd, F_GETPATH, &buffer) != -1 else { return nil }
        return String(cString: buffer)
    }

    private static func identity(of fd: Int32) -> FileIdentity? {
        var info = stat()
        guard fstat(fd, &info) == 0 else { return nil }
        return FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    private static func identity(at path: String) -> FileIdentity? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    /// Finder puts deleted files under `.Trash` (home) or `.Trashes` (other
    /// volumes). A move there should behave like a deletion, not like an
    /// ordinary rename the shelf follows.
    private static func isInTrash(_ path: String) -> Bool {
        let parts = (path as NSString).pathComponents
        return parts.contains(".Trash") || parts.contains(".Trashes")
    }
}
