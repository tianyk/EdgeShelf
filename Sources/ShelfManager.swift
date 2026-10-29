import AppKit
import UniformTypeIdentifiers

/// Owns shelf state, disk persistence, and the pre-created edge windows.
///
/// Threading rule: every method here is called on the main thread. File checks
/// and writes for stored payloads run on `ioQueue` and report back with
/// DispatchQueue.main.async.
final class ShelfManager {
    private let store = Store.shared
    private let prefs = Preferences.shared
    private let ioQueue = DispatchQueue(label: "com.doge.edgeshelf.io", qos: .utility)
    private var states: [ShelfKey: ShelfState] = [:]
    /// Groups the user has expanded. The membership itself lives on
    /// `ShelfItem.groupID`; this is only the current presentation state.
    private var expandedGroups: Set<UUID> = []
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
    private var reconcileInFlight = false
    private var pendingReconcile = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var fileWatchers: [UUID: FileWatcher] = [:]
    private var watchGenerations: [UUID: UUID] = [:]
    private var desktopRevealTimer: Timer?
    private var desktopRevealLevel: NSWindow.Level?

    private struct MissingFile {
        let key: ShelfKey
        let id: UUID
        let name: String
        let originalPath: String?
        let relativePath: String?
        /// The watcher generation when the path was checked, if a watcher was
        /// active. A mismatch means the file moved while the check was in
        /// flight, so the result is stale.
        let generation: UUID?
    }

    private struct MovedFile {
        let key: ShelfKey
        let id: UUID
        let generation: UUID
        let watchedPath: String
        let newPath: String
    }

    private struct DeferredWatchEvent {
        let resolution: FileWatcher.Resolution
        let itemID: UUID
        let generation: UUID
        let watchedPath: String
    }

    private var deferredWatchEvents: [DeferredWatchEvent] = []

    init() {
        for state in store.loadStates() {
            states[state.key] = state
        }
        normalizeGroups()
        if store.loadFailed {
            // The state file was unreadable and has been moved aside. Every
            // item folder is therefore unreferenced, and pruning now would
            // delete stored images and promised files the user may still want.
            // Keep them and let the next successful save take over.
            NSLog("EdgeShelf: skipping the item cleanup after an unreadable shelves.json")
        } else {
            migrateLegacyCopies()
            let referenced = Set(states.values.flatMap { state in
                state.items.compactMap { $0.relativePath == nil ? nil : $0.id }
            })
            store.cleanUnreferencedFolders(referenced: referenced)
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.scheduleRebuild()
        }

        // If the app launches while Show Desktop is already revealed, the
        // windows have to be born above the reveal window, not behind it.
        desktopRevealLevel = Self.desktopRevealLayer().map { NSWindow.Level(rawValue: $0 + 1) }
        rebuildWindows()
        startDesktopRevealPolling()
        ensureFileWatchers()
        observeWorkspaceEvents()
        reconcileFileItems()
    }

    deinit {
        desktopRevealTimer?.invalidate()
        for token in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        for watcher in fileWatchers.values {
            watcher.cancel()
        }
    }

    // MARK: - Legacy storage

    /// A group only makes sense with at least two surviving members. A crash
    /// between removing a member and saving, or a file deleted on disk while
    /// the app was closed, can leave a lone member behind; show it as a
    /// normal card again.
    private func normalizeGroups() {
        var changed = false
        for key in Array(states.keys) {
            guard var state = states[key] else { continue }
            var counts: [UUID: Int] = [:]
            for item in state.items {
                if let groupID = item.groupID {
                    counts[groupID, default: 0] += 1
                }
            }
            var stateChanged = false
            for index in state.items.indices {
                guard let groupID = state.items[index].groupID,
                      (counts[groupID] ?? 0) < 2 else { continue }
                state.items[index].groupID = nil
                stateChanged = true
            }
            if stateChanged {
                states[key] = state
                changed = true
            }
        }
        if changed {
            save()
        }
    }

    /// Older versions copied everything into Items/. Where the original is
    /// still there, that copy is redundant: drop the local path and keep a
    /// plain reference, and the launch cleanup reclaims the disk space. A copy
    /// whose original is already gone is the only remaining content, so it
    /// stays available on the shelf.
    private func migrateLegacyCopies() {
        var changed = false
        for key in Array(states.keys) {
            guard var state = states[key] else { continue }
            for index in state.items.indices {
                guard state.items[index].relativePath != nil,
                      let original = state.items[index].originalPath,
                      FileManager.default.fileExists(atPath: original) else { continue }
                state.items[index].relativePath = nil
                changed = true
            }
            states[key] = state
        }
        if changed {
            NSLog("EdgeShelf: switched legacy item copies to direct references")
            save()
        }
    }

    // MARK: - Source file changes

    /// Watchers do the work while the app is running. There is no periodic
    /// timer: a one-off reconciliation runs at launch, after sleep, and when a
    /// volume is mounted or unmounted. That catches anything that happened
    /// while no watcher was alive, without polling the file system.
    private func observeWorkspaceEvents() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didWakeNotification,
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.reconcileFileItems()
            }
            workspaceObservers.append(token)
        }
    }

    private func reconcileFileItems() {
        guard !isDragging else {
            pendingReconcile = true
            return
        }
        guard !reconcileInFlight else {
            pendingReconcile = true
            return
        }

        var candidates: [(key: ShelfKey, item: ShelfItem)] = []
        for (key, state) in states {
            for item in state.items
            where item.isFileBacked && !pendingItems.contains(item.id) {
                candidates.append((key, item))
            }
        }
        guard !candidates.isEmpty else {
            ensureFileWatchers()
            return
        }
        reconcileInFlight = true
        let watchers = fileWatchers
        let generations = watchGenerations

        ioQueue.async { [weak self] in
            guard let self else { return }
            var missing: [MissingFile] = []
            var moved: [MovedFile] = []
            var unmounted: [UUID] = []

            for candidate in candidates where !self.store.isReachable(candidate.item) {
                // An unmounted drive is not a deleted file. Keep the item so a
                // reconnected volume brings it back.
                if let original = candidate.item.originalPath,
                   Self.isOnUnmountedVolume(original) {
                    unmounted.append(candidate.item.id)
                    continue
                }

                // An ancestor folder can be renamed without the file's own
                // vnode receiving an event. The open descriptor can still
                // tell us where the same inode lives now.
                if let original = candidate.item.originalPath,
                   let watcher = watchers[candidate.item.id],
                   let generation = generations[candidate.item.id] {
                    switch watcher.resolve() {
                    case .moved(let newPath):
                        moved.append(MovedFile(key: candidate.key,
                                               id: candidate.item.id,
                                               generation: generation,
                                               watchedPath: original,
                                               newPath: newPath))
                        continue
                    case .unchanged, .replaced:
                        // The path reappeared; leave it alone.
                        continue
                    case .gone, .revoked:
                        break
                    }
                }

                missing.append(MissingFile(key: candidate.key,
                                           id: candidate.item.id,
                                           name: candidate.item.displayName,
                                           originalPath: candidate.item.originalPath,
                                           relativePath: candidate.item.relativePath,
                                           generation: watchers[candidate.item.id] != nil
                                               ? generations[candidate.item.id]
                                               : nil))
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reconcileInFlight = false
                self.applyMissingFileCheck(missing, moved: moved, unmounted: unmounted)
                if self.pendingReconcile {
                    self.pendingReconcile = false
                    self.reconcileFileItems()
                }
            }
        }
    }

    private func applyMissingFileCheck(_ missing: [MissingFile],
                                       moved: [MovedFile],
                                       unmounted: [UUID]) {
        for entry in moved {
            guard watchGenerations[entry.id] == entry.generation,
                  let (key, item) = location(of: entry.id),
                  item.originalPath == entry.watchedPath else { continue }
            followMove(item: item, to: entry.newPath, in: key)
        }

        // A dead watcher on an unmounted volume would otherwise stay in the
        // table forever; dropping it lets `ensureFileWatchers` retry later.
        for itemID in unmounted {
            stopWatcher(for: itemID)
        }
        for entry in missing {
            guard let item = states[entry.key]?.items.first(where: { $0.id == entry.id }),
                  !pendingItems.contains(item.id),
                  item.originalPath == entry.originalPath,
                  item.relativePath == entry.relativePath,
                  entry.generation == nil || watchGenerations[item.id] == entry.generation else { continue }
            NSLog("EdgeShelf: removing \(entry.name) because its file is gone")
            remove(item: item, from: entry.key)
        }
        ensureFileWatchers()
    }

    // MARK: - File watchers

    private func ensureFileWatchers() {
        var wanted: [UUID: String] = [:]
        for state in states.values {
            for item in state.items where item.isFileBacked && item.relativePath == nil {
                guard let path = item.originalPath else { continue }
                wanted[item.id] = path
            }
        }

        for itemID in Array(fileWatchers.keys) {
            guard let watcher = fileWatchers[itemID] else { continue }
            if wanted[itemID] != watcher.path {
                stopWatcher(for: itemID)
            }
        }
        for itemID in Array(watchGenerations.keys) where wanted[itemID] == nil {
            stopWatcher(for: itemID)
        }

        for state in states.values {
            for item in state.items where wanted[item.id] != nil {
                guard fileWatchers[item.id] == nil,
                      watchGenerations[item.id] == nil else { continue }
                startWatcher(for: item)
            }
        }
    }

    private func startWatcher(for item: ShelfItem) {
        guard item.isFileBacked, item.relativePath == nil,
              let path = item.originalPath else { return }
        if let existing = fileWatchers[item.id], existing.path == path { return }

        let itemID = item.id
        let generation = UUID()
        watchGenerations[itemID] = generation

        ioQueue.async { [weak self] in
            guard let self else { return }
            guard let watcher = FileWatcher(path: path, queue: self.ioQueue, handler: { [weak self] resolution in
                self?.deliverWatchResolution(resolution,
                                             itemID: itemID,
                                             generation: generation,
                                             watchedPath: path)
            }) else {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.watchGenerations[itemID] == generation else { return }
                    self.watchGenerations[itemID] = nil
                }
                return
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.watchGenerations[itemID] == generation else {
                    watcher.cancel()
                    return
                }
                self.fileWatchers[itemID] = watcher
            }
        }
    }

    private func stopWatcher(for itemID: UUID) {
        watchGenerations[itemID] = nil
        fileWatchers.removeValue(forKey: itemID)?.cancel()
    }

    private func deliverWatchResolution(_ resolution: FileWatcher.Resolution,
                                        itemID: UUID,
                                        generation: UUID,
                                        watchedPath: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Rebuilding the shelf inside a drag is exactly what this app
            // avoids; hold the event until the drag ends.
            guard !self.isDragging else {
                self.deferredWatchEvents.append(DeferredWatchEvent(resolution: resolution,
                                                                   itemID: itemID,
                                                                   generation: generation,
                                                                   watchedPath: watchedPath))
                return
            }
            self.applyWatchResolution(resolution,
                                      itemID: itemID,
                                      generation: generation,
                                      watchedPath: watchedPath)
        }
    }

    private func applyWatchResolution(_ resolution: FileWatcher.Resolution,
                                      itemID: UUID,
                                      generation: UUID,
                                      watchedPath: String) {
        guard watchGenerations[itemID] == generation,
              let (key, item) = location(of: itemID),
              item.originalPath == watchedPath else { return }

        switch resolution {
        case .unchanged:
            break
        case .replaced:
            refreshReplacedFile(item: item, in: key)
            rearmWatcher(for: itemID)
        case .moved(let newPath):
            followMove(item: item, to: newPath, in: key)
        case .gone:
            remove(item: item, from: key)
        case .revoked:
            // The volume is unavailable, not deleted. Keep the item and let
            // the next launch/wake/mount reconciliation retry the watcher.
            stopWatcher(for: itemID)
        }
    }

    private func flushDeferredWatchEvents() {
        guard !isDragging, !deferredWatchEvents.isEmpty else { return }
        let events = deferredWatchEvents
        deferredWatchEvents.removeAll()
        for event in events {
            applyWatchResolution(event.resolution,
                                 itemID: event.itemID,
                                 generation: event.generation,
                                 watchedPath: event.watchedPath)
        }
    }

    private func rearmWatcher(for itemID: UUID) {
        guard let (_, item) = location(of: itemID) else { return }
        stopWatcher(for: itemID)
        startWatcher(for: item)
    }

    private func refreshReplacedFile(item: ShelfItem, in key: ShelfKey) {
        guard let path = item.originalPath else { return }
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let isDirectory = values?.isDirectory ?? (item.kind == .folder)
        let isImage = !isDirectory
            && UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
        updateItem(id: item.id, in: key) {
            $0.byteSize = values?.fileSize.map(Int64.init)
            $0.kind = isDirectory ? .folder : (isImage ? .image : .file)
        }
        windows[key]?.refreshItem(id: item.id, reloadThumbnail: true)
    }

    private func followMove(item: ShelfItem, to path: String, in key: ShelfKey) {
        let url = URL(fileURLWithPath: path)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        let isDirectory = values?.isDirectory ?? (item.kind == .folder)
        let isImage = !isDirectory
            && UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true

        updateItem(id: item.id, in: key) {
            $0.originalPath = path
            $0.displayName = url.lastPathComponent
            $0.byteSize = values?.fileSize.map(Int64.init)
            $0.kind = isDirectory ? .folder : (isImage ? .image : .file)
        }
        stopWatcher(for: item.id)
        guard let moved = states[key]?.items.first(where: { $0.id == item.id }) else { return }
        startWatcher(for: moved)
        windows[key]?.refreshItem(id: item.id)
    }

    private func location(of itemID: UUID) -> (ShelfKey, ShelfItem)? {
        for (key, state) in states {
            if let item = state.items.first(where: { $0.id == itemID }) {
                return (key, item)
            }
        }
        return nil
    }

    /// True when the path sits on a volume that is currently not mounted.
    /// Without this, unplugging a drive would quietly empty its shelf.
    private static func isOnUnmountedVolume(_ path: String) -> Bool {
        let parts = (path as NSString).pathComponents
        guard parts.count > 2, parts[1] == "Volumes" || parts[1] == "Network" else {
            return false
        }
        return !FileManager.default.fileExists(atPath: "/\(parts[1])/\(parts[2])")
    }

    // MARK: - State access

    func items(for key: ShelfKey) -> [ShelfItem] {
        states[key]?.items ?? []
    }

    /// What the shelf actually shows: standalone cards, group headers, and —
    /// when expanded — the group's members.
    func rows(for key: ShelfKey) -> [ShelfRow] {
        Self.buildRows(items: items(for: key), expandedGroups: expandedGroups)
    }

    /// Pure row builder, so the grouping rules can be covered by `--self-test`
    /// without starting the window server.
    static func buildRows(items all: [ShelfItem],
                          expandedGroups: Set<UUID>) -> [ShelfRow] {
        var rows: [ShelfRow] = []
        var seenGroups: Set<UUID> = []
        for item in all {
            guard let groupID = item.groupID else {
                rows.append(.item(item))
                continue
            }
            guard !seenGroups.contains(groupID) else { continue }
            seenGroups.insert(groupID)
            let members = all.filter { $0.groupID == groupID }
            if members.count > 1 {
                rows.append(.group(id: groupID, items: members))
                if expandedGroups.contains(groupID) {
                    rows.append(contentsOf: members.map { .member($0, groupID: groupID) })
                }
            } else if let only = members.first {
                rows.append(.item(only))
            }
        }
        return rows
    }

    /// The number of cards currently on the shelf, which is what the window
    /// height is based on. An expanded group counts its members too.
    func displayCount(for key: ShelfKey) -> Int {
        rows(for: key).count
    }

    func isGroupExpanded(_ groupID: UUID) -> Bool {
        expandedGroups.contains(groupID)
    }

    func toggleGroup(_ groupID: UUID, in key: ShelfKey) {
        guard states[key]?.items.contains(where: { $0.groupID == groupID }) == true else { return }
        if expandedGroups.contains(groupID) {
            expandedGroups.remove(groupID)
        } else {
            expandedGroups.insert(groupID)
        }
        // The click may have come from a view that is about to be replaced by
        // refresh(); let AppKit finish dispatching first.
        DispatchQueue.main.async { [weak self] in
            self?.windows[key]?.refresh()
            self?.updateHeights(animated: true)
        }
    }

    /// Break a group apart without removing any of its files.
    func ungroup(_ groupID: UUID, in key: ShelfKey) {
        guard var state = states[key] else { return }
        var changed = false
        for index in state.items.indices where state.items[index].groupID == groupID {
            state.items[index].groupID = nil
            changed = true
        }
        guard changed else { return }
        states[key] = state
        expandedGroups.remove(groupID)
        save()
        windows[key]?.refresh()
        updateHeights(animated: true)
    }

    /// The URL the user should get when opening, revealing, copying, or
    /// dragging an item out. Preference order:
    ///   1. the original file, when the item references one and it still exists,
    ///   2. the store's own file, for pasted images, promised files, and
    ///      legacy copies whose original is gone.
    func userFacingURL(for item: ShelfItem) -> URL? {
        store.absoluteURL(for: item)
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

    /// The layer of the Dock's Show Desktop reveal window, or nil when the
    /// desktop is not revealed.
    ///
    /// Show Desktop has no notification and no public state. While it is
    /// active, the Dock owns an on-screen window at a layer between the
    /// desktop and the Dock itself (layer 18 on macOS 26) that is exactly one
    /// screen in size. In normal use the Dock only has windows at negative
    /// layers and at its own bar level (20), so this window is the state we
    /// can observe. The query returns window metadata only; it needs no
    /// Screen Recording permission.
    private static func desktopRevealLayer() -> Int? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let screenSizes = NSScreen.screens.map { $0.frame.size }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int32) == dock.processIdentifier,
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer > 0, layer < 20,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"],
                  screenSizes.contains(where: { abs($0.width - width) < 2 && abs($0.height - height) < 2 }) else {
                continue
            }
            return layer
        }
        return nil
    }

    /// Show Desktop is only observable by looking. Poll at the same cadence as
    /// the drag watchdog; one window-list query takes about a millisecond.
    private func startDesktopRevealPolling() {
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.pollDesktopReveal()
        }
        RunLoop.main.add(timer, forMode: .common)
        desktopRevealTimer = timer
    }

    private func pollDesktopReveal() {
        if let layer = Self.desktopRevealLayer() {
            // A reveal that starts mid-drag is picked up after the drag ends.
            guard !isDragging else { return }
            let level = NSWindow.Level(rawValue: layer + 1)
            guard desktopRevealLevel != level else { return }
            let wasRevealed = desktopRevealLevel != nil
            desktopRevealLevel = level
            if wasRevealed {
                setShelfWindowLevel(level)
            } else {
                NSLog("EdgeShelf: Show Desktop is active; rebuilding the edge windows")
                rebuildWindowsNow(expandNonEmpty: false)
            }
        } else if desktopRevealLevel != nil, !isDragging {
            // Keep the raised level until a drag ends; lowering it mid-drag
            // would take the drop target out from under the pointer.
            desktopRevealLevel = nil
            setShelfWindowLevel(.floating)
        }
    }

    private func setShelfWindowLevel(_ level: NSWindow.Level) {
        for controller in windows.values {
            controller.window?.level = level
        }
    }

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
        rebuildWindowsNow(expandNonEmpty: true)
    }

    /// Replaces every edge window. Existing windows are closed first.
    ///
    /// `expandNonEmpty` is false when rebuilding during Show Desktop: the new
    /// windows start in their resting state and are expanded by the drag
    /// preview as usual.
    private func rebuildWindowsNow(expandNonEmpty: Bool) {
        needsRebuild = false
        activePreview = nil

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
                let count = displayCount(for: key)
                let controller = ShelfWindowController(key: key,
                                                       frame: frame(for: screen, edge: edge, itemCount: count),
                                                       level: desktopRevealLevel ?? .floating,
                                                       manager: self)
                windows[key] = controller
                if count > 0 {
                    controller.setPresentation(expandNonEmpty ? .expanded : .collapsed, animated: false)
                    if expandNonEmpty {
                        scheduleAutoHide(key)
                    }
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

        // The half-second poll may not have seen a reveal that began just
        // before the drag. Rebuild on the next run-loop turn, before the
        // pointer can reach an edge, so the drag finds a live shelf there.
        guard desktopRevealLevel == nil, let layer = Self.desktopRevealLayer() else { return }
        desktopRevealLevel = NSWindow.Level(rawValue: layer + 1)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.isDragging else {
                // The drag ended first; let the poll rebuild when idle.
                self.desktopRevealLevel = nil
                return
            }
            self.rebuildWindowsNow(expandNonEmpty: false)
            self.updateDrag(cursor: NSEvent.mouseLocation)
        }
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
        flushDeferredWatchEvents()
        if pendingReconcile {
            pendingReconcile = false
            reconcileFileItems()
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
            controller.resize(forItemCount: displayCount(for: key), animated: animated)
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
            let groupID = (prefs.mergeDroppedFiles && receivers.count > 1) ? UUID() : nil
            for receiver in receivers {
                ingestPromise(receiver, into: key, groupID: groupID)
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
            var newFileItems: [ShelfItem] = []
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
                    newFileItems.append(item)
                    added = true
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

            // One Finder drag is one record. The group is derived from the
            // items themselves, so each file keeps its own watcher and can
            // still be removed individually after expanding the group.
            if prefs.mergeDroppedFiles, newFileItems.count > 1 {
                let groupID = UUID()
                let ids = Set(newFileItems.map(\.id))
                for index in state.items.indices where ids.contains(state.items[index].id) {
                    state.items[index].groupID = groupID
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
        ensureFileWatchers()

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

    /// Writes bitmap bytes that arrived on the pasteboard.
    ///
    /// The bytes are stored exactly as they arrived. Decoding a photo and
    /// re-encoding it as PNG costs about a second for 6 MP, changes the file
    /// the user gets back, and used to run inside the drop callback.
    private func storePayload(item: ShelfItem, data: Data, fileExtension: String, into key: ShelfKey) {
        ioQueue.async { [weak self] in
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

    private func ingestPromise(_ receiver: NSFilePromiseReceiver, into key: ShelfKey, groupID: UUID? = nil) {
        var state = ensureState(for: key)
        let id = UUID()
        let destination = store.itemsURL.appendingPathComponent(id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let item = ShelfItem(kind: .file,
                             displayName: receiver.fileNames.first ?? L10n.incomingFile,
                             groupID: groupID)
        state.items.append(item)
        states[key] = state
        pendingItems.insert(item.id)

        receiver.receivePromisedFiles(atDestination: destination, options: [:], operationQueue: .main) { [weak self] url, error in
            guard let self else { return }
            self.pendingItems.remove(item.id)
            guard error == nil else {
                NSLog("EdgeShelf: file promise failed: \(String(describing: error))")
                self.remove(item: item, from: key)
                NSSound.beep()
                return
            }
            let relative = "\(id.uuidString)/\(url.lastPathComponent)"
            self.updateItem(id: item.id, in: key) {
                $0.relativePath = relative
                $0.displayName = url.lastPathComponent
            }
            self.windows[key]?.refreshItem(id: item.id)
            self.save()
        }
    }

    // MARK: - Item actions

    func remove(item: ShelfItem, from key: ShelfKey, deleteFiles: Bool = true) {
        removeItems([item], from: key, deleteFiles: deleteFiles)
    }

    func removeGroup(_ groupID: UUID, in key: ShelfKey) {
        guard let state = states[key] else { return }
        let members = state.items.filter { $0.groupID == groupID }
        guard !members.isEmpty else { return }
        removeItems(members, from: key, deleteFiles: true)
    }

    private func removeItems(_ items: [ShelfItem], from key: ShelfKey, deleteFiles: Bool) {
        guard var state = states[key], !items.isEmpty else { return }
        let ids = Set(items.map(\.id))
        let groupIDs = Set(items.compactMap(\.groupID))
        state.items.removeAll { ids.contains($0.id) }

        for item in items {
            pendingItems.remove(item.id)
            stopWatcher(for: item.id)
            if deleteFiles {
                store.deleteFiles(for: item.id)
            }
        }

        // A group with one member is no longer a group. This also covers a
        // file removed by its watcher while the group was expanded.
        for groupID in groupIDs {
            let remaining = state.items.filter { $0.groupID == groupID }
            if remaining.count <= 1 {
                for index in state.items.indices where state.items[index].groupID == groupID {
                    state.items[index].groupID = nil
                }
                expandedGroups.remove(groupID)
            }
        }

        states[key] = state
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
        didDragOut(items: [item], from: key)
    }

    /// Called once a drag session completes. A group drops all of its members
    /// in one session, so the removal has to be a batch operation too.
    func didDragOut(items: [ShelfItem], from key: ShelfKey) {
        guard prefs.removeAfterDragOut, !items.isEmpty else { return }
        let ids = Set(items.map(\.id))
        // Give the destination time to start reading the original file before
        // the cards leave the shelf. Removing a card never touches user files.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, let state = self.states[key] else { return }
            let current = state.items.filter { ids.contains($0.id) }
            self.removeItems(current, from: key, deleteFiles: false)
        }
    }

    func closeShelf(_ key: ShelfKey) {
        guard let state = states[key] else { return }
        for item in state.items {
            if let groupID = item.groupID {
                expandedGroups.remove(groupID)
            }
            stopWatcher(for: item.id)
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
        lines.append("desktopRevealed=\(desktopRevealLevel != nil)")
        lines.append("hovered=\(hoveredKeys.map(\.edge.rawValue))")
        lines.append("timers=\(autoHideTimers.count)")
        for (key, controller) in windows {
            lines.append("\(key.edge.rawValue): presentation=\(controller.presentation) alpha=\(controller.window?.alphaValue ?? -1) items=\(items(for: key).count) rows=\(displayCount(for: key))")
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

            if let group = controller.shelfView.groupViews.values.first {
                let groupTitles = group.makeContextMenu().items.map { $0.isSeparatorItem ? "---" : $0.title }
                lines.append("\(key.edge.rawValue) group(\(group.items.count)): \(groupTitles.joined(separator: " | "))")
            }

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
        }

        // Debug-only group content for `--snapshot-groups`. It exercises a
        // collapsed summary card and, with `--expand-groups`, its members.
        if CommandLine.arguments.contains("--snapshot-groups") {
            let directory = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("EdgeShelf-GroupDemo", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let groupID = UUID()
            let names = ["Roadmap.pdf", "Budget.xlsx", "Notes.md"]
            for name in names {
                let url = directory.appendingPathComponent(name)
                let body = "EdgeShelf group demo: \(name)"
                try? body.write(to: url, atomically: true, encoding: .utf8)
                let size = Int64(body.utf8.count)
                state.items.append(ShelfItem(kind: .file,
                                             displayName: name,
                                             groupID: groupID,
                                             originalPath: url.path,
                                             byteSize: size))
            }
        }

        states[key] = state
        save()
        ensureFileWatchers()

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
