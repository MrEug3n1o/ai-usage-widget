import AppKit

// Generates the app icon. Kept as code rather than a binary asset so the
// palette stays tied to the one the widget and panel use.
//
//   swift Scripts/make-icon.swift && ...   (see Scripts/make-icon.sh)
//
// Visual target: dark squircle + open-bottom gauge (lime → cyan) + white "%".

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }
let cs = CGColorSpaceCreateDeviceRGB()

// macOS icons leave breathing room around the rounded body.
let inset: CGFloat = S * 0.085
let body = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let radius = body.width * 0.2237          // Big Sur squircle-ish corner

ctx.saveGState()
ctx.addPath(CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius,
                   transform: nil))
ctx.clip()

// Near-black graphite with a soft top highlight — matches the release icon art.
let bg = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.16, green: 0.16, blue: 0.17, alpha: 1),
    CGColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: body.midX, y: body.maxY),
                       end: CGPoint(x: body.midX, y: body.minY), options: [])
ctx.restoreGState()

// A 270-degree gauge with the gap at the bottom: reads as a meter rather than
// as a progress ring, and the open bottom distinguishes it from closed rings.
let center = CGPoint(x: S / 2, y: S / 2 + S * 0.01)
let ringR = S * 0.255
let lw = S * 0.105
let startAngle = CGFloat.pi * 1.25         // 225°, lower left
let sweep = CGFloat.pi * 1.5               // 270°, clockwise
let fill: CGFloat = 0.72

ctx.setLineCap(.round)
ctx.setLineWidth(lw)

// Track.
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.14))
ctx.addArc(center: center, radius: ringR, startAngle: startAngle,
           endAngle: startAngle - sweep, clockwise: true)
ctx.strokePath()

// Value arc, stroked with a gradient. CoreGraphics cannot stroke a gradient
// directly, so the stroke is converted to a fillable path, clipped, and the
// gradient drawn through it.
ctx.saveGState()
ctx.addArc(center: center, radius: ringR, startAngle: startAngle,
           endAngle: startAngle - sweep * fill, clockwise: true)
ctx.replacePathWithStrokedPath()
ctx.clip()
// Lime → emerald → cyan, matching the provided release icon art.
let arc = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.55, green: 0.95, blue: 0.20, alpha: 1),
    CGColor(red: 0.20, green: 0.90, blue: 0.55, alpha: 1),
    CGColor(red: 0.25, green: 0.75, blue: 0.95, alpha: 1),
] as CFArray, locations: [0, 0.45, 1])!
ctx.drawLinearGradient(arc,
                       start: CGPoint(x: center.x - ringR - lw / 2, y: center.y),
                       end: CGPoint(x: center.x + ringR + lw / 2, y: center.y),
                       options: [])
ctx.restoreGState()

// Percent sign in the middle. The one glyph that says "share of a limit"
// without needing to be read.
let text = "%" as NSString
let font = NSFont.systemFont(ofSize: S * 0.23, weight: .semibold)
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let size = text.size(withAttributes: attrs)
text.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2),
          withAttributes: attrs)

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
