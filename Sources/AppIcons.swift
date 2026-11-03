import AppKit

/// Brand colours shared by the app icon and the interface.
enum HamsterPalette {
    static let caramel = NSColor(calibratedRed: 0.84, green: 0.57, blue: 0.33, alpha: 1)
    static let cream = NSColor(calibratedRed: 1, green: 0.93, blue: 0.81, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.29, green: 0.17, blue: 0.10, alpha: 1)
    static let apricot = NSColor(calibratedRed: 0.96, green: 0.59, blue: 0.33, alpha: 1)
    static let paleApricot = NSColor(calibratedRed: 1, green: 0.77, blue: 0.53, alpha: 1)
}

/// Shared vector artwork; fullness changes the cheeks, never the image bounds.
enum AppIcons {
    static func fullness(for count: Int) -> CGFloat { count == 0 ? 0 : count <= 3 ? 0.5 : 1 }
    static let status = hamster(fullness: 0, size: 18, template: true)

    static func hamster(fullness: CGFloat, size: CGFloat, template: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            draw(fullness: fullness, size: size, template: template)
            return true
        }
        image.isTemplate = template
        return image
    }

    static func draw(fullness: CGFloat, size: CGFloat, template: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = AffineTransform(scale: size / 100)
        (transform as NSAffineTransform).concat()
        let caramel = HamsterPalette.caramel
        let cream = HamsterPalette.cream
        let ink = HamsterPalette.ink
        func oval(_ rect: NSRect, _ color: NSColor) {
            color.setFill(); NSBezierPath(ovalIn: rect).fill()
        }
        for x: CGFloat in [19, 61] {
            oval(NSRect(x: x, y: 66, width: 20, height: 23), template ? .black : caramel)
            if !template { oval(NSRect(x: x + 4, y: 71, width: 12, height: 14), cream) }
        }
        let spread = 10 * min(1, max(0, fullness))
        let head = NSBezierPath()
        head.move(to: NSPoint(x: 50, y: 80))
        head.curve(to: NSPoint(x: 82 + spread, y: 32), controlPoint1: NSPoint(x: 73, y: 81), controlPoint2: NSPoint(x: 81 + spread, y: 55))
        head.curve(to: NSPoint(x: 50, y: 14), controlPoint1: NSPoint(x: 84 + spread, y: 14), controlPoint2: NSPoint(x: 67, y: 14))
        head.curve(to: NSPoint(x: 18 - spread, y: 32), controlPoint1: NSPoint(x: 33, y: 14), controlPoint2: NSPoint(x: 16 - spread, y: 14))
        head.curve(to: NSPoint(x: 50, y: 80), controlPoint1: NSPoint(x: 19 - spread, y: 55), controlPoint2: NSPoint(x: 27, y: 81))
        head.close()
        (template ? NSColor.black : caramel).setFill(); head.fill()
        if !template {
            NSGraphicsContext.saveGraphicsState(); head.addClip()
            oval(NSRect(x: 12 - spread, y: 8, width: 76 + spread * 2, height: 46), cream)
            NSGraphicsContext.restoreGraphicsState()
        }
        if template { NSGraphicsContext.current?.compositingOperation = .destinationOut }
        for x: CGFloat in [35, 59] { oval(NSRect(x: x, y: 49, width: 6, height: 8), template ? .black : ink) }
        if !template {
            oval(NSRect(x: 46, y: 39, width: 8, height: 6), caramel)
            let mouth = NSBezierPath()
            mouth.move(to: NSPoint(x: 50, y: 40)); mouth.line(to: NSPoint(x: 50, y: 35))
            mouth.curve(to: NSPoint(x: 41, y: 33), controlPoint1: NSPoint(x: 49, y: 30), controlPoint2: NSPoint(x: 44, y: 30))
            mouth.move(to: NSPoint(x: 50, y: 35))
            mouth.curve(to: NSPoint(x: 59, y: 33), controlPoint1: NSPoint(x: 51, y: 30), controlPoint2: NSPoint(x: 56, y: 30))
            mouth.lineWidth = 1.8; mouth.lineCapStyle = .round; ink.setStroke(); mouth.stroke()
        }
    }
}

/// A short, interruptible transition. No timer runs while the hamster is idle.
final class HamsterAnimator {
    private var timer: Timer?
    private var value: CGFloat = 0
    private var target: CGFloat = -1
    deinit { timer?.invalidate() }

    func update(count: Int, render: @escaping (CGFloat) -> Void) {
        let next = AppIcons.fullness(for: count)
        guard next != target else { return }
        let initial = target < 0
        target = next
        timer?.invalidate(); timer = nil
        if initial || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            value = next; render(next); return
        }
        let from = value
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let t = min(1, (ProcessInfo.processInfo.systemUptime - start) / 0.28)
            let eased = CGFloat(t * t * (3 - 2 * t))
            self.value = from + (next - from) * eased
            render(self.value)
            if t >= 1 { timer.invalidate(); self.timer = nil }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}
