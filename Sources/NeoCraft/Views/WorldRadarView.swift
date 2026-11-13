import AppKit
import SwiftUI

// MARK: - Deterministic biome field

/// Biome categories the radar can display, with Minecraft-ish colors.
enum RadarBiome: String, CaseIterable, Sendable {
    case ocean
    case beach
    case desert
    case plains
    case forest
    case birchForest
    case darkForest
    case snow
    case iceSpikes
    case badlands
    case cherryGrove
    case deepDark
    case mountains
    case river

    var colorHex: String {
        switch self {
        case .ocean: "3B6FD4"
        case .river: "4A8FE8"
        case .beach: "E8D9A0"
        case .desert: "E0C878"
        case .plains: "7FBF5A"
        case .forest: "4E8F3E"
        case .birchForest: "9CCB6E"
        case .darkForest: "2E5B2A"
        case .snow: "EDF2F7"
        case .iceSpikes: "CFE4F2"
        case .badlands: "C97B4A"
        case .cherryGrove: "F2A7C3"
        case .deepDark: "241F3D"
        case .mountains: "8A8F98"
        }
    }

    var color: Color { Color(hex: colorHex) }

    var displayName: String {
        switch self {
        case .ocean: "Ocean"
        case .river: "River"
        case .beach: "Beach"
        case .desert: "Desert"
        case .plains: "Plains"
        case .forest: "Forest"
        case .birchForest: "Birch Forest"
        case .darkForest: "Dark Forest"
        case .snow: "Snowy Tundra"
        case .iceSpikes: "Ice Spikes"
        case .badlands: "Badlands"
        case .cherryGrove: "Cherry Grove"
        case .deepDark: "Deep Dark"
        case .mountains: "Mountains"
        }
    }
}

/// A point-of-interest marker estimated from the seed.
struct RadarPOI: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case village = "Village"
        case outpost = "Pillager Outpost"
        case trialChamber = "Trial Chamber"
        case ancientCity = "Ancient City"
    }

    var id: Int
    var kind: Kind
    var x: Int
    var z: Int
}

/// Fast deterministic value-noise biome approximation seeded by the
/// world's `RandomSeed`. Not a Mojang-accurate generator — it's a smooth,
/// stable preview that preserves biome *regions* for a given seed.
struct BiomeField: Sendable {
    let seed: Int64

    /// Biome lookup in block coordinates.
    func biome(atX x: Int, z: Int) -> RadarBiome {
        // Large-scale continental noise → elevation; two mid noises →
        // temperature & humidity; small noise → detail.
        let elevation = noise2(x, z, scale: 420, seedOffset: 11)
        let temperature = noise2(x, z, scale: 260, seedOffset: 37)
        let humidity = noise2(x, z, scale: 300, seedOffset: 71)
        let detail = noise2(x, z, scale: 90, seedOffset: 113)

        // Oceans where elevation is lowest.
        if elevation < 0.34 {
            if elevation < 0.24 && humidity > 0.55 { return .deepDark }
            if detail > 0.82 && elevation < 0.38 { return .river }
            return .ocean
        }
        if elevation < 0.385 { return .beach }

        // Temperature bands.
        if temperature < 0.30 {
            return detail > 0.86 ? .iceSpikes : .snow
        }
        if temperature > 0.72 {
            if humidity < 0.34 { return .desert }
            if humidity > 0.62 && elevation > 0.62 { return .badlands }
            return .desert
        }

        // Temperate zone — humidity decides forest density.
        if humidity > 0.72 {
            if detail > 0.78 { return .darkForest }
            if detail > 0.55 { return .forest }
            return .birchForest
        }
        if humidity > 0.55 {
            return detail > 0.7 ? .forest : .plains
        }

        // Rare cherry grove pockets in warm, humid temperate areas.
        if temperature > 0.55 && humidity > 0.6 {
            let cherry = noise2(x, z, scale: 640, seedOffset: 199)
            if cherry > 0.78 { return .cherryGrove }
        }

        if elevation > 0.78 { return .mountains }
        return .plains
    }

    /// Deterministic POIs scattered around the world origin. These are
    /// *estimates* — real structure positions come from the game's own
    /// generation, which this preview can't reproduce.
    func pointsOfInterest(radius: Int = 640, count: Int = 14) -> [RadarPOI] {
        var pois: [RadarPOI] = []
        var attempts = 0
        while pois.count < count && attempts < count * 30 {
            attempts += 1
            let index = attempts
            let base = UInt64(bitPattern: seed)
            let hx = mix(base &+ UInt64(index) &* 0x9E3779B97F4A7C15)
            let hz = mix(base &+ UInt64(index &* 7) &* 0xBF58476D1CE4E5B9)
            let span = UInt64(radius * 2)
            let x = Int(hx % span) - radius
            let z = Int(hz % span) - radius
            let kindRoll = Int(hx % 100)
            let kind: RadarPOI.Kind = switch kindRoll {
            case 0..<55: .village
            case 55..<75: .outpost
            case 75..<92: .trialChamber
            default: .ancientCity
            }
            // Skip POIs that land in the ocean.
            guard biome(atX: x, z: z) != .ocean else { continue }
            pois.append(RadarPOI(id: index, kind: kind, x: x, z: z))
        }
        return pois
    }

    // MARK: - Value noise

    /// 2D value noise in [0,1): integer-lattice hash + smoothstep
    /// interpolation, 3 octaves.
    private func noise2(_ x: Int, _ z: Int, scale: Int, seedOffset: Int64) -> Double {
        let fx = Double(x) / Double(max(scale, 1))
        let fz = Double(z) / Double(max(scale, 1))
        var total = 0.0
        var amplitude = 1.0
        var norm = 0.0
        var freq = 1.0

        for octave in 0..<3 {
            let cx = Int(floor(fx * freq))
            let cz = Int(floor(fz * freq))
            let tx = smooth(fx * freq - Double(cx))
            let tz = smooth(fz * freq - Double(cz))

            let v00 = lattice(cx, cz, octave: octave, seedOffset: seedOffset)
            let v10 = lattice(cx + 1, cz, octave: octave, seedOffset: seedOffset)
            let v01 = lattice(cx, cz + 1, octave: octave, seedOffset: seedOffset)
            let v11 = lattice(cx + 1, cz + 1, octave: octave, seedOffset: seedOffset)

            let top = v00 + (v10 - v00) * tx
            let bottom = v01 + (v11 - v01) * tx
            total += (top + (bottom - top) * tz) * amplitude
            norm += amplitude
            amplitude *= 0.5
            freq *= 2
        }
        return total / norm
    }

    private func lattice(_ ix: Int, _ iz: Int, octave: Int, seedOffset: Int64) -> Double {
        var h = UInt64(bitPattern: seed)
        h = h &+ UInt64(bitPattern: Int64(ix)) &* 0x27D4EB2F165667C5
        h ^= UInt64(bitPattern: Int64(iz)) &* 0x165667B19E3779F9
        h ^= UInt64(bitPattern: seedOffset) &* 0x9E3779B97F4A7C15
        h &+= UInt64(octave) &* 0xD1B54A32D192ED03
        return Double(mix(h) % 10_000) / 10_000.0
    }

    private func smooth(_ t: Double) -> Double {
        t * t * (3 - 2 * t)
    }

    /// SplitMix64-style finalizer.
    private func mix(_ value: UInt64) -> UInt64 {
        var z = value
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Radar map canvas

/// Zoomable, pannable 2D biome map rendered with SwiftUI Canvas.
/// World coordinates are Minecraft block coordinates; the view tracks its
/// own pan/zoom state internally.
struct BiomeRadarMap: View {
    let field: BiomeField
    var spawnX: Int?
    var spawnZ: Int?

    @State private var centerBlockX: Int
    @State private var centerBlockZ: Int
    @State private var blocksPerPoint: CGFloat = 2.2
    @State private var inspected: (x: Int, z: Int)?

    init(field: BiomeField, spawnX: Int? = nil, spawnZ: Int? = nil) {
        self.field = field
        self.spawnX = spawnX
        self.spawnZ = spawnZ
        _centerBlockX = State(initialValue: spawnX ?? 0)
        _centerBlockZ = State(initialValue: spawnZ ?? 0)
    }

    private var pois: [RadarPOI] { field.pointsOfInterest() }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                // Biome cells.
                Canvas { context, canvasSize in
                    drawBiomes(&context, size: canvasSize)
                }

                // POI markers (drawn in a second Canvas so they stay crisp
                // at every zoom level).
                Canvas { context, canvasSize in
                    drawPOIs(&context, size: canvasSize)
                }
                .allowsHitTesting(false)

                // Spawn marker.
                if let sx = spawnX, let sz = spawnZ {
                    let p = screenPoint(x: sx, z: sz, size: size)
                    ZStack {
                        Circle()
                            .stroke(NeoPalette.mint, lineWidth: 2)
                            .frame(width: 22, height: 22)
                        Circle()
                            .fill(NeoPalette.mint)
                            .frame(width: 6, height: 6)
                    }
                    .position(p)
                    .allowsHitTesting(false)
                }

                // Coordinate inspector.
                if let inspected {
                    inspector(for: inspected)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(10)
                }

                // Zoom controls.
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            zoomButton("plus.magnifyingglass") {
                                blocksPerPoint = min(blocksPerPoint * 0.7, 24)
                            }
                            zoomButton("minus.magnifyingglass") {
                                blocksPerPoint = max(blocksPerPoint * 1.4, 0.4)
                            }
                            Button {
                                resetView()
                            } label: {
                                Image(systemName: "scope")
                                    .font(.system(size: 11, weight: .bold))
                                    .frame(width: 26, height: 26)
                                    .background(.regularMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                            .help("Center on spawn")
                        }
                        .padding(10)
                    }
                }
                .allowsHitTesting(true)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                inspected = worldPoint(from: location, size: size)
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let dx = value.translation.width - lastDragX
                        let dy = value.translation.height - lastDragY
                        lastDragX = value.translation.width
                        lastDragY = value.translation.height
                        centerBlockX -= Int((dx / blocksPerPoint).rounded())
                        centerBlockZ += Int((dy / blocksPerPoint).rounded())
                    }
                    .onEnded { _ in
                        lastDragX = 0
                        lastDragY = 0
                    }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        blocksPerPoint = min(max(0.4, blocksPerPoint / value.magnification), 24)
                    }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
        }
    }

    @State private var lastDragX: CGFloat = 0
    @State private var lastDragY: CGFloat = 0

    // MARK: - Drawing

    private func drawBiomes(_ context: inout GraphicsContext, size: CGSize) {
        let cell = max(blocksPerPoint, 0.4)
        // Only draw cells covering the viewport.
        let minX = centerBlockX - Int(size.width / (2 * cell)) - 1
        let maxX = centerBlockX + Int(size.width / (2 * cell)) + 1
        let minZ = centerBlockZ - Int(size.height / (2 * cell)) - 1
        let maxZ = centerBlockZ + Int(size.height / (2 * cell)) + 1

        // Cache biome per row segment is overkill; evaluate per cell.
        for wz in minZ...maxZ {
            for wx in minX...maxX {
                let biome = field.biome(atX: wx, z: wz)
                let rect = CGRect(
                    x: CGFloat(wx - centerBlockX) * cell + size.width / 2 - cell / 2,
                    y: CGFloat(wz - centerBlockZ) * cell + size.height / 2 - cell / 2,
                    width: cell + 0.6,
                    height: cell + 0.6
                )
                context.fill(Path(rect), with: .color(biome.color))
            }
        }
    }

    private func drawPOIs(_ context: inout GraphicsContext, size: CGSize) {
        for poi in pois {
            let p = screenPoint(x: poi.x, z: poi.z, size: size)
            guard p.x > -30, p.x < size.width + 30,
                  p.y > -30, p.y < size.height + 30 else { continue }

            let color: Color = switch poi.kind {
            case .village: NeoPalette.amber
            case .outpost: NeoPalette.danger
            case .trialChamber: NeoPalette.violet
            case .ancientCity: NeoPalette.ink
            }

            var marker = Path()
            marker.addEllipse(in: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8))
            context.fill(marker, with: .color(color))
            context.stroke(marker, with: .color(.white.opacity(0.85)), lineWidth: 1.2)

            // Plain Text only — GraphicsContext.draw requires Text/Image,
            // so the pill backdrop is faked with a dark offset copy.
            let label = Text(poi.kind.rawValue)
                .font(.system(size: 8, weight: .bold, design: .rounded))
            context.draw(
                label.foregroundStyle(.black.opacity(0.7)),
                at: CGPoint(x: p.x + 0.7, y: p.y - 12.7),
                anchor: .center
            )
            context.draw(
                label.foregroundStyle(.white),
                at: CGPoint(x: p.x, y: p.y - 13),
                anchor: .center
            )
        }
    }

    private func inspector(for point: (x: Int, z: Int)) -> some View {
        let biome = field.biome(atX: point.x, z: point.z)
        return HStack(spacing: 10) {
            Circle()
                .fill(biome.color)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.8))

            VStack(alignment: .leading, spacing: 1) {
                Text("\(point.x), \(point.z)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Text(biome.displayName)
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
            }

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("\(point.x), \(point.z)", forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Copy coordinates")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
        }
    }

    private func zoomButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func resetView() {
        centerBlockX = spawnX ?? 0
        centerBlockZ = spawnZ ?? 0
        blocksPerPoint = 2.2
    }

    // MARK: - Coordinate math

    private func screenPoint(x: Int, z: Int, size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(x - centerBlockX) * blocksPerPoint + size.width / 2,
            y: CGFloat(z - centerBlockZ) * blocksPerPoint + size.height / 2
        )
    }

    private func worldPoint(from location: CGPoint, size: CGSize) -> (x: Int, z: Int) {
        (
            x: centerBlockX + Int(((location.x - size.width / 2) / blocksPerPoint).rounded()),
            z: centerBlockZ + Int(((location.y - size.height / 2) / blocksPerPoint).rounded())
        )
    }
}

// MARK: - Radar thumbnail

/// Static, non-interactive biome preview rendered as a world-list
/// thumbnail. Shows a fixed ~1.6k-block window centered on spawn (or the
/// world origin) as chunky pixel cells — a minimap at a glance.
struct RadarThumbnail: View {
    let field: BiomeField
    var spawnX: Int?
    var spawnZ: Int?

    /// Cells per axis — chunky "voxel" pixels, not per-block resolution.
    private let columns = 44
    /// World blocks covered by the whole thumbnail.
    private let span = 1_600

    var body: some View {
        Canvas { context, size in
            let cell = min(size.width, size.height) / CGFloat(columns)
            let originX = size.width / 2 - CGFloat(columns) * cell / 2
            let originY = size.height / 2 - CGFloat(columns) * cell / 2
            let blocksPerCell = Double(span) / Double(columns)
            let centerX = spawnX ?? 0
            let centerZ = spawnZ ?? 0

            for row in 0..<columns {
                for col in 0..<columns {
                    let bx = centerX + Int((Double(col) + 0.5 - Double(columns) / 2) * blocksPerCell)
                    let bz = centerZ + Int((Double(row) + 0.5 - Double(columns) / 2) * blocksPerCell)
                    let rect = CGRect(
                        x: originX + CGFloat(col) * cell,
                        y: originY + CGFloat(row) * cell,
                        width: cell + 0.5,
                        height: cell + 0.5
                    )
                    context.fill(Path(rect), with: .color(field.biome(atX: bx, z: bz).color))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - World radar sheet

/// Sheet shown from the World Manager (and usable standalone for custom
/// seed previews). Shows level.dat metadata plus the interactive radar.
struct WorldRadarView: View {
    @Environment(\.dismiss) private var dismiss

    /// The world being inspected — nil in "custom seed" preview mode.
    var world: WorldInfo?

    @State private var customSeedText = ""
    @State private var customSeed: Int64?
    @State private var previewMode = false

    private var effectiveSeed: Int64? {
        if previewMode {
            return customSeed
        }
        return world?.seed
    }

    private var field: BiomeField? {
        guard let seed = effectiveSeed else { return nil }
        return BiomeField(seed: seed)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            NeoDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metadataCard
                    seedPreviewCard

                    if let field {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(
                                title: "Biome Radar",
                                subtitle: "Estimated from the world seed · drag to pan, pinch to zoom"
                            )
                            BiomeRadarMap(
                                field: field,
                                spawnX: previewMode ? nil : world?.spawnX,
                                spawnZ: previewMode ? nil : world?.spawnZ
                            )
                            .frame(height: 380)

                            poiLegend
                        }
                    } else {
                        EmptyStateView(
                            symbol: "map",
                            title: previewMode ? "Enter a seed" : "No seed data",
                            message: previewMode
                                ? "Type any number to preview the approximate biome layout for a custom-seed world."
                                : "This world's level.dat doesn't expose a seed (very old format?)."
                        )
                        .frame(height: 200)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)

            NeoDivider()
            footer
        }
        .frame(width: 760, height: 720)
        .background(.regularMaterial)
        .onAppear {
            if world == nil { previewMode = true }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [NeoPalette.sky, NeoPalette.violet],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "map.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(previewMode ? "Seed Preview" : (world?.levelName ?? world?.name ?? "World Radar"))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(previewMode ? "Custom-seed world preview" : "World seed & biome radar")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                previewMode.toggle()
                if !previewMode, customSeedText.isEmpty {
                    customSeedText = world?.seed.map(String.init) ?? ""
                }
            } label: {
                Text(previewMode ? "Show World" : "Preview Seed")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            }
            .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            .disabled(world == nil)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
    }

    // MARK: Metadata

    private var metadataCard: some View {
        NeoCard {
            if let world, let meta = world.metadata {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 10)],
                    spacing: 10
                ) {
                    InfoRow(label: "Seed", value: meta.seed.map { String($0) } ?? "—", symbol: "number")
                    InfoRow(label: "Spawn", value: meta.hasCoordinates ? "\(meta.spawnX!), \(meta.spawnY!), \(meta.spawnZ!)" : "—", symbol: "scope")
                    InfoRow(label: "Game Mode", value: meta.gameType ?? "—", symbol: "gamecontroller")
                    InfoRow(label: "World Size", value: Formatters.bytes(world.sizeBytes), symbol: "internaldrive")
                }
            } else if previewMode {
                HStack {
                    Text("Seed")
                        .font(.neoCaption)
                        .foregroundStyle(.secondary)
                    TextField("e.g. 8675309", text: $customSeedText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .onChange(of: customSeedText) { _, new in
                            customSeed = Int64(new.trimmingCharacters(in: .whitespaces))
                        }
                    if let seed = customSeed {
                        Text("→ \(seed)")
                            .font(.neoCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No metadata available for this world.")
                    .font(.neoCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var seedPreviewCard: some View {
        Group {
            if previewMode, let seed = customSeed, world != nil {
                NeoCard {
                    HStack(spacing: 8) {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(NeoPalette.amber)
                        Text("Previewing seed \(seed). When you create the world in-game with this seed, the real layout will match these biome regions.")
                            .font(.neoCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var poiLegend: some View {
        HStack(spacing: 14) {
            legendDot(NeoPalette.amber, "Village")
            legendDot(NeoPalette.danger, "Outpost")
            legendDot(NeoPalette.violet, "Trial Chamber")
            legendDot(NeoPalette.ink, "Ancient City")
            Spacer()
            Text("POIs are estimates — tap the map for exact X/Z")
                .font(.neoCaption)
                .foregroundStyle(.secondary)
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.neoCaption).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if let world {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(world.name)", forType: .string)
                } label: {
                    Label("Copy World Name", systemImage: "doc.on.doc")
                }
                .buttonStyle(NeoButtonStyle(kind: .ghost, compact: true))
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(NeoButtonStyle(kind: .secondary))
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
    }
}
