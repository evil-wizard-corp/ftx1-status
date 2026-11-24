// Draws the app icon: radio waves from a green "status OK" node above a WSJT-X-style waterfall.
// Usage: swift scripts/make-icon.swift Icon/AppIcon.png
// build-app.sh turns the PNG into AppIcon.icns; rerun this only when changing the artwork.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "Icon/AppIcon.png"

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Deterministic noise, so the waterfall texture is the same every run.
struct LCG { var s: UInt64; mutating func next() -> CGFloat {
    s = s &* 6364136223846793005 &+ 1442695040888963407
    return CGFloat((s >> 33) & 0xFFFF) / 0xFFFF
} }

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// macOS icon grid: an 824 pt body centered on the 1024 canvas, leaving room for the shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(0x0E1B2E)); ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape); ctx.clip()

// Night-sky background.
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x23426B), rgb(0x0C1728)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])

// Waterfall strip along the bottom: dim noise rows, then a few FT8 signals (narrow vertical traces).
let fall = CGRect(x: body.minX, y: body.minY, width: body.width, height: 270)
// Base fades out over the top 90 pt so the strip blends into the sky instead of ending at a seam.
let base = CGGradient(colorsSpace: space, colors: [rgb(0x081222), rgb(0x081222), rgb(0x081222, 0)] as CFArray,
                      locations: [0, 0.62, 1])!
ctx.drawLinearGradient(base, start: CGPoint(x: 0, y: fall.minY), end: CGPoint(x: 0, y: fall.maxY + 30), options: [])
var rng = LCG(s: 7)
let cell: CGFloat = 12
var y = fall.minY
while y < fall.maxY {
    var x = fall.minX
    while x < fall.maxX {
        let v = rng.next()
        let edge = min(1, max(0, (fall.maxY - y) / 110))  // noise thins out toward the top
        ctx.setFillColor(rgb(0x1D4E89, (0.15 + 0.45 * v * v) * edge)); ctx.fill(CGRect(x: x, y: y, width: cell, height: cell))
        x += cell
    }
    y += cell
}
// (x center, top, height, color): staggered like decodes arriving in successive 15 s periods.
let signals: [(CGFloat, CGFloat, CGFloat, UInt32)] = [
    (215, 345, 150, 0xFFD60A), (330, 300, 120, 0x64D2FF), (450, 350, 170, 0xFFD60A),
    (600, 320, 110, 0x30D158), (705, 345, 160, 0xFFD60A), (810, 290, 100, 0x64D2FF),
]
for (cx, top, h, color) in signals {
    let r = CGRect(x: cx - 9, y: top - h, width: 18, height: h)
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 18, color: rgb(color, 0.9))
    ctx.setFillColor(rgb(color, 0.95))
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
    ctx.restoreGState()
}

// Radio waves: three arc pairs around the node.
let node = CGPoint(x: 512, y: 590)
ctx.setLineCap(.round)
for (i, radius) in [CGFloat(105), 180, 255].enumerated() {
    ctx.setStrokeColor(rgb(0xFFFFFF, [1.0, 0.8, 0.55][i]))
    ctx.setLineWidth(34)
    let spread = CGFloat.pi / 4.2
    for center in [CGFloat.pi, 0] {
        ctx.addArc(center: node, radius: radius, startAngle: center - spread, endAngle: center + spread, clockwise: false)
        ctx.strokePath()
    }
}

// Status node: green with a soft glow and a highlight.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 40, color: rgb(0x30D158, 0.9))
ctx.setFillColor(rgb(0x30D158))
ctx.fillEllipse(in: CGRect(x: node.x - 46, y: node.y - 46, width: 92, height: 92))
ctx.restoreGState()
ctx.setFillColor(rgb(0xFFFFFF, 0.35))
ctx.fillEllipse(in: CGRect(x: node.x - 24, y: node.y + 4, width: 30, height: 26))

ctx.restoreGState()

// Thin inner stroke so the edge holds up on dark backgrounds.
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
ctx.setStrokeColor(rgb(0xFFFFFF, 0.12)); ctx.setLineWidth(3); ctx.strokePath()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
