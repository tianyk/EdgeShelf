import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

// MARK: - Small controls

class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class HoverIconButton: FirstMouseButton {
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = frameRect.height / 2
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Thumbnails

private let thumbnailCache = NSCache<NSString, NSImage>()

private extension NSImage {
    func squareCropped() -> NSImage {
        let side = min(size.width, size.height)
        guard side > 0 else { return self }
        let source = NSRect(x: (size.width - side) / 2,
                            y: (size.height - side) / 2,
                            width: side,
                            height: side)
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            self.draw(in: rect, from: source, operation: .copy, fraction: 1)
            return true
        }
    }
}

enum ThumbnailLoader {
    static func invalidate(itemID: UUID) {
        thumbnailCache.removeObject(forKey: itemID.uuidString as NSString)
    }

    static func icon(for item: ShelfItem, store: Store, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = item.id.uuidString as NSString
        if let cached = thumbnailCache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        guard let url = store.absoluteURL(for: item) else {
            let image = generatedIcon(for: item, url: nil)
            thumbnailCache.setObject(image, forKey: cacheKey)
            completion(image)
            return
        }

        if item.kind == .image, let image = NSImage(contentsOf: url) {
            let cropped = image.squareCropped()
            thumbnailCache.setObject(cropped, forKey: cacheKey)
            completion(cropped)
            return
        }

        if shouldUseQuickLook(url) {
            let fallback = generatedIcon(for: item, url: url)
            let request = QLThumbnailGenerator.Request(fileAt: url,
                                                       size: CGSize(width: 96, height: 96),
                                                       scale: 2,
                                                       representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                let image = representation?.nsImage ?? fallback
                thumbnailCache.setObject(image, forKey: cacheKey)
                DispatchQueue.main.async { completion(image) }
            }
        } else {
            let image = generatedIcon(for: item, url: url)
            thumbnailCache.setObject(image, forKey: cacheKey)
            completion(image)
        }
    }

    private static func shouldUseQuickLook(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let types: Set<String> = [
            "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx",
            "key", "pages", "numbers", "rtf", "rtfd",
            "mp4", "mov", "m4v", "avi", "mkv",
            "psd", "sketch", "fig",
        ]
        return types.contains(ext)
    }

    private static func generatedIcon(for item: ShelfItem, url: URL?) -> NSImage {
        let size = NSSize(width: 96, height: 96)
        let ext = url?.pathExtension.lowercased() ?? ""
        let (background, symbol, label) = style(for: item, ext: ext)

        return NSImage(size: size, flipped: false) { rect in
            let inset = rect.insetBy(dx: 5, dy: 5)
            let path = NSBezierPath(roundedRect: inset, xRadius: 18, yRadius: 18)
            background.setFill()
            path.fill()

            // Subtle top sheen.
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let gradient = NSGradient(colors: [
                NSColor.white.withAlphaComponent(0.18),
                NSColor.white.withAlphaComponent(0.0),
            ])
            gradient?.draw(in: inset, angle: -90)
            NSGraphicsContext.restoreGraphicsState()

            let config = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white.withAlphaComponent(0.95)]))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let imageSize = image.size
                let target = NSRect(x: (rect.width - imageSize.width) / 2,
                                    y: (rect.height - imageSize.height) / 2 + 6,
                                    width: imageSize.width,
                                    height: imageSize.height)
                image.draw(in: target)
            }

            if !label.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.88),
                ]
                let string = NSAttributedString(string: label.uppercased(), attributes: attributes)
                let stringSize = string.size()
                string.draw(at: NSPoint(x: (rect.width - stringSize.width) / 2, y: 12))
            }
            return true
        }
    }

    private static func style(for item: ShelfItem, ext: String) -> (NSColor, String, String) {
        switch item.kind {
        case .folder:
            return (NSColor(calibratedRed: 0.30, green: 0.51, blue: 0.78, alpha: 1), "folder.fill", "")
        case .url:
            return (NSColor(calibratedRed: 0.20, green: 0.55, blue: 0.53, alpha: 1), "link", "")
        case .image:
            return (NSColor(calibratedRed: 0.36, green: 0.45, blue: 0.62, alpha: 1), "photo.fill", ext)
        case .text:
            return (colorForExtension(ext), "doc.text.fill", ext)
        case .file:
            return (colorForExtension(ext), "doc.fill", ext)
        }
    }

    private static func colorForExtension(_ ext: String) -> NSColor {
        switch ext {
        case "md", "markdown":
            return NSColor(calibratedRed: 0.32, green: 0.45, blue: 0.66, alpha: 1)
        case "json", "yaml", "yml", "toml":
            return NSColor(calibratedRed: 0.72, green: 0.44, blue: 0.22, alpha: 1)
        case "swift", "js", "ts", "py", "rb", "go", "rs", "java", "c", "cpp", "h":
            return NSColor(calibratedRed: 0.43, green: 0.34, blue: 0.66, alpha: 1)
        case "txt", "log", "csv":
            return NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.56, alpha: 1)
        case "zip", "tar", "gz", "7z", "rar":
            return NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.28, alpha: 1)
        case "pdf":
            return NSColor(calibratedRed: 0.68, green: 0.28, blue: 0.28, alpha: 1)
        default:
            return NSColor(calibratedRed: 0.40, green: 0.42, blue: 0.48, alpha: 1)
        }
    }
}

// MARK: - Item card

final class ItemView: NSView, NSDraggingSource, NSMenuItemValidation {
    private(set) var item: ShelfItem
    private weak var manager: ShelfManager?
    private let key: ShelfKey
    private let isGroupMember: Bool

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let closeButton = HoverIconButton()
    private let groupMarker = NSView()
    private let spinner = NSProgressIndicator()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isDraggingOut = false

    init(item: ShelfItem,
         key: ShelfKey,
         manager: ShelfManager,
         isGroupMember: Bool = false) {
        self.item = item
        self.key = key
        self.manager = manager
        self.isGroupMember = isGroupMember
        super.init(frame: NSRect(x: 0, y: 0, width: ShelfMetrics.itemWidth, height: ShelfMetrics.itemHeight))
        wantsLayer = true
        layer?.cornerRadius = ShelfMetrics.itemCornerRadius
        layer?.borderWidth = 1
        layer?.masksToBounds = false

        iconView.frame = NSRect(x: 10, y: 10, width: 44, height: 44)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 9
        iconView.layer?.masksToBounds = true
        iconView.layer?.borderWidth = 1
        iconView.layer?.borderColor = NSColor.black.withAlphaComponent(0.06).cgColor
        addSubview(iconView)

        groupMarker.wantsLayer = true
        groupMarker.layer?.cornerRadius = 1.5
        groupMarker.layer?.backgroundColor = ShelfTheme.accent.withAlphaComponent(0.45).cgColor
        groupMarker.isHidden = !isGroupMember
        addSubview(groupMarker)

        titleLabel.frame = NSRect(x: 64, y: 12, width: ShelfMetrics.itemWidth - 64 - 34, height: 18)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        subtitleLabel.frame = NSRect(x: 64, y: 33, width: ShelfMetrics.itemWidth - 64 - 34, height: 15)
        subtitleLabel.font = .systemFont(ofSize: 10.5)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.textColor = .secondaryLabelColor
        addSubview(subtitleLabel)

        closeButton.frame = NSRect(x: ShelfMetrics.itemWidth - 34, y: 21, width: 22, height: 22)
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L10n.remove)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(removeSelf)
        closeButton.toolTip = L10n.removeItemHelp
        closeButton.isHidden = true
        addSubview(closeButton)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.frame = NSRect(x: ShelfMetrics.itemWidth - 32, y: 24, width: 16, height: 16)
        addSubview(spinner)

        updateLabels()
        loadThumbnail()
        needsLayout = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let rtl = L10n.isRTL
        let iconX = rtl ? bounds.width - 10 - 44 : 10
        iconView.frame = NSRect(x: iconX, y: 10, width: 44, height: 44)

        groupMarker.frame = NSRect(x: rtl ? bounds.width - 3 : 0,
                                   y: 14,
                                   width: 3,
                                   height: max(0, bounds.height - 28))

        let textX: CGFloat = rtl ? 42 : 64
        let textWidth = rtl ? bounds.width - 42 - 64 : bounds.width - 64 - 34
        titleLabel.frame = NSRect(x: textX, y: 12, width: textWidth, height: 18)
        subtitleLabel.frame = NSRect(x: textX, y: 33, width: textWidth, height: 15)
        titleLabel.alignment = rtl ? .right : .left
        subtitleLabel.alignment = rtl ? .right : .left

        closeButton.frame = NSRect(x: rtl ? 12 : bounds.width - 34, y: 21, width: 22, height: 22)
        spinner.frame = NSRect(x: rtl ? 14 : bounds.width - 32, y: 24, width: 16, height: 16)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // AppKit passes the point in the *superview's* coordinate system.
        // Checking `bounds` here made every card whose frame origin was not
        // (0, 0) fall through to the scroll view, so only the first/last card
        // appeared to support clicks.
        guard frame.contains(point) else { return nil }
        let localPoint = convert(point, from: superview)
        if !closeButton.isHidden, closeButton.frame.contains(localPoint) {
            return closeButton
        }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Appearance

    func update(with item: ShelfItem, reloadThumbnail: Bool = false) {
        let gainedStoredFile = self.item.relativePath == nil && item.relativePath != nil
        let pathChanged = self.item.originalPath != item.originalPath
        self.item = item
        updateLabels()
        if gainedStoredFile || pathChanged || reloadThumbnail {
            ThumbnailLoader.invalidate(itemID: item.id)
            loadThumbnail()
        }
    }

    func updateLabels() {
        titleLabel.stringValue = item.displayName
        subtitleLabel.stringValue = subtitleText()

        let pending = manager?.isPending(item.id) ?? false
        if pending {
            subtitleLabel.stringValue = L10n.copying
            spinner.startAnimation(nil)
            spinner.isHidden = false
            closeButton.isHidden = true
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            closeButton.isHidden = !isHovered
        }
        updateBackground()
    }

    private func subtitleText() -> String {
        switch item.kind {
        case .file:
            let ext = (item.displayName as NSString).pathExtension.uppercased()
            let size = item.byteSize.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            }
            return [ext.isEmpty ? L10n.file : ext, size].compactMap { $0 }.joined(separator: " · ")
        case .folder:
            return L10n.folder
        case .image:
            let ext = (item.displayName as NSString).pathExtension.uppercased()
            let size = item.byteSize.map {
                ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
            }
            return [ext.isEmpty ? L10n.image : ext, size].compactMap { $0 }.joined(separator: " · ")
        case .text:
            let body = (item.text ?? "").replacingOccurrences(of: "\n", with: " ")
            return body.isEmpty ? L10n.text : String(body.prefix(48))
        case .url:
            return item.urlString ?? L10n.link
        }
    }

    private func updateBackground() {
        let base = isHovered ? ShelfTheme.cardHover : ShelfTheme.card
        layer?.backgroundColor = base.cgColor
        layer?.borderColor = (isHovered
            ? ShelfTheme.accentBorder.cgColor
            : ShelfTheme.border.cgColor)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isHovered ? 0.10 : 0.0
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    private func loadThumbnail() {
        let expected = item.id
        ThumbnailLoader.icon(for: item, store: .shared) { [weak self] image in
            guard let self, self.item.id == expected else { return }
            self.iconView.image = image
        }
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateLabels()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateLabels()
    }

    // MARK: Actions

    @objc private func removeSelf() {
        manager?.remove(item: item, from: key)
    }

    func openItem() {
        switch item.kind {
        case .text:
            openTextItem()
        case .url:
            if let string = item.urlString, let url = URL(string: string) {
                NSWorkspace.shared.open(url)
            }
        case .file, .folder, .image:
            if let url = manager?.userFacingURL(for: item) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func openTextItem() {
        guard let text = item.text, !text.isEmpty else { return }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EdgeShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = item.displayName.isEmpty ? "Text" : item.displayName
        let safe = base.replacingOccurrences(of: "/", with: "-").prefix(60)
        let url = directory.appendingPathComponent("\(safe)-\(item.id.uuidString.prefix(8)).txt")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(url)
        } catch {
            NSSound.beep()
        }
    }

    private var canOpen: Bool {
        switch item.kind {
        case .text:
            return !(item.text ?? "").isEmpty
        case .url:
            return URL(string: item.urlString ?? "") != nil
        case .file, .folder, .image:
            return manager?.userFacingURL(for: item) != nil
        }
    }

    private var canCopy: Bool {
        switch item.kind {
        case .text:
            return !(item.text ?? "").isEmpty
        case .url:
            return !(item.urlString ?? "").isEmpty
        case .file, .folder, .image:
            return manager?.userFacingURL(for: item) != nil
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(menuOpen):
            return canOpen
        case #selector(menuReveal):
            return manager?.userFacingURL(for: item) != nil
        case #selector(menuCopy):
            return canCopy
        default:
            return true
        }
    }

    private func copyItem() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .file, .folder, .image:
            if let url = manager?.userFacingURL(for: item) {
                pasteboard.writeObjects([url as NSURL])
            }
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .url:
            if let string = item.urlString {
                pasteboard.setString(string, forType: .string)
                pasteboard.setString(string, forType: .URL)
            }
        }
    }

    private func showInFinder() {
        guard let url = manager?.userFacingURL(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }

    /// The card's menu. Split out of `rightMouseDown` so `--debug-menus` can
    /// assert on what a right-click actually offers.
    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(menuItem(L10n.open, symbol: "arrow.up.forward.app", action: #selector(menuOpen), key: "\r", modifiers: []))
        if item.kind == .file || item.kind == .folder || item.kind == .image {
            menu.addItem(menuItem(L10n.showInFinder, symbol: "folder", action: #selector(menuReveal), key: "r", modifiers: .command))
        }
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.copy, symbol: "doc.on.doc", action: #selector(menuCopy), key: "c", modifiers: .command))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.removeFromShelf, symbol: "trash", action: #selector(menuRemove), key: "\u{8}", modifiers: []))
        // Right-clicking a card is the most likely way a user looks for shelf
        // actions, so the whole-shelf command is reachable from here too.
        if let manager, !manager.items(for: key).isEmpty {
            menu.addItem(.separator())
            menu.addItem(menuItem(L10n.clearShelf,
                                  symbol: "trash.slash",
                                  action: #selector(menuClearShelf)))
        }

        return menu
    }

    private func menuItem(_ title: String,
                          symbol: String,
                          action: Selector,
                          key: String = "",
                          modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func menuOpen() { openItem() }
    @objc private func menuReveal() { showInFinder() }
    @objc private func menuCopy() { copyItem() }
    @objc private func menuRemove() { manager?.remove(item: item, from: key) }
    @objc private func menuClearShelf() { manager?.clearShelfAfterConfirmation(key) }

    // MARK: Dragging out

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            openItem()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let manager, !manager.isPending(item.id) else { return }
        guard let writer = pasteboardWriter() else { return }

        isDraggingOut = true
        updateBackground()

        let image = snapshotImage() ?? iconView.image
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.setDraggingFrame(bounds, contents: image)

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
    }

    private func snapshotImage() -> NSImage? {
        guard bounds.width > 0, bounds.height > 0,
              let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private func pasteboardWriter() -> NSPasteboardWriting? {
        switch item.kind {
        case .file, .folder, .image:
            guard let url = manager?.userFacingURL(for: item) else { return nil }
            return url as NSURL
        case .text:
            return (item.text ?? "") as NSString
        case .url:
            guard let string = item.urlString, let url = URL(string: string) else {
                return (item.urlString ?? "") as NSString
            }
            return url as NSURL
        }
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        isDraggingOut = false
        updateBackground()
        if operation != [] {
            manager?.didDragOut(item: item, from: key)
        }
    }
}

// MARK: - Group card

/// A summary card for one multi-file drop. Every member is still a normal
/// `ShelfItem` underneath; this view only aggregates them for display and for
/// a single drag session that carries all of their URLs.
final class GroupItemView: NSView, NSDraggingSource, NSMenuItemValidation {
    private(set) var groupID: UUID
    private(set) var items: [ShelfItem]
    private weak var manager: ShelfManager?
    private let key: ShelfKey

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let closeButton = HoverIconButton()
    private let spinner = NSProgressIndicator()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isDraggingOut = false
    private var startedDrag = false
    private var draggedItems: [ShelfItem] = []
    private var iconLoadToken = UUID()

    init(groupID: UUID,
         items: [ShelfItem],
         key: ShelfKey,
         manager: ShelfManager) {
        self.groupID = groupID
        self.items = items
        self.key = key
        self.manager = manager
        super.init(frame: NSRect(x: 0, y: 0, width: ShelfMetrics.itemWidth, height: ShelfMetrics.itemHeight))
        wantsLayer = true
        layer?.cornerRadius = ShelfMetrics.itemCornerRadius
        layer?.borderWidth = 1
        layer?.masksToBounds = false

        iconView.frame = NSRect(x: 10, y: 10, width: 44, height: 44)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.image = Self.composeGroupIcon(images: [])
        iconView.wantsLayer = true
        iconView.layer?.masksToBounds = false
        addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.textColor = .labelColor
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 10.5)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.textColor = .secondaryLabelColor
        addSubview(subtitleLabel)

        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: L10n.remove)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(removeSelf)
        closeButton.toolTip = L10n.removeGroup
        closeButton.isHidden = true
        addSubview(closeButton)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        addSubview(spinner)

        toolTip = L10n.groupHelp
        updateLabels()
        loadIcon()
        needsLayout = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let rtl = L10n.isRTL
        let iconX = rtl ? bounds.width - 10 - 44 : 10
        iconView.frame = NSRect(x: iconX, y: 10, width: 44, height: 44)

        let textX: CGFloat = rtl ? 42 : 64
        let textWidth = rtl ? bounds.width - 42 - 64 : bounds.width - 64 - 34
        titleLabel.frame = NSRect(x: textX, y: 12, width: textWidth, height: 18)
        subtitleLabel.frame = NSRect(x: textX, y: 33, width: textWidth, height: 15)
        titleLabel.alignment = rtl ? .right : .left
        subtitleLabel.alignment = rtl ? .right : .left

        closeButton.frame = NSRect(x: rtl ? 12 : bounds.width - 34, y: 21, width: 22, height: 22)
        spinner.frame = NSRect(x: rtl ? 14 : bounds.width - 32, y: 24, width: 16, height: 16)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        let localPoint = convert(point, from: superview)
        if !closeButton.isHidden, closeButton.frame.contains(localPoint) {
            return closeButton
        }
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(with items: [ShelfItem], reloadThumbnail: Bool = false) {
        let oldByID = Dictionary(uniqueKeysWithValues: self.items.map { ($0.id, $0) })
        let membershipChanged = self.items.map(\.id) != items.map(\.id)
        var iconChanged = membershipChanged

        for item in items {
            guard let old = oldByID[item.id] else {
                iconChanged = true
                continue
            }
            if reloadThumbnail {
                ThumbnailLoader.invalidate(itemID: item.id)
                iconChanged = true
            }
            if old.relativePath != item.relativePath
                || old.originalPath != item.originalPath
                || old.kind != item.kind {
                iconChanged = true
                ThumbnailLoader.invalidate(itemID: item.id)
            }
        }

        self.items = items
        updateLabels()
        if iconChanged {
            loadIcon()
        }
    }

    private func updateLabels() {
        titleLabel.stringValue = L10n.groupItems(items.count)

        let pending = items.contains { manager?.isPending($0.id) == true }
        if pending {
            subtitleLabel.stringValue = L10n.copying
            spinner.startAnimation(nil)
            spinner.isHidden = false
            closeButton.isHidden = true
        } else {
            let names = items.prefix(3).map(\.displayName).joined(separator: " · ")
            subtitleLabel.stringValue = items.count > 3 ? names + " …" : names
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            closeButton.isHidden = !isHovered
        }

        updateBackground()
    }

    /// The group icon is a small pile of the first few member thumbnails.
    /// Three is enough to read as a stack without turning the icon into mush.
    private func loadIcon() {
        let token = UUID()
        iconLoadToken = token
        let members = Array(items.prefix(3))
        guard !members.isEmpty else {
            iconView.image = Self.composeGroupIcon(images: [])
            return
        }

        var loaded: [UUID: NSImage] = [:]
        var remaining = members.count
        for item in members {
            ThumbnailLoader.icon(for: item, store: .shared) { [weak self] image in
                guard let self, self.iconLoadToken == token else { return }
                if let image {
                    loaded[item.id] = image
                }
                remaining -= 1
                guard remaining == 0 else { return }
                let ordered = members.compactMap { loaded[$0.id] }
                self.iconView.image = Self.composeGroupIcon(images: ordered)
            }
        }
    }

    private static func composeGroupIcon(images: [NSImage]) -> NSImage {
        // Back-to-front geometry: a small hand of photos, not a grid.
        let pictures = Array(images.prefix(3))
        let centers = [
            NSPoint(x: 38, y: 36),
            NSPoint(x: 47, y: 45),
            NSPoint(x: 56, y: 54),
        ]
        let angles: [CGFloat] = [-8, 1, 10]
        let side: CGFloat = 58

        return NSImage(size: NSSize(width: 96, height: 96), flipped: false) { _ in
            let count = pictures.isEmpty ? 3 : pictures.count
            for depth in stride(from: count - 1, through: 0, by: -1) {
                let center = centers[depth]
                let angle = angles[depth]
                let card = NSRect(x: center.x - side / 2,
                                  y: center.y - side / 2,
                                  width: side,
                                  height: side)
                let path = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)

                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform()
                transform.translateX(by: center.x, yBy: center.y)
                transform.rotate(byDegrees: angle)
                transform.translateX(by: -center.x, yBy: -center.y)
                transform.concat()

                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
                shadow.shadowBlurRadius = 6
                shadow.shadowOffset = NSSize(width: 0, height: -2)
                NSGraphicsContext.saveGraphicsState()
                shadow.set()
                ShelfTheme.card.setFill()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()

                if depth < pictures.count {
                    NSGraphicsContext.saveGraphicsState()
                    path.addClip()
                    drawFilling(pictures[depth], in: card)
                    NSGraphicsContext.restoreGraphicsState()
                }

                ShelfTheme.border.setStroke()
                path.lineWidth = 1.5
                path.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
    }

    private static func drawFilling(_ image: NSImage, in rect: NSRect) {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = max(rect.width / size.width, rect.height / size.height)
        let target = NSRect(x: rect.midX - size.width * scale / 2,
                            y: rect.midY - size.height * scale / 2,
                            width: size.width * scale,
                            height: size.height * scale)
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func updateBackground() {
        let expanded = manager?.isGroupExpanded(groupID) ?? false
        let base = isHovered
            ? ShelfTheme.cardHover
            : (expanded ? ShelfTheme.accentSoft : ShelfTheme.card)
        layer?.backgroundColor = base.cgColor
        layer?.borderColor = (isHovered || expanded
            ? ShelfTheme.accentBorder.cgColor
            : ShelfTheme.border.cgColor)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = isHovered ? 0.10 : 0.0
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
        loadIcon()
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateLabels()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateLabels()
    }

    // MARK: Click and drag

    override func mouseDown(with event: NSEvent) {
        startedDrag = false
    }

    override func mouseUp(with event: NSEvent) {
        defer { startedDrag = false }
        guard !startedDrag, event.clickCount == 1 else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        manager?.toggleGroup(groupID, in: key)
    }

    override func mouseDragged(with event: NSEvent) {
        guard !startedDrag, let manager else { return }
        let draggable = items.filter {
            !manager.isPending($0.id) && manager.userFacingURL(for: $0) != nil
        }
        guard !draggable.isEmpty else { return }

        startedDrag = true
        isDraggingOut = true
        updateBackground()

        let image = snapshotImage() ?? iconView.image
        var draggingItems: [NSDraggingItem] = []
        var includedItems: [ShelfItem] = []
        for item in draggable {
            guard let url = manager.userFacingURL(for: item) else { continue }
            let draggingItem = NSDraggingItem(pasteboardWriter: url as NSURL)
            draggingItem.setDraggingFrame(bounds, contents: image)
            draggingItems.append(draggingItem)
            includedItems.append(item)
        }
        guard !draggingItems.isEmpty else {
            startedDrag = false
            isDraggingOut = false
            updateBackground()
            return
        }
        draggedItems = includedItems

        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = draggingItems.count > 1 ? .stack : .none
    }

    private func snapshotImage() -> NSImage? {
        guard bounds.width > 0, bounds.height > 0,
              let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession,
                         endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        isDraggingOut = false
        updateBackground()
        if operation != [], !draggedItems.isEmpty {
            manager?.didDragOut(items: draggedItems, from: key)
        }
        draggedItems = []
    }

    // MARK: Actions

    private var urls: [URL] {
        guard let manager else { return [] }
        return items.compactMap { manager.userFacingURL(for: $0) }
    }

    @objc private func removeSelf() {
        manager?.removeGroup(groupID, in: key)
    }

    private func openAll() {
        for url in urls {
            NSWorkspace.shared.open(url)
        }
    }

    private func showAllInFinder() {
        let urls = urls
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func copyAll() {
        let urls = urls
        guard !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(makeContextMenu(), with: event, for: self)
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        let expanded = manager?.isGroupExpanded(groupID) ?? false

        menu.addItem(menuItem(expanded ? L10n.collapseGroup : L10n.expandGroup,
                              symbol: expanded ? "chevron.up" : "chevron.down",
                              action: #selector(menuToggle)))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.openAll,
                              symbol: "arrow.up.forward.app",
                              action: #selector(menuOpenAll)))
        menu.addItem(menuItem(L10n.showAllInFinder,
                              symbol: "folder",
                              action: #selector(menuRevealAll)))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.copyAll,
                              symbol: "doc.on.doc",
                              action: #selector(menuCopyAll)))
        menu.addItem(menuItem(L10n.ungroup,
                              symbol: "rectangle.split.2x1",
                              action: #selector(menuUngroup)))
        menu.addItem(.separator())
        menu.addItem(menuItem(L10n.removeGroup,
                              symbol: "trash",
                              action: #selector(menuRemoveGroup)))
        if let manager, !manager.items(for: key).isEmpty {
            menu.addItem(.separator())
            menu.addItem(menuItem(L10n.clearShelf,
                                  symbol: "trash.slash",
                                  action: #selector(menuClearShelf)))
        }
        return menu
    }

    private func menuItem(_ title: String,
                          symbol: String,
                          action: Selector,
                          key: String = "",
                          modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(menuOpenAll), #selector(menuRevealAll), #selector(menuCopyAll):
            return !urls.isEmpty
        default:
            return true
        }
    }

    @objc private func menuToggle() { manager?.toggleGroup(groupID, in: key) }
    @objc private func menuOpenAll() { openAll() }
    @objc private func menuRevealAll() { showAllInFinder() }
    @objc private func menuCopyAll() { copyAll() }
    @objc private func menuUngroup() { manager?.ungroup(groupID, in: key) }
    @objc private func menuRemoveGroup() { manager?.removeGroup(groupID, in: key) }
    @objc private func menuClearShelf() { manager?.clearShelfAfterConfirmation(key) }
}

// MARK: - Shelf panel

final class ShelfView: NSView {
    let key: ShelfKey
    private weak var manager: ShelfManager?

    private let contentContainer = FlippedView()
    private let background = ShelfBackgroundView()
    private let headerIcon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: L10n.shelf)
    private let countBackground = NSView()
    private let countLabel = NSTextField(labelWithString: "")
    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let emptyState = EmptyStateView()
    private let tabView = ShelfTabView()

    private(set) var itemViews: [UUID: ItemView] = [:]
    private(set) var groupViews: [UUID: GroupItemView] = [:]
    private var isDropHighlighted = false
    private var isCollapsed = false

    init(key: ShelfKey, manager: ShelfManager) {
        self.key = key
        self.manager = manager
        super.init(frame: NSRect(x: 0, y: 0, width: ShelfMetrics.windowWidth, height: ShelfMetrics.windowHeight(forItemCount: 0)))
        wantsLayer = true

        contentContainer.wantsLayer = true
        contentContainer.alphaValue = 1
        addSubview(contentContainer)

        background.autoresizingMask = [.width, .height]
        contentContainer.addSubview(background)

        headerIcon.image = AppIcons.status
        headerIcon.contentTintColor = .secondaryLabelColor
        headerIcon.imageScaling = .scaleProportionallyUpOrDown
        headerIcon.setAccessibilityElement(false)
        headerIcon.setAccessibilityLabel(L10n.shelf)
        contentContainer.addSubview(headerIcon)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        contentContainer.addSubview(titleLabel)

        countBackground.wantsLayer = true
        countBackground.layer?.cornerRadius = 9
        countBackground.layer?.backgroundColor = ShelfTheme.accentSoft.cgColor
        contentContainer.addSubview(countBackground)

        countLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        countLabel.textColor = ShelfTheme.accentText
        countLabel.alignment = .center
        countBackground.addSubview(countLabel)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        contentContainer.addSubview(scrollView)

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document

        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = ShelfMetrics.itemSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])

        contentContainer.addSubview(emptyState)

        tabView.isHidden = true
        addSubview(tabView)

        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff, .rtf, .rtfd, .html]
            + IngestPayload.extraDraggedTypes
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })

        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    // MARK: Layout

    override func layout() {
        super.layout()
        let margin = ShelfMetrics.shadowMargin
        let panelWidth = bounds.width - margin * 2
        let panelHeight = bounds.height - margin * 2

        contentContainer.frame = NSRect(x: margin, y: margin, width: panelWidth, height: panelHeight)
        background.frame = contentContainer.bounds

        let badgeHeight: CGFloat = 18
        countLabel.sizeToFit()
        let textSize = countLabel.frame.size
        let countWidth = max(20, textSize.width + 10)

        // The icon, title and count badge share the header's vertical centre.
        // NSTextField draws a single line from the top of its frame, so the
        // label must be exactly one line tall; a taller frame would push the
        // text up and leave the icon looking low.
        let iconSide: CGFloat = 17
        let iconY = (ShelfMetrics.headerHeight - iconSide) / 2
        let badgeY = (ShelfMetrics.headerHeight - badgeHeight) / 2

        if L10n.isRTL {
            headerIcon.frame = NSRect(x: panelWidth - 14 - iconSide, y: iconY, width: iconSide, height: iconSide)
            titleLabel.sizeToFit()
            titleLabel.frame = NSRect(x: headerIcon.frame.minX - 8 - titleLabel.frame.width,
                                      y: (ShelfMetrics.headerHeight - titleLabel.frame.height) / 2,
                                      width: titleLabel.frame.width,
                                      height: titleLabel.frame.height)
            countBackground.frame = NSRect(x: titleLabel.frame.minX - 8 - countWidth,
                                           y: badgeY,
                                           width: countWidth,
                                           height: badgeHeight)
        } else {
            headerIcon.frame = NSRect(x: 14, y: iconY, width: iconSide, height: iconSide)
            titleLabel.sizeToFit()
            titleLabel.frame = NSRect(x: 39,
                                      y: (ShelfMetrics.headerHeight - titleLabel.frame.height) / 2,
                                      width: titleLabel.frame.width,
                                      height: titleLabel.frame.height)
            countBackground.frame = NSRect(x: titleLabel.frame.maxX + 8,
                                           y: badgeY,
                                           width: countWidth,
                                           height: badgeHeight)
        }

        countLabel.frame = NSRect(x: (countWidth - textSize.width) / 2,
                                  y: (badgeHeight - textSize.height) / 2,
                                  width: textSize.width,
                                  height: textSize.height)

        scrollView.frame = NSRect(x: ShelfMetrics.contentInset,
                                  y: ShelfMetrics.headerHeight + 6,
                                  width: panelWidth - ShelfMetrics.contentInset * 2,
                                  height: max(0, panelHeight - ShelfMetrics.headerHeight - 16))

        emptyState.frame = NSRect(x: (panelWidth - 240) / 2,
                                  y: ShelfMetrics.headerHeight + 22,
                                  width: 240,
                                  height: 140)

        let tabWidth: CGFloat = 8
        let tabHeight: CGFloat = 96
        let tabX = key.edge == .left ? margin : bounds.width - margin - tabWidth
        tabView.frame = NSRect(x: tabX, y: (bounds.height - tabHeight) / 2, width: tabWidth, height: tabHeight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        background.needsDisplay = true
        countBackground.layer?.backgroundColor = ShelfTheme.accentSoft.cgColor
        emptyState.setHighlighted(isDropHighlighted)
    }

    // MARK: Content

    func refresh() {
        guard let manager else { return }
        let items = manager.items(for: key)
        let rows = manager.rows(for: key)
        let previousItemIDs = Set(itemViews.keys)
        let previousGroupIDs = Set(groupViews.keys)

        titleLabel.stringValue = L10n.shelf
        titleLabel.sizeToFit()
        countLabel.stringValue = "\(items.count)"
        countBackground.isHidden = items.isEmpty

        emptyState.isHidden = !rows.isEmpty
        scrollView.isHidden = rows.isEmpty

        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        itemViews.removeAll()
        groupViews.removeAll()

        var appearingViews: [NSView] = []
        func addCard(_ view: NSView, isNew: Bool) {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.heightAnchor.constraint(equalToConstant: ShelfMetrics.itemHeight).isActive = true
            if isNew {
                view.alphaValue = 0
                appearingViews.append(view)
            }
            stack.addArrangedSubview(view)
        }

        for row in rows {
            switch row {
            case .item(let item):
                let view = ItemView(item: item, key: key, manager: manager)
                addCard(view, isNew: !previousItemIDs.contains(item.id))
                itemViews[item.id] = view
            case .group(let groupID, let members):
                let view = GroupItemView(groupID: groupID,
                                         items: members,
                                         key: key,
                                         manager: manager)
                addCard(view, isNew: !previousGroupIDs.contains(groupID))
                groupViews[groupID] = view
            case .member(let item, _):
                let view = ItemView(item: item,
                                    key: key,
                                    manager: manager,
                                    isGroupMember: true)
                addCard(view, isNew: !previousItemIDs.contains(item.id))
                itemViews[item.id] = view
            }
        }

        if !appearingViews.isEmpty, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for view in appearingViews {
                    view.animator().alphaValue = 1
                }
            }
        }

        needsLayout = true
    }

    func refreshItem(id: UUID, reloadThumbnail: Bool = false) {
        guard let manager,
              let item = manager.items(for: key).first(where: { $0.id == id }) else { return }
        itemViews[id]?.update(with: item, reloadThumbnail: reloadThumbnail)

        // A member can change while the group is collapsed, in which case only
        // the summary card is on screen. Keep its title and subtitle in sync.
        if let groupID = item.groupID, let groupView = groupViews[groupID] {
            let members = manager.items(for: key).filter { $0.groupID == groupID }
            groupView.update(with: members, reloadThumbnail: reloadThumbnail)
        }
    }

    /// Used by `--debug-hittest`; verifies the item cards are actually
    /// reachable through AppKit's superview-coordinate hit testing.
    func debugHitTestReport() -> String {
        layoutSubtreeIfNeeded()
        var lines: [String] = []
        for view in itemViews.values {
            let center = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
            let point = view.convert(center, to: view.superview)
            let hit = view.hitTest(point)
            lines.append("\(view.item.displayName): frame=\(view.frame) hit=\(hit === view)")
        }
        for view in groupViews.values {
            let center = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
            let point = view.convert(center, to: view.superview)
            let hit = view.hitTest(point)
            lines.append("\(L10n.groupItems(view.items.count)): frame=\(view.frame) hit=\(hit === view)")
        }
        return lines.joined(separator: "\n")
    }

    /// Clearing is destructive and cannot be undone, so it lives on a
    /// right-click rather than on a button in the header, where an "x" reads
    /// as "close" but actually deleted every item.
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = makeContextMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// The panel's own menu. `ItemView` handles right-clicks on a card; this
    /// covers the empty area around them.
    func makeContextMenu() -> NSMenu? {
        guard let manager, !manager.items(for: key).isEmpty else { return nil }
        let menu = NSMenu()
        let clear = NSMenuItem(title: L10n.clearShelf,
                               action: #selector(clearShelfConfirmed),
                               keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        return menu
    }

    @objc private func clearShelfConfirmed() {
        guard let manager else { return }
        manager.clearShelfAfterConfirmation(key)
    }

    // MARK: Presentation

    func setCollapsed(_ collapsed: Bool, animated: Bool) {
        isCollapsed = collapsed
        tabView.isHidden = !collapsed

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldAnimate = animated && !reduceMotion
        let shift: CGFloat = key.edge == .left ? -10 : 10

        if collapsed {
            guard !contentContainer.isHidden else { return }
            if shouldAnimate {
                contentContainer.isHidden = false
                let animation = CABasicAnimation(keyPath: "transform.translation.x")
                animation.fromValue = 0
                animation.toValue = shift
                animation.duration = 0.16
                animation.timingFunction = CAMediaTimingFunction(name: .easeIn)
                contentContainer.layer?.add(animation, forKey: "collapseSlide")

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    contentContainer.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    guard let self, self.isCollapsed else { return }
                    self.contentContainer.isHidden = true
                }
            } else {
                contentContainer.alphaValue = 0
                contentContainer.isHidden = true
            }
        } else {
            contentContainer.isHidden = false
            if shouldAnimate {
                contentContainer.alphaValue = 0
                let animation = CABasicAnimation(keyPath: "transform.translation.x")
                animation.fromValue = shift
                animation.toValue = 0
                animation.duration = 0.16
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentContainer.layer?.add(animation, forKey: "expandSlide")

                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.16
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    contentContainer.animator().alphaValue = 1
                }
            } else {
                contentContainer.alphaValue = 1
            }
        }
    }

    // MARK: Drag destination

    private func setDropHighlight(_ highlighted: Bool) {
        guard highlighted != isDropHighlighted else { return }
        isDropHighlighted = highlighted
        background.setHighlighted(highlighted)
        emptyState.setHighlighted(highlighted)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        setDropHighlight(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setDropHighlight(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        setDropHighlight(false)
        // Reporting the truth matters: a rejected payload animates back to
        // where it came from instead of silently vanishing.
        return manager?.ingest(pasteboard: sender.draggingPasteboard, into: key) ?? false
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        setDropHighlight(false)
    }
}
