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

        print("EdgeShelf self-test: OK")
        exit(0)
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
