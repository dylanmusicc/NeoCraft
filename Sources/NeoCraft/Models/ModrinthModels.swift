import Foundation

enum ModrinthProjectType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case mod
    case resourcepack
    case shader
    case datapack
    case modpack
    case plugin

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mod: "Mods"
        case .resourcepack: "Resource Packs"
        case .shader: "Shaders"
        case .datapack: "Data Packs"
        case .modpack: "Modpacks"
        case .plugin: "Plugins"
        }
    }

    var singular: String {
        switch self {
        case .mod: "Mod"
        case .resourcepack: "Resource Pack"
        case .shader: "Shader"
        case .datapack: "Data Pack"
        case .modpack: "Modpack"
        case .plugin: "Plugin"
        }
    }

    var symbol: String {
        switch self {
        case .mod: "puzzlepiece.extension.fill"
        case .resourcepack: "paintpalette.fill"
        case .shader: "camera.filters"
        case .datapack: "cylinder.split.1x2.fill"
        case .modpack: "shippingbox.fill"
        case .plugin: "server.rack"
        }
    }

    var folderName: String {
        switch self {
        case .mod: "mods"
        case .resourcepack: "resourcepacks"
        case .shader: "shaderpacks"
        case .datapack: "datapacks"
        case .modpack: "modpacks"
        case .plugin: "plugins"
        }
    }

    static var browserTypes: [ModrinthProjectType] { [.mod, .resourcepack, .shader] }

    /// Reverse lookup used when only the on-disk folder name is known
    /// (e.g. from the installed-content manifest).
    init?(folderName: String) {
        switch folderName {
        case "mods": self = .mod
        case "resourcepacks": self = .resourcepack
        case "shaderpacks": self = .shader
        case "datapacks": self = .datapack
        case "modpacks": self = .modpack
        case "plugins": self = .plugin
        default: return nil
        }
    }
}

enum ModrinthSort: String, CaseIterable, Identifiable, Hashable, Sendable {
    case relevance
    case downloads
    case follows
    case newest
    case updated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: "Relevance"
        case .downloads: "Downloads"
        case .follows: "Followers"
        case .newest: "Newest"
        case .updated: "Recently Updated"
        }
    }
}

struct ModrinthSearchResponse: Decodable, Sendable {
    var hits: [ModrinthSearchHit]
    var offset: Int
    var limit: Int
    var totalHits: Int

    enum CodingKeys: String, CodingKey {
        case hits, offset, limit
        case totalHits = "total_hits"
    }
}

struct ModrinthSearchHit: Decodable, Identifiable, Hashable, Sendable {
    var projectID: String
    var slug: String
    var title: String
    var description: String
    var author: String?
    var projectType: String
    var categories: [String]
    var displayCategories: [String]?
    var downloads: Int
    var follows: Int
    var iconURL: String?
    var latestVersion: String?
    var versions: [String]?
    var license: String?
    var color: Int?

    var id: String { projectID }
    var type: ModrinthProjectType { ModrinthProjectType(rawValue: projectType) ?? .mod }
    var icon: URL? { iconURL.flatMap(URL.init(string:)) }

    enum CodingKeys: String, CodingKey {
        case slug, title, description, author, categories, downloads, follows, versions, license, color
        case projectID = "project_id"
        case projectType = "project_type"
        case displayCategories = "display_categories"
        case iconURL = "icon_url"
        case latestVersion = "latest_version"
    }
}

struct ModrinthProject: Decodable, Identifiable, Sendable {
    var id: String
    var slug: String
    var title: String
    var description: String
    var projectType: String
    var categories: [String]
    var clientSide: String?
    var serverSide: String?
    var downloads: Int
    var followers: Int
    var iconURL: String?
    var body: String?
    var gallery: [ModrinthGalleryItem]?
    var sourceURL: String?
    var issuesURL: String?
    var wikiURL: String?
    var discordURL: String?
    var gameVersions: [String]?
    var loaders: [String]?
    var license: ModrinthLicense?

    var type: ModrinthProjectType { ModrinthProjectType(rawValue: projectType) ?? .mod }
    var icon: URL? { iconURL.flatMap(URL.init(string:)) }
    var webURL: URL? { URL(string: "https://modrinth.com/\(projectType)/\(slug)") }

    enum CodingKeys: String, CodingKey {
        case id, slug, title, description, categories, downloads, followers, body, gallery, loaders, license
        case projectType = "project_type"
        case clientSide = "client_side"
        case serverSide = "server_side"
        case iconURL = "icon_url"
        case sourceURL = "source_url"
        case issuesURL = "issues_url"
        case wikiURL = "wiki_url"
        case discordURL = "discord_url"
        case gameVersions = "game_versions"
    }
}

struct ModrinthLicense: Decodable, Sendable {
    var id: String?
    var name: String?
    var url: String?
}

struct ModrinthGalleryItem: Decodable, Sendable, Identifiable {
    var url: String
    var featured: Bool?
    var title: String?
    var description: String?
    var id: String { url }
}

struct ModrinthVersion: Decodable, Identifiable, Sendable {
    var id: String
    var projectID: String
    var name: String
    var versionNumber: String
    var gameVersions: [String]
    var loaders: [String]
    var dependencies: [ModrinthDependency]
    var files: [ModrinthFile]
    var datePublished: String?
    var changelog: String?

    var primaryFile: ModrinthFile? {
        files.first(where: { $0.primary == true }) ?? files.first
    }

    enum CodingKeys: String, CodingKey {
        case id, name, gameVersions, loaders, dependencies, files, changelog
        case projectID = "project_id"
        case versionNumber = "version_number"
        case datePublished = "date_published"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        projectID = try container.decode(String.self, forKey: .projectID)
        name = try container.decode(String.self, forKey: .name)
        versionNumber = try container.decode(String.self, forKey: .versionNumber)
        gameVersions = try container.decodeIfPresent([String].self, forKey: .gameVersions) ?? []
        loaders = try container.decodeIfPresent([String].self, forKey: .loaders) ?? []
        dependencies = try container.decodeIfPresent([ModrinthDependency].self, forKey: .dependencies) ?? []
        files = try container.decodeIfPresent([ModrinthFile].self, forKey: .files) ?? []
        datePublished = try container.decodeIfPresent(String.self, forKey: .datePublished)
        changelog = try container.decodeIfPresent(String.self, forKey: .changelog)
    }
}

struct ModrinthDependency: Decodable, Sendable {
    var versionID: String?
    var projectID: String?
    var fileName: String?
    var dependencyType: String?

    var isRequired: Bool { dependencyType == "required" }

    enum CodingKeys: String, CodingKey {
        case fileName = "file_name"
        case versionID = "version_id"
        case projectID = "project_id"
        case dependencyType = "dependency_type"
    }
}

struct ModrinthFile: Decodable, Sendable {
    var url: String
    var filename: String
    var primary: Bool?
    var size: Int64?
    var hashes: [String: String]?
}

enum ModrinthError: LocalizedError, Sendable {
    case invalidURL
    case noCompatibleVersion(project: String, gameVersion: String, loader: String)
    case noFiles(project: String)
    case dependencyResolution(String)
    case requiresFabric
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Modrinth request URL could not be built."
        case .noCompatibleVersion(let project, let gameVersion, let loader):
            return "\(project) has no \(loader.isEmpty ? "" : loader + " ")version compatible with Minecraft \(gameVersion)."
        case .noFiles(let project):
            return "\(project) did not provide a downloadable file."
        case .dependencyResolution(let detail):
            return "Could not resolve a required dependency: \(detail)"
        case .requiresFabric:
            return "This content requires a Fabric instance. Create a Fabric instance or switch this instance to Fabric first."
        case .installFailed(let detail):
            return "Installation failed: \(detail)"
        }
    }
}
