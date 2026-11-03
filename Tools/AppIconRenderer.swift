import AppKit

private func drawIcon(size: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: size / 1024, y: size / 1024)
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
    NSGradient(starting: HamsterPalette.paleApricot, ending: HamsterPalette.apricot)!.draw(in: tile, angle: -90)
    ctx.translateBy(x: 112, y: 110)
    AppIcons.draw(fullness: 0.5, size: 800)
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

// ICNS supports PNG payloads directly, including native Retina representations.
func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
let entries = [("icp4", 16), ("icp5", 32), ("icp6", 64), ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024), ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]
var payload = Data()
for (type, size) in entries {
    let png = drawIcon(size: CGFloat(size))
    payload.append(Data(type.utf8)); payload.append(bigEndian(png.count + 8)); payload.append(png)
}
var icns = Data("icns".utf8)
icns.append(bigEndian(payload.count + 8)); icns.append(payload)
try icns.write(to: outputDirectory.appendingPathExtension("icns"))
