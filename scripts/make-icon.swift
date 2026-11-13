// Renders the Prism Keys app icon (1024x1024 PNG). Usage: swift scripts/make-icon.swift out.png
import AppKit
import CoreImage

let S: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

func makeContext() -> CGContext {
    CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func hue(_ h: CGFloat, _ a: CGFloat = 1) -> CGColor {
    let c = NSColor(hue: h, saturation: 0.9, brightness: 1, alpha: a).usingColorSpace(.sRGB)!
    return c.cgColor
}
func gradient(_ colors: [CGColor], _ locs: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locs)!
}
let spectrum = (0..<7).map { hue(CGFloat($0) / 7 * 0.83) }

// --- Glow layer (rainbow light spilling from under the keycap), blurred
let glowCtx = makeContext()
let glowRect = CGRect(x: 280, y: 250, width: 464, height: 200)
glowCtx.addPath(CGPath(roundedRect: glowRect, cornerWidth: 120, cornerHeight: 120, transform: nil))
glowCtx.clip()
glowCtx.drawLinearGradient(gradient(spectrum), start: CGPoint(x: glowRect.minX, y: 0), end: CGPoint(x: glowRect.maxX, y: 0), options: [])
let ci = CIImage(cgImage: glowCtx.makeImage()!)
let blurred = ci.clampedToExtent().applyingGaussianBlur(sigma: 42).cropped(to: ci.extent)
let glow = CIContext().createCGImage(blurred, from: ci.extent)!

// --- Main
let ctx = makeContext()
// Background squircle (Apple icon grid: 824pt body centered)
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bgPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0, 0, 0, 0.45))
ctx.addPath(bgPath); ctx.setFillColor(rgb(0.07, 0.075, 0.11)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0.17, 0.18, 0.26), rgb(0.05, 0.05, 0.08)]),
                       start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
// glow
ctx.setAlpha(0.9)
ctx.draw(glow, in: CGRect(x: 0, y: -30, width: S, height: S))
ctx.setAlpha(1)

// Keycap: skirt (sides) then top face
let skirt = CGRect(x: 262, y: 300, width: 500, height: 450)
let skirtPath = CGPath(roundedRect: skirt, cornerWidth: 70, cornerHeight: 70, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(0, 0, 0, 0.6))
ctx.addPath(skirtPath); ctx.setFillColor(rgb(0.2, 0.21, 0.28)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(skirtPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0.30, 0.31, 0.40), rgb(0.13, 0.13, 0.18)]),
                       start: CGPoint(x: 0, y: skirt.maxY), end: CGPoint(x: 0, y: skirt.minY), options: [])
// rainbow rim light along the bottom edge of the cap
ctx.setBlendMode(.plusLighter)
ctx.drawLinearGradient(gradient(spectrum.map { $0.copy(alpha: 0.55)! }), start: CGPoint(x: skirt.minX, y: 0), end: CGPoint(x: skirt.maxX, y: 0), options: [])
ctx.setBlendMode(.normal)
ctx.drawLinearGradient(gradient([rgb(0.16, 0.17, 0.22, 0), rgb(0.16, 0.17, 0.22, 1)], [0, 1]),
                       start: CGPoint(x: 0, y: skirt.minY), end: CGPoint(x: 0, y: skirt.minY + 90), options: [.drawsAfterEndLocation])
ctx.restoreGState()

let top = CGRect(x: 312, y: 368, width: 400, height: 352)
let topPath = CGPath(roundedRect: top, cornerWidth: 52, cornerHeight: 52, transform: nil)
ctx.saveGState()
ctx.addPath(topPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0.36, 0.37, 0.48), rgb(0.23, 0.24, 0.32)]),
                       start: CGPoint(x: 0, y: top.maxY), end: CGPoint(x: 0, y: top.minY), options: [])

// Glowing rainbow prism on the keycap face
let cx: CGFloat = 512, cy: CGFloat = 530, side: CGFloat = 230
let h = side * sqrt(3) / 2
let a = CGPoint(x: cx, y: cy + h * 2 / 3)          // apex
let b = CGPoint(x: cx + side / 2, y: cy - h / 3)   // bottom right
let c = CGPoint(x: cx - side / 2, y: cy - h / 3)   // bottom left
let center = CGPoint(x: cx, y: cy)
ctx.restoreGState()
let tri = CGMutablePath(); tri.move(to: a); tri.addLine(to: b); tri.addLine(to: c); tri.closeSubpath()
// soft colored halo behind the prism
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 60, color: hue(0.55, 0.8))
ctx.addPath(tri); ctx.setFillColor(rgb(0.4, 0.5, 1, 0.6)); ctx.fillPath()
ctx.restoreGState()
// three facets, each a slice of the spectrum
let facets: [(CGPoint, CGPoint, [CGColor])] = [
    (a, b, [hue(0.0), hue(0.08), hue(0.15)]),     // right facet: red → yellow
    (b, c, [hue(0.28), hue(0.42), hue(0.52)]),    // bottom facet: green → cyan
    (c, a, [hue(0.6), hue(0.7), hue(0.8)]),       // left facet: blue → violet
]
for (p1, p2, cols) in facets {
    let f = CGMutablePath(); f.move(to: center); f.addLine(to: p1); f.addLine(to: p2); f.closeSubpath()
    ctx.saveGState(); ctx.addPath(f); ctx.clip()
    ctx.drawLinearGradient(gradient(cols), start: p1, end: p2, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    // shade toward the center for a glassy, faceted look
    ctx.drawRadialGradient(gradient([rgb(1, 1, 1, 0.55), rgb(1, 1, 1, 0)]), startCenter: center, startRadius: 0,
                           endCenter: center, endRadius: side * 0.45, options: [])
    ctx.restoreGState()
}
// facet edges + outline
ctx.setLineJoin(.round); ctx.setLineCap(.round)
for p in [a, b, c] { ctx.move(to: center); ctx.addLine(to: p) }
ctx.setStrokeColor(rgb(1, 1, 1, 0.55)); ctx.setLineWidth(4); ctx.strokePath()
ctx.addPath(tri); ctx.setStrokeColor(rgb(1, 1, 1, 0.95)); ctx.setLineWidth(9); ctx.strokePath()
ctx.saveGState()
ctx.addPath(bgPath); ctx.clip()

// subtle top highlight on the cap
ctx.saveGState()
ctx.addPath(topPath); ctx.clip()
ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.14), rgb(1, 1, 1, 0)]), start: CGPoint(x: 0, y: top.maxY), end: CGPoint(x: 0, y: top.maxY - 120), options: [])
ctx.restoreGState()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
