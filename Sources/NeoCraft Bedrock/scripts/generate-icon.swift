import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Generates the NeoCraft app icon as an .iconset directory. The build script
// runs this and then feeds the directory to `iconutil`.
//
// Design: a Minecraft grass block in isometric view — pixel-green top,
// layered dirt sides — centered on a deep forest-green tile. Flat, chunky
// and readable at 16 px, like a real block texture.

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
    let radius = rect.width * 0.235
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
        color: CGColor(red: 0.01, green: 0.03, blue: 0.02, alpha: 0.45)
    )
    context.addPath(backgroundPath)
    context.setFillColor(CGColor(red: 0.10, green: 0.20, blue: 0.13, alpha: 1))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(backgroundPath)
    context.clip()

    // Background: deep forest gradient, darker at the bottom like a cave wall.
    let bgColors = [
        CGColor(red: 0.16, green: 0.32, blue: 0.19, alpha: 1),
        CGColor(red: 0.08, green: 0.17, blue: 0.11, alpha: 1),
        CGColor(red: 0.05, green: 0.11, blue: 0.08, alpha: 1)
    ] as CFArray
    if let bg = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0, 0.55, 1]) {
        context.drawLinearGradient(
            bg,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY),
            options: []
        )
    }

    // Faint pixel-grid texture on the background (Minecraft dirt vibe).
    let gridAlpha = pixels >= 64 ? 0.05 : 0.0
    if gridAlpha > 0 {
        let cell = size / 16
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: gridAlpha))
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
    }

    // Soft glow behind the block.
    let glowColors = [
        CGColor(red: 0.55, green: 0.85, blue: 0.35, alpha: 0.30),
        CGColor(red: 0.55, green: 0.85, blue: 0.35, alpha: 0)
    ] as CFArray
    if let glow = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0, 1]) {
        let glowCenter = CGPoint(x: rect.midX, y: rect.midY - rect.height * 0.04)
        context.drawRadialGradient(
            glow,
            startCenter: glowCenter,
            startRadius: 0,
            endCenter: glowCenter,
            endRadius: rect.width * 0.55,
            options: []
        )
    }

    // Drop shadow under the block.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.03,
        color: CGColor(red: 0.0, green: 0.02, blue: 0.01, alpha: 0.55)
    )

    // Isometric grass block.
    let cx = rect.midX
    let cy = rect.midY - rect.height * 0.01
    let cubeRadius = rect.width * 0.27
    let dx = cubeRadius * 0.8660
    let top = CGPoint(x: cx, y: cy + cubeRadius)
    let upperRight = CGPoint(x: cx + dx, y: cy + cubeRadius * 0.5)
    let lowerRight = CGPoint(x: cx + dx, y: cy - cubeRadius * 0.5)
    let bottom = CGPoint(x: cx, y: cy - cubeRadius)
    let lowerLeft = CGPoint(x: cx - dx, y: cy - cubeRadius * 0.5)
    let upperLeft = CGPoint(x: cx - dx, y: cy + cubeRadius * 0.5)
    let center = CGPoint(x: cx, y: cy)

    func facePath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    /// Fills a face path, then lays a linear gradient clipped to that face.
    func fillFaceGradient(
        _ points: [CGPoint],
        bbox: CGRect,
        colors: [CGColor],
        locations: [CGFloat] = [0, 1]
    ) {
        context.saveGState()
        context.addPath(facePath(points))
        context.clip()
        if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: bbox.minX, y: bbox.maxY),
                end: CGPoint(x: bbox.maxX, y: bbox.minY),
                options: []
            )
        }
        context.restoreGState()
    }

    // Grass top: bright green with a sunlit gradient.
    fillFaceGradient(
        [top, upperRight, center, upperLeft],
        bbox: CGRect(x: cx - dx, y: cy, width: dx * 2, height: cubeRadius),
        colors: [
            CGColor(red: 0.62, green: 0.86, blue: 0.32, alpha: 1),
            CGColor(red: 0.45, green: 0.72, blue: 0.25, alpha: 1)
        ]
    )

    // Dirt sides: right face lit, left face shaded (classic MC lighting).
    fillFaceGradient(
        [center, upperRight, lowerRight, bottom],
        bbox: CGRect(x: cx, y: cy - cubeRadius, width: dx, height: cubeRadius * 2),
        colors: [
            CGColor(red: 0.56, green: 0.39, blue: 0.26, alpha: 1),
            CGColor(red: 0.42, green: 0.28, blue: 0.17, alpha: 1)
        ]
    )
    fillFaceGradient(
        [center, upperLeft, lowerLeft, bottom],
        bbox: CGRect(x: cx - dx, y: cy - cubeRadius, width: dx, height: cubeRadius * 2),
        colors: [
            CGColor(red: 0.40, green: 0.27, blue: 0.17, alpha: 1),
            CGColor(red: 0.30, green: 0.19, blue: 0.11, alpha: 1)
        ]
    )

    // Pixel speckles on the dirt faces — the blocky texture signature.
    if pixels >= 48 {
        let speck = max(1.5, size * 0.006)
        let dirtDark = CGColor(red: 0.22, green: 0.14, blue: 0.08, alpha: 0.8)
        let dirtLight = CGColor(red: 0.62, green: 0.45, blue: 0.30, alpha: 0.7)
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rand() -> CGFloat {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return CGFloat(seed % 1000) / 1000
        }
        // Scatter inside the right face bbox.
        for _ in 0..<26 {
            let px = cx + dx * rand() * 0.9
            let py = cy - cubeRadius + cubeRadius * 2 * rand()
            let col = rand() > 0.5 ? dirtDark : dirtLight
            context.setFillColor(col)
            context.fill(CGRect(x: px, y: py, width: speck, height: speck))
        }
        for _ in 0..<22 {
            let px = cx - dx + dx * rand() * 0.9
            let py = cy - cubeRadius + cubeRadius * 2 * rand()
            let col = rand() > 0.5 ? dirtDark : dirtLight
            context.setFillColor(col)
            context.fill(CGRect(x: px, y: py, width: speck, height: speck))
        }
        // Grass tufts: tiny lighter-green pixels on the top face.
        let tuft = CGColor(red: 0.75, green: 0.95, blue: 0.40, alpha: 0.9)
        for _ in 0..<18 {
            let px = cx - dx + dx * 2 * rand()
            let py = cy + cubeRadius * rand()
            context.setFillColor(tuft)
            context.fill(CGRect(x: px, y: py, width: speck, height: speck))
        }
    }

    // Block edges: crisp darker outline like a voxel silhouette.
    context.setStrokeColor(CGColor(red: 0.10, green: 0.16, blue: 0.08, alpha: 0.85))
    context.setLineWidth(max(1, size * 0.008))
    context.setLineJoin(.round)
    context.beginPath()
    context.move(to: top)
    context.addLine(to: upperRight)
    context.addLine(to: lowerRight)
    context.addLine(to: bottom)
    context.addLine(to: lowerLeft)
    context.addLine(to: upperLeft)
    context.closePath()
    context.move(to: upperLeft)
    context.addLine(to: center)
    context.addLine(to: upperRight)
    context.move(to: center)
    context.addLine(to: bottom)
    context.strokePath()

    // Grass fringe: a 1-2px lighter lip along the top-face front edges,
    // like the overhanging grass layer on a real grass block.
    context.setStrokeColor(CGColor(red: 0.72, green: 0.95, blue: 0.38, alpha: 0.9))
    context.setLineWidth(max(1, size * 0.006))
    context.beginPath()
    context.move(to: upperLeft)
    context.addLine(to: top)
    context.addLine(to: upperRight)
    context.strokePath()

    context.restoreGState()

    // Crisp inner border on the tile.
    context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    context.setLineWidth(max(1, size * 0.006))
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
