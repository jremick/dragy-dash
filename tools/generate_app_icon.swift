import AppKit
import Foundation

struct IconSlot {
  let idiom: String
  let pointSize: String
  let scale: Int
  let pixels: Int

  var filename: String {
    let normalizedSize = pointSize.replacingOccurrences(of: ".", with: "_")
    return "DragyDash-\(idiom)-\(normalizedSize)@\(scale)x.png"
  }
}

let outputDirectory = URL(fileURLWithPath: "DragyDash/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let slots = [
  IconSlot(idiom: "iphone", pointSize: "20x20", scale: 2, pixels: 40),
  IconSlot(idiom: "iphone", pointSize: "20x20", scale: 3, pixels: 60),
  IconSlot(idiom: "iphone", pointSize: "29x29", scale: 2, pixels: 58),
  IconSlot(idiom: "iphone", pointSize: "29x29", scale: 3, pixels: 87),
  IconSlot(idiom: "iphone", pointSize: "40x40", scale: 2, pixels: 80),
  IconSlot(idiom: "iphone", pointSize: "40x40", scale: 3, pixels: 120),
  IconSlot(idiom: "iphone", pointSize: "60x60", scale: 2, pixels: 120),
  IconSlot(idiom: "iphone", pointSize: "60x60", scale: 3, pixels: 180),
  IconSlot(idiom: "ipad", pointSize: "20x20", scale: 1, pixels: 20),
  IconSlot(idiom: "ipad", pointSize: "20x20", scale: 2, pixels: 40),
  IconSlot(idiom: "ipad", pointSize: "29x29", scale: 1, pixels: 29),
  IconSlot(idiom: "ipad", pointSize: "29x29", scale: 2, pixels: 58),
  IconSlot(idiom: "ipad", pointSize: "40x40", scale: 1, pixels: 40),
  IconSlot(idiom: "ipad", pointSize: "40x40", scale: 2, pixels: 80),
  IconSlot(idiom: "ipad", pointSize: "76x76", scale: 1, pixels: 76),
  IconSlot(idiom: "ipad", pointSize: "76x76", scale: 2, pixels: 152),
  IconSlot(idiom: "ipad", pointSize: "83.5x83.5", scale: 2, pixels: 167),
  IconSlot(idiom: "ios-marketing", pointSize: "1024x1024", scale: 1, pixels: 1024)
]

for file in try fileManager.contentsOfDirectory(at: outputDirectory, includingPropertiesForKeys: nil) where file.pathExtension == "png" {
  try fileManager.removeItem(at: file)
}

func drawIcon(size: Int) -> NSBitmapImageRep {
  let bounds = NSRect(x: 0, y: 0, width: size, height: size)
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    fatalError("Unable to create bitmap")
  }

  NSGraphicsContext.saveGraphicsState()
  let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap)!
  NSGraphicsContext.current = graphicsContext
  let context = graphicsContext.cgContext

  context.setShouldAntialias(true)
  context.setAllowsAntialiasing(true)

  let background = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
      NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.06, alpha: 1).cgColor,
      NSColor(calibratedRed: 0.06, green: 0.11, blue: 0.16, alpha: 1).cgColor,
      NSColor(calibratedRed: 0.00, green: 0.48, blue: 0.82, alpha: 1).cgColor
    ] as CFArray,
    locations: [0.0, 0.64, 1.0]
  )!
  context.drawLinearGradient(
    background,
    start: CGPoint(x: 0, y: size),
    end: CGPoint(x: size, y: 0),
    options: []
  )

  let inset = CGFloat(size) * 0.105
  let center = CGPoint(x: CGFloat(size) * 0.5, y: CGFloat(size) * 0.51)
  let radius = CGFloat(size) * 0.34

  NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.13).setStroke()
  let baseArc = NSBezierPath()
  baseArc.lineWidth = CGFloat(size) * 0.052
  baseArc.lineCapStyle = .round
  baseArc.appendArc(
    withCenter: center,
    radius: radius,
    startAngle: 205,
    endAngle: -25,
    clockwise: true
  )
  baseArc.stroke()

  NSColor(calibratedRed: 0.12, green: 0.72, blue: 1, alpha: 1).setStroke()
  let speedArc = NSBezierPath()
  speedArc.lineWidth = CGFloat(size) * 0.062
  speedArc.lineCapStyle = .round
  speedArc.appendArc(
    withCenter: center,
    radius: radius,
    startAngle: 205,
    endAngle: 15,
    clockwise: false
  )
  speedArc.stroke()

  NSColor(calibratedRed: 0.92, green: 0.98, blue: 1, alpha: 1).setStroke()
  let needle = NSBezierPath()
  needle.lineWidth = CGFloat(size) * 0.046
  needle.lineCapStyle = .round
  needle.move(to: center)
  needle.line(to: CGPoint(x: center.x + CGFloat(size) * 0.205, y: center.y + CGFloat(size) * 0.195))
  needle.stroke()

  NSColor(calibratedRed: 0.92, green: 0.98, blue: 1, alpha: 1).setFill()
  NSBezierPath(ovalIn: CGRect(
    x: center.x - CGFloat(size) * 0.042,
    y: center.y - CGFloat(size) * 0.042,
    width: CGFloat(size) * 0.084,
    height: CGFloat(size) * 0.084
  )).fill()

  NSColor(calibratedRed: 0.12, green: 0.72, blue: 1, alpha: 0.92).setStroke()
  let signalOrigin = CGPoint(x: CGFloat(size) * 0.285, y: CGFloat(size) * 0.73)
  for index in 0..<3 {
    let signal = NSBezierPath()
    signal.lineWidth = CGFloat(size) * 0.018
    signal.lineCapStyle = .round
    signal.appendArc(
      withCenter: signalOrigin,
      radius: CGFloat(size) * CGFloat(0.047 + Double(index) * 0.045),
      startAngle: 300,
      endAngle: 60,
      clockwise: false
    )
    signal.stroke()
  }
  NSBezierPath(ovalIn: CGRect(
    x: signalOrigin.x - CGFloat(size) * 0.018,
    y: signalOrigin.y - CGFloat(size) * 0.018,
    width: CGFloat(size) * 0.036,
    height: CGFloat(size) * 0.036
  )).fill()

  NSColor(calibratedRed: 1, green: 1, blue: 1, alpha: 0.15).setStroke()
  let inner = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: CGFloat(size) * 0.18, yRadius: CGFloat(size) * 0.18)
  inner.lineWidth = CGFloat(size) * 0.012
  inner.stroke()

  NSGraphicsContext.restoreGraphicsState()
  return bitmap
}

func writePNG(_ bitmap: NSBitmapImageRep, to url: URL) throws {
  guard let data = bitmap.representation(using: .png, properties: [:]) else {
    throw CocoaError(.fileWriteUnknown)
  }

  try data.write(to: url)
}

for slot in slots {
  try writePNG(drawIcon(size: slot.pixels), to: outputDirectory.appendingPathComponent(slot.filename))
}

let images = slots.map { slot in
  """
      {
        "filename" : "\(slot.filename)",
        "idiom" : "\(slot.idiom)",
        "scale" : "\(slot.scale)x",
        "size" : "\(slot.pointSize)"
      }
  """
}.joined(separator: ",\n")

let contents = """
{
  "images" : [
\(images)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""

try contents.write(to: outputDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
