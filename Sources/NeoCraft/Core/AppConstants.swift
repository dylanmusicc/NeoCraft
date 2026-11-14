import Foundation

enum AppConstants {
    static let appName = "NeoCraft"
    static let displayName = "NeoCraft"
    static let version = "2.3.0"
    static let build = "3"
    static let bundleIdentifier = "com.neocraft.launcher"
    static let userAgent = "NeoCraft/\(version) (macOS; Minecraft Launcher; +https://modrinth.com)"
    static let minimumMacOS = "14.0"

    /// Public Microsoft identity client registration used for the device-code flow.
    /// It can be overridden for development without rebuilding by setting
    /// NEOCRAFT_MSA_CLIENT_ID in the environment.
    static let defaultMSAClientID = "c36a9fb6-4f2a-41ff-90bd-ae7cc92031eb"

    static var msaClientID: String {
        if let override = ProcessInfo.processInfo.environment["NEOCRAFT_MSA_CLIENT_ID"],
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return defaultMSAClientID
    }

    static let microsoftAuthorizeBase = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
    static let xboxUserAuthURL = "https://user.auth.xboxlive.com/user/authenticate"
    static let xstsAuthURL = "https://xsts.auth.xboxlive.com/xsts/authorize"
    static let minecraftLoginURL = "https://api.minecraftservices.com/authentication/login_with_xbox"
    static let minecraftProfileURL = "https://api.minecraftservices.com/minecraft/profile"

    static let versionManifestURL = "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
    static let fabricMetaBase = "https://meta.fabricmc.net/v2"
    static let modrinthBase = "https://api.modrinth.com/v2"
    static let adoptiumBase = "https://api.adoptium.net/v3"
    static let launcherContentBase = "https://launchercontent.mojang.com/v2"
}
