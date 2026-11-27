import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

func drawIcon(size: Int, url: URL) throws {
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let background = NSBezierPath(roundedRect: NSRect(x: 28, y: 28, width: 968, height: 968), xRadius: 215, yRadius: 215)
    let gradient = NSGradient(starting: NSColor(red: 0.25, green: 0.24, blue: 0.31, alpha: 1), ending: NSColor(red: 0.12, green: 0.11, blue: 0.15, alpha: 1))!
    gradient.draw(in: background, angle: 270)
    NSColor.white.withAlphaComponent(0.09).setStroke()
    background.lineWidth = 3
    background.stroke()
    let accent = NSColor(red: 0.78, green: 0.75, blue: 0.96, alpha: 1)
    accent.setStroke()
    for pair: (CGFloat, CGFloat) in [(12, 160), (192, 340)] {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 235, startAngle: pair.0, endAngle: pair.1)
        arc.lineWidth = 58
        arc.lineCapStyle = .round
        arc.stroke()
    }
    accent.setFill()
    NSBezierPath(ovalIn: NSRect(x: 483, y: 483, width: 58, height: 58)).fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
    try data.write(to: url)
}

for base in [16, 32, 128, 256, 512] {
    try drawIcon(size: base, url: directory.appendingPathComponent("icon_\(base)x\(base).png"))
    try drawIcon(size: base * 2, url: directory.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}

// Encode the standard ICNS container directly; no system icon conversion service is needed.
func lengthData(_ length: Int) -> Data {
    var encoded = UInt32(length).bigEndian
    return withUnsafeBytes(of: &encoded) { Data($0) }
}
var chunks = Data()
let variants = [
    ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]
for (type, name) in variants {
    let png = try Data(contentsOf: directory.appendingPathComponent(name))
    chunks.append(Data(type.utf8))
    chunks.append(lengthData(png.count + 8))
    chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(lengthData(chunks.count + 8))
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
