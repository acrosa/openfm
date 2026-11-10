import AppKit
// App icon: algorithm 5 drawn as three carrier/modulator pairs on near-black.
let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSColor(red: 0.035, green: 0.035, blue: 0.04, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
let ink = NSColor(red: 0.957, green: 0.953, blue: 0.937, alpha: 1)
let accent = NSColor(red: 0.8, green: 1.0, blue: 0.0, alpha: 1)
let node: CGFloat = 176, pitchX: CGFloat = 264, top: CGFloat = 612, bottom: CGFloat = 300
for i in 0..<3 {
    let x = 512 + CGFloat(i - 1) * pitchX
    let line = NSBezierPath()
    line.lineWidth = 22
    line.move(to: NSPoint(x: x, y: top)); line.line(to: NSPoint(x: x, y: bottom))
    line.move(to: NSPoint(x: x, y: bottom)); line.line(to: NSPoint(x: x, y: bottom - 150))
    ink.withAlphaComponent(0.4).setStroke(); line.stroke()
    let m = NSBezierPath(roundedRect: NSRect(x: x - node/2, y: top - node/2, width: node, height: node), xRadius: 44, yRadius: 44)
    NSColor(red: 0.035, green: 0.035, blue: 0.04, alpha: 1).setFill(); m.fill()
    m.lineWidth = 22; (i == 2 ? accent : ink).setStroke(); m.stroke()
    let c = NSBezierPath(roundedRect: NSRect(x: x - node/2, y: bottom - node/2, width: node, height: node), xRadius: 44, yRadius: 44)
    (i == 2 ? accent : ink).setFill(); c.fill()
}
let bus = NSBezierPath(); bus.lineWidth = 22; bus.lineCapStyle = .round
bus.move(to: NSPoint(x: 512 - pitchX, y: bottom - 150)); bus.line(to: NSPoint(x: 512 + pitchX + 110, y: bottom - 150))
ink.withAlphaComponent(0.4).setStroke(); bus.stroke()
NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
