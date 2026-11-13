import AppKit
import Foundation

// Generates the DMG window background in the NeoCraft visual language:
// deep forest gradient, pixel grid, isometric grass block, pixel sparkles
// and the wordmark with a drag hint. Output: PNG path given as argv[1],
// optional version string as argv[2].

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/dmg-background.png"
let version = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
let scale: CGFloat = 2
let W: CGFloat = 760
let H: CGFloat = 440

let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()

let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Background: deep forest diagonal gradient.
let bg = NSGradient(colors: [
    rgb(0.16, 0.32, 0.19),
    rgb(0.08, 0.17, 0.11),
    rgb(0.05, 0.11, 0.08)
])!
bg.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -55)

// Pixel grid overlay.
let cell: CGFloat = 20
var gy: CGFloat = 0
while gy < H {
    var gx: CGFloat = 0
    while gx < W {
        if Int((gx / cell) + (gy / cell)) % 2 == 0 {
            rgb(1, 1, 1, 0.018).setFill()
            NSRect(x: gx, y: gy, width: cell, height: cell).fill()
        }
        gx += cell
    }
    gy += cell
}

// Isometric grass block (left side, large).
let bx: CGFloat = 150, by: CGFloat = 250, r: CGFloat = 78
let dx = r * 0.866
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: bx + x, y: by + y) }
let top = pt(0, r), ur = pt(dx, r * 0.5), lr = pt(dx, -r * 0.5)
let bot = pt(0, -r), ll = pt(-dx, -r * 0.5), ul = pt(-dx, r * 0.5), c = pt(0, 0)

func poly(_ pts: [CGPoint], _ colors: [NSColor]) {
    let path = NSBezierPath()
    path.move(to: pts[0])
    for p in pts.dropFirst() { path.line(to: p) }
    path.close()
    path.addClip()
    let grad = NSGradient(colors: colors)!
    grad.draw(in: NSRect(x: bx - dx, y: by - r, width: dx * 2, height: r * 2), angle: -45)
}

// Right dirt face (lit), left dirt face (shadowed), grass top.
poly([c, ur, lr, bot], [rgb(0.56, 0.39, 0.26), rgb(0.40, 0.27, 0.17)])
poly([c, ul, ll, bot], [rgb(0.38, 0.26, 0.16), rgb(0.27, 0.17, 0.10)])
poly([top, ur, c, ul], [rgb(0.66, 0.90, 0.36), rgb(0.45, 0.70, 0.24)])

// Grass fringe on top edges.
rgb(0.78, 0.97, 0.42).setStroke()
let fringe = NSBezierPath()
fringe.lineWidth = 3
fringe.move(to: ul); fringe.line(to: top); fringe.line(to: ur)
fringe.stroke()

// Block outline.
rgb(0.08, 0.13, 0.07, 0.9).setStroke()
let outline = NSBezierPath()
outline.lineWidth = 2.5
outline.lineJoinStyle = .round
outline.move(to: top); outline.line(to: ur); outline.line(to: lr)
outline.line(to: bot); outline.line(to: ll); outline.line(to: ul)
outline.close(); outline.stroke()
outline.move(to: ul); outline.line(to: c); outline.line(to: ur)
outline.move(to: c); outline.line(to: bot)
outline.stroke()

// Dirt speckles.
var seed: UInt64 = 0xDEADBEEF
func rnd() -> CGFloat {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
    return CGFloat(seed % 1000) / 1000
}
for _ in 0..<40 {
    let px = bx - dx + dx * 2 * rnd()
    let py = by - r + r * 2 * rnd()
    (rnd() > 0.5 ? rgb(0.25, 0.16, 0.09, 0.7) : rgb(0.66, 0.48, 0.32, 0.6)).setFill()
    NSRect(x: px, y: py, width: 4, height: 4).fill()
}
for _ in 0..<14 {
    let px = bx - dx + dx * 2 * rnd()
    let py = by + r * rnd()
    rgb(0.80, 1.0, 0.45, 0.8).setFill()
    NSRect(x: px, y: py, width: 4, height: 4).fill()
}

// Pixel sparkles scattered on the right.
for i in 0..<26 {
    let sx = 430 + CGFloat(i * 37 % 280)
    let sy = 60 + CGFloat(i * 53 % 300)
    let s = CGFloat(2 + i % 3)
    let col = i % 4 == 0 ? rgb(0.55, 0.85, 0.35) : rgb(1, 1, 1, 0.25)
    col.setFill()
    NSRect(x: sx, y: sy, width: s, height: s).fill()
}

// Wordmark.
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "HelveticaNeue-Bold", size: 64) ?? NSFont.boldSystemFont(ofSize: 64),
    .foregroundColor: NSColor.white
]
"NeoCraft".draw(at: NSPoint(x: 420, y: H - 150), withAttributes: titleAttrs)

let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "HelveticaNeue-Medium", size: 22) ?? NSFont.systemFont(ofSize: 22),
    .foregroundColor: rgb(0.75, 0.95, 0.55)
]
let subtitle = version.isEmpty
    ? "Native Minecraft Launcher"
    : "Version \(version) · Native Minecraft Launcher"
"\(subtitle)".draw(at: NSPoint(x: 424, y: H - 195), withAttributes: subAttrs)

// Drag hint arrow (pixel style).
rgb(1, 1, 1, 0.85).setFill()
var ax: CGFloat = 560
let ay: CGFloat = 300
for step in 0..<3 {
    let w = CGFloat(90 - step * 22)
    NSRect(x: ax + CGFloat(step) * 14, y: ay - CGFloat(step) * 6, width: w, height: 8).fill()
}
// Arrow head pixels.
for i in 0..<4 {
    NSRect(x: ax + 96 + CGFloat(i) * 8, y: ay - 12 + CGFloat(i) * 6, width: 8, height: 8).fill()
    NSRect(x: ax + 96 + CGFloat(i) * 8, y: ay + 4 - CGFloat(i) * 6, width: 8, height: 8).fill()
}

let hintAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 17, weight: .semibold),
    .foregroundColor: rgb(1, 1, 1, 0.8)
]
"Drag to Applications".draw(at: NSPoint(x: 430, y: ay - 46), withAttributes: hintAttrs)

// Bottom-left voxel signature: three grass pixels.
rgb(0.49, 0.80, 0.29, 0.9).setFill()
for i in 0..<3 {
    NSRect(x: 36 + CGFloat(i) * 10, y: 30, width: 7, height: 7).fill()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("Could not encode background\n".data(using: .utf8)!)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath) (\(Int(W))x\(Int(H)) @\(Int(scale))x)")
