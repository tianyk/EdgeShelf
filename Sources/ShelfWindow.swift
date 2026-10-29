import AppKit

final class ShelfWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // A context menu on an inactive floating window should open on the
        // first right-click, not require a preliminary click to focus.
        if event.type == .rightMouseDown, !isKeyWindow {
            makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
        super.sendEvent(event)
    }
}

/// A borderless, non-activating panel that lives at one screen edge.
///
/// The frame is set before the window is ordered in and is only changed while
/// no drag is in flight. Showing/hiding only animates content layers and
/// toggles mouse acceptance. Resizing or re-ordering a drag destination inside
/// a Core Drag callback is what makes several shelf apps (and Dropshelf)
/// beachball on macOS 26.
final class ShelfWindowController: NSWindowController {
    enum Presentation {
        case hidden
        case collapsed
        case expanded
    }

    let key: ShelfKey
    let shelfView: ShelfView

    private(set) var presentation: Presentation = .hidden
    var isExpanded: Bool { presentation == .expanded }

    init(key: ShelfKey, frame: NSRect, level: NSWindow.Level = .floating, manager: ShelfManager) {
        self.key = key

        let window = ShelfWindow(contentRect: frame,
                                 styleMask: .borderless,
                                 backing: .buffered,
                                 defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = level
        window.collectionBehavior = [.canJoinAllSpaces,
                                     .stationary,
                                     .fullScreenAuxiliary,
                                     .ignoresCycle,
                                     .transient]
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true
        window.isReleasedWhenClosed = false

        self.shelfView = ShelfView(key: key, manager: manager)
        window.contentView = shelfView

        super.init(window: window)
        window.orderFrontRegardless()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPresentation(_ presentation: Presentation, animated: Bool = true) {
        guard let window else { return }
        let wasCollapsed = self.presentation == .collapsed
        self.presentation = presentation

        switch presentation {
        case .hidden:
            shelfView.setCollapsed(false, animated: false)
            window.alphaValue = 0
            window.ignoresMouseEvents = true
        case .collapsed:
            shelfView.setCollapsed(true, animated: animated && !wasCollapsed)
            window.alphaValue = 1
            window.ignoresMouseEvents = true
        case .expanded:
            shelfView.setCollapsed(false, animated: animated && wasCollapsed)
            window.alphaValue = 1
            window.ignoresMouseEvents = false
        }
    }

    /// Resizes the window to fit the current item count. The manager only
    /// calls this when no mouse button is down and no drag is active.
    func resize(forItemCount count: Int, animated: Bool) {
        guard let window else { return }
        let newHeight = ShelfMetrics.windowHeight(forItemCount: count)
        var frame = window.frame
        guard abs(frame.height - newHeight) > 0.5 else { return }

        let centerY = frame.midY
        frame.size.height = newHeight
        frame.origin.y = centerY - newHeight / 2

        if let visible = window.screen?.visibleFrame {
            frame.origin.y = min(max(frame.origin.y, visible.minY + 8),
                                 visible.maxY - newHeight - 8)
        }

        window.setFrame(frame, display: true, animate: animated)
        shelfView.needsLayout = true
    }

    func refresh() {
        shelfView.refresh()
    }

    func refreshItem(id: UUID, reloadThumbnail: Bool = false) {
        shelfView.refreshItem(id: id, reloadThumbnail: reloadThumbnail)
    }
}
