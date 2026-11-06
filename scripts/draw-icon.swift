import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedRed: 0.92, green: 0.79, blue: 0.60, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let ink = NSColor(calibratedRed: 0.25, green: 0.18, blue: 0.12, alpha: 1)
let cream = NSColor(calibratedRed: 0.99, green: 0.95, blue: 0.85, alpha: 1)
func ellipse(_ rect: NSRect, _ color: NSColor) { color.setFill(); NSBezierPath(ovalIn: rect).fill() }
ellipse(NSRect(x: 210, y: 330, width: 180, height: 430), ink)
ellipse(NSRect(x: 634, y: 330, width: 180, height: 430), ink)
let head = NSBezierPath(roundedRect: NSRect(x: 300, y: 220, width: 424, height: 560), xRadius: 190, yRadius: 190)
cream.setFill(); head.fill()
ellipse(NSRect(x: 393, y: 516, width: 36, height: 45), ink)
ellipse(NSRect(x: 595, y: 516, width: 36, height: 45), ink)
ellipse(NSRect(x: 462, y: 399, width: 100, height: 72), ink)
ink.setStroke()
let mouth = NSBezierPath()
mouth.lineWidth = 18; mouth.lineCapStyle = .round
mouth.move(to: NSPoint(x: 512, y: 411)); mouth.line(to: NSPoint(x: 512, y: 350))
mouth.curve(to: NSPoint(x: 439, y: 335), controlPoint1: NSPoint(x: 486, y: 324), controlPoint2: NSPoint(x: 465, y: 322))
mouth.move(to: NSPoint(x: 512, y: 350))
mouth.curve(to: NSPoint(x: 585, y: 335), controlPoint1: NSPoint(x: 538, y: 324), controlPoint2: NSPoint(x: 559, y: 322))
mouth.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Pet/Assets.xcassets/AppIcon.appiconset/icon.png"))
