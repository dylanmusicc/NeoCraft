import Foundation

// MARK: - Models

struct MCProfile: Decodable, Sendable {
    var id: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case id, name
    }
}

struct MCPlayerAttributes: Decodable, Sendable {
    var privileges: Privileges?

    struct Privileges: Decodable, Sendable {
        var onlineChat: Bool?
        var multiplayerServer: Bool?
        var multiplayerRealms: Bool?
        var telemetry: Bool?
        var nicknameChange: Bool?
    }
}

struct MCSkin: Decodable, Identifiable, Sendable {
    var id: String
    var variant: String   // "classic" | "slim"
    var url: String

    var imageURL: URL? { URL(string: url) }
}

struct MCCape: Decodable, Identifiable, Sendable {
    var id: String
    var alias: String?
    var url: String

    var imageURL: URL? { URL(string: url) }
}

enum MinecraftServicesError: LocalizedError, Sendable {
    case unauthorized
    case http(Int, String)
    case decode
    case uploadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Your Microsoft session expired. Sign in again."
        case .http(let code, let message):
            return "Minecraft Services error \(code): \(message)"
        case .decode:
            return "Minecraft Services returned an unexpected response."
        case .uploadFailed(let detail):
            return "Skin upload failed: \(detail)"
        }
    }
}

/// Talks to api.minecraftservices.com with the Minecraft access token that
/// the existing Microsoft auth flow already produces. Powers the Account /
/// Skin Studio section: profile, skins, capes, uploads and arm variants.
actor MinecraftServices {
    private let base = "https://api.minecraftservices.com"

    // MARK: - Reads

    func profile(accessToken: String) async throws -> MCProfile {
        try await get("/minecraft/profile", token: accessToken)
    }

    func attributes(accessToken: String) async throws -> MCPlayerAttributes {
        try await get("/player/attributes", token: accessToken)
    }

    func skins(accessToken: String) async throws -> [MCSkin] {
        try await get("/player/skins", token: accessToken)
    }

    func capes(accessToken: String) async throws -> [MCCape] {
        try await get("/player/capes", token: accessToken)
    }

    // MARK: - Writes

    /// Uploads a PNG skin and makes it active. `variant` selects the arm
    /// model: "classic" (Steve) or "slim" (Alex).
    func uploadSkin(pngData: Data, variant: String, accessToken: String) async throws {
        struct Body: Encodable {
            var variant: String
            var data: String
        }
        let body = try JSONEncoder().encode(Body(variant: variant, data: pngData.base64EncodedString()))
        _ = try await send("PUT", "/player/skins", token: accessToken, body: body)
    }

    /// Activates a previously uploaded skin by id, or hides all skins when nil.
    func equipSkin(skinId: String?, variant: String?, accessToken: String) async throws {
        struct Body: Encodable {
            var skinId: String?
            var variant: String?
        }
        let body = try JSONEncoder().encode(Body(skinId: skinId, variant: variant))
        _ = try await send("PUT", "/player/skins", token: accessToken, body: body)
    }

    /// Equips a cape by id; nil removes the currently equipped cape.
    func equipCape(capeId: String?, accessToken: String) async throws {
        struct Body: Encodable {
            var capeId: String?
        }
        let body = try JSONEncoder().encode(Body(capeId: capeId))
        _ = try await send("PUT", "/player/capes", token: accessToken, body: body)
    }

    // MARK: - HTTP

    private func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        let data = try await send("GET", path, token: token, body: nil)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MinecraftServicesError.decode
        }
    }

    @discardableResult
    private func send(_ method: String, _ path: String, token: String, body: Data?) async throws -> Data {
        guard let url = URL(string: base + path) else {
            throw MinecraftServicesError.decode
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("NeoCraft/\(AppConstants.version)", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MinecraftServicesError.decode
        }
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw MinecraftServicesError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw MinecraftServicesError.http(http.statusCode, String(message.prefix(200)))
        }
    }
}
