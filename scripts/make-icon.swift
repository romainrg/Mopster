import AppKit

// Draws the Mopster app icon (a jaunty mop on a teal-to-blue tile) into the given AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift Mopster/Resources/Assets.xcassets/AppIcon.appiconset [icon.png]
// The optional second argument also writes a 512 px copy (used by the README).
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func sparkle(center: NSPoint, radius: CGFloat, fill: NSColor) {
    let path = NSBezierPath()
    let inner = radius * 0.2
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4
        let r = i % 2 == 0 ? radius : inner
        let p = NSPoint(x: center.x + cos(angle + .pi / 2) * r, y: center.y + sin(angle + .pi / 2) * r)
        i == 0 ? path.move(to: p) : path.line(to: p)
    }
    path.close()
    fill.setFill()
    path.fill()
}

func drawMop(in context: CGContext) {
    // Local coordinates: mop upright, origin at the ferrule centre; then tilted.
    context.saveGState()
    context.translateBy(x: 530, y: 480)
    context.rotate(by: 28 * .pi / 180)

    // Soft drop shadow for the whole mop.
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: -6, height: -14)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()

    // Handle
    let handle = NSBezierPath(roundedRect: NSRect(x: -26, y: 0, width: 52, height: 400), xRadius: 26, yRadius: 26)
    NSGradient(colors: [color(0.80, 0.50, 0.24), color(0.98, 0.76, 0.45), color(0.80, 0.50, 0.24)])!
        .draw(in: handle, angle: 0)

    // Mop head: fluffy strands fanning out below the ferrule.
    let strandColors = [color(1, 1, 1), color(0.93, 0.97, 1), color(0.85, 0.93, 0.98)]
    let count = 13
    for i in 0..<count {
        let t = CGFloat(i) / CGFloat(count - 1)
        let x = -140 + t * 280
        let tipX = x * 1.2 + (t - 0.5) * 20
        let length: CGFloat = 300 - abs(t - 0.5) * 70
        let strand = NSBezierPath()
        strand.move(to: NSPoint(x: x * 0.45 - 32, y: 0))
        strand.curve(to: NSPoint(x: tipX, y: -length),
                     controlPoint1: NSPoint(x: x * 0.9 - 30, y: -length * 0.35),
                     controlPoint2: NSPoint(x: tipX - 36, y: -length * 0.8))
        strand.curve(to: NSPoint(x: x * 0.45 + 32, y: 0),
                     controlPoint1: NSPoint(x: tipX + 40, y: -length * 0.8),
                     controlPoint2: NSPoint(x: x * 0.9 + 30, y: -length * 0.3))
        strand.close()
        strandColors[i % 3].setFill()
        strand.fill()
        color(0.55, 0.75, 0.88, 0.55).setStroke()
        strand.lineWidth = 2.5
        strand.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()

    // Ferrule band in the warm accent colour.
    let band = NSBezierPath(roundedRect: NSRect(x: -88, y: -34, width: 176, height: 84), xRadius: 26, yRadius: 26)
    NSGradient(colors: [color(1.0, 0.62, 0.20), color(1.0, 0.43, 0.22)])!.draw(in: band, angle: -90)
    color(1, 1, 1, 0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: -70, y: 26, width: 140, height: 10), xRadius: 5, yRadius: 5).fill()

    // Jaunty handle knob.
    color(1.0, 0.43, 0.22).setFill()
    NSBezierPath(ovalIn: NSRect(x: -34, y: 384, width: 68, height: 68)).fill()
    context.restoreGState()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor.black.setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0.10, 0.78, 0.74), ending: color(0.08, 0.28, 0.62))!.draw(in: body, angle: -60)

    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    // Swoosh arcs suggesting a sweeping motion.
    for (i, alpha) in [(0, 0.30), (1, 0.18)] {
        let swoosh = NSBezierPath()
        swoosh.lineWidth = CGFloat(34 - i * 12)
        swoosh.lineCapStyle = .round
        swoosh.appendArc(withCenter: NSPoint(x: 640, y: 760), radius: CGFloat(520 + i * 90), startAngle: 200, endAngle: 285)
        NSColor.white.withAlphaComponent(alpha).setStroke()
        swoosh.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()

    drawMop(in: context)

    sparkle(center: NSPoint(x: 735, y: 300), radius: 66, fill: color(1.0, 0.93, 0.55))
    sparkle(center: NSPoint(x: 810, y: 410), radius: 34, fill: .white)
    sparkle(center: NSPoint(x: 245, y: 700), radius: 38, fill: .white)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let variants: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for variant in variants {
    let suffix = variant.scale == 2 ? "@2x" : ""
    let filename = "icon_\(variant.points)x\(variant.points)\(suffix).png"
    try render(pixels: variant.points * variant.scale).write(to: output.appendingPathComponent(filename))
    images.append(["size": "\(variant.points)x\(variant.points)", "idiom": "mac", "filename": filename, "scale": "\(variant.scale)x"])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
if CommandLine.arguments.count > 2 {
    try render(pixels: 512).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
print("AppIcon written to \(output.path)")
