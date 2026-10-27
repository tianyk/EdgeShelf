import AppKit
import UniformTypeIdentifiers

/// Owns shelf state, disk persistence, and the pre-created edge windows.
///
/// Threading rule: every method here is called on the main thread. The only
/// background work is file copying, which reports back with
/// DispatchQueue.main.async.
final class ShelfManager {
    private let store = Store.shared
    private let prefs = Preferences.shared
    private let copyQueue = DispatchQueue(label: "com.doge.edgeshelf.copy", qos: .utility)
    private var states: [ShelfKey: ShelfState] = [:]
    private(set) var windows: [ShelfKey: ShelfWindowController] = [:]
    private var pendingItems: Set<UUID> = []
    private(set) var isDragging = false
    private var needsRebuild = false
    private var rebuildWorkItem: DispatchWorkItem?
    private var activePreview: ShelfKey?
    private var hoveredKeys: Set<ShelfKey> = []
    private var autoHideTimers: [ShelfKey: Timer] = [:]
    private var pendingHeightUpdate = false
    private var heightRetry: DispatchWorkItem?

    init() {
        for state in store.loadStates() {
            states[state.key] = state
        }
        if store.loadFailed {
            // The state file was unreadable and has been moved aside. Every
            // item folder is therefore unreferenced, and pruning now would
            // delete copies the user may still want. Keep them and let the
            // next successful save take over.
            NSLog("EdgeShelf: skipping the item cleanup after an unreadable shelves.json")
        } else {
            let referenced = Set(states.values.flatMap { $0.items.map(\.id) })
            store.cleanUnreferencedFolders(referenced: referenced)
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.scheduleRebuild()
        }

        rebuildWindows()
    }

    // MARK: - State access

    func items(for key: ShelfKey) -> [ShelfItem] {
        states[key]?.items ?? []
    }

    /// The URL the user should get when opening, revealing, copying, or
    /// dragging an item out. Preference order:
    ///   1. the original file, if it still exists (so dragging back to the
    ///      same folder is a no-op instead of a "replace?" prompt),
    ///   2. the shelf's own copy, if the original has moved or been deleted.
    func userFacingURL(for item: ShelfItem) -> URL? {
        if let path = item.originalPath {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return store.absoluteURL(for: item)
    }

    func isPending(_ id: UUID) -> Bool {
        pendingItems.contains(id)
    }

    private func ensureState(for key: ShelfKey) -> ShelfState {
        if let state = states[key] { return state }
        let state = ShelfState(key: key)
        states[key] = state
        return state
    }

    private func save() {
        store.save(Array(states.values))
    }

    private func updateItem(id: UUID, in key: ShelfKey, _ mutate: (inout ShelfItem) -> Void) {
        guard var state = states[key],
              let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&state.items[index])
        states[key] = state
        save()
    }

    // MARK: - Windows

    private func frame(for screen: NSScreen, edge: ShelfEdge, itemCount: Int) -> NSRect {
        let width = ShelfMetrics.windowWidth
        let height = ShelfMetrics.windowHeight(forItemCount: itemCount)
        let x = edge == .left
            ? screen.frame.minX - ShelfMetrics.shadowMargin
            : screen.frame.maxX - width + ShelfMetrics.shadowMargin
        let y = screen.visibleFrame.midY - height / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }

    func rebuildWindows() {
        guard !isDragging else {
            needsRebuild = true
            return
        }
        needsRebuild = false

        for timer in autoHideTimers.values { timer.invalidate() }
        autoHideTimers.removeAll()
        hoveredKeys.removeAll()

        for controller in windows.values {
            controller.window?.orderOut(nil)
            controller.window?.close()
        }
        windows.removeAll()

        for screen in NSScreen.screens {
            let screenID = screen.edgeShelfDisplayID
            for edge in prefs.enabledEdges {
                let key = ShelfKey(screenID: screenID, edge: edge)
                let count = items(for: key).count
                let controller = ShelfWindowController(key: key,
                                                       frame: frame(for: screen, edge: edge, itemCount: count),
                                                       manager: self)
                windows[key] = controller
                if count > 0 {
                    controller.setPresentation(.expanded, animated: false)
                    scheduleAutoHide(key)
                }
            }
        }
    }

    private func scheduleRebuild() {
        rebuildWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.rebuildWindows()
        }
        rebuildWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // MARK: - Drag lifecycle

    func beginDrag() {
        isDragging = true
    }

    /// Called on the next main-runloop turn after a mouseDragged event, never
    /// from inside AppKit's drag IPC path.
    func updateDrag(cursor: NSPoint) {
        isDragging = true
        guard !windows.isEmpty else { return }

        guard let match = nearestEdge(to: cursor, threshold: 200) else {
            if let activePreview, items(for: activePreview).isEmpty {
                windows[activePreview]?.setPresentation(.hidden)
            }
            activePreview = nil
            return
        }

        let key = match.key
        if let activePreview, activePreview != key, items(for: activePreview).isEmpty {
            windows[activePreview]?.setPresentation(.hidden)
        }
        activePreview = key
        if windows[key]?.isExpanded != true {
            windows[key]?.setPresentation(.expanded, animated: false)
        }
        cancelAutoHide(key)
    }

    func endDrag() {
        isDragging = false
        activePreview = nil

        let cursor = NSEvent.mouseLocation
        for (key, controller) in windows {
            if items(for: key).isEmpty {
                controller.setPresentation(.hidden)
                cancelAutoHide(key)
            } else if controller.window?.frame.contains(cursor) == true {
                hoveredKeys.insert(key)
                cancelAutoHide(key)
            } else {
                scheduleAutoHide(key)
            }
        }

        if needsRebuild {
            rebuildWindows()
        }
        updateHeights(animated: true)
    }

    /// Polled while no mouse button is down. Reveals a shelf when the pointer
    /// rests against an edge that already holds items, and starts the
    /// auto-hide countdown when it leaves.
    func hoverUpdate(cursor: NSPoint) {
        guard !isDragging else { return }

        for (key, controller) in windows where controller.isExpanded {
            if let frame = controller.window?.frame, frame.contains(cursor) {
                hoveredKeys.insert(key)
                cancelAutoHide(key)
                return
            }
        }

        let leftKeys = hoveredKeys
        hoveredKeys.removeAll()
        for key in leftKeys {
            scheduleAutoHide(key)
        }

        if let match = nearestEdge(to: cursor),
           !items(for: match.key).isEmpty,
           let frame = windows[match.key]?.window?.frame,
           cursor.y >= frame.minY - 6, cursor.y <= frame.maxY + 6 {
            let key = match.key
            hoveredKeys.insert(key)
            cancelAutoHide(key)
            if windows[key]?.isExpanded != true {
                windows[key]?.setPresentation(.expanded)
            }
        }
    }

    private func scheduleAutoHide(_ key: ShelfKey) {
        guard !isDragging, !items(for: key).isEmpty else { return }
        cancelAutoHide(key)
        // No grace period: collapse on the next run-loop turn unless the
        // pointer is actually inside the shelf window.
        let timer = Timer(timeInterval: 0, repeats: false) { [weak self] _ in
            guard let self else { return }
            guard !self.isDragging, !self.hoveredKeys.contains(key) else { return }
            if let frame = self.windows[key]?.window?.frame,
               frame.contains(NSEvent.mouseLocation) {
                self.hoveredKeys.insert(key)
                self.autoHideTimers[key] = nil
                return
            }
            if self.items(for: key).isEmpty {
                self.windows[key]?.setPresentation(.hidden)
            } else {
                self.windows[key]?.setPresentation(.collapsed)
            }
            self.autoHideTimers[key] = nil
        }
        RunLoop.main.add(timer, forMode: .common)
        autoHideTimers[key] = timer
    }

    private func cancelAutoHide(_ key: ShelfKey) {
        autoHideTimers[key]?.invalidate()
        autoHideTimers[key] = nil
    }

    /// Only resize while idle. During a drag the window frame is frozen; the
    /// pending update is applied by `endDrag`. A click that removes an item
    /// schedules a short retry so the shelf also shrinks after mouse-up.
    func updateHeights(animated: Bool = true) {
        guard !isDragging, NSEvent.pressedMouseButtons == 0 else {
            pendingHeightUpdate = true
            if !isDragging {
                scheduleHeightRetry()
            }
            return
        }
        pendingHeightUpdate = false
        heightRetry?.cancel()
        heightRetry = nil
        for (key, controller) in windows {
            controller.resize(forItemCount: items(for: key).count, animated: animated)
        }
    }

    private func scheduleHeightRetry() {
        heightRetry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard !self.isDragging, NSEvent.pressedMouseButtons == 0 else {
                self.scheduleHeightRetry()
                return
            }
            self.updateHeights(animated: true)
        }
        heightRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func nearestEdge(to point: NSPoint, threshold: CGFloat = 8) -> (key: ShelfKey, distance: CGFloat)? {
        var best: (key: ShelfKey, distance: CGFloat)?

        for screen in NSScreen.screens {
            let screenID = screen.edgeShelfDisplayID
            for edge in prefs.enabledEdges {
                let distance: CGFloat
                let inside: Bool
                switch edge {
                case .left:
                    distance = point.x - screen.frame.minX
                    inside = point.y >= screen.frame.minY - 2 && point.y <= screen.frame.maxY + 2
                case .right:
                    distance = screen.frame.maxX - point.x
                    inside = point.y >= screen.frame.minY - 2 && point.y <= screen.frame.maxY + 2
                }
                guard inside, distance >= -2, distance <= threshold else { continue }
                let key = ShelfKey(screenID: screenID, edge: edge)
                guard windows[key] != nil else { continue }
                if best == nil || distance < best!.distance {
                    best = (key, distance)
                }
            }
        }
        return best
    }

    // MARK: - Ingest

    /// Returns `false` when nothing on the pasteboard could become a shelf
    /// item, so the dragging source animates the item back instead of being
    /// told the drop was accepted.
    @discardableResult
    func ingest(pasteboard: NSPasteboard, into key: ShelfKey) -> Bool {
        guard let payload = IngestPayload.classify(pasteboard) else {
            NSSound.beep()
            return false
        }

        var state = ensureState(for: key)
        var added = false

        switch payload {
        case .promises(let receivers):
            // Resolving a promise synchronously on the main thread is a
            // classic multi-second hang, so hand them off and return.
            for receiver in receivers {
                ingestPromise(receiver, into: key)
            }
            save()
            DispatchQueue.main.async { [weak self] in
                self?.windows[key]?.refresh()
                self?.windows[key]?.setPresentation(.expanded)
                self?.scheduleAutoHide(key)
                self?.updateHeights(animated: true)
            }
            return true

        case .urls(let urls):
            for url in urls {
                if url.isFileURL {
                    if state.items.contains(where: { $0.originalPath == url.path }) {
                        continue
                    }
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .nameKey])
                    let isDirectory = values?.isDirectory ?? false
                    let isImage = !isDirectory
                        && UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
                    let size = values?.fileSize.map(Int64.init)
                    let item = ShelfItem(kind: isDirectory ? .folder : (isImage ? .image : .file),
                                         displayName: url.lastPathComponent,
                                         originalPath: url.path,
                                         byteSize: size)
                    state.items.append(item)
                    pendingItems.insert(item.id)
                    added = true
                    copyInBackground(item: item, from: url, into: key)
                } else {
                    let string = url.absoluteString
                    guard !state.items.contains(where: { $0.urlString == string }) else { continue }
                    let item = ShelfItem(kind: .url,
                                         displayName: url.host ?? url.lastPathComponent,
                                         urlString: string)
                    state.items.append(item)
                    added = true
                }
            }

        case .bitmap(let data, let fileExtension):
            let item = ShelfItem(kind: .image,
                                 displayName: L10n.image,
                                 byteSize: Int64(data.count))
            state.items.append(item)
            pendingItems.insert(item.id)
            added = true
            storePayload(item: item, data: data, fileExtension: fileExtension, into: key)

        case .text(let string):
            if !state.items.contains(where: { $0.kind == .text && $0.text == string }) {
                let item = ShelfItem(kind: .text,
                                     displayName: IngestPayload.firstLine(of: string),
                                     text: string)
                state.items.append(item)
                added = true
            }

        case .richText(let data, let documentType):
            // Rich text is deduplicated by its decoded body, which is not
            // available yet, so a repeated drop adds a second card.
            let item = ShelfItem(kind: .text, displayName: L10n.text)
            state.items.append(item)
            pendingItems.insert(item.id)
            added = true
            decodeRichText(item: item, data: data, documentType: documentType, into: key)
        }

        guard added else {
            NSSound.beep()
            return false
        }

        states[key] = state
        save()

        // Never rebuild the stack or create thumbnails inside the drag
        // destination callback. Let the drop finish first.
        DispatchQueue.main.async { [weak self] in
            self?.windows[key]?.refresh()
            self?.windows[key]?.setPresentation(.expanded)
            self?.scheduleAutoHide(key)
            self?.updateHeights(animated: true)
        }
        return true
    }

    private func copyInBackground(item: ShelfItem, from url: URL, into key: ShelfKey) {
        copyQueue.async { [weak self] in
            guard let self else { return }
            let relative = self.store.copyFile(at: url, itemID: item.id)
            DispatchQueue.main.async {
                self.pendingItems.remove(item.id)
                if let relative {
                    self.updateItem(id: item.id, in: key) { $0.relativePath = relative }
                }
                self.windows[key]?.refreshItem(id: item.id)
                self.save()
            }
        }
    }

    /// Writes bitmap bytes that arrived on the pasteboard.
    ///
    /// The bytes are stored exactly as they arrived. Decoding a photo and
    /// re-encoding it as PNG costs about a second for 6 MP, changes the file
    /// the user gets back, and used to run inside the drop callback.
    private func storePayload(item: ShelfItem, data: Data, fileExtension: String, into key: ShelfKey) {
        copyQueue.async { [weak self] in
            guard let self else { return }
            let relative = self.store.writeData(data, itemID: item.id, fileExtension: fileExtension)
            DispatchQueue.main.async {
                self.pendingItems.remove(item.id)
                guard let relative else {
                    // The payload was not a decodable image after all, so the
                    // placeholder should not stay on the shelf.
                    self.remove(item: item, from: key)
                    NSSound.beep()
                    return
                }
                self.updateItem(id: item.id, in: key) { $0.relativePath = relative }
                self.windows[key]?.refreshItem(id: item.id)
                self.save()
            }
        }
    }

    /// Imports RTF, flat RTFD, or HTML that carried no plain-text flavour.
    ///
    /// This runs on the next main-runloop turn. `NSAttributedString`'s HTML
    /// importer synchronises with the main thread by design, and a cold import
    /// measured 675 ms, so it must never run inside AppKit's drop callback.
    private func decodeRichText(item: ShelfItem,
                                data: Data,
                                documentType: NSAttributedString.DocumentType,
                                into key: ShelfKey) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingItems.remove(item.id)
            let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: documentType],
                documentAttributes: nil
            )
            guard let text = attributed?.string, IngestPayload.hasReadableText(text) else {
                // A fragment that was nothing but an inline picture decodes to
                // a single object-replacement character; there is no card here.
                self.remove(item: item, from: key)
                NSSound.beep()
                return
            }
            self.updateItem(id: item.id, in: key) {
                $0.text = text
                $0.displayName = IngestPayload.firstLine(of: text)
            }
            self.windows[key]?.refreshItem(id: item.id)
            self.save()
        }
    }

    private func ingestPromise(_ receiver: NSFilePromiseReceiver, into key: ShelfKey) {
        var state = ensureState(for: key)
        let id = UUID()
        let destination = store.itemsURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let item = ShelfItem(kind: .file,
                             displayName: receiver.fileNames.first ?? L10n.incomingFile)
        state.items.append(item)
        states[key] = state
        pendingItems.insert(item.id)

        receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: .main) { [weak self] url, error in
            guard let self else { return }
            self.pendingItems.remove(item.id)
            if error == nil {
                let relative = "\(id.uuidString)/\(url.lastPathComponent)"
                self.updateItem(id: item.id, in: key) {
                    $0.relativePath = relative
                    $0.displayName = url.lastPathComponent
                }
            } else {
                NSLog("EdgeShelf: file promise failed: \(String(describing: error))")
                self.updateItem(id: item.id, in: key) {
                    $0.displayName = L10n.unavailableFile
                }
            }
            self.windows[key]?.refreshItem(id: item.id)
            self.save()
        }
    }

    // MARK: - Item actions

    func remove(item: ShelfItem, from key: ShelfKey, deleteFiles: Bool = true) {
        guard var state = states[key],
              let index = state.items.firstIndex(where: { $0.id == item.id }) else { return }
        state.items.remove(at: index)
        states[key] = state
        pendingItems.remove(item.id)
        if deleteFiles {
            store.deleteFiles(for: item.id)
        }
        save()
        windows[key]?.refresh()
        updateHeights(animated: true)

        if state.items.isEmpty, prefs.closeWhenEmpty {
            windows[key]?.setPresentation(.hidden)
            cancelAutoHide(key)
            hoveredKeys.remove(key)
        } else {
            scheduleAutoHide(key)
        }
    }

    func didDragOut(item: ShelfItem, from key: ShelfKey) {
        guard prefs.removeAfterDragOut else { return }
        // Give the destination time to copy the file before the item leaves
        // the shelf. The files themselves are cleaned up on next launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.remove(item: item, from: key, deleteFiles: false)
        }
    }

    func closeShelf(_ key: ShelfKey) {
        guard let state = states[key] else { return }
        for item in state.items {
            store.deleteFiles(for: item.id)
        }
        states[key] = ShelfState(key: key)
        save()
        windows[key]?.refresh()
        windows[key]?.setPresentation(.hidden)
        cancelAutoHide(key)
        hoveredKeys.remove(key)
        updateHeights(animated: true)
    }

    // MARK: - Menu commands

    func showAllNonEmpty() {
        for (key, controller) in windows where !items(for: key).isEmpty {
            controller.setPresentation(.expanded)
            scheduleAutoHide(key)
        }
        updateHeights(animated: true)
    }

    func hideEmptyShelves() {
        for (key, controller) in windows where items(for: key).isEmpty {
            controller.setPresentation(.hidden)
        }
    }

    /// Asks for confirmation and empties a shelf.
    ///
    /// Both the panel's own menu and each card's menu route through here, so
    /// "clear" is one action with one warning however it is reached.
    func clearShelfAfterConfirmation(_ key: ShelfKey) {
        guard !items(for: key).isEmpty else { return }
        if ShelfConfirmation.clearShelf() {
            closeShelf(key)
        }
    }

    func closeAllShelves() {
        for key in windows.keys {
            closeShelf(key)
        }
    }

    /// True when at least one shelf still holds something, so destructive
    /// menu items are not offered when there is nothing to clear.
    var hasAnyItems: Bool {
        states.values.contains { !$0.items.isEmpty }
    }

    func flush() {
        store.saveNow(Array(states.values))
    }

    // MARK: - Debug

    func debugState() -> String {
        var lines: [String] = []
        lines.append("isDragging=\(isDragging)")
        lines.append("hovered=\(hoveredKeys.map(\.edge.rawValue))")
        lines.append("timers=\(autoHideTimers.count)")
        for (key, controller) in windows {
            lines.append("\(key.edge.rawValue): presentation=\(controller.presentation) alpha=\(controller.window?.alphaValue ?? -1) items=\(items(for: key).count)")
        }
        return lines.joined(separator: "\n")
    }

    /// Prints what a right-click offers, so the shelf and card menus can be
    /// asserted without driving the GUI.
    func debugMenus() -> String {
        var lines: [String] = []
        let ordered = windows.sorted { $0.key.edge.rawValue < $1.key.edge.rawValue }
        for (key, controller) in ordered {
            let items = items(for: key)
            let titles = controller.shelfView.makeContextMenu()?
                .items.map { $0.isSeparatorItem ? "---" : $0.title } ?? ["<none>"]
            lines.append("\(key.edge.rawValue) shelf(count=\(items.count)): \(titles.joined(separator: " | "))")

            guard let first = controller.shelfView.itemViews.values.first else { continue }
            let cardTitles = first.makeContextMenu().items.map { $0.isSeparatorItem ? "---" : $0.title }
            lines.append("\(key.edge.rawValue) card(\(first.item.kind.rawValue)): \(cardTitles.joined(separator: " | "))")
        }
        return lines.joined(separator: "\n")
    }

    func showEmptyShelfForSnapshot() {
        guard let key = windows.keys.first(where: { $0.edge == .left }) else { return }
        windows[key]?.setPresentation(.expanded, animated: false)
    }

    /// Used by `--demo` to exercise the shelf UI without a mouse drag.
    func addDemoItems() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let key = ShelfKey(screenID: screen.edgeShelfDisplayID, edge: .left)
        var state = ensureState(for: key)

        state.items.append(ShelfItem(kind: .text,
                                     displayName: L10n.demoWelcomeTitle,
                                     text: L10n.demoWelcomeText))

        if CommandLine.arguments.contains("--snapshot-many") {
            state.items.append(ShelfItem(kind: .text,
                                         displayName: L10n.demoDesignTitle,
                                         text: L10n.demoDesignText))
            state.items.append(ShelfItem(kind: .url,
                                         displayName: "pilotmoon.com",
                                         urlString: "https://pilotmoon.com/dropshelf/"))
            state.items.append(ShelfItem(kind: .text,
                                         displayName: L10n.demoReadingTitle,
                                         text: L10n.demoReadingText))
            state.items.append(ShelfItem(kind: .text,
                                         displayName: L10n.demoScreenshotTitle,
                                         text: L10n.demoScreenshotText))
        }

        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(L10n.demoFileName)
        try? L10n.demoFileText.write(to: fileURL, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            let item = ShelfItem(kind: .file,
                                 displayName: fileURL.lastPathComponent,
                                 originalPath: fileURL.path)
            state.items.append(item)
            pendingItems.insert(item.id)
            copyInBackground(item: item, from: fileURL, into: key)
        }

        states[key] = state
        save()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.windows[key]?.refresh()
            self?.windows[key]?.setPresentation(.expanded)
            self?.updateHeights(animated: true)
        }
    }

    /// Used by `--snapshot-collapsed`; demo mode intentionally keeps the shelf
    /// expanded so the other snapshot modes can render it.
    func collapseForSnapshot() {
        guard let key = windows.keys.first(where: { $0.edge == .left }) else { return }
        windows[key]?.setPresentation(.collapsed, animated: false)
    }
}
