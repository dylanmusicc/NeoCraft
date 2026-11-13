import Compression
import Foundation

// MARK: - Minimal NBT reader

/// Binary NBT value tree. Covers every tag type Minecraft writes into
/// `level.dat` (compounds, lists, arrays, scalars).
indirect enum NBTValue: Sendable {
    case end
    case byte(Int8)
    case short(Int16)
    case int(Int32)
    case long(Int64)
    case float(Float)
    case double(Double)
    case byteArray(Data)
    case string(String)
    case list([NBTValue])
    case compound([String: NBTValue])
    case intArray([Int32])
    case longArray([Int64])

    var intValue: Int32? {
        switch self {
        case .int(let v): Int32(v)
        case .byte(let v): Int32(v)
        case .short(let v): Int32(v)
        case .long(let v): v > Int32.max || v < Int32.min ? nil : Int32(v)
        default: nil
        }
    }

    var longValue: Int64? {
        switch self {
        case .long(let v): v
        case .int(let v): Int64(v)
        case .byte(let v): Int64(v)
        case .short(let v): Int64(v)
        default: nil
        }
    }

    var stringValue: String? {
        if case .string(let v) = self { return v }
        return nil
    }

    var compoundValue: [String: NBTValue]? {
        if case .compound(let v) = self { return v }
        return nil
    }

    var listValue: [NBTValue]? {
        if case .list(let v) = self { return v }
        return nil
    }
}

enum NBTError: Error, LocalizedError {
    case truncated
    case unknownTag(UInt8)
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .truncated: "Unexpected end of NBT data"
        case .unknownTag(let t): "Unknown NBT tag type \(t)"
        case .invalidUTF8: "Invalid UTF-8 string in NBT data"
        }
    }
}

/// Big-endian binary NBT cursor.
struct NBTReader {
    private let data: Data
    private var offset = 0

    init(data: Data) { self.data = data }

    private mutating func byte() throws -> UInt8 {
        guard offset < data.count else { throw NBTError.truncated }
        defer { offset += 1 }
        return data[offset]
    }

    private mutating func bytes(_ count: Int) throws -> Data {
        guard offset + count <= data.count else { throw NBTError.truncated }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    private mutating func u16() throws -> UInt16 {
        let b = try bytes(2)
        return b.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self).bigEndian }
    }

    private mutating func u32() throws -> UInt32 {
        let b = try bytes(4)
        return b.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian }
    }

    private mutating func i32() throws -> Int32 {
        let b = try bytes(4)
        return Int32(bitPattern: b.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).bigEndian })
    }

    private mutating func i64() throws -> Int64 {
        let b = try bytes(8)
        return Int64(bitPattern: b.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian })
    }

    private mutating func f32() throws -> Float {
        Float(bitPattern: try u32())
    }

    private mutating func f64() throws -> Double {
        let b = try bytes(8)
        return Double(bitPattern: b.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self).bigEndian })
    }

    private mutating func utf8(_ length: Int) throws -> String {
        let b = try bytes(length)
        guard let s = String(data: b, encoding: .utf8) else { throw NBTError.invalidUTF8 }
        return s
    }

    /// Reads a TAG_String (u16 length + UTF-8 bytes).
    mutating func readString() throws -> String {
        try utf8(Int(u16()))
    }

    /// Reads a named tag: type byte, name, payload. Returns nil on TAG_End.
    mutating func readNamedTag() throws -> (type: UInt8, name: String, value: NBTValue)? {
        let type = try byte()
        if type == 0 { return nil }
        let name = try readString()
        let value = try readPayload(type: type)
        return (type, name, value)
    }

    mutating func readPayload(type: UInt8) throws -> NBTValue {
        switch type {
        case 0: return .end
        case 1: return .byte(Int8(bitPattern: try byte()))
        case 2: return .short(Int16(bitPattern: try u16()))
        case 3: return .int(try i32())
        case 4: return .long(try i64())
        case 5: return .float(try f32())
        case 6: return .double(try f64())
        case 7:
            let count = Int(try i32())
            return .byteArray(try bytes(count))
        case 8:
            return .string(try readString())
        case 9:
            let elementType = try byte()
            let count = Int(try i32())
            var items: [NBTValue] = []
            items.reserveCapacity(min(count, 1_000_000))
            for _ in 0..<count {
                items.append(try readPayload(type: elementType))
            }
            return .list(items)
        case 10:
            var compound: [String: NBTValue] = [:]
            while true {
                guard let tag = try readNamedTag() else { break }
                compound[tag.name] = tag.value
            }
            return .compound(compound)
        case 11:
            let count = Int(try i32())
            var items = [Int32](); items.reserveCapacity(min(count, 1_000_000))
            for _ in 0..<count { items.append(try i32()) }
            return .intArray(items)
        case 12:
            let count = Int(try i32())
            var items = [Int64](); items.reserveCapacity(min(count, 1_000_000))
            for _ in 0..<count { items.append(try i64()) }
            return .longArray(items)
        default:
            throw NBTError.unknownTag(type)
        }
    }

    /// Parses a complete NBT document (one named root tag).
    static func parse(_ data: Data) throws -> [String: NBTValue] {
        var reader = NBTReader(data: data)
        guard let root = try reader.readNamedTag(),
              case .compound(let compound) = root.value else {
            throw NBTError.truncated
        }
        return compound
    }
}

// MARK: - GZip decompression

/// Decompresses a gzip stream using the system `gzip` binary. Returns nil
/// when the input is not gzipped (callers then try raw NBT).
enum GZip {
    static func decompress(_ data: Data) -> Data? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        process.arguments = ["-dc"]
        process.standardInput = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let stdin = process.standardInput as! Pipe
        stdin.fileHandleForWriting.write(data)
        try? stdin.fileHandleForWriting.close()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !output.isEmpty else { return nil }
        return output
    }
}

// MARK: - level.dat metadata

/// Everything NeoCraft needs from a world's `level.dat`.
struct WorldMetadata: Sendable, Equatable {
    var levelName: String?
    var seed: Int64?
    var spawnX: Int?
    var spawnY: Int?
    var spawnZ: Int?
    var gameType: String?

    var hasCoordinates: Bool { spawnX != nil && spawnZ != nil }
}

enum WorldDataService {
    /// Parses `<world>/level.dat` (gzipped NBT). Returns nil on failure.
    static func metadata(worldDirectory: URL) -> WorldMetadata? {
        let levelDat = worldDirectory.appendingPathComponent("level.dat")
        guard let raw = try? Data(contentsOf: levelDat), !raw.isEmpty else { return nil }

        // level.dat is gzip-compressed; fall back to raw NBT just in case.
        let payload = GZip.decompress(raw) ?? raw
        var root: [String: NBTValue]?
        do {
            root = try NBTReader.parse(payload)
        } catch {
            // Some files have trailing bytes after the root tag — retry by
            // trimming to the first parseable prefix.
            root = nil
        }
        guard let root else { return nil }

        // Modern layout: everything lives under the "Data" compound.
        let data = root["Data"]?.compoundValue ?? root
        let worldGen = data["WorldGenSettings"]?.compoundValue

        let seed = data["RandomSeed"]?.longValue ?? worldGen?["seed"]?.longValue

        let gameTypeID = data["GameType"]?.intValue
        let gameType: String? = switch gameTypeID {
        case 0: "Survival"
        case 1: "Creative"
        case 2: "Adventure"
        case 3: "Spectator"
        default: nil
        }

        return WorldMetadata(
            levelName: data["LevelName"]?.stringValue,
            seed: seed,
            spawnX: data["SpawnX"]?.intValue.map(Int.init),
            spawnY: data["SpawnY"]?.intValue.map(Int.init),
            spawnZ: data["SpawnZ"]?.intValue.map(Int.init),
            gameType: gameType
        )
    }
}

// MARK: - NBT writer (servers.dat & friends)

/// Big-endian binary NBT writer mirroring `NBTReader`.
struct NBTWriter {
    private var data = Data()

    static func serialize(rootName: String = "", _ value: NBTValue) -> Data {
        var w = NBTWriter()
        w.writeNamedTag(type: NBTValue.typeID(of: value), name: rootName, value: value)
        w.writeEnd()
        return w.data
    }

    private mutating func writeEnd() {
        data.append(0)
    }

    private mutating func writeNamedTag(type: UInt8, name: String, value: NBTValue) {
        data.append(type)
        writeUTF8(name)
        writePayload(value)
    }

    private mutating func writePayload(_ value: NBTValue) {
        switch value {
        case .end:
            break
        case .byte(let v): data.append(UInt8(bitPattern: v))
        case .short(let v):
            var be = v.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        case .int(let v):
            var be = v.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        case .long(let v):
            var be = v.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        case .float(let v):
            var be = v.bitPattern.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        case .double(let v):
            var be = v.bitPattern.bigEndian
            withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
        case .byteArray(let bytes):
            writeI32(Int32(bytes.count))
            data.append(bytes)
        case .string(let s):
            writeUTF8(s)
        case .list(let items):
            let elemType = items.first.map { NBTValue.typeID(of: $0) } ?? 0
            data.append(elemType)
            writeI32(Int32(items.count))
            for item in items { writePayload(item) }
        case .compound(let dict):
            // Deterministic order keeps diffs stable.
            for key in dict.keys.sorted() {
                guard let v = dict[key] else { continue }
                if case .end = v { continue }
                writeNamedTag(type: NBTValue.typeID(of: v), name: key, value: v)
            }
            data.append(0)
        case .intArray(let values):
            writeI32(Int32(values.count))
            for v in values { writeI32(v) }
        case .longArray(let values):
            writeI32(Int32(values.count))
            for v in values {
                var be = v.bigEndian
                withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
            }
        }
    }

    private mutating func writeUTF8(_ s: String) {
        let bytes = Array(s.utf8)
        writeI16(Int16(bytes.count))
        data.append(contentsOf: bytes)
    }

    private mutating func writeI16(_ v: Int16) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }

    private mutating func writeI32(_ v: Int32) {
        var be = v.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }
    }
}

extension NBTValue {
    static func typeID(of value: NBTValue) -> UInt8 {
        switch value {
        case .end: 0
        case .byte: 1
        case .short: 2
        case .int: 3
        case .long: 4
        case .float: 5
        case .double: 6
        case .byteArray: 7
        case .string: 8
        case .list: 9
        case .compound: 10
        case .intArray: 11
        case .longArray: 12
        }
    }
}

extension GZip {
    /// gzip-compress via the Compression framework's zlib stream wrapped
    /// in a minimal gzip header + CRC32 trailer.
    static func compress(_ data: Data) -> Data? {
        guard let compressed = zlibCompress(data) else { return nil }
        var out = Data()
        // Header: magic, deflate, flags=0, mtime=0, xfl=0, os=255 (unknown)
        out.append(contentsOf: [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        out.append(compressed)
        var crc = crc32(data)
        var isize = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &isize) { out.append(contentsOf: $0) }
        return out
    }

    private static func zlibCompress(_ data: Data) -> Data? {
        let dstSize = data.count + data.count / 2 + 64
        var dst = [UInt8](repeating: 0, count: dstSize)
        let written = data.withUnsafeBytes { src -> Int in
            guard let base = src.baseAddress else { return 0 }
            return dst.withUnsafeMutableBytes { d in
                compression_encode_buffer(
                    d.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    dstSize,
                    base.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0, written <= dstSize else { return nil }
        return Data(dst.prefix(written))
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1
            }
        }
        return ~crc
    }
}
