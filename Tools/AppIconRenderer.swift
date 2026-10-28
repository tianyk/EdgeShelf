#!/usr/bin/env swift
import AppKit

// Renders the EdgeShelf app icon (B4: terracotta tile, cream edge tab,
// two shelf cards, the top one slightly tilted) into an .iconset directory.
//
// Usage:
//   swift Tools/AppIconRenderer.swift <output-directory>
//
// The artwork is drawn as vectors at every size instead of being downsampled
// from a single master, so 16 pt and 32 pt stay crisp.

private let canvas: CGFloat = 1024
private let iconRect = NSRect(x: 100, y: 100, width: 824, height: 824)

private extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

private func squirclePath(_ rect: NSRect) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.224, yRadius: rect.width * 0.224)
}

private func drawDocShape(in rect: NSRect, color: NSColor) {
    let fold = min(rect.width, rect.height) * 0.26
    let page = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.08, yRadius: rect.width * 0.08)
    let notch = NSBezierPath()
    notch.move(to: NSPoint(x: rect.maxX - fold, y: rect.maxY + 1))
    notch.line(to: NSPoint(x: rect.maxX + 1, y: rect.maxY + 1))
    notch.line(to: NSPoint(x: rect.maxX + 1, y: rect.maxY - fold))
    notch.close()
    page.append(notch)
    page.windingRule = .evenOdd
    color.setFill()
    page.fill()
}

private func drawCard(_ rect: NSRect, thumb: NSColor, angle: CGFloat) {
    NSGraphicsContext.saveGraphicsState()

    if angle != 0 {
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.rotate(byDegrees: angle)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()
    }

    let path = NSBezierPath(roundedRect: rect, xRadius: 32, yRadius: 32)
    let fill = NSColor(hex: 0xFFF9EC)

    // Soft paper shadow, then the card itself.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    fill.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    fill.setFill()
    path.fill()
    NSColor.black.withAlphaComponent(0.055).setStroke()
    path.lineWidth = 1.5
    path.stroke()

    // Thumbnail tile.
    let thumbRect = NSRect(x: rect.minX + 28, y: rect.midY - 54, width: 108, height: 108)
    NSColor(hex: 0xFFF9EC).setFill()
    let thumbPath = NSBezierPath(roundedRect: thumbRect, xRadius: 26, yRadius: 26)
    thumb.setFill()
    thumbPath.fill()
    drawDocShape(in: thumbRect.insetBy(dx: 32, dy: 20), color: NSColor(hex: 0xFFF9EC))

    // Two text lines.
    NSColor(hex: 0x5A4433).withAlphaComponent(0.70).setFill()
    NSBezierPath(roundedRect: NSRect(x: rect.minX + 160, y: rect.midY + 14, width: 210, height: 20),
                 xRadius: 10, yRadius: 10).fill()
    NSColor(hex: 0x5A4433).withAlphaComponent(0.22).setFill()
    NSBezierPath(roundedRect: NSRect(x: rect.minX + 160, y: rect.midY - 20, width: 250, height: 14),
                 xRadius: 7, yRadius: 7).fill()

    NSGraphicsContext.restoreGraphicsState()
}

private func drawIcon(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    context.cgContext.interpolationQuality = .high
    context.cgContext.scaleBy(x: size / canvas, y: size / canvas)

    let shape = squirclePath(iconRect)
    let top = NSColor(hex: 0xD9823C)
    let bottom = NSColor(hex: 0xA9501A)

    // Soft depth behind the tile.
    let outerShadow = NSShadow()
    outerShadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
    outerShadow.shadowBlurRadius = 26
    outerShadow.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState()
    outerShadow.set()
    bottom.setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Terracotta gradient, with Apple's top-light.
    let gradient = NSGradient(starting: top, ending: bottom)!
    gradient.draw(in: shape, angle: -90)
    NSColor.white.withAlphaComponent(0.22).setStroke()
    shape.lineWidth = 2
    shape.stroke()

    // Quiet diagonal paper stripes.
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    NSColor.white.withAlphaComponent(0.045).setStroke()
    var offset = -iconRect.height
    while offset < iconRect.width + iconRect.height {
        let stripe = NSBezierPath()
        stripe.move(to: NSPoint(x: iconRect.minX + offset, y: iconRect.minY))
        stripe.line(to: NSPoint(x: iconRect.minX + offset + iconRect.height, y: iconRect.maxY))
        stripe.lineWidth = 2
        stripe.stroke()
        offset += 46
    }
    NSGraphicsContext.restoreGraphicsState()

    // Cream edge tab.
    let tabRect = NSRect(x: 208, y: 296, width: 104, height: 432)
    let tab = NSBezierPath(roundedRect: tabRect, xRadius: 52, yRadius: 52)
    NSColor(hex: 0xFFF7E8).setFill()
    tab.fill()

    // Two cards; the top one is tilted to suggest a drag in progress.
    drawCard(NSRect(x: 286, y: 512, width: 460, height: 176),
             thumb: NSColor(hex: 0x7E8592),
             angle: -4)
    drawCard(NSRect(x: 300, y: 300, width: 460, height: 176),
             thumb: NSColor(hex: 0x4E9B9D).withAlphaComponent(0.85),
             angle: 0)

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

private let layers: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: AppIconRenderer.swift <output-directory>\n".utf8))
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for layer in layers {
    let data = drawIcon(size: CGFloat(layer.pixels))
    try data.write(to: outputDirectory.appendingPathComponent(layer.name))
}

print("Wrote \(layers.count) icon layers to \(outputDirectory.path)")
