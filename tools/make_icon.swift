// Draws the app icon (a stack of Newton packages under a lightbulb, on a Newton
// LCD screen) and writes every size the asset catalog needs.
//   xcrun swift tools/make_icon.swift NewtonLibrary/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func draw(_ s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(s), pixelsHigh: Int(s), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let u = s / 1024   // design units are for a 1024-pixel icon

    // macOS icon shape: a rounded square inset from the edges
    let tile = NSRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * u, yRadius: 185 * u)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * u)
    shadow.shadowBlurRadius = 24 * u
    shadow.set()
    NSColor(calibratedRed: 0.28, green: 0.29, blue: 0.27, alpha: 1).setFill()   // the MessagePad's dark case
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    // The greenish Newton screen
    let screen = NSRect(x: 160 * u, y: 160 * u, width: 704 * u, height: 704 * u)
    let screenPath = NSBezierPath(roundedRect: screen, xRadius: 120 * u, yRadius: 120 * u)
    NSGradient(starting: NSColor(calibratedRed: 0.78, green: 0.81, blue: 0.70, alpha: 1),
               ending: NSColor(calibratedRed: 0.64, green: 0.68, blue: 0.56, alpha: 1))!.draw(in: screenPath, angle: -90)

    let ink = NSColor(calibratedWhite: 0.08, alpha: 1)
    let grey = NSColor(calibratedWhite: 0.42, alpha: 1)
    let light = NSColor(calibratedWhite: 0.88, alpha: 1)

    // Three package cartridges, stacked and slightly offset
    let boxes: [(x: CGFloat, y: CGFloat, fill: NSColor)] = [(262, 230, grey), (292, 350, light), (248, 470, grey)]
    for box in boxes {
        let r = NSRect(x: box.x * u, y: box.y * u, width: 500 * u, height: 105 * u)
        let p = NSBezierPath(roundedRect: r, xRadius: 16 * u, yRadius: 16 * u)
        box.fill.setFill()
        p.fill()
        ink.setStroke()
        p.lineWidth = 14 * u
        p.stroke()
        // the label
        let label = NSRect(x: (box.x + 40) * u, y: (box.y + 30) * u, width: 200 * u, height: 45 * u)
        (box.fill == light ? grey : light).setFill()
        NSBezierPath(roundedRect: label, xRadius: 6 * u, yRadius: 6 * u).fill()
        // grip lines on the right
        ink.setFill()
        for i in 0..<3 {
            NSRect(x: (box.x + 330 + CGFloat(i) * 40) * u, y: (box.y + 25) * u, width: 14 * u, height: 55 * u).fill()
        }
    }

    // A lightbulb (the idea behind the Newton) above the stack
    let bulb = NSBezierPath(ovalIn: NSRect(x: 412 * u, y: 640 * u, width: 200 * u, height: 190 * u))
    light.setFill()
    bulb.fill()
    ink.setStroke()
    bulb.lineWidth = 14 * u
    bulb.stroke()
    let neck = NSRect(x: 462 * u, y: 600 * u, width: 100 * u, height: 52 * u)
    light.setFill()
    neck.fill()
    let neckPath = NSBezierPath(rect: neck)
    neckPath.lineWidth = 14 * u
    neckPath.stroke()
    for i in 0..<2 {
        NSRect(x: 470 * u, y: (610 + CGFloat(i) * 22) * u, width: 84 * u, height: 8 * u).fill()
    }
    ink.setFill()
    NSBezierPath(roundedRect: NSRect(x: 482 * u, y: 586 * u, width: 60 * u, height: 22 * u), xRadius: 8 * u, yRadius: 8 * u).fill()
    // a glint
    let glint = NSBezierPath()
    glint.lineWidth = 16 * u
    glint.lineCapStyle = .round
    glint.appendArc(withCenter: NSPoint(x: 512 * u, y: 735 * u), radius: 62 * u, startAngle: 110, endAngle: 160)
    NSColor.white.setStroke()
    glint.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

var images: [[String: String]] = []
for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let png = draw(CGFloat(points * scale)).representation(using: .png, properties: [:])!
        try! png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
        images.append(["idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: URL(fileURLWithPath: outDir).appendingPathComponent("Contents.json"))
print("wrote \(images.count) icon sizes to \(outDir)")
