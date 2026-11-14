import AppKit
import Foundation

// Generates the .pkg installer welcome background in the NeoCraft visual
// language: deep forest gradient, pixel grid, isometric grass block,
// pixel sparkles and the wordmark. Output: PNG path given as argv[1],
// optional version string as argv[2].

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/installer-background.png"
let version = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
let W: CGFloat = 680
let H: CGFloat = 400

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
let bx: CGFloat = 110, by: CGFloat = 235, r: CGFloat = 66
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
var seed: UInt64 = 0xBADC0DE
func rnd() -> CGFloat {
    seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
    return CGFloat(seed % 1000) / 1000
}
for _ in 0..<30 {
    let px = bx - dx + dx * 2 * rnd()
    let py = by - r + r * 2 * rnd()
    (rnd() > 0.5 ? rgb(0.25, 0.16, 0.09, 0.7) : rgb(0.66, 0.48, 0.32, 0.6)).setFill()
    NSRect(x: px, y: py, width: 4, height: 4).fill()
}
for _ in 0..<10 {
    let px = bx - dx + dx * 2 * rnd()
    let py = by + r * rnd()
    rgb(0.80, 1.0, 0.45, 0.8).setFill()
    NSRect(x: px, y: py, width: 4, height: 4).fill()
}

// Pixel sparkles scattered on the right.
for i in 0..<22 {
    let sx = 320 + CGFloat(i * 41 % 320)
    let sy = 50 + CGFloat(i * 47 % 290)
    let s = CGFloat(2 + i % 3)
    let col = i % 4 == 0 ? rgb(0.55, 0.85, 0.35) : rgb(1, 1, 1, 0.25)
    col.setFill()
    NSRect(x: sx, y: sy, width: s, height: s).fill()
}

// Wordmark.
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "HelveticaNeue-Bold", size: 52) ?? NSFont.boldSystemFont(ofSize: 52),
    .foregroundColor: NSColor.white
]
"NeoCraft".draw(at: NSPoint(x: 330, y: H - 130), withAttributes: titleAttrs)

let subtitle = version.isEmpty
    ? "Voxel Edition"
    : "Version \(version) · Voxel Edition"
let subAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "HelveticaNeue-Medium", size: 19) ?? NSFont.systemFont(ofSize: 19),
    .foregroundColor: rgb(0.75, 0.95, 0.55)
]
subtitle.draw(at: NSPoint(x: 334, y: H - 168), withAttributes: subAttrs)

// Bottom-left voxel signature: three grass pixels.
rgb(0.49, 0.80, 0.29, 0.9).setFill()
for i in 0..<3 {
    NSRect(x: 30 + CGFloat(i) * 10, y: 26, width: 7, height: 7).fill()
}

image.unlockFocus()

// JPEG keeps the installer HTML small enough to embed as a data URI —
// productbuild only ships resources explicitly referenced by the
// Distribution XML, so a sibling PNG would never reach the webview.
let isJPEG = outPath.hasSuffix(".jpg") || outPath.hasSuffix(".jpeg")
let type: NSBitmapImageRep.FileType = isJPEG ? .jpeg : .png
let properties: [NSBitmapImageRep.PropertyKey: Any] = isJPEG
    ? [.compressionFactor: 0.82]
    : [:]

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let data = rep.representation(using: type, properties: properties) else {
    FileHandle.standardError.write("Could not encode background\n".data(using: .utf8)!)
    exit(1)
}
try data.write(to: URL(fileURLWithPath: outPath))
print("Wrote \(outPath) (\(Int(W))x\(Int(H)))")
