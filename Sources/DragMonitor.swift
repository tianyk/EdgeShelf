import AppKit

/// Watches global mouse events to know when the user is dragging something
/// toward a screen edge.
///
/// Two deliberate safeguards:
/// 1. A plain window drag or text selection is not treated as a drag: the
///    drag pasteboard must actually change after mouse-down.
/// 2. Edge UI updates are pushed to the next main-runloop turn instead of
///    running inside the event callback. That keeps every window operation
///    out of AppKit's Core Drag IPC path.
final class DragMonitor {
    private weak var manager: ShelfManager?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var watchdog: Timer?
    private var hoverTimer: Timer?

    private var mouseDownPoint: NSPoint?
    private var pasteboardCountAtMouseDown = -1
    private var mouseIsDown = false
    private var isDragging = false
    private var lastCursor = NSPoint.zero
    private var updateScheduled = false

    init(manager: ShelfManager) {
        self.manager = manager
    }

    deinit {
        stop()
    }

    func start() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.watchdogFired()
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer

        // Polling the pointer is cheaper and more reliable than a global
        // mouseMoved monitor, and works without any privacy permission.
        let hover = Timer(timeInterval: 0.18, repeats: true) { [weak self] _ in
            guard let self, !self.mouseIsDown, !self.isDragging else { return }
            self.manager?.hoverUpdate(cursor: NSEvent.mouseLocation)
        }
        RunLoop.main.add(hover, forMode: .common)
        hoverTimer = hover
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        watchdog?.invalidate()
        watchdog = nil
        hoverTimer?.invalidate()
        hoverTimer = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseIsDown = true
            isDragging = false
            mouseDownPoint = NSEvent.mouseLocation
            pasteboardCountAtMouseDown = NSPasteboard(name: .drag).changeCount

        case .leftMouseDragged:
            guard mouseIsDown, let start = mouseDownPoint else { return }
            let point = NSEvent.mouseLocation

            if !isDragging {
                guard point.distance(to: start) >= 5 else { return }
                let pasteboard = NSPasteboard(name: .drag)
                // A real drag-and-drop session publishes types on NSDragPboard.
                // Window moves and marquee selections do not.
                guard pasteboard.changeCount != pasteboardCountAtMouseDown,
                      pasteboard.types?.isEmpty == false else { return }
                isDragging = true
                manager?.beginDrag()
            }

            scheduleUpdate(at: point)

        case .leftMouseUp:
            mouseIsDown = false
            mouseDownPoint = nil
            if isDragging {
                isDragging = false
                manager?.endDrag()
            }

        default:
            break
        }
    }

    private func scheduleUpdate(at point: NSPoint) {
        lastCursor = point
        guard !updateScheduled else { return }
        updateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updateScheduled = false
            self.manager?.updateDrag(cursor: self.lastCursor)
        }
    }

    private func watchdogFired() {
        guard isDragging || mouseIsDown else { return }
        if NSEvent.pressedMouseButtons & 1 == 0 {
            mouseIsDown = false
            mouseDownPoint = nil
            if isDragging {
                isDragging = false
                manager?.endDrag()
            }
        }
    }
}
