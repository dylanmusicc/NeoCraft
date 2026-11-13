import CryptoKit
import Foundation

struct MinecraftAccount: Identifiable, Codable, Hashable, Sendable {
    var id: String { uuid }
    var uuid: String
    var name: String
    var skinURL: URL?
    var addedAt: Date
    var lastUsed: Date?
    /// Offline (cracked-style) profiles launch without Xbox Live or Minecraft
    /// Services. Their UUID is derived deterministically from the username.
    var isOffline: Bool = false

    init(uuid: String, name: String, skinURL: URL?, addedAt: Date, lastUsed: Date?, isOffline: Bool = false) {
        self.uuid = uuid
        self.name = name
        self.skinURL = skinURL
        self.addedAt = addedAt
        self.lastUsed = lastUsed
        self.isOffline = isOffline
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uuid = try container.decode(String.self, forKey: .uuid)
        name = try container.decode(String.self, forKey: .name)
        skinURL = try container.decodeIfPresent(URL.self, forKey: .skinURL)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
        isOffline = try container.decodeIfPresent(Bool.self, forKey: .isOffline) ?? false
    }

    var shortUUID: String {
        String(uuid.prefix(8))
    }

    var kindTitle: String {
        isOffline ? "Offline" : "Microsoft"
    }

    var kindSymbol: String {
        isOffline ? "bolt.horizontal.circle" : "person.badge.key"
    }
}

/// Deterministic identities for local offline profiles.
///
/// Minecraft derives an offline player's UUID by taking the MD5 of
/// `"OfflinePlayer:" + username` and stamping the version-3 / RFC-4122 variant
/// bits — the same name-based UUID scheme Mojang uses.
enum OfflineIdentity {
    static func isValidUsername(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...16).contains(trimmed.count) else { return false }
        return trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static func uuid(for name: String) -> String {
        let digest = Insecure.MD5.hash(data: Data("OfflinePlayer:\(name)".utf8))
        var bytes = [UInt8](digest)
        bytes[6] = (bytes[6] & 0x0F) | 0x30
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        var uuid = ""
        for (offset, character) in hex.enumerated() {
            if offset == 8 || offset == 12 || offset == 16 || offset == 20 {
                uuid.append("-")
            }
            uuid.append(character)
        }
        return uuid
    }
}

struct MinecraftSession: Sendable {
    var accessToken: String
    var uuid: String
    var name: String
    var xuid: String
    var expiresAt: Date
}

struct StoredAuth: Codable, Sendable {
    var msaAccessToken: String
    var msaRefreshToken: String
    var msaExpiresAt: Date
    var minecraftAccessToken: String
    var minecraftExpiresAt: Date
    var xuid: String
    var username: String
}

struct MSAToken: Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

struct DeviceCode: Codable, Sendable {
    var deviceCode: String
    var userCode: String
    var verificationURI: String
    var expiresIn: Int
    var interval: Int
    var message: String

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
        case message
    }
}

enum AuthError: LocalizedError, Sendable {
    case invalidResponse
    case deviceCodeExpired
    case authorizationDeclined
    case microsoftRejected(String)
    case noXboxProfile
    case xboxRegionUnavailable
    case childAccount
    case xboxBanned
    case xboxError(code: String, message: String)
    case noMinecraftProfile
    case noGameOwnership
    case reauthenticationRequired
    case offlineAccount
    case canceled

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Microsoft returned an unexpected response. Please try again."
        case .deviceCodeExpired:
            return "The sign-in code expired. Start sign-in again to get a fresh code."
        case .authorizationDeclined:
            return "The Microsoft sign-in was cancelled from the browser."
        case .microsoftRejected(let detail):
            return detail.isEmpty ? "Microsoft rejected the sign-in request." : detail
        case .noXboxProfile:
            return "This Microsoft account does not have an Xbox profile yet. Sign in at xbox.com once, then try again."
        case .xboxRegionUnavailable:
            return "Xbox Live is not available in this account's region. Change the Microsoft account region and try again."
        case .childAccount:
            return "This is a child account. A parent must grant permission at account.xbox.com before a third-party launcher can sign in."
        case .xboxBanned:
            return "This Xbox account is suspended and cannot sign in to Minecraft."
        case .xboxError(let code, let message):
            return "Xbox authorization failed (XErr \(code)). \(message)"
        case .noMinecraftProfile:
            return "This Microsoft account does not own Minecraft: Java Edition."
        case .noGameOwnership:
            return "Minecraft: Java Edition was not found for this account."
        case .reauthenticationRequired:
            return "Your Microsoft session expired. Sign in again to continue."
        case .offlineAccount:
            return "Offline accounts don't have a Minecraft Services profile."
        case .canceled:
            return "Sign-in was cancelled."
        }
    }
}
