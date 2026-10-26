import AppKit

/// Disk layout:
///   ~/Library/Application Support/EdgeShelf/
///     shelves.json
///     Items/<item-uuid>/<original file name>
///
/// The app copies dropped files into Items/ so a shelf item survives even if
/// the user moves or deletes the original. All file work happens on a serial
/// background queue; nothing here touches AppKit.
final class Store {
    static let shared = Store()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.doge.edgeshelf.store", qos: .utility)

    let rootURL: URL
    let itemsURL: URL
    private let stateURL: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootURL = appSupport.appendingPathComponent("EdgeShelf", isDirectory: true)
        itemsURL = rootURL.appendingPathComponent("Items", isDirectory: true)
        stateURL = rootURL.appendingPathComponent("shelves.json")

        try? fileManager.createDirectory(at: itemsURL, withIntermediateDirectories: true)
    }

    // MARK: - State

    func loadStates() -> [ShelfState] {
        guard let data = try? Data(contentsOf: stateURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let states = try? decoder.decode([ShelfState].self, from: data) else {
            NSLog("EdgeShelf: could not decode shelves.json")
            return []
        }
        return states
    }

    /// Debounced, atomic write. Safe to call from the main thread.
    private var saveWorkItem: DispatchWorkItem?

    func save(_ states: [ShelfState]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(states) else { return }

        saveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async {
                do {
                    try self.fileManager.createDirectory(at: self.rootURL, withIntermediateDirectories: true)
                    try data.write(to: self.stateURL, options: .atomic)
                } catch {
                    NSLog("EdgeShelf: save failed: \(error)")
                }
            }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    func saveNow(_ states: [ShelfState]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(states) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    // MARK: - Paths

    func url(forRelativePath path: String) -> URL {
        itemsURL.appendingPathComponent(path)
    }

    func absoluteURL(for item: ShelfItem) -> URL? {
        if let relativePath = item.relativePath {
            let url = url(forRelativePath: relativePath)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        if let originalPath = item.originalPath {
            let url = URL(fileURLWithPath: originalPath)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    // MARK: - Item files

    /// Copies a file or folder into the store. Returns the path relative to
    /// Items/. Call from a background queue.
    func copyFile(at source: URL, itemID: UUID) -> String? {
        let folderName = itemID.uuidString
        let destinationFolder = itemsURL.appendingPathComponent(folderName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
            var destination = destinationFolder.appendingPathComponent(source.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                let base = destination.deletingPathExtension().lastPathComponent
                let ext = destination.pathExtension
                let unique = ext.isEmpty ? "\(base)-\(UUID().uuidString.prefix(6))" : "\(base)-\(UUID().uuidString.prefix(6)).\(ext)"
                destination = destinationFolder.appendingPathComponent(unique)
            }
            try fileManager.copyItem(at: source, to: destination)
            return "\(folderName)/\(destination.lastPathComponent)"
        } catch {
            NSLog("EdgeShelf: copy failed \(source.path): \(error)")
            return nil
        }
    }

    /// Writes raw image data into the store. Returns a relative path.
    func writeData(_ data: Data, itemID: UUID, fileExtension: String) -> String? {
        let folderName = itemID.uuidString
        let folder = itemsURL.appendingPathComponent(folderName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = "image-\(itemID.uuidString.prefix(8)).\(fileExtension)"
            let url = folder.appendingPathComponent(name)
            try data.write(to: url, options: .atomic)
            return "\(folderName)/\(name)"
        } catch {
            NSLog("EdgeShelf: write failed: \(error)")
            return nil
        }
    }

    func deleteFiles(for itemID: UUID) {
        let folder = itemsURL.appendingPathComponent(itemID.uuidString, isDirectory: true)
        queue.async { [fileManager] in
            try? fileManager.removeItem(at: folder)
        }
    }

    /// Removes item folders that no persisted item references. Call on launch.
    func cleanUnreferencedFolders(referenced: Set<UUID>) {
        queue.async { [fileManager, itemsURL] in
            guard let contents = try? fileManager.contentsOfDirectory(at: itemsURL,
                                                                       includingPropertiesForKeys: nil) else { return }
            for url in contents {
                guard let id = UUID(uuidString: url.lastPathComponent) else { continue }
                if !referenced.contains(id) {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }
}
