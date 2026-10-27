import AppKit

private enum SelfTest {
    private final class ResolutionBox {
        private let lock = NSLock()
        private var value: FileWatcher.Resolution?
        let semaphore = DispatchSemaphore(value: 0)

        func set(_ resolution: FileWatcher.Resolution) {
            lock.lock()
            value = resolution
            lock.unlock()
            semaphore.signal()
        }

        func take() -> FileWatcher.Resolution? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    static func run() {
        var state = ShelfState(key: ShelfKey(screenID: "1", edge: .left))
        state.items.append(ShelfItem(kind: .text,
                                     displayName: "hello",
                                     text: "hello world"))
        state.items.append(ShelfItem(kind: .url,
                                     displayName: "example.com",
                                     urlString: "https://example.com/"))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(ShelfState.self, from: data)
            precondition(decoded.items.count == 2)
            precondition(decoded.items[0].text == "hello world")
            precondition(decoded.items[1].urlString == "https://example.com/")
            precondition(decoded.key.edge == .left)
        } catch {
            print("EdgeShelf self-test: FAILED — \(error)")
            exit(1)
        }

        // Pasteboard round-trip (file URL + plain text).
        let testPath = NSTemporaryDirectory() + "edgeshelf-selftest.txt"
        try? "hello".write(toFile: testPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: testPath) }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.doge.edgeshelf.selftest"))
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: testPath) as NSURL])
        let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                          options: [.urlReadingFileURLsOnly: false]) as? [URL]
        precondition(urls?.first?.path == testPath)

        pasteboard.clearContents()
        pasteboard.setString("plain text", forType: .string)
        precondition(pasteboard.string(forType: .string) == "plain text")

        // Stored-payload round-trip: pasted images and promised files have no
        // external path, so they still live under Items/.
        let itemID = UUID()
        if let relative = Store.shared.writeData(Data("hello".utf8),
                                                  itemID: itemID,
                                                  fileExtension: "txt") {
            let written = Store.shared.url(forRelativePath: relative)
            let stored = ShelfItem(kind: .image, displayName: "payload", relativePath: relative)
            if Store.shared.absoluteURL(for: stored)?.path != written.path {
                failSelfTest("a stored payload must resolve inside Items")
            }
            // A legacy item whose original is gone still falls back to its copy.
            let legacy = ShelfItem(kind: .file,
                                   displayName: "legacy",
                                   relativePath: relative,
                                   originalPath: testPath + ".moved")
            if Store.shared.absoluteURL(for: legacy)?.path != written.path {
                failSelfTest("a stored copy must be the fallback when the original is gone")
            }
            try? FileManager.default.removeItem(at: written.deletingLastPathComponent())
        } else {
            failSelfTest("store payload write")
        }

        // A Finder drop is a plain reference: the original path wins while it
        // exists, and nothing is copied into the store.
        let referenced = ShelfItem(kind: .file, displayName: "selftest", originalPath: testPath)
        if Store.shared.absoluteURL(for: referenced)?.path != testPath {
            failSelfTest("a file item must resolve to its original path")
        }
        if !Store.shared.isReachable(referenced) {
            failSelfTest("an existing original must be reachable")
        }
        let missing = ShelfItem(kind: .file,
                                displayName: "gone",
                                originalPath: testPath + ".missing")
        if Store.shared.absoluteURL(for: missing) != nil || Store.shared.isReachable(missing) {
            failSelfTest("a missing original must not be reachable")
        }

        // Drag classification. These are the rules that decide whether a drop
        // becomes a card or a beep.
        runClassificationTests()

        // kqueue watcher: rename/move, delete, Trash, and atomic replacement.
        runFileWatcherTests()

        // A state file that cannot be decoded must be preserved, and must not
        // make the caller believe the user has no items.
        runStoreRecoveryTests()

        print("EdgeShelf self-test: OK")
        exit(0)
    }

    private static func runStoreRecoveryTests() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EdgeShelf-SelfTest-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = Store(rootURL: root)
        let itemID = UUID()
        let itemFolder = store.itemsURL.appendingPathComponent(itemID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: itemFolder, withIntermediateDirectories: true)
        let keptFile = itemFolder.appendingPathComponent("keep.txt")
        try? "user data".write(to: keptFile, atomically: true, encoding: .utf8)
        try? "not json".write(to: root.appendingPathComponent("shelves.json"), atomically: true, encoding: .utf8)

        let loaded = store.loadStates()
        if !loaded.isEmpty { failSelfTest("a corrupt state file must load as empty") }
        if !store.loadFailed { failSelfTest("a corrupt state file must be reported as a failure") }
        if !FileManager.default.fileExists(atPath: keptFile.path) {
            failSelfTest("stored files must survive a corrupt state file")
        }
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: root.path))?
            .filter { $0.hasPrefix("shelves.corrupt-") } ?? []
        if backups.count != 1 {
            failSelfTest("the unreadable state file must be kept as a backup, found \(backups)")
        }

        // A readable file must load, and must not be reported as a failure.
        let goodState = ShelfState(key: ShelfKey(screenID: "1", edge: .left),
                                   items: [ShelfItem(kind: .text, displayName: "x", text: "y")])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode([goodState]).write(to: root.appendingPathComponent("shelves.json"))
        if store.loadStates().count != 1 { failSelfTest("a valid state file must load") }
        if store.loadFailed { failSelfTest("a valid state file must not be reported as a failure") }
    }

    private static func failSelfTest(_ message: String) -> Never {
        print("EdgeShelf self-test: FAILED — \(message)")
        exit(1)
    }

    private static func runFileWatcherTests() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .resolvingSymlinksInPath()
            .appendingPathComponent("EdgeShelf-Watcher-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let queue = DispatchQueue(label: "com.doge.edgeshelf.selftest.watcher")

        func makeFile(_ url: URL, contents: String = "hello") {
            try? contents.write(to: url, atomically: true, encoding: .utf8)
        }

        func watch(_ url: URL) -> (FileWatcher, ResolutionBox) {
            let box = ResolutionBox()
            guard let watcher = FileWatcher(path: url.path, queue: queue, handler: { box.set($0) }) else {
                failSelfTest("could not start a file watcher")
            }
            return (watcher, box)
        }

        func expect(_ box: ResolutionBox,
                    _ description: String,
                    matches: (FileWatcher.Resolution) -> Bool) {
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if box.semaphore.wait(timeout: .now() + 0.2) == .success,
                   let resolution = box.take(),
                   matches(resolution) {
                    return
                }
            }
            failSelfTest("file watcher did not report \(description)")
        }

        // A rename or move within the volume must produce the new path.
        let a = root.appendingPathComponent("a.txt")
        makeFile(a)
        let (renameWatcher, renameBox) = watch(a)
        let b = root.appendingPathComponent("b.txt")
        do {
            try FileManager.default.moveItem(at: a, to: b)
        } catch {
            failSelfTest("could not move the watcher test file: \(error)")
        }
        expect(renameBox, "the new path") {
            if case .moved(let path) = $0 {
                return FileWatcher.canonicalPath(path) == FileWatcher.canonicalPath(b.path)
            }
            return false
        }
        renameWatcher.cancel()

        // Renaming an ancestor folder is invisible to the file's own vnode,
        // but reconciliation can still resolve the new path from the open
        // descriptor.
        let parent = root.appendingPathComponent("parent", isDirectory: true)
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let inside = parent.appendingPathComponent("c.txt")
        makeFile(inside)
        let (parentWatcher, _) = watch(inside)
        let movedParent = root.appendingPathComponent("parent2", isDirectory: true)
        do {
            try FileManager.default.moveItem(at: parent, to: movedParent)
        } catch {
            failSelfTest("could not rename the watcher test folder: \(error)")
        }
        let ancestorResolution = queue.sync { parentWatcher.resolve() }
        guard case .moved(let resolvedAncestor) = ancestorResolution,
              FileWatcher.canonicalPath(resolvedAncestor)
                == FileWatcher.canonicalPath(movedParent.appendingPathComponent("c.txt").path) else {
            failSelfTest("an ancestor rename must resolve to the new path")
        }
        parentWatcher.cancel()

        // Deleting the file must be reported as gone.
        makeFile(a)
        let (deleteWatcher, deleteBox) = watch(a)
        try? FileManager.default.removeItem(at: a)
        expect(deleteBox, "a deletion") {
            if case .gone = $0 { return true }
            return false
        }
        deleteWatcher.cancel()

        // Moving a file to the Trash is a deletion as far as the shelf is
        // concerned, even though it is technically a rename.
        makeFile(a)
        let trash = root.appendingPathComponent(".Trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let (trashWatcher, trashBox) = watch(a)
        do {
            try FileManager.default.moveItem(at: a, to: trash.appendingPathComponent("a.txt"))
        } catch {
            failSelfTest("could not move the watcher test file to Trash: \(error)")
        }
        expect(trashBox, "a move to the Trash") {
            if case .gone = $0 { return true }
            return false
        }
        trashWatcher.cancel()

        // An atomic save replaces the inode at the same path. The item must
        // stay, but the watcher has to re-arm on the new file.
        makeFile(a, contents: "old")
        let (replaceWatcher, replaceBox) = watch(a)
        let temp = root.appendingPathComponent("replacement.txt")
        makeFile(temp, contents: "new")
        if (try? FileManager.default.replaceItemAt(a, withItemAt: temp)) == nil {
            failSelfTest("could not atomically replace the watcher test file")
        }
        expect(replaceBox, "an atomic replacement") {
            if case .replaced = $0 { return true }
            return false
        }
        replaceWatcher.cancel()
    }

    private static func runClassificationTests() {
        func board(_ name: String) -> NSPasteboard {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("com.doge.edgeshelf.selftest.\(name)"))
            pasteboard.clearContents()
            return pasteboard
        }

        func fail(_ message: String) -> Never {
            print("EdgeShelf self-test: FAILED — \(message)")
            exit(1)
        }

        // Rich text with no plain-text flavour used to be accepted by the view
        // and then dropped with a beep. AppKit derives a plain string for RTF
        // on its own, so HTML and flat RTFD are the flavours that hit that
        // path.
        func checkRichText(_ suffix: String, _ type: NSPasteboard.PasteboardType, _ data: Data) {
            let richBoard = board("rich-\(suffix)")
            richBoard.setData(data, forType: type)
            if richBoard.string(forType: .string) != nil {
                fail("\(suffix) unexpectedly exposes a plain string")
            }
            switch IngestPayload.classify(richBoard) {
            case .some(.richText): break
            default: fail("\(suffix) without plain text must classify as richText")
            }
        }

        checkRichText("html", .html, "<p>Hello <b>html</b></p>".data(using: .utf8)!)

        let rtfdSource = NSAttributedString(string: "Hello rtfd")
        if let rtfdData = try? rtfdSource.data(from: NSRange(location: 0, length: rtfdSource.length),
                                               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtfd]) {
            checkRichText("rtfd", .rtfd, rtfdData)
        } else {
            fail("could not build flat RTFD data")
        }

        // A browser publishes an image's alt text as `.string` next to the
        // bitmap, so the bitmap has to win.
        let imageBoard = board("image")
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                      pixelsWide: 2,
                                      pixelsHigh: 2,
                                      bitsPerSample: 8,
                                      samplesPerPixel: 4,
                                      hasAlpha: true,
                                      isPlanar: false,
                                      colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0,
                                      bitsPerPixel: 0)
        guard let png = bitmap?.representation(using: .png, properties: [:]) else {
            fail("could not build a test bitmap")
        }
        imageBoard.setData(png, forType: .png)
        imageBoard.setString("alt text", forType: .string)
        imageBoard.setString("<img src=\"x.png\">", forType: .html)
        switch IngestPayload.classify(imageBoard) {
        case .some(.bitmap): break
        default: fail("a bitmap must win over its text flavours")
        }

        // A file URL must stay a file, so dragging it back is a no-op.
        let fileBoard = board("file")
        fileBoard.writeObjects([URL(fileURLWithPath: "/tmp/edgeshelf-classify.txt") as NSURL])
        switch IngestPayload.classify(fileBoard) {
        case .some(.urls(let urls)) where urls.first?.isFileURL == true: break
        default: fail("a file URL must classify as a file URL")
        }

        // Plain text stays text, and whitespace-only text is not a card.
        let textBoard = board("text")
        textBoard.setString("plain", forType: .string)
        switch IngestPayload.classify(textBoard) {
        case .some(.text(let text)) where text == "plain": break
        default: fail("plain text must classify as text")
        }

        let blankBoard = board("blank")
        blankBoard.setString("  \n\t ", forType: .string)
        if IngestPayload.classify(blankBoard) != nil {
            fail("whitespace-only text must not become a card")
        }

        // An HTML fragment that is only an inline picture decodes to a single
        // U+FFFC, which is not readable content.
        if IngestPayload.hasReadableText("\u{FFFC}") {
            fail("an attachment placeholder must not count as readable text")
        }
        if !IngestPayload.hasReadableText("before \u{FFFC} after") {
            fail("text around an attachment must count as readable")
        }

        if IngestPayload.firstLine(of: "\n\nfirst line\nsecond line") != "first line" {
            fail("firstLine must skip blank leading lines")
        }
    }
}

if CommandLine.arguments.contains("--self-test") {
    SelfTest.run()
}

let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.doge.edgeshelf")
if running.count > 1 {
    print("EdgeShelf is already running.")
    exit(0)
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
