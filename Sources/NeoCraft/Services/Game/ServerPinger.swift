import Foundation
import Network

/// Result of a Minecraft Server List Ping (status handshake).
struct ServerStatus: Sendable {
    var reachable: Bool
    var motd: String
    var playersOnline: Int
    var playersMax: Int
    var versionName: String
    var latencyMilliseconds: Int?
    /// Raw base64 PNG payload from the server's `favicon` field
    /// (`data:image/png;base64,…` stripped). `nil` when absent.
    var faviconBase64: String? = nil

    /// `faviconBase64` decoded into image data, ready for `NSImage`.
    var faviconData: Data? {
        guard let faviconBase64, !faviconBase64.isEmpty else { return nil }
        return Data(base64Encoded: faviconBase64)
    }
}

/// Minimal Minecraft "Server List Ping" client over a raw TCP connection.
/// Implements the status handshake + status request and parses the JSON
/// response — enough for live player counts in the Quick-Join bar.
enum ServerPinger {
    /// Pings `address` ("host" or "host:port", default 25565).
    static func ping(_ address: String, timeout: TimeInterval = 4) async -> ServerStatus {
        let parts = address.split(separator: ":", maxSplits: 1).map(String.init)
        let host = parts.first ?? address
        let port = parts.count > 1 ? (UInt16(parts[1]) ?? 25565) : 25565

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port) ?? 25565,
                using: .tcp
            )

            let claimed = ResumeFlag()
            let finish: @Sendable (ServerStatus) -> Void = { status in
                guard claimed.claim() else { return }
                connection.cancel()
                continuation.resume(returning: status)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let started = Date()
                    sendStatusRequest(on: connection, host: host, port: port, started: started, finish: finish)
                case .failed, .cancelled:
                    finish(ServerStatus(reachable: false, motd: "", playersOnline: 0, playersMax: 0, versionName: "", latencyMilliseconds: nil))
                default:
                    break
                }
            }
            connection.start(queue: .global())

            // Hard timeout so a blackholed server can't hang the UI.
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                finish(ServerStatus(reachable: false, motd: "", playersOnline: 0, playersMax: 0, versionName: "", latencyMilliseconds: nil))
            }
        }
    }

    private static func sendStatusRequest(
        on connection: NWConnection,
        host: String,
        port: UInt16,
        started: Date,
        finish: @escaping @Sendable (ServerStatus) -> Void
    ) {
        // Handshake packet (id 0x00): protocol version, server address, port, next state = 1 (status)
        var handshake = Data()
        handshake.appendVarint(0x00)
        handshake.appendVarint(770) // 1.21.x protocol; status pings are lenient about the version
        let hostData = Data(host.utf8)
        handshake.appendVarint(hostData.count)
        handshake.append(hostData)
        handshake.appendUInt16(port)
        handshake.appendVarint(1)

        var payload = Data()
        payload.appendVarint(handshake.count)
        payload.append(handshake)
        // Status request packet (id 0x00, empty)
        payload.appendVarint(1)
        payload.append(0x00)

        connection.send(content: payload, completion: .contentProcessed { _ in
            receiveLoop(connection: connection, buffer: Data(), started: started, finish: finish)
        })
    }

    /// Accumulates TCP segments until the full status packet arrives —
    /// large MOTDs or slow networks routinely split the response.
    private static func receiveLoop(
        connection: NWConnection,
        buffer: Data,
        started: Date,
        finish: @escaping @Sendable (ServerStatus) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { chunk, _, isComplete, _ in
            var combined = buffer
            if let chunk { combined.append(chunk) }

            if let status = parseStatus(data: combined, latency: Int(Date().timeIntervalSince(started) * 1000)) {
                finish(status)
                return
            }
            if isComplete || combined.isEmpty {
                finish(ServerStatus(reachable: false, motd: "", playersOnline: 0, playersMax: 0, versionName: "", latencyMilliseconds: nil))
                return
            }
            receiveLoop(connection: connection, buffer: combined, started: started, finish: finish)
        }
    }

    private static func parseStatus(data: Data, latency: Int) -> ServerStatus? {
        // Response packet: varint length, packet id (0x00), varint json length, json.
        var offset = 0
        guard let packetLength = readVarint(data, &offset), packetLength > 0 else { return nil }
        guard let packetID = readVarint(data, &offset), packetID == 0 else { return nil }
        guard let jsonLength = readVarint(data, &offset), jsonLength > 0 else { return nil }
        guard offset + jsonLength <= data.count else { return nil }
        let jsonData = data.subdata(in: offset..<(offset + jsonLength))
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { return nil }

        let motd = plainText(json["description"])
            // Strip legacy § formatting codes.
            .replacingOccurrences(of: "§.", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var online = 0
        var max = 0
        if let players = json["players"] as? [String: Any] {
            online = players["online"] as? Int ?? 0
            max = players["max"] as? Int ?? 0
        }
        let versionName = (json["version"] as? [String: Any])?["name"] as? String ?? ""

        // favicon arrives as "data:image/png;base64,<payload>".
        var favicon: String?
        if let raw = json["favicon"] as? String {
            if let comma = raw.firstIndex(of: ",") {
                favicon = String(raw[raw.index(after: comma)...])
            } else {
                favicon = raw
            }
        }

        return ServerStatus(
            reachable: true,
            motd: motd,
            playersOnline: online,
            playersMax: max,
            versionName: versionName,
            latencyMilliseconds: latency,
            faviconBase64: favicon
        )
    }

    /// Recursively flattens a Minecraft chat component (plain string,
    /// `{text, extra:[…]}` object or array) into plain text.
    private static func plainText(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let dict as [String: Any]:
            var out = (dict["text"] as? String) ?? ""
            if let extra = dict["extra"] as? [Any] {
                for item in extra { out += plainText(item) }
            }
            return out
        case let array as [Any]:
            return array.map { plainText($0) }.joined()
        default:
            return ""
        }
    }

    private static func readVarint(_ data: Data, _ offset: inout Int) -> Int? {
        var value = 0
        var shift = 0
        while offset < data.count {
            let byte = Int(data[offset])
            offset += 1
            value |= (byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
            if shift > 35 { return nil }
        }
        return nil
    }
}

/// Thread-safe one-shot flag so racing NWConnection callbacks and the
/// timeout can't resume the continuation twice.
private final class ResumeFlag: @unchecked Sendable {
    private var claimed = false
    private let lock = NSLock()

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

private extension Data {
    mutating func appendVarint(_ value: Int) {
        var v = UInt32(bitPattern: Int32(value))
        while v & 0xFFFFFF80 != 0 {
            append(UInt8(v & 0x7F | 0x80))
            v >>= 7
        }
        append(UInt8(v))
    }

    /// Minecraft protocol integers are big-endian.
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.bigEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
