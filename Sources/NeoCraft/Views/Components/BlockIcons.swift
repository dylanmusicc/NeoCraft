import AppKit
import SwiftUI

// MARK: - Minecraft block icon library

/// Every block that can illustrate an instance. Raw values are the real
/// Minecraft block ids so `GameInstance.iconBlock` stays human-readable.
enum MinecraftBlockIcon: String, CaseIterable, Sendable {
    // Stone & earth
    case stone, cobblestone, mossy_cobblestone, tuff, andesite, diorite, granite
    case deepslate, cobbled_deepslate, dirt, coarse_dirt, rooted_dirt
    case grass_block, podzol, mycelium, moss_block
    case mud, packed_mud, mud_bricks, clay
    case sandstone, cut_sandstone, smooth_sandstone, red_sandstone, red_sandstone_slab

    // Ores
    case coal_ore, iron_ore, gold_ore, redstone_ore, lapis_ore, diamond_ore, emerald_ore, copper_ore
    case deepslate_coal_ore, deepslate_iron_ore, deepslate_gold_ore, deepslate_redstone_ore
    case deepslate_lapis_ore, deepslate_diamond_ore, deepslate_emerald_ore, deepslate_copper_ore

    // Minerals & storage blocks
    case iron_block, gold_block, diamond_block, emerald_block, lapis_block, redstone_block
    case netherite_block, coal_block, bone_block, raw_iron_block, raw_gold_block, raw_copper_block
    case copper_block, exposed_copper, weathered_copper, oxidized_copper, cut_copper
    case amethyst_block, budding_amethyst, amethyst_cluster, calcite, dripstone_block
    case glowstone, sea_lantern, shroomlight, magma_block
    case honey_block, slime_block, honeycomb_block, target, beacon, lodestone
    case respawn_anchor, dragon_egg, obsidian, crying_obsidian, bedrock

    // Logs, stems, planks & leaves
    case oak_log, spruce_log, birch_log, jungle_log, acacia_log, dark_oak_log
    case mangrove_log, cherry_log, pale_oak_log, crimson_stem, warped_stem
    case oak_planks, spruce_planks, birch_planks, jungle_planks, acacia_planks
    case dark_oak_planks, mangrove_planks, cherry_planks, pale_oak_planks
    case bamboo_block, bamboo_mosaic
    case oak_leaves, spruce_leaves, birch_leaves, jungle_leaves, acacia_leaves
    case dark_oak_leaves, cherry_leaves, mangrove_leaves

    // Functional blocks
    case crafting_table, furnace, blast_furnace, smoker, enchanting_table
    case note_block, jukebox, chest, barrel, bookshelf, observer, dropper, dispenser
    case hopper, loom, smithing_table, stonecutter, cartography_table, fletching_table
    case composter, spawner, command_block, structure_block, end_portal_frame
    case bee_nest, hay_block, pumpkin, jack_o_lantern, melon, tnt

    // Nether & end
    case netherrack, nether_bricks, quartz_block, polished_blackstone, basalt
    case blackstone, end_stone, purpur_block, nylium_crimson, nylium_warped

    // Ice & snow
    case snow_block, ice, packed_ice, blue_ice

    // Wool (16)
    case white_wool, orange_wool, magenta_wool, light_blue_wool, yellow_wool, lime_wool
    case pink_wool, gray_wool, light_gray_wool, cyan_wool, purple_wool, blue_wool
    case brown_wool, green_wool, red_wool, black_wool

    // Concrete (16)
    case white_concrete, orange_concrete, magenta_concrete, light_blue_concrete
    case yellow_concrete, lime_concrete, pink_concrete, gray_concrete
    case light_gray_concrete, cyan_concrete, purple_concrete, blue_concrete
    case brown_concrete, green_concrete, red_concrete, black_concrete

    // Terracotta (16)
    case white_terracotta, orange_terracotta, magenta_terracotta, light_blue_terracotta
    case yellow_terracotta, lime_terracotta, pink_terracotta, gray_terracotta
    case light_gray_terracotta, cyan_terracotta, purple_terracotta, blue_terracotta
    case brown_terracotta, green_terracotta, red_terracotta, black_terracotta

    // Glass
    case glass, tinted_glass

    // Prismarine family
    case prismarine, prismarine_bricks, dark_prismarine

    var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

// MARK: - Pixel grid

/// A mutable 16×16 pixel canvas for block faces.
private struct IconGrid {
    var pixels: [Color]

    init(base: Color) {
        pixels = [Color](repeating: base, count: 256)
    }

    subscript(x: Int, y: Int) -> Color {
        get { pixels[y * 16 + x] }
        set { pixels[y * 16 + x] = newValue }
    }

    mutating func px(_ x: Int, _ y: Int, _ color: Color) {
        guard (0..<16).contains(x), (0..<16).contains(y) else { return }
        self[x, y] = color
    }

    mutating func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: Color) {
        for y in max(0, y0)...min(15, y1) {
            for x in max(0, x0)...min(15, x1) {
                px(x, y, color)
            }
        }
    }

    /// Dark 1-px frame — the bevel Minecraft block icons get for free.
    mutating func edgeBorder(factor: Double = 0.62) {
        let edge = Color.white.opacity(0)
        _ = edge
        for i in 0..<16 {
            shadePixel(x: i, y: 0, factor: factor)
            shadePixel(x: i, y: 15, factor: factor)
            shadePixel(x: 0, y: i, factor: factor)
            shadePixel(x: 15, y: i, factor: factor)
        }
    }

    private mutating func shadePixel(x: Int, y: Int, factor: Double) {
        guard let rgb = pixels[y * 16 + x].rgb else { return }
        pixels[y * 16 + x] = Color(
            .sRGB,
            red: min(1, rgb.red * factor),
            green: min(1, rgb.green * factor),
            blue: min(1, rgb.blue * factor),
            opacity: rgb.alpha
        )
    }

    /// Deterministic per-pixel brightness jitter so flat colors get a
    /// hand-textured Minecraft feel.
    mutating func noise(_ amount: Double = 0.07, seed: Int = 0) {
        for y in 0..<16 {
            for x in 0..<16 {
                let h = Self.hash(x, y, seed)
                let factor = 1.0 + (h - 0.5) * 2.0 * amount
                shadePixel(x: x, y: y, factor: factor)
            }
        }
    }

    /// Sprinkles `count` clusters of `size`×`size` pixels in `color`.
    mutating func speckle(_ color: Color, count: Int, size: Int = 2, seed: Int) {
        for i in 0..<count {
            let cx = Int(Self.hash(i, seed &* 7 &+ 3, seed) * 15)
            let cy = Int(Self.hash(i &* 11 &+ 5, seed &* 13 &+ 1, seed &+ 7) * 15)
            let jitter = Int(Self.hash(i &* 3, seed &* 5, seed &+ 11) * 2) - 1
            for dy in 0..<size {
                for dx in 0..<size {
                    px(cx + dx - size / 2 + jitter, cy + dy - size / 2, color)
                }
            }
        }
    }

    /// Ore-style mineral clusters: 2×2 blobs with a bright core pixel.
    mutating func ore(_ color: Color, count: Int = 6, seed: Int) {
        speckle(color, count: count, size: 2, seed: seed)
        speckle(color.opacity(0.0), count: 0, size: 1, seed: 0) // no-op keeps symmetry obvious
        for i in 0..<count {
            let cx = Int(Self.hash(i, seed &* 7 &+ 3, seed) * 15)
            let cy = Int(Self.hash(i &* 11 &+ 5, seed &* 13 &+ 1, seed &+ 7) * 15)
            px(cx, cy, .white.opacity(0.35))
        }
    }

    /// Horizontal plank seams every `period` rows plus staggered joints.
    mutating func plankLines(_ color: Color, period: Int = 4) {
        guard period > 0 else { return }
        for y in stride(from: period - 1, to: 16, by: period) {
            for x in 0..<16 { px(x, y, color) }
        }
        // Vertical butt joints, offset per row band.
        for band in 0..<4 {
            let y0 = band * period
            guard y0 < 16 else { break }
            let jointX = (band * 5 + 3) % 14 + 1
            for y in y0..<min(16, y0 + period) {
                px(jointX, y, color)
                px(jointX + 1, y, color)
            }
        }
        // Nail heads.
        for band in 0..<4 {
            let y = band * period + 1
            guard y < 16 else { break }
            px(2, y, color.opacity(0.8))
            px(13, y, color.opacity(0.8))
        }
    }

    /// Vertical bark stripes for log side textures.
    mutating func logStripes(_ dark: Color, _ light: Color) {
        for x in 0..<16 {
            let stripe = (x / 4) % 2 == 0 ? light : dark
            for y in 0..<16 { px(x, y, stripe) }
        }
        // Occasional knot.
        for (kx, ky) in [(5, 4), (11, 10)] {
            px(kx, ky, dark)
            px(kx + 1, ky, dark)
            px(kx, ky + 1, dark)
        }
    }

    /// Leaf noise: large soft darker/lighter blotches.
    mutating func leafBlotch(_ dark: Color, _ light: Color, seed: Int) {
        for i in 0..<14 {
            let cx = Int(Self.hash(i, 17, seed) * 15)
            let cy = Int(Self.hash(i &* 7, 29, seed &+ 3) * 15)
            let color = i % 2 == 0 ? dark : light
            for dy in -1...1 {
                for dx in -1...1 where abs(dx) + abs(dy) <= 1 {
                    px(cx + dx, cy + dy, color)
                }
            }
        }
    }

    /// Glass: translucent fill, bright rim and diagonal shine streaks.
    mutating func glassStyle(_ tint: Color, opacity: Double = 0.16) {
        for y in 0..<16 {
            for x in 0..<16 {
                pixels[y * 16 + x] = tint.opacity(opacity)
            }
        }
        for i in 1..<15 {
            px(i, 0, tint.opacity(0.75))
            px(i, 15, tint.opacity(0.75))
            px(0, i, tint.opacity(0.75))
            px(15, i, tint.opacity(0.75))
        }
        for i in 0..<11 {
            px(3 + i, 11 - i, .white.opacity(0.55))
            px(4 + i, 11 - i, .white.opacity(0.30))
        }
    }

    /// Brick pattern: offset rows of bricks with mortar lines.
    mutating func brickPattern(_ mortar: Color) {
        for y in stride(from: 3, to: 16, by: 4) {
            for x in 0..<16 { px(x, y, mortar) }
        }
        for row in 0..<4 {
            let y0 = row * 4
            let offset = row % 2 == 0 ? 0 : 4
            for x in stride(from: offset, to: 16, by: 8) {
                for y in y0..<min(16, y0 + 3) { px(x, y, mortar) }
            }
        }
    }

    /// Cobblestone: rounded stone cells separated by dark mortar.
    mutating func cobble(_ mortar: Color, seed: Int) {
        for i in 0..<9 {
            let cx = 2 + Int(Self.hash(i, 3, seed) * 12)
            let cy = 2 + Int(Self.hash(i &* 5, 7, seed &+ 1) * 12)
            let r = 2 + Int(Self.hash(i, 11, seed &+ 4) * 2)
            for dy in -r...r {
                for dx in -r...r where dx * dx + dy * dy <= r * r + 1 {
                    px(cx + dx, cy + dy, Color.white.opacity(0.10))
                }
            }
        }
        noise(0.05, seed: seed)
        // Re-darken mortar afterwards so cells read as raised stones.
        for y in 0..<16 {
            for x in 0..<16 where Self.hash(x, y, seed &+ 9) < 0.16 {
                shadePixel(x: x, y: y, factor: 0.55)
            }
        }
        _ = mortar
    }

    static func hash(_ x: Int, _ y: Int, _ seed: Int) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 144_269_504_088_896_340))
        h = (h ^ (h >> 13)) &* 1_274_126_177
        h ^= h >> 16
        return Double(h % 10_000) / 10_000
    }
}

private extension Color {
    var rgb: (red: Double, green: Double, blue: Double, alpha: Double)? {
        guard let converted = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return (converted.redComponent, converted.greenComponent, converted.blueComponent, converted.alphaComponent)
    }
}

// MARK: - Renderer

/// Procedurally draws each block face at 16×16 and caches the result.
/// Main-actor only: rasterization uses AppKit drawing primitives.
@MainActor
enum BlockIconRenderer {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for icon: MinecraftBlockIcon, scale: CGFloat = 1) -> NSImage {
        let key = "\(icon.rawValue)@\(Int(scale * 100))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = render(icon)
        cache.setObject(image, forKey: key)
        return image
    }

    private static func render(_ icon: MinecraftBlockIcon) -> NSImage {
        var grid = IconGrid(base: baseColor(for: icon))
        applyFeatures(icon, to: &grid)
        return rasterize(grid)
    }

    private static func rasterize(_ grid: IconGrid) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSGraphicsContext.current?.cgContext.clear(CGRect(x: 0, y: 0, width: 16, height: 16))
        for y in 0..<16 {
            for x in 0..<16 {
                let color = grid[x, y]
                NSGraphicsContext.current?.cgContext.setFillColor(NSColor(color).cgColor)
                NSRect(x: x, y: 15 - y, width: 1, height: 1).fill()
            }
        }
        image.unlockFocus()
        return image
    }

    // MARK: Base colors

    private static func baseColor(for icon: MinecraftBlockIcon) -> Color {
        switch icon {
        // Stone & earth
        case .stone: Color(hex: "7D7D7D")
        case .cobblestone: Color(hex: "7A7A7A")
        case .mossy_cobblestone: Color(hex: "6E7A5E")
        case .tuff: Color(hex: "6E6E6E")
        case .andesite: Color(hex: "828282")
        case .diorite: Color(hex: "B0B0B0")
        case .granite: Color(hex: "8C5E52")
        case .deepslate: Color(hex: "4A4A52")
        case .cobbled_deepslate: Color(hex: "3E3E46")
        case .dirt: Color(hex: "8A5F3C")
        case .coarse_dirt: Color(hex: "7A5233")
        case .rooted_dirt: Color(hex: "6B4E33")
        case .grass_block: Color(hex: "6FA83F")
        case .podzol: Color(hex: "7A5A3A")
        case .mycelium: Color(hex: "5E4E66")
        case .moss_block: Color(hex: "4E7A35")
        case .mud: Color(hex: "5A4632")
        case .packed_mud: Color(hex: "6B5138")
        case .mud_bricks: Color(hex: "7A5C40")
        case .clay: Color(hex: "A4A8B0")
        case .sandstone: Color(hex: "DBD3A0")
        case .cut_sandstone: Color(hex: "D8CF9C")
        case .smooth_sandstone: Color(hex: "DCD5A4")
        case .red_sandstone: Color(hex: "C98B5E")
        case .red_sandstone_slab: Color(hex: "C98B5E")

        // Ores — stone/deepslate host colors.
        case .coal_ore: Color(hex: "7D7D7D")
        case .iron_ore: Color(hex: "7D7D7D")
        case .gold_ore: Color(hex: "7D7D7D")
        case .redstone_ore: Color(hex: "7D7D7D")
        case .lapis_ore: Color(hex: "7D7D7D")
        case .diamond_ore: Color(hex: "7D7D7D")
        case .emerald_ore: Color(hex: "7D7D7D")
        case .copper_ore: Color(hex: "7D7D7D")
        case .deepslate_coal_ore: Color(hex: "4A4A52")
        case .deepslate_iron_ore: Color(hex: "4A4A52")
        case .deepslate_gold_ore: Color(hex: "4A4A52")
        case .deepslate_redstone_ore: Color(hex: "4A4A52")
        case .deepslate_lapis_ore: Color(hex: "4A4A52")
        case .deepslate_diamond_ore: Color(hex: "4A4A52")
        case .deepslate_emerald_ore: Color(hex: "4A4A52")
        case .deepslate_copper_ore: Color(hex: "4A4A52")

        // Minerals & storage
        case .iron_block: Color(hex: "D8D8D8")
        case .gold_block: Color(hex: "FCEE4B")
        case .diamond_block: Color(hex: "5DECF5")
        case .emerald_block: Color(hex: "17E85F")
        case .lapis_block: Color(hex: "345EC3")
        case .redstone_block: Color(hex: "C00000")
        case .netherite_block: Color(hex: "403A42")
        case .coal_block: Color(hex: "181818")
        case .bone_block: Color(hex: "D8D2C4")
        case .raw_iron_block: Color(hex: "C6A58E")
        case .raw_gold_block: Color(hex: "D8BF6E")
        case .raw_copper_block: Color(hex: "B87352")
        case .copper_block: Color(hex: "B87333")
        case .exposed_copper: Color(hex: "9E8148")
        case .weathered_copper: Color(hex: "6E8C7B")
        case .oxidized_copper: Color(hex: "4FA3A5")
        case .cut_copper: Color(hex: "C98A5B")
        case .amethyst_block: Color(hex: "9C68CF")
        case .budding_amethyst: Color(hex: "7C4FA8")
        case .amethyst_cluster: Color(hex: "8A5CC0")
        case .calcite: Color(hex: "E8E4DA")
        case .dripstone_block: Color(hex: "8A7E72")
        case .glowstone: Color(hex: "FBE77A")
        case .sea_lantern: Color(hex: "BFE8E2")
        case .shroomlight: Color(hex: "D8A0B0")
        case .magma_block: Color(hex: "C23A12")
        case .honey_block: Color(hex: "E8A93C")
        case .slime_block: Color(hex: "8FD45A")
        case .honeycomb_block: Color(hex: "D8B060")
        case .target: Color(hex: "C33A2A")
        case .beacon: Color(hex: "9FB8D8")
        case .lodestone: Color(hex: "4E5560")
        case .respawn_anchor: Color(hex: "3A2A4E")
        case .dragon_egg: Color(hex: "14141C")
        case .obsidian: Color(hex: "1C1426")
        case .crying_obsidian: Color(hex: "2A1A3E")
        case .bedrock: Color(hex: "3E3E42")

        // Logs & stems
        case .oak_log: Color(hex: "6B543A")
        case .spruce_log: Color(hex: "4E3826")
        case .birch_log: Color(hex: "D8D8D0")
        case .jungle_log: Color(hex: "8A6E4E")
        case .acacia_log: Color(hex: "5E4028")
        case .dark_oak_log: Color(hex: "3E2C1E")
        case .mangrove_log: Color(hex: "6E3E2A")
        case .cherry_log: Color(hex: "6E4E58")
        case .pale_oak_log: Color(hex: "C9BCA8")
        case .crimson_stem: Color(hex: "7A2E3A")
        case .warped_stem: Color(hex: "2E6E6E")

        // Planks & bamboo
        case .oak_planks: Color(hex: "A88A5E")
        case .spruce_planks: Color(hex: "6E5638")
        case .birch_planks: Color(hex: "D8CFAE")
        case .jungle_planks: Color(hex: "9E7E42")
        case .acacia_planks: Color(hex: "8A5A2E")
        case .dark_oak_planks: Color(hex: "4A3220")
        case .mangrove_planks: Color(hex: "6E4E3E")
        case .cherry_planks: Color(hex: "C98A72")
        case .pale_oak_planks: Color(hex: "C9BCA0")
        case .bamboo_block: Color(hex: "B8A870")
        case .bamboo_mosaic: Color(hex: "C4B478")

        // Leaves
        case .oak_leaves: Color(hex: "3E7A24")
        case .spruce_leaves: Color(hex: "2E5220")
        case .birch_leaves: Color(hex: "6FA83F")
        case .jungle_leaves: Color(hex: "2E7A1E")
        case .acacia_leaves: Color(hex: "7AA02E")
        case .dark_oak_leaves: Color(hex: "2E4422")
        case .cherry_leaves: Color(hex: "E88AA8")
        case .mangrove_leaves: Color(hex: "4E7A3E")

        // Functional
        case .crafting_table: Color(hex: "A88A5E")
        case .furnace: Color(hex: "6E6E6E")
        case .blast_furnace: Color(hex: "5E5E62")
        case .smoker: Color(hex: "6E5638")
        case .enchanting_table: Color(hex: "3E4E8E")
        case .note_block: Color(hex: "9E7E42")
        case .jukebox: Color(hex: "8A5A2E")
        case .chest: Color(hex: "A88A5E")
        case .barrel: Color(hex: "8E8E8E")
        case .bookshelf: Color(hex: "8A5E38")
        case .observer: Color(hex: "8E8E8E")
        case .dropper: Color(hex: "8E8E8E")
        case .dispenser: Color(hex: "8E8E8E")
        case .hopper: Color(hex: "8E8E8E")
        case .loom: Color(hex: "A88A5E")
        case .smithing_table: Color(hex: "8E8E8E")
        case .stonecutter: Color(hex: "8E8E8E")
        case .cartography_table: Color(hex: "A88A5E")
        case .fletching_table: Color(hex: "A88A5E")
        case .composter: Color(hex: "6E5638")
        case .spawner: Color(hex: "1E2024")
        case .command_block: Color(hex: "7D7D7D")
        case .structure_block: Color(hex: "8E8E8E")
        case .end_portal_frame: Color(hex: "4E7A4E")
        case .bee_nest: Color(hex: "D8A838")
        case .hay_block: Color(hex: "D8B84E")
        case .pumpkin: Color(hex: "C8761E")
        case .jack_o_lantern: Color(hex: "D8901E")
        case .melon: Color(hex: "5E9E3A")
        case .tnt: Color(hex: "C23A1E")

        // Nether & end
        case .netherrack: Color(hex: "6E2A24")
        case .nether_bricks: Color(hex: "2E1E20")
        case .quartz_block: Color(hex: "E8E4DA")
        case .polished_blackstone: Color(hex: "26262C")
        case .basalt: Color(hex: "3E3E42")
        case .blackstone: Color(hex: "2A2A30")
        case .end_stone: Color(hex: "E8DCA8")
        case .purpur_block: Color(hex: "8E6EC0")
        case .nylium_crimson: Color(hex: "5E2030")
        case .nylium_warped: Color(hex: "1E4E4E")

        // Ice & snow
        case .snow_block: Color(hex: "F2F7F7")
        case .ice: Color(hex: "8EC8E8")
        case .packed_ice: Color(hex: "6AA8D8")
        case .blue_ice: Color(hex: "4E8ED8")

        // Glass
        case .glass: Color(hex: "C8E8F0")
        case .tinted_glass: Color(hex: "2E3A4E")

        // Prismarine
        case .prismarine: Color(hex: "5EA8A0")
        case .prismarine_bricks: Color(hex: "4E8E88")
        case .dark_prismarine: Color(hex: "3E6E68")

        // Color families — resolved by name below.
        default:
            familyColor(for: icon)
        }
    }

    /// Wool / concrete / terracotta share the 16-color palette; wool is
    /// matte, concrete saturated, terracotta earthy.
    private static func familyColor(for icon: MinecraftBlockIcon) -> Color {
        let raw = icon.rawValue
        let isWool = raw.hasSuffix("_wool")
        let isConcrete = raw.hasSuffix("_concrete")
        let base = isWool ? raw.dropLast(5) : (isConcrete ? raw.dropLast(9) : raw.dropLast(11))
        let hex: String
        switch base {
        case "white": hex = isWool ? "F0F0F0" : (isConcrete ? "F9FFFE" : "CFC6B8")
        case "orange": hex = isWool ? "E8A33D" : (isConcrete ? "F9801D" : "A85A28")
        case "magenta": hex = isWool ? "C85A9E" : (isConcrete ? "C74EBD" : "8E4A82")
        case "light_blue": hex = isWool ? "5AB8D8" : (isConcrete ? "3AB3DA" : "5A88A8")
        case "yellow": hex = isWool ? "EED83D" : (isConcrete ? "FED83D" : "B8A03E")
        case "lime": hex = isWool ? "8ED83D" : (isConcrete ? "80C71F" : "6E9E2E")
        case "pink": hex = isWool ? "F0A0B8" : (isConcrete ? "F38BAA" : "B87E8E")
        case "gray": hex = isWool ? "5E5E5E" : (isConcrete ? "474F52" : "5E5E5E")
        case "light_gray": hex = isWool ? "B8B8B8" : (isConcrete ? "9D9D97" : "9A9A92")
        case "cyan": hex = isWool ? "1AA8A0" : (isConcrete ? "169C9C" : "3E8E8E")
        case "purple": hex = isWool ? "8E4EC0" : (isConcrete ? "8932B8" : "6E4490")
        case "blue": hex = isWool ? "3E4EA8" : (isConcrete ? "3C44AA" : "4E5AA8")
        case "brown": hex = isWool ? "8A5A32" : (isConcrete ? "835432" : "6E4A2E")
        case "green": hex = isWool ? "5E8E1E" : (isConcrete ? "5E7C16" : "4E6E2E")
        case "red": hex = isWool ? "B03030" : (isConcrete ? "B02E26" : "8E2E26")
        case "black": hex = isWool ? "2A2A2A" : (isConcrete ? "1D1D21" : "2A2A2E")
        default: hex = "888888"
        }
        return Color(hex: hex)
    }

    // MARK: Features

    private static func applyFeatures(_ icon: MinecraftBlockIcon, to grid: inout IconGrid) {
        switch icon {
        // --- Plain noisy fills ---
        case .stone, .tuff, .andesite, .diorite, .granite, .clay, .packed_mud:
            grid.noise(0.06, seed: 1)
        case .cobblestone:
            grid.cobble(Color.black, seed: 5)
        case .mossy_cobblestone:
            grid.cobble(Color.black, seed: 8)
            grid.speckle(Color(hex: "4E7A35"), count: 8, size: 2, seed: 21)
        case .deepslate, .cobbled_deepslate:
            grid.noise(0.09, seed: 2)
            grid.speckle(Color.black.opacity(0.35), count: 10, size: 2, seed: 4)
        case .dirt, .rooted_dirt:
            grid.noise(0.08, seed: 3)
        case .coarse_dirt:
            grid.noise(0.10, seed: 6)
            grid.speckle(Color(hex: "5E4028"), count: 6, size: 2, seed: 9)
        case .grass_block:
            // Dirt body with a grass top band and drips.
            grid.rect(0, 0, 15, 4, Color(hex: "6FA83F"))
            grid.rect(0, 4, 15, 5, Color(hex: "5E8E35"))
            grid.noise(0.07, seed: 7)
            for x in stride(from: 1, to: 16, by: 3) {
                grid.px(x, 6, Color(hex: "6FA83F"))
                grid.px(x + 1, 7, Color(hex: "5E8E35"))
            }
        case .podzol:
            grid.rect(0, 0, 15, 4, Color(hex: "6FA83F"))
            grid.noise(0.08, seed: 10)
        case .mycelium:
            grid.rect(0, 0, 15, 4, Color(hex: "8A7A9E"))
            grid.noise(0.08, seed: 11)
        case .moss_block:
            grid.noise(0.08, seed: 12)
            grid.speckle(Color(hex: "3E6428"), count: 8, size: 2, seed: 13)
        case .mud:
            grid.noise(0.06, seed: 14)
            grid.speckle(Color(hex: "3E2E20"), count: 6, size: 2, seed: 15)
        case .mud_bricks:
            grid.brickPattern(Color(hex: "4E3A28"))
        case .sandstone, .cut_sandstone, .smooth_sandstone:
            grid.noise(0.04, seed: 16)
            // Sandstone strata lines.
            for y in [5, 10] {
                for x in 0..<16 { grid.px(x, y, Color(hex: "C4B888")) }
            }
        case .red_sandstone, .red_sandstone_slab:
            grid.noise(0.04, seed: 17)
            for y in [5, 10] {
                for x in 0..<16 { grid.px(x, y, Color(hex: "A86E44")) }
            }

        // --- Ores ---
        case .coal_ore: oreStyle(&grid, Color(hex: "2A2A2A"), seed: 30)
        case .iron_ore: oreStyle(&grid, Color(hex: "D8AF93"), seed: 31)
        case .gold_ore: oreStyle(&grid, Color(hex: "FCEE4B"), seed: 32)
        case .redstone_ore: oreStyle(&grid, Color(hex: "E02828"), seed: 33)
        case .lapis_ore: oreStyle(&grid, Color(hex: "345EC3"), seed: 34)
        case .diamond_ore: oreStyle(&grid, Color(hex: "5DECF5"), seed: 35)
        case .emerald_ore: oreStyle(&grid, Color(hex: "17E85F"), seed: 36)
        case .copper_ore: oreStyle(&grid, Color(hex: "E08A5B"), seed: 37)
        case .deepslate_coal_ore: oreStyle(&grid, Color(hex: "1A1A1A"), seed: 38)
        case .deepslate_iron_ore: oreStyle(&grid, Color(hex: "C89A80"), seed: 39)
        case .deepslate_gold_ore: oreStyle(&grid, Color(hex: "E8D84B"), seed: 40)
        case .deepslate_redstone_ore: oreStyle(&grid, Color(hex: "C81E1E"), seed: 41)
        case .deepslate_lapis_ore: oreStyle(&grid, Color(hex: "2A4EA8"), seed: 42)
        case .deepslate_diamond_ore: oreStyle(&grid, Color(hex: "4ED8E8"), seed: 43)
        case .deepslate_emerald_ore: oreStyle(&grid, Color(hex: "12C856"), seed: 44)
        case .deepslate_copper_ore: oreStyle(&grid, Color(hex: "D07A4E"), seed: 45)

        // --- Minerals & storage blocks ---
        case .iron_block, .raw_iron_block, .gold_block, .raw_gold_block,
             .diamond_block, .emerald_block, .lapis_block, .redstone_block,
             .netherite_block, .coal_block, .bone_block, .copper_block,
             .exposed_copper, .weathered_copper, .oxidized_copper, .cut_copper,
             .raw_copper_block:
            metalBlock(&grid)
        case .amethyst_block:
            grid.noise(0.05, seed: 50)
            grid.speckle(Color(hex: "B88AE0"), count: 6, size: 2, seed: 51)
        case .budding_amethyst:
            grid.noise(0.06, seed: 52)
            grid.speckle(Color(hex: "C89AE8"), count: 7, size: 2, seed: 53)
        case .amethyst_cluster:
            // Dark rock base with shard spikes.
            grid.rect(0, 0, 15, 15, Color(hex: "4E3E66"))
            grid.noise(0.08, seed: 54)
            for (sx, sy, s) in [(4, 9, 3), (8, 6, 4), (12, 10, 2)] {
                for i in 0..<s {
                    grid.px(sx, sy - i, Color(hex: "B070E8"))
                    grid.px(sx - 1, sy - i + 1, Color(hex: "8E4EC0"))
                    grid.px(sx + 1, sy - i + 1, Color(hex: "8E4EC0"))
                }
            }
        case .calcite:
            grid.noise(0.04, seed: 55)
            grid.speckle(Color(hex: "D8D4C8"), count: 5, size: 2, seed: 56)
        case .dripstone_block:
            grid.noise(0.07, seed: 57)
            grid.speckle(Color(hex: "6E6258"), count: 6, size: 2, seed: 58)
        case .glowstone:
            glowCluster(&grid, seed: 60)
        case .sea_lantern:
            seaLantern(&grid)
        case .shroomlight:
            grid.noise(0.06, seed: 62)
            grid.speckle(Color(hex: "C88AB0"), count: 6, size: 2, seed: 63)
        case .magma_block:
            grid.noise(0.08, seed: 64)
            grid.speckle(Color(hex: "E8A03C"), count: 7, size: 2, seed: 65)
            grid.speckle(Color(hex: "3E1E0E"), count: 5, size: 2, seed: 66)
        case .honey_block:
            grid.noise(0.05, seed: 67)
            // Hex-ish cell seams.
            for y in stride(from: 3, to: 16, by: 5) {
                for x in 0..<16 { grid.px(x, y, Color(hex: "C88E2A")) }
            }
            for y in stride(from: 1, to: 16, by: 5) {
                for x in stride(from: (y / 5) % 2 == 0 ? 4 : 0, to: 16, by: 8) {
                    for dy in 0..<3 { grid.px(x, y + dy, Color(hex: "C88E2A")) }
                }
            }
        case .slime_block:
            grid.noise(0.05, seed: 68)
            grid.speckle(Color(hex: "5E9E3A"), count: 8, size: 2, seed: 69)
        case .honeycomb_block:
            grid.noise(0.04, seed: 70)
            for y in stride(from: 2, to: 16, by: 4) {
                for x in stride(from: (y / 4) % 2 == 0 ? 2 : 0, to: 16, by: 4) {
                    grid.px(x, y, Color(hex: "B08A44"))
                    grid.px(x + 1, y, Color(hex: "B08A44"))
                    grid.px(x, y + 1, Color(hex: "B08A44"))
                }
            }
        case .target:
            targetFace(&grid)
        case .beacon:
            beaconFace(&grid)
        case .lodestone:
            grid.noise(0.07, seed: 72)
            grid.rect(5, 5, 10, 10, Color(hex: "6E7684"))
            grid.rect(6, 6, 9, 9, Color(hex: "3E9E8E"))
        case .respawn_anchor:
            grid.noise(0.06, seed: 73)
            grid.rect(4, 4, 11, 11, Color(hex: "6E4E9E"))
            grid.rect(6, 6, 9, 9, Color(hex: "B04ED8"))
            grid.px(7, 7, Color(hex: "E8C8FF"))
            grid.px(8, 7, Color(hex: "E8C8FF"))
        case .dragon_egg:
            grid.noise(0.12, seed: 74)
            grid.speckle(Color(hex: "2A2A38"), count: 8, size: 1, seed: 75)
        case .obsidian:
            grid.noise(0.08, seed: 76)
            grid.speckle(Color(hex: "3E2E55"), count: 7, size: 2, seed: 77)
        case .crying_obsidian:
            grid.noise(0.08, seed: 78)
            grid.speckle(Color(hex: "8E3E9E"), count: 7, size: 1, seed: 79)
            grid.speckle(Color(hex: "D86AE8"), count: 4, size: 1, seed: 80)
        case .bedrock:
            bedrock(&grid)

        // --- Logs & stems ---
        case .oak_log, .spruce_log, .birch_log, .jungle_log, .acacia_log,
             .dark_oak_log, .mangrove_log, .cherry_log, .pale_oak_log,
             .crimson_stem, .warped_stem:
            logFace(&grid, icon: icon)

        // --- Planks & bamboo ---
        case .oak_planks, .spruce_planks, .birch_planks, .jungle_planks,
             .acacia_planks, .dark_oak_planks, .mangrove_planks, .cherry_planks,
             .pale_oak_planks, .bamboo_block, .bamboo_mosaic:
            plankFace(&grid, icon: icon)

        // --- Leaves ---
        case .oak_leaves, .spruce_leaves, .birch_leaves, .jungle_leaves,
             .acacia_leaves, .dark_oak_leaves, .cherry_leaves, .mangrove_leaves:
            leafFace(&grid, icon: icon)

        // --- Functional blocks ---
        case .crafting_table:
            plankFace(&grid, icon: .oak_planks)
            grid.plankLines(Color(hex: "6E5638"), period: 16)
            // Tool grid: darker cross.
            for i in 0..<16 {
                if i >= 5 && i <= 10 {
                    grid.px(i, 7, Color(hex: "6E5638"))
                    grid.px(7, i, Color(hex: "6E5638"))
                }
            }
            grid.rect(5, 5, 10, 10, Color(hex: "8A6E46"))
        case .furnace, .blast_furnace, .smoker:
            furnaceFace(&grid, icon: icon)
        case .enchanting_table:
            enchantingFace(&grid)
        case .note_block:
            plankFace(&grid, icon: .oak_planks)
            grid.rect(6, 6, 9, 9, Color(hex: "3E5E9E"))
            grid.px(7, 7, Color(hex: "8EB8FF"))
        case .jukebox:
            plankFace(&grid, icon: .dark_oak_planks)
            grid.rect(0, 0, 15, 3, Color(hex: "4E3826"))
            grid.rect(3, 6, 12, 9, Color(hex: "D8B84E"))
        case .chest:
            chestFace(&grid, trapped: false)
        case .barrel:
            barrelFace(&grid)
        case .bookshelf:
            bookshelfFace(&grid)
        case .observer:
            observerFace(&grid)
        case .dropper, .dispenser, .hopper, .smithing_table, .stonecutter,
             .cartography_table, .fletching_table, .composter, .loom:
            utilityFace(&grid, icon: icon)
        case .spawner:
            spawnerFace(&grid)
        case .command_block:
            commandFace(&grid)
        case .structure_block:
            structureFace(&grid)
        case .end_portal_frame:
            endPortalFrame(&grid)
        case .bee_nest:
            beeNestFace(&grid)
        case .hay_block:
            hayFace(&grid)
        case .pumpkin:
            pumpkinFace(&grid, lit: false)
        case .jack_o_lantern:
            pumpkinFace(&grid, lit: true)
        case .melon:
            melonFace(&grid)
        case .tnt:
            tntFace(&grid)

        // --- Nether & end ---
        case .netherrack:
            grid.noise(0.10, seed: 90)
            grid.speckle(Color(hex: "8E3A30"), count: 6, size: 2, seed: 91)
        case .nether_bricks:
            grid.brickPattern(Color(hex: "1E1416"))
        case .quartz_block:
            quartzFace(&grid)
        case .polished_blackstone:
            grid.noise(0.05, seed: 92)
            grid.speckle(Color(hex: "3E3E46"), count: 6, size: 2, seed: 93)
        case .basalt:
            grid.noise(0.07, seed: 94)
            for x in stride(from: 2, to: 16, by: 4) {
                for y in 0..<16 { grid.px(x, y, Color(hex: "2E2E32")) }
            }
        case .blackstone:
            grid.noise(0.08, seed: 95)
            grid.speckle(Color(hex: "3E3A44"), count: 6, size: 2, seed: 96)
        case .end_stone:
            grid.noise(0.05, seed: 97)
            grid.speckle(Color(hex: "D8CC90"), count: 6, size: 2, seed: 98)
        case .purpur_block:
            grid.noise(0.05, seed: 99)
            for y in stride(from: 3, to: 16, by: 6) {
                for x in 0..<16 { grid.px(x, y, Color(hex: "7A5EB0")) }
            }
        case .nylium_crimson:
            grid.rect(0, 0, 15, 4, Color(hex: "8E4A5E"))
            grid.noise(0.08, seed: 100)
        case .nylium_warped:
            grid.rect(0, 0, 15, 4, Color(hex: "3E8E8E"))
            grid.noise(0.08, seed: 101)

        // --- Ice & snow ---
        case .snow_block:
            grid.noise(0.04, seed: 102)
            grid.speckle(Color(hex: "D8E8F0"), count: 5, size: 2, seed: 103)
        case .ice:
            iceFace(&grid, deep: false)
        case .packed_ice:
            iceFace(&grid, deep: true)
        case .blue_ice:
            iceFace(&grid, deep: true)
            grid.speckle(Color(hex: "8EC8FF"), count: 6, size: 1, seed: 105)

        // --- Glass ---
        case .glass:
            grid.glassStyle(Color(hex: "C8E8F0"))
        case .tinted_glass:
            grid.glassStyle(Color(hex: "3E5E8E"), opacity: 0.45)

        // --- Prismarine ---
        case .prismarine:
            grid.noise(0.06, seed: 106)
            grid.speckle(Color(hex: "4E9890"), count: 7, size: 2, seed: 107)
        case .prismarine_bricks:
            grid.brickPattern(Color(hex: "3E7A72"))
        case .dark_prismarine:
            grid.noise(0.06, seed: 108)
            grid.speckle(Color(hex: "2E5E58"), count: 6, size: 2, seed: 109)

        // --- Color families: matte noise + subtle border only ---
        default:
            grid.noise(0.05, seed: 110)
            grid.edgeBorder(factor: 0.85)
        }
    }

    // MARK: Feature helpers

    private static func oreStyle(_ grid: inout IconGrid, _ color: Color, seed: Int) {
        grid.noise(0.06, seed: seed)
        grid.ore(color, count: 6, seed: seed)
    }

    private static func metalBlock(_ grid: inout IconGrid) {
        grid.noise(0.04, seed: 120)
        // Brushed vertical streaks + corner bolts.
        for x in stride(from: 3, to: 16, by: 5) {
            for y in 0..<16 {
                grid.px(x, y, Color.white.opacity(0.10))
                grid.px(x + 1, y, Color.black.opacity(0.08))
            }
        }
        for (bx, by) in [(1, 1), (14, 1), (1, 14), (14, 14)] {
            grid.px(bx, by, Color.black.opacity(0.35))
            grid.px(bx + 1, by, Color.black.opacity(0.35))
            grid.px(bx, by + 1, Color.black.opacity(0.35))
        }
    }

    private static func glowCluster(_ grid: inout IconGrid, seed: Int) {
        grid.noise(0.05, seed: seed)
        for i in 0..<9 {
            let cx = 2 + Int(IconGrid.hash(i, 5, seed) * 11)
            let cy = 2 + Int(IconGrid.hash(i &* 3, 9, seed &+ 2) * 11)
            for dy in 0..<2 {
                for dx in 0..<2 {
                    grid.px(cx + dx, cy + dy, i % 3 == 0 ? Color(hex: "FFF2A8") : Color(hex: "F0B83C"))
                }
            }
        }
    }

    private static func seaLantern(_ grid: inout IconGrid) {
        grid.rect(0, 0, 15, 15, Color(hex: "BFE8E2"))
        grid.noise(0.04, seed: 130)
        // Grid of glowing cells.
        for y in stride(from: 2, to: 15, by: 4) {
            for x in stride(from: 2, to: 15, by: 4) {
                grid.px(x, y, Color.white)
                grid.px(x + 1, y, Color(hex: "E8FFFA"))
                grid.px(x, y + 1, Color(hex: "E8FFFA"))
            }
        }
    }

    private static func bedrock(_ grid: inout IconGrid) {
        grid.noise(0.14, seed: 140)
        grid.speckle(Color.black, count: 12, size: 2, seed: 141)
        grid.speckle(Color(hex: "6E6E76"), count: 8, size: 2, seed: 142)
    }

    private static func logFace(_ grid: inout IconGrid, icon: MinecraftBlockIcon) {
        // Bark: dark/light vertical stripes + top/bottom ring caps.
        let dark = Color.black.opacity(0.30)
        let light = Color.white.opacity(0.14)
        grid.logStripes(dark, light)
        // Bark tint variation per species via an overlay wash.
        let wash: Color?
        switch icon {
        case .birch_log: wash = Color.white.opacity(0.35)
        case .spruce_log, .dark_oak_log: wash = Color.black.opacity(0.22)
        case .crimson_stem: wash = Color(hex: "E85A6E").opacity(0.25)
        case .warped_stem: wash = Color(hex: "5ED8D8").opacity(0.25)
        default: wash = nil
        }
        if let wash {
            for y in 0..<16 {
                for x in 0..<16 {
                    // Cheap tint: blend by drawing wash over.
                    grid.px(x, y, wash)
                }
            }
            // Re-apply stripes on top so bark still reads.
            grid.logStripes(dark, light)
        }
        grid.edgeBorder(factor: 0.8)
    }

    private static func plankFace(_ grid: inout IconGrid, icon: MinecraftBlockIcon) {
        let line: Color
        switch icon {
        case .spruce_planks, .dark_oak_planks: line = Color.black.opacity(0.35)
        case .bamboo_block, .bamboo_mosaic: line = Color(hex: "8E7A44")
        default: line = Color.black.opacity(0.28)
        }
        grid.noise(0.05, seed: 150)
        grid.plankLines(line, period: icon == .bamboo_block || icon == .bamboo_mosaic ? 8 : 4)
        grid.edgeBorder(factor: 0.85)
    }

    private static func leafFace(_ grid: inout IconGrid, icon: MinecraftBlockIcon) {
        let dark = Color.black.opacity(0.30)
        let light = Color.white.opacity(0.16)
        grid.leafBlotch(dark, light, seed: 160)
        grid.noise(0.08, seed: 161)
        if icon == .birch_leaves {
            grid.speckle(Color.black, count: 8, size: 1, seed: 162)
        }
    }

    private static func furnaceFace(_ grid: inout IconGrid, icon: MinecraftBlockIcon) {
        grid.noise(0.05, seed: 170)
        // Top slab highlight, then the firebox opening.
        for x in 0..<16 { grid.px(x, 0, Color.white.opacity(0.18)) }
        for x in 0..<16 { grid.px(x, 1, Color.black.opacity(0.25)) }
        let opening: (Int, Int, Int, Int) = icon == .smoker ? (5, 9, 10, 14) : (4, 8, 11, 14)
        grid.rect(opening.0, opening.1, opening.2, opening.3, Color(hex: "141414"))
        // Fire glow inside the opening.
        grid.rect(opening.0 + 1, opening.3 - 1, opening.2 - 1, opening.3, Color(hex: "E86A1E"))
        if icon == .blast_furnace {
            grid.rect(5, 4, 10, 6, Color(hex: "3E3E46"))
        }
        grid.edgeBorder(factor: 0.8)
    }

    private static func enchantingFace(_ grid: inout IconGrid) {
        grid.noise(0.06, seed: 180)
        // Bookshelf-like bottom + floating book on top.
        grid.rect(0, 11, 15, 15, Color(hex: "8A5E38"))
        for x in stride(from: 0, to: 16, by: 4) {
            for y in 11..<16 { grid.px(x, y, Color(hex: "5E3E20")) }
        }
        grid.rect(5, 4, 10, 10, Color(hex: "E8E4DA"))
        grid.rect(5, 4, 10, 5, Color(hex: "C8C0AE"))
        grid.rect(6, 6, 9, 8, Color(hex: "345EC3"))
        for i in 6..<9 { grid.px(i, 7, Color.white.opacity(0.7)) }
        grid.px(7, 3, Color(hex: "5DECF5"))
        grid.px(8, 3, Color(hex: "5DECF5"))
        grid.px(7, 2, Color(hex: "5DECF5"))
        grid.px(8, 2, Color(hex: "5DECF5"))
    }

    private static func chestFace(_ grid: inout IconGrid, trapped: Bool) {
        plankFace(&grid, icon: .oak_planks)
        // Lid seam + latch.
        for x in 0..<16 { grid.px(x, 7, Color.black.opacity(0.4)) }
        grid.rect(7, 6, 8, 8, Color(hex: "6E5638"))
        grid.px(7, 7, Color(hex: "D8B84E"))
        grid.px(8, 7, Color(hex: "D8B84E"))
        if trapped {
            grid.px(3, 3, Color(hex: "3EC8C8"))
            grid.px(12, 3, Color(hex: "3EC8C8"))
        }
    }

    private static func barrelFace(_ grid: inout IconGrid) {
        grid.noise(0.05, seed: 190)
        // Staves + metal hoops.
        for x in stride(from: 2, to: 16, by: 4) {
            for y in 0..<16 { grid.px(x, y, Color.black.opacity(0.3)) }
        }
        for y in [3, 12] {
            for x in 0..<16 { grid.px(x, y, Color(hex: "5E5E66")) }
        }
    }

    private static func bookshelfFace(_ grid: inout IconGrid) {
        plankFace(&grid, icon: .oak_planks)
        // Two shelves of colored book spines.
        let bookColors: [Color] = [
            Color(hex: "B03030"), Color(hex: "3050B0"), Color(hex: "30A050"),
            Color(hex: "B08030"), Color(hex: "8030B0"), Color(hex: "30A0A0"),
            Color(hex: "C0C0C0"), Color(hex: "5030B0"), Color(hex: "B05030")
        ]
        for shelf in 0..<2 {
            let y0 = shelf * 8 + 1
            for x in 1..<15 {
                let c = bookColors[(x + shelf * 3) % bookColors.count]
                grid.px(x, y0, c)
                grid.px(x, y0 + 1, c.opacity(0.85))
                grid.px(x, y0 + 2, c.opacity(0.7))
                grid.px(x, y0 + 3, c.opacity(0.55))
            }
            for x in 0..<16 { grid.px(x, y0 + 4, Color(hex: "6E5638")) }
        }
    }

    private static func observerFace(_ grid: inout IconGrid) {
        grid.noise(0.05, seed: 200)
        grid.rect(0, 0, 15, 15, Color(hex: "8E8E8E"))
        grid.noise(0.05, seed: 201)
        // Face: quartz panel + redstone dot.
        grid.rect(3, 3, 12, 12, Color(hex: "D8D4C8"))
        grid.rect(5, 5, 10, 10, Color(hex: "3E3E46"))
        grid.px(7, 7, Color(hex: "E02828"))
        grid.px(8, 7, Color(hex: "E02828"))
        grid.px(7, 8, Color(hex: "E02828"))
        grid.px(8, 8, Color(hex: "E02828"))
        // Side sensor strip.
        for y in 4..<12 { grid.px(1, y, Color(hex: "5E5E66")) }
    }

    /// Shared look for the stone-ish utility blocks: cobble body, dark
    /// front face details per kind.
    private static func utilityFace(_ grid: inout IconGrid, icon: MinecraftBlockIcon) {
        grid.cobble(Color.black, seed: 210)
        switch icon {
        case .hopper:
            grid.rect(6, 4, 9, 7, Color.black)
            grid.rect(4, 9, 11, 12, Color(hex: "3E3E46"))
        case .composter:
            grid.rect(0, 0, 15, 3, Color(hex: "4E3A20"))
            grid.rect(4, 5, 11, 12, Color.black.opacity(0.5))
            grid.speckle(Color(hex: "7A5A30"), count: 5, size: 1, seed: 211)
        case .loom:
            grid.rect(0, 0, 15, 15, Color(hex: "A88A5E"))
            grid.plankLines(Color.black.opacity(0.3), period: 16)
            grid.rect(3, 3, 12, 6, Color(hex: "D8B84E"))
            grid.rect(5, 8, 10, 12, Color(hex: "8A5A2E"))
        case .cartography_table, .fletching_table:
            grid.rect(0, 0, 15, 4, Color(hex: "E8E4DA"))
            grid.rect(3, 6, 12, 9, Color(hex: "B0A888"))
        case .smithing_table:
            grid.rect(4, 4, 11, 11, Color(hex: "5E5E66"))
            grid.rect(6, 6, 9, 9, Color(hex: "3E9E8E"))
        case .stonecutter:
            grid.rect(0, 8, 15, 15, Color(hex: "5E5E66"))
            grid.rect(3, 3, 12, 7, Color(hex: "D8D4C8"))
        case .dropper, .dispenser:
            grid.rect(4, 4, 11, 11, Color.black)
            grid.px(7, 7, Color(hex: "8E8E8E"))
            grid.px(8, 7, Color(hex: "8E8E8E"))
            grid.px(7, 8, Color(hex: "8E8E8E"))
            grid.px(8, 8, Color(hex: "8E8E8E"))
        default:
            break
        }
    }

    private static func spawnerFace(_ grid: inout IconGrid) {
        grid.noise(0.08, seed: 220)
        // Cage: dark frame + bars.
        for i in 0..<16 {
            grid.px(i, 0, Color(hex: "3E3E46"))
            grid.px(i, 15, Color(hex: "3E3E46"))
            grid.px(0, i, Color(hex: "3E3E46"))
            grid.px(15, i, Color(hex: "3E3E46"))
        }
        for x in stride(from: 3, to: 16, by: 5) {
            for y in 1..<15 { grid.px(x, y, Color(hex: "3E3E46")) }
        }
        for y in stride(from: 3, to: 16, by: 5) {
            for x in 1..<15 { grid.px(x, y, Color(hex: "3E3E46")) }
        }
        // Swirling mob center.
        grid.rect(6, 6, 9, 9, Color(hex: "3E9E5E"))
        grid.px(7, 7, Color(hex: "B8FFD8"))
        grid.px(8, 8, Color(hex: "B8FFD8"))
    }

    private static func commandFace(_ grid: inout IconGrid) {
        grid.noise(0.05, seed: 230)
        // Three colored buttons on the front.
        grid.rect(0, 0, 15, 2, Color(hex: "D8D4C8"))
        let colors: [(Int, Color)] = [(2, Color(hex: "B03030")), (7, Color(hex: "D8B83C")), (12, Color(hex: "30A0B0"))]
        for (cx, c) in colors {
            grid.rect(cx, 5, cx + 3, 8, c)
            grid.rect(cx + 1, 6, cx + 2, 7, Color.white.opacity(0.6))
        }
        grid.rect(2, 11, 13, 13, Color(hex: "4E4E58"))
    }

    private static func structureFace(_ grid: inout IconGrid) {
        grid.noise(0.06, seed: 240)
        grid.rect(0, 0, 15, 15, Color(hex: "8E8E8E"))
        grid.noise(0.05, seed: 241)
        // Corner brackets like the structure-block UI.
        let c = Color(hex: "3E9E8E")
        for i in 2..<6 {
            grid.px(i, 2, c); grid.px(2, i, c)
            grid.px(15 - i, 2, c); grid.px(13, i, c)
            grid.px(i, 13, c); grid.px(2, 15 - i, c)
            grid.px(15 - i, 13, c); grid.px(13, 15 - i, c)
        }
        grid.rect(6, 6, 9, 9, c.opacity(0.5))
    }

    private static func endPortalFrame(_ grid: inout IconGrid) {
        grid.noise(0.06, seed: 250)
        // Stone frame around a dark portal hole with green "eye".
        grid.rect(0, 0, 15, 15, Color(hex: "4E7A4E"))
        grid.noise(0.06, seed: 251)
        grid.rect(3, 3, 12, 12, Color(hex: "0E1410"))
        grid.px(7, 7, Color(hex: "3EE86A"))
        grid.px(8, 7, Color(hex: "3EE86A"))
        grid.px(7, 8, Color(hex: "3EE86A"))
        grid.px(8, 8, Color(hex: "3EE86A"))
        // Frame border stones.
        for i in 0..<16 {
            grid.px(i, 0, Color(hex: "6E9E62"))
            grid.px(i, 15, Color(hex: "6E9E62"))
            grid.px(0, i, Color(hex: "6E9E62"))
            grid.px(15, i, Color(hex: "6E9E62"))
        }
    }

    private static func beeNestFace(_ grid: inout IconGrid) {
        grid.noise(0.06, seed: 260)
        // Honeycomb texture + dark entrance.
        for y in stride(from: 1, to: 16, by: 4) {
            for x in stride(from: (y / 4) % 2 == 0 ? 1 : 3, to: 16, by: 4) {
                grid.px(x, y, Color(hex: "B8862E"))
            }
        }
        grid.rect(6, 9, 9, 13, Color(hex: "3E2A12"))
        grid.rect(7, 10, 8, 12, Color.black)
    }

    private static func hayFace(_ grid: inout IconGrid) {
        grid.noise(0.06, seed: 270)
        // Bundled straw lines.
        for y in stride(from: 2, to: 16, by: 3) {
            for x in 0..<16 {
                grid.px(x, y, Color(hex: "B8983E"))
            }
        }
        for x in stride(from: 1, to: 16, by: 5) {
            for y in 0..<16 { grid.px(x, y, Color(hex: "B8983E")) }
        }
        grid.rect(0, 7, 15, 8, Color(hex: "A88030"))
    }

    private static func pumpkinFace(_ grid: inout IconGrid, lit: Bool) {
        grid.noise(0.05, seed: 280)
        // Ribbed grooves.
        for x in [3, 7, 11, 14] {
            for y in 0..<16 { grid.px(x, y, Color.black.opacity(0.22)) }
        }
        // Stem.
        grid.rect(7, 0, 8, 2, Color(hex: "4E6E2E"))
        // Face.
        let face = lit ? Color(hex: "FFE89E") : Color(hex: "3E2410")
        let glow = lit ? Color(hex: "FFF4C8") : face
        // Eyes.
        grid.rect(4, 6, 5, 7, face)
        grid.rect(10, 6, 11, 7, face)
        // Nose + mouth.
        grid.px(7, 9, face); grid.px(8, 9, face)
        for x in 4...11 where x != 5 && x != 10 {
            grid.px(x, 12, face)
        }
        grid.px(5, 11, face); grid.px(10, 11, face)
        if lit {
            grid.px(4, 6, glow); grid.px(10, 6, glow)
        }
    }

    private static func melonFace(_ grid: inout IconGrid) {
        grid.noise(0.05, seed: 290)
        // Stripe grooves.
        for x in [2, 6, 10, 14] {
            for y in 0..<16 { grid.px(x, y, Color(hex: "3E7A24")) }
        }
        // Vine scar.
        grid.rect(7, 0, 8, 1, Color(hex: "6E5638"))
    }

    private static func tntFace(_ grid: inout IconGrid) {
        grid.noise(0.05, seed: 300)
        // Black band with "TNT" marking.
        for y in 5..<11 {
            for x in 0..<16 { grid.px(x, y, Color(hex: "1A1A1A")) }
        }
        for x in 0..<16 {
            grid.px(x, 4, Color.white)
            grid.px(x, 11, Color.white)
        }
        // Pixel "TNT" letters (3×5 font, rows 6-10).
        let font: [Character: [String]] = [
            "T": ["XXX", "..X", "..X", "..X", "XXX"],
            "N": ["X.X", "XX.", "X.X", "X.X", "X.X"]
        ]
        var cx = 4
        for ch in "TNT" {
            if let rows = font[ch] {
                for (ry, row) in rows.enumerated() {
                    for (rx, bit) in row.enumerated() where bit == "X" {
                        grid.px(cx + rx, 6 + ry, Color.white)
                    }
                }
            }
            cx += 4
        }
    }

    private static func quartzFace(_ grid: inout IconGrid) {
        grid.noise(0.04, seed: 310)
        // Pillar grooves on two edges.
        for x in [3, 12] {
            for y in 0..<16 { grid.px(x, y, Color(hex: "D0CCC0")) }
        }
        grid.speckle(Color(hex: "F5F2EA"), count: 5, size: 1, seed: 311)
    }

    private static func iceFace(_ grid: inout IconGrid, deep: Bool) {
        grid.noise(0.04, seed: 320)
        // Cracks / frost streaks.
        for i in 0..<5 {
            let x0 = Int(IconGrid.hash(i, 1, 321) * 12)
            let y0 = Int(IconGrid.hash(i, 2, 322) * 12)
            for s in 0..<4 {
                grid.px(x0 + s, y0 + (s % 2), Color.white.opacity(deep ? 0.5 : 0.7))
                grid.px(x0 + s, y0 + 1 + (s % 2), Color.white.opacity(0.3))
            }
        }
        grid.speckle(Color.white.opacity(0.5), count: 6, size: 1, seed: 323)
    }

    private static func targetFace(_ grid: inout IconGrid) {
        // Red body, cream rings, dark bullseye.
        grid.rect(0, 0, 15, 15, Color(hex: "C33A2A"))
        grid.noise(0.05, seed: 330)
        grid.rect(2, 2, 13, 13, Color(hex: "E8DCC0"))
        grid.rect(4, 4, 11, 11, Color(hex: "C33A2A"))
        grid.rect(6, 6, 9, 9, Color(hex: "E8DCC0"))
        grid.rect(7, 7, 8, 8, Color(hex: "1A1A1A"))
    }

    private static func beaconFace(_ grid: inout IconGrid) {
        // Glass shell with inner beam core.
        grid.glassStyle(Color(hex: "9FB8D8"), opacity: 0.25)
        grid.rect(6, 6, 9, 9, Color(hex: "5DECF5"))
        grid.rect(7, 7, 8, 8, Color.white)
        grid.px(7, 3, Color(hex: "5DECF5"))
        grid.px(8, 3, Color(hex: "5DECF5"))
        grid.px(7, 2, Color(hex: "5DECF5"))
        grid.px(8, 2, Color(hex: "5DECF5"))
    }

}

// MARK: - SwiftUI tile

/// Cached 16×16 → NSImage lookup used by `BlockIconTile`.
@MainActor
enum BlockIconCache {
    static func image(for block: String, size: CGFloat) -> NSImage? {
        guard let icon = MinecraftBlockIcon(rawValue: block) else { return nil }
        return BlockIconRenderer.image(for: icon)
    }
}

/// Self-contained instance icon: renders the Minecraft block pixel art
/// when `block` matches a known `MinecraftBlockIcon`, otherwise falls back
/// to the legacy SF-symbol `InstanceIconTile`.
struct BlockIconTile: View {
    var block: String
    var color: Color = NeoPalette.accent
    var symbol: String = "cube.fill"
    var size: CGFloat = 40

    var body: some View {
        if let icon = MinecraftBlockIcon(rawValue: block) {
            Image(nsImage: BlockIconRenderer.image(for: icon))
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                }
                .shadow(color: color.opacity(0.30), radius: size * 0.18, x: 0, y: size * 0.08)
                .help(icon.displayName)
        } else {
            InstanceIconTile(symbol: symbol, color: color, size: size)
        }
    }
}
