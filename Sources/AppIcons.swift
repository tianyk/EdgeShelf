import AppKit

enum AppIcons {
    /// Menu-bar and shelf-header glyph: the edge tab and two cards from the
    /// app icon, reduced to three solid shapes so it still reads at 18 pt.
    /// Template image, so AppKit tints it for light/dark menu bars and for
    /// the header's secondary label colour.
    static let status: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()

            let tab = NSBezierPath(
                roundedRect: NSRect(x: 2.0, y: 2.6, width: 3.8, height: 12.8),
                xRadius: 1.9,
                yRadius: 1.9
            )
            tab.fill()

            let topCard = NSBezierPath(
                roundedRect: NSRect(x: 7.4, y: 9.4, width: 8.6, height: 3.9),
                xRadius: 1.3,
                yRadius: 1.3
            )
            topCard.fill()

            let bottomCard = NSBezierPath(
                roundedRect: NSRect(x: 7.4, y: 4.7, width: 8.6, height: 3.9),
                xRadius: 1.3,
                yRadius: 1.3
            )
            bottomCard.fill()

            return true
        }
        image.isTemplate = true
        return image
    }()
}
