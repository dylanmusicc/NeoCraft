import Foundation

enum NetworkError: LocalizedError, Sendable {
    case invalidURL(String)
    case transport(String)
    case http(status: Int, message: String)
    case decoding(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .transport(let message):
            return "Network error: \(message)"
        case .http(let status, let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Server returned HTTP \(status)." : "Server returned HTTP \(status): \(trimmed)"
        case .decoding(let message):
            return "Could not read the server response: \(message)"
        case .emptyResponse:
            return "The server returned an empty response."
        }
    }
}

struct HTTPResponse: Sendable {
    var data: Data
    var response: HTTPURLResponse

    var statusCode: Int { response.statusCode }
    var text: String { String(data: data, encoding: .utf8) ?? "" }
}

enum HTTPClient {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 900
        configuration.httpAdditionalHeaders = [
            "User-Agent": AppConstants.userAgent,
            "Accept-Encoding": "gzip"
        ]
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    static func url(_ base: String, query: [URLQueryItem] = []) throws -> URL {
        guard var components = URLComponents(string: base) else {
            throw NetworkError.invalidURL(base)
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw NetworkError.invalidURL(base)
        }
        return url
    }

    static func get(
        _ url: URL,
        headers: [String: String] = [:],
        accept: String = "application/json"
    ) async throws -> HTTPResponse {
        try await request(url, method: "GET", headers: headers, body: nil, accept: accept)
    }

    static func postForm(_ url: URL, fields: [String: String]) async throws -> HTTPResponse {
        var components = URLComponents()
        components.queryItems = fields
            .sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = (components.percentEncodedQuery ?? "").data(using: .utf8)
        return try await request(
            url,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: body,
            accept: "application/json"
        )
    }

    static func postJSON<Body: Encodable>(
        _ url: URL,
        body: Body,
        headers: [String: String] = [:]
    ) async throws -> HTTPResponse {
        let encoder = JSONEncoder()
        let data = try encoder.encode(body)
        var allHeaders = headers
        allHeaders["Content-Type"] = "application/json"
        return try await request(url, method: "POST", headers: allHeaders, body: data, accept: "application/json")
    }

    static func request(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        accept: String = "application/json"
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.transport("The server did not return an HTTP response.")
            }
            return HTTPResponse(data: data, response: http)
        } catch let error as NetworkError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NetworkError.transport(error.localizedDescription)
        }
    }

    static func requireSuccess(_ response: HTTPResponse) throws -> Data {
        guard (200...299).contains(response.statusCode) else {
            throw NetworkError.http(status: response.statusCode, message: response.text)
        }
        return response.data
    }

    static func decode<T: Decodable & Sendable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let preview = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw NetworkError.decoding("\(error.localizedDescription) \(preview)")
        }
    }

    static func getJSON<T: Decodable & Sendable>(
        _ type: T.Type,
        _ url: URL,
        headers: [String: String] = [:]
    ) async throws -> T {
        let response = try await get(url, headers: headers)
        let data = try requireSuccess(response)
        return try decode(type, from: data)
    }
}
