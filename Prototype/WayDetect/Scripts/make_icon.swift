import AppKit
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
let bounds = NSRect(x: 0, y: 0, width: size, height: size)
NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.33, blue: 0.91, alpha: 1), ending: NSColor(srgbRed: 0.13, green: 0.17, blue: 0.52, alpha: 1))!.draw(in: bounds, angle: -65)
let ring = NSBezierPath(ovalIn: NSRect(x: 186, y: 186, width: 652, height: 652))
NSColor.white.withAlphaComponent(0.25).setStroke(); ring.lineWidth = 28; ring.stroke()
for index in 0..<12 {
    let angle = Double(index) * .pi / 6
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 512 + sin(angle) * 360, y: 512 + cos(angle) * 360))
    path.line(to: NSPoint(x: 512 + sin(angle) * 382, y: 512 + cos(angle) * 382))
    path.lineWidth = 10; path.lineCapStyle = .round; NSColor.white.withAlphaComponent(0.65).setStroke(); path.stroke()
}
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 512, y: 786)); arrow.line(to: NSPoint(x: 300, y: 322))
arrow.line(to: NSPoint(x: 512, y: 417)); arrow.line(to: NSPoint(x: 724, y: 322)); arrow.close()
NSColor.white.setFill(); arrow.fill()
NSGraphicsContext.restoreGraphicsState()
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
try bitmap.representation(using: .png, properties: [:])!.write(to: url)
