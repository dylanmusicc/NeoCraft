import Foundation

actor ModrinthService {
    private var projectCache: [String: ModrinthProject] = [:]

    func search(
        query: String,
        type: ModrinthProjectType,
        gameVersion: String,
        loader: String,
        sort: ModrinthSort,
        offset: Int,
        limit: Int = 20
    ) async throws -> ModrinthSearchResponse {
        var facets: [[String]] = [["project_type:\(type.rawValue)"]]
        if !gameVersion.isEmpty {
            facets.append(["versions:\(gameVersion)"])
        }
        if type == .mod, !loader.isEmpty {
            facets.append(["categories:\(loader)"])
        }
        let facetsData = try JSONEncoder().encode(facets)
        let facetsString = String(decoding: facetsData, as: UTF8.self)

        let url = try HTTPClient.url(
            "\(AppConstants.modrinthBase)/search",
            query: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "facets", value: facetsString),
                URLQueryItem(name: "index", value: sort.rawValue),
                URLQueryItem(name: "offset", value: String(offset)),
                URLQueryItem(name: "limit", value: String(limit))
            ]
        )
        let data = try await getData(url)
        return try HTTPClient.decode(ModrinthSearchResponse.self, from: data)
    }

    func project(idOrSlug: String, useCache: Bool = true) async throws -> ModrinthProject {
        if useCache, let cached = projectCache[idOrSlug] {
            return cached
        }
        let encoded = idOrSlug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? idOrSlug
        let url = try HTTPClient.url("\(AppConstants.modrinthBase)/project/\(encoded)")
        let data = try await getData(url)
        let project = try HTTPClient.decode(ModrinthProject.self, from: data)
        projectCache[idOrSlug] = project
        projectCache[project.id] = project
        projectCache[project.slug] = project
        return project
    }

    func versions(
        projectID: String,
        gameVersion: String,
        loader: String?
    ) async throws -> [ModrinthVersion] {
        var query: [URLQueryItem] = []
        if !gameVersion.isEmpty {
            let data = try JSONEncoder().encode([gameVersion])
            query.append(URLQueryItem(name: "game_versions", value: String(decoding: data, as: UTF8.self)))
        }
        if let loader, !loader.isEmpty {
            let data = try JSONEncoder().encode([loader])
            query.append(URLQueryItem(name: "loaders", value: String(decoding: data, as: UTF8.self)))
        }
        let encoded = projectID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? projectID
        let url = try HTTPClient.url("\(AppConstants.modrinthBase)/project/\(encoded)/version", query: query)
        let data = try await getData(url)
        let versions = try HTTPClient.decode([ModrinthVersion].self, from: data)
        return versions.sorted {
            ($0.datePublished ?? "") > ($1.datePublished ?? "")
        }
    }

    func version(id: String) async throws -> ModrinthVersion {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let url = try HTTPClient.url("\(AppConstants.modrinthBase)/version/\(encoded)")
        let data = try await getData(url)
        return try HTTPClient.decode(ModrinthVersion.self, from: data)
    }

    private func getData(_ url: URL) async throws -> Data {
        var lastError: (any Error)?
        for attempt in 0..<3 {
            do {
                let response = try await HTTPClient.get(url)
                if response.statusCode == 429 || (500...599).contains(response.statusCode) {
                    lastError = NetworkError.http(status: response.statusCode, message: response.text)
                    if attempt < 2 {
                        try await Task.sleep(for: .milliseconds(700 * (attempt + 1)))
                        continue
                    }
                }
                return try HTTPClient.requireSuccess(response)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(500 * (attempt + 1)))
                    continue
                }
            }
        }
        throw lastError ?? NetworkError.transport("Modrinth request failed.")
    }
}
