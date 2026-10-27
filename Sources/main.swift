import AppKit

private enum SelfTest {
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

        // Store copy round-trip.
        if let relative = Store.shared.copyFile(at: URL(fileURLWithPath: testPath), itemID: UUID()) {
            let copied = Store.shared.url(forRelativePath: relative)
            precondition(FileManager.default.fileExists(atPath: copied.path))
            try? FileManager.default.removeItem(at: copied.deletingLastPathComponent())
        } else {
            print("EdgeShelf self-test: FAILED — store copy")
            exit(1)
        }

        // Drag classification. These are the rules that decide whether a drop
        // becomes a card or a beep.
        runClassificationTests()

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
            failSelfTest("item copies must survive a corrupt state file")
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
