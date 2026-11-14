import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Generates the NeoCraft app icon as an .iconset directory. The build script
// runs this and then feeds the directory to `iconutil`.
//
// Design (2.3.0 rebrand): a chunky pixel-art grass block floating on a deep
// "bedrock" tile — grass-green noisy top, dirt-brown sides with a grass
// overhang, dark voxel outline and teal ambient glow. Readable at 16 px.

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "build/icon.iconset"
let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)

do {
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write("Could not create \(outputPath): \(error)\n".data(using: .utf8)!)
    exit(1)
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

// Deterministic per-cell hash so the pixel noise is stable across sizes.
func hash2(_ x: Int, _ y: Int, _ salt: Int) -> CGFloat {
    var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ salt &* 97_531))
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return CGFloat(h % 10_000) / 10_000
}

/// Ray-casting point-in-polygon test for filling faces with pixel cells.
func inside(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
    var result = false
    var j = poly.count - 1
    for i in 0..<poly.count {
        let a = poly[i], b = poly[j]
        if (a.y > p.y) != (b.y > p.y),
           p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
            result.toggle()
        }
        j = i
    }
    return result
}

/// Distance from point to segment — used for the grass overhang strip.
func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lenSq = dx * dx + dy * dy
    guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq
    t = max(0, min(1, t))
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

func lerpColor(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat), _ t: CGFloat) -> CGColor {
    let k = max(0, min(1, t))
    return CGColor(
        colorSpace: CGColorSpaceCreateDeviceRGB(),
        components: [
            a.0 + (b.0 - a.0) * k,
            a.1 + (b.1 - a.1) * k,
            a.2 + (b.2 - a.2) * k,
            1
        ]
    )!
}

func makeIcon(pixels: Int) -> CGImage? {
    let size = CGFloat(pixels)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return nil
    }

    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)

    let inset = size * 0.035
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.225
    let backgroundPath = CGPath(
        roundedRect: rect,
        cornerWidth: radius,
        cornerHeight: radius,
        transform: nil
    )

    // Soft drop shadow around the rounded tile.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.018),
        blur: max(1, size * 0.045),
        color: CGColor(red: 0.0, green: 0.01, blue: 0.03, alpha: 0.5)
    )
    context.addPath(backgroundPath)
    context.setFillColor(CGColor(red: 0.05, green: 0.06, blue: 0.14, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(backgroundPath)
    context.clip()

    // Background: deep "bedrock night" gradient with a teal ambient bloom.
    let bgColors = [
        CGColor(red: 0.11, green: 0.13, blue: 0.30, alpha: 1),
        CGColor(red: 0.06, green: 0.07, blue: 0.18, alpha: 1),
        CGColor(red: 0.03, green: 0.04, blue: 0.11, alpha: 1)
    ] as CFArray
    if let bg = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 0.55, 1]) {
        context.drawLinearGradient(
            bg,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.minX + rect.width * 0.4, y: rect.minY),
            options: []
        )
    }

    // Teal glow behind the block — the new brand accent.
    let glowColors = [
        CGColor(red: 0.18, green: 0.85, blue: 0.75, alpha: 0.20),
        CGColor(red: 0.18, green: 0.85, blue: 0.75, alpha: 0)
    ] as CFArray
    if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1]) {
        let glowCenter = CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.03)
        context.drawRadialGradient(
            glow,
            startCenter: glowCenter,
            startRadius: 0,
            endCenter: glowCenter,
            endRadius: rect.width * 0.6,
            options: []
        )
    }

    // Faint pixel grid on the tile.
    let cell = size / 20
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.03))
    var gy = rect.minY
    while gy < rect.maxY {
        var gx = rect.minX
        while gx < rect.maxX {
            if Int(gx / cell + gy / cell) % 2 == 0 {
                context.fill(CGRect(x: gx, y: gy, width: cell, height: cell))
            }
            gx += cell
        }
        gy += cell
    }

    // MARK: Pixel-art grass block

    let cx = rect.midX
    let cy = rect.midY - rect.height * 0.01
    let cubeR = rect.width * 0.26
    let dx = cubeR * 0.8660

    let top = CGPoint(x: cx, y: cy + cubeR)
    let upperRight = CGPoint(x: cx + dx, y: cy + cubeR * 0.5)
    let lowerRight = CGPoint(x: cx + dx, y: cy - cubeR * 0.5)
    let bottom = CGPoint(x: cx, y: cy - cubeR)
    let lowerLeft = CGPoint(x: cx - dx, y: cy - cubeR * 0.5)
    let upperLeft = CGPoint(x: cx - dx, y: cy + cubeR * 0.5)
    let center = CGPoint(x: cx, y: cy)

    let topFace = [top, upperRight, center, upperLeft]
    let rightFace = [center, upperRight, lowerRight, bottom]
    let leftFace = [center, upperLeft, lowerLeft, bottom]

    /// Minecraft-ish palette stops (sRGB 0…1 triples).
    let grassA: (CGFloat, CGFloat, CGFloat) = (0.49, 0.80, 0.29)   // #7CBD4B
    let grassB: (CGFloat, CGFloat, CGFloat) = (0.36, 0.68, 0.22)   // #5CAE38
    let grassC: (CGFloat, CGFloat, CGFloat) = (0.57, 0.86, 0.35)   // #92DC59
    let dirtA: (CGFloat, CGFloat, CGFloat) = (0.47, 0.33, 0.23)    // #79553A
    let dirtB: (CGFloat, CGFloat, CGFloat) = (0.37, 0.26, 0.17)    // #5F422B
    let dirtC: (CGFloat, CGFloat, CGFloat) = (0.55, 0.40, 0.28)    // #8C6847

    let pixel = max(2, cubeR * 0.30)

    /// Fills a face polygon with a grid of shaded "texels" — the pixel-art
    /// signature. `shade` darkens cells near the polygon's lower area for
    /// cheap ambient occlusion.
    func paintFace(
        _ poly: [CGPoint],
        palette: [(CGFloat, CGFloat, CGFloat)],
        salt: Int,
        grassEdge: (CGPoint, CGPoint)? = nil
    ) {
        let minX = poly.map(\.x).min()! - pixel
        let maxX = poly.map(\.x).max()! + pixel
        let minY = poly.map(\.y).min()! - pixel
        let maxY = poly.map(\.y).max()! + pixel

        var iy = Int(floor(minY / pixel))
        while CGFloat(iy) * pixel < maxY {
            var ix = Int(floor(minX / pixel))
            while CGFloat(ix) * pixel < maxX {
                let px = (CGFloat(ix) + 0.5) * pixel
                let py = (CGFloat(iy) + 0.5) * pixel
                let pt = CGPoint(x: px, y: py)
                if inside(pt, poly) {
                    let n = hash2(ix, iy, salt)
                    var color = palette[Int(n * CGFloat(palette.count)) % palette.count]
                    // Slight per-texel brightness jitter.
                    let jitter = 0.92 + hash2(ix &+ 31, iy &+ 17, salt &+ 7) * 0.16
                    // Grass overhang strip along the face's top edge.
                    if let edge = grassEdge,
                       distanceToSegment(pt, edge.0, edge.1) < pixel * 1.15 {
                        color = n > 0.5 ? grassB : grassA
                    }
                    context.setFillColor(
                        lerpColor(color, (0, 0, 0), 1 - jitter)
                    )
                    context.fill(CGRect(x: CGFloat(ix) * pixel, y: CGFloat(iy) * pixel, width: pixel, height: pixel))
                }
                ix += 1
            }
            iy += 1
        }
    }

    // Soft contact shadow under the block.
    context.saveGState()
    context.setShadow(offset: .zero, blur: cubeR * 0.55, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))
    context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.55))
    context.fillEllipse(in: CGRect(x: cx - dx * 1.05, y: bottom.y - cubeR * 0.35, width: dx * 2.1, height: cubeR * 0.7))
    context.restoreGState()

    // Faces back-to-front: left, right, top.
    paintFace(leftFace, palette: [dirtA, dirtB, dirtC], salt: 11,
              grassEdge: (center, upperLeft))
    paintFace(rightFace, palette: [dirtA, dirtB, dirtC], salt: 23,
              grassEdge: (center, upperRight))
    paintFace(topFace, palette: [grassA, grassB, grassC], salt: 37)

    // Crisp voxel outline.
    func stroke(_ pts: [CGPoint]) {
        context.setStrokeColor(CGColor(red: 0.07, green: 0.05, blue: 0.02, alpha: 0.95))
        context.setLineWidth(max(1, size * 0.005))
        context.setLineJoin(.round)
        context.beginPath()
        context.move(to: pts[0])
        for p in pts.dropFirst() { context.addLine(to: p) }
        context.closePath()
        context.strokePath()
    }
    stroke([top, upperRight, lowerRight, bottom, lowerLeft, upperLeft])
    context.setStrokeColor(CGColor(red: 0.07, green: 0.05, blue: 0.02, alpha: 0.95))
    context.setLineWidth(max(1, size * 0.005))
    context.beginPath()
    context.move(to: upperLeft); context.addLine(to: center); context.addLine(to: upperRight)
    context.move(to: center); context.addLine(to: bottom)
    context.strokePath()

    // Lit top rim — the voxel signature highlight.
    context.setStrokeColor(CGColor(red: 0.85, green: 1.0, blue: 0.55, alpha: 0.85))
    context.setLineWidth(max(1, size * 0.004))
    context.beginPath()
    context.move(to: upperLeft); context.addLine(to: top); context.addLine(to: upperRight)
    context.strokePath()

    context.restoreGState()

    // Inner glass rim on the tile.
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.22))
    context.setLineWidth(max(1, size * 0.005))
    context.addPath(backgroundPath)
    context.strokePath()

    context.restoreGState()
    return context.makeImage()
}

for item in sizes {
    guard let image = makeIcon(pixels: item.pixels) else {
        FileHandle.standardError.write("Could not render \(item.name)\n".data(using: .utf8)!)
        exit(1)
    }

    let fileURL = outputURL.appendingPathComponent(item.name, isDirectory: false)
    guard let destination = CGImageDestinationCreateWithURL(
        fileURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        FileHandle.standardError.write("Could not create \(item.name)\n".data(using: .utf8)!)
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        FileHandle.standardError.write("Could not write \(item.name)\n".data(using: .utf8)!)
        exit(1)
    }
}

print("Generated \(sizes.count) icon images in \(outputPath)")
