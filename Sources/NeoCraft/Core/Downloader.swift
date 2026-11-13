import CryptoKit
import Foundation

enum HashAlgorithm: String, Sendable {
    case sha1
    case sha256
}

struct FileChecksum: Sendable {
    var algorithm: HashAlgorithm
    var value: String
}

struct DownloadRequest: Sendable {
    var url: URL
    var destination: URL
    var checksum: FileChecksum?
    var expectedSize: Int64?
    var label: String

    init(
        url: URL,
        destination: URL,
        checksum: FileChecksum? = nil,
        expectedSize: Int64? = nil,
        label: String = ""
    ) {
        self.url = url
        self.destination = destination
        self.checksum = checksum
        self.expectedSize = expectedSize
        self.label = label
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let handler: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var lastFraction: Double = -1
    private var lastTime = Date.distantPast

    init(handler: @escaping @Sendable (Double) -> Void) {
        self.handler = handler
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
        lock.lock()
        let now = Date()
        let shouldReport = fraction - lastFraction >= 0.005 || now.timeIntervalSince(lastTime) > 0.4 || fraction >= 1
        if shouldReport {
            lastFraction = fraction
            lastTime = now
        }
        lock.unlock()
        if shouldReport {
            handler(fraction)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Completion-handler based tasks receive the file in their completion
        // block. This stub satisfies URLSessionDownloadDelegate.
    }
}

enum Downloader {
    /// A cached file counts as valid only when its size matches *and* its
    /// checksum verifies — a same-sized but corrupted download must never be
    /// silently reused.
    static func isValid(_ request: DownloadRequest) -> Bool {
        guard FileManager.default.fileExists(atPath: request.destination.path) else { return false }
        if let expectedSize = request.expectedSize {
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: request.destination.path),
                  let size = attributes[.size] as? NSNumber,
                  size.int64Value == expectedSize else {
                return false
            }
        }
        if let checksum = request.checksum {
            guard let actual = try? hashFile(request.destination, algorithm: checksum.algorithm),
                  actual.caseInsensitiveCompare(checksum.value) == .orderedSame else {
                return false
            }
        }
        return true
    }

    static func download(
        _ request: DownloadRequest,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        try FileManager.default.createDirectory(
            at: request.destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if isValid(request) {
            progress?(1)
            return
        }

        try FileManager.default.createDirectory(at: AppPaths.cache, withIntermediateDirectories: true)
        let temporary = AppPaths.cache.appendingPathComponent("\(UUID().uuidString).download")
        let http = try await fetch(request.url, to: temporary, progress: progress)

        guard (200...299).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temporary)
            let message = String(data: http.data.prefix(600), encoding: .utf8) ?? ""
            throw NetworkError.http(status: http.statusCode, message: message)
        }

        if let expectedSize = request.expectedSize {
            let attributes = try FileManager.default.attributesOfItem(atPath: temporary.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard size == expectedSize else {
                try? FileManager.default.removeItem(at: temporary)
                throw NetworkError.transport("Downloaded size did not match for \(request.label.isEmpty ? request.url.lastPathComponent : request.label) (expected \(expectedSize), got \(size)).")
            }
        }

        if let checksum = request.checksum {
            let actual = try hashFile(temporary, algorithm: checksum.algorithm)
            guard actual.caseInsensitiveCompare(checksum.value) == .orderedSame else {
                try? FileManager.default.removeItem(at: temporary)
                throw NetworkError.transport("Checksum mismatch for \(request.label.isEmpty ? request.destination.lastPathComponent : request.label).")
            }
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: request.destination.path) {
            try fileManager.removeItem(at: request.destination)
        }
        try fileManager.moveItem(at: temporary, to: request.destination)
        progress?(1)
    }

    static func downloadMany(
        _ requests: [DownloadRequest],
        concurrency: Int,
        progress: @escaping @Sendable (Int, Int, String) -> Void
    ) async throws {
        let total = requests.count
        guard total > 0 else { return }

        // Partition once — isValid may hash the file, so don't run it twice.
        var cached: [DownloadRequest] = []
        var pending: [DownloadRequest] = []
        for request in requests {
            if isValid(request) {
                cached.append(request)
            } else {
                pending.append(request)
            }
        }
        if !cached.isEmpty {
            progress(cached.count, total, "Using \(cached.count) cached files")
        }
        guard !pending.isEmpty else { return }

        let workerCount = max(1, min(concurrency, pending.count))
        let counter = ProgressCounter(total: total, initial: cached.count, handler: progress)

        try await withThrowingTaskGroup(of: Void.self) { group in
            var nextIndex = 0
            for _ in 0..<workerCount {
                let request = pending[nextIndex]
                nextIndex += 1
                group.addTask {
                    try await download(request)
                    await counter.complete(request.label)
                }
            }

            while let _ = try await group.next() {
                if nextIndex < pending.count {
                    let request = pending[nextIndex]
                    nextIndex += 1
                    group.addTask {
                        try await download(request)
                        await counter.complete(request.label)
                    }
                }
            }
        }
    }

    static func hashFile(_ url: URL, algorithm: HashAlgorithm) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        switch algorithm {
        case .sha1:
            var hasher = Insecure.SHA1()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        case .sha256:
            var hasher = SHA256()
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
    }

    private static func fetch(
        _ url: URL,
        to destination: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.timeoutInterval = 900
        request.setValue(AppConstants.userAgent, forHTTPHeaderField: "User-Agent")

        if progress == nil {
            return try await fastFetch(request, to: destination)
        }

        let delegate = progress.map { handler in
            DownloadProgressDelegate(handler: handler)
        }
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 1800
        configuration.waitsForConnectivity = true
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )

        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: request) { temporaryURL, response, error in
                defer { session.finishTasksAndInvalidate() }
                if let error {
                    if let urlError = error as? URLError, urlError.code == .cancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: NetworkError.transport(error.localizedDescription))
                    }
                    return
                }
                guard let http = response as? HTTPURLResponse else {
                    continuation.resume(throwing: NetworkError.transport("No HTTP response."))
                    return
                }
                guard let temporaryURL else {
                    continuation.resume(throwing: NetworkError.emptyResponse)
                    return
                }
                do {
                    try stage(temporaryURL, at: destination)
                    let data = errorBody(for: http, at: destination)
                    continuation.resume(returning: HTTPResponse(data: data, response: http))
                } catch {
                    continuation.resume(throwing: NetworkError.transport(error.localizedDescription))
                }
            }
            task.resume()
        }
    }

    /// Downloads without creating a session per file. This is used for the thousands
    /// of small asset files, so the launcher stays well below its memory budget.
    private static func fastFetch(_ request: URLRequest, to destination: URL) async throws -> HTTPResponse {
        do {
            let (temporaryURL, response) = try await HTTPClient.session.download(for: request)
            guard let http = response as? HTTPURLResponse else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw NetworkError.transport("No HTTP response.")
            }
            if (200...299).contains(http.statusCode) {
                try stage(temporaryURL, at: destination)
                return HTTPResponse(data: Data(), response: http)
            }
            let data = (try? Data(contentsOf: temporaryURL)).map { Data($0.prefix(65_536)) } ?? Data()
            try? FileManager.default.removeItem(at: temporaryURL)
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

    private static func stage(_ temporaryURL: URL, at destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
    }

    private static func errorBody(for response: HTTPURLResponse, at url: URL) -> Data {
        guard !(200...299).contains(response.statusCode) else { return Data() }
        return (try? Data(contentsOf: url)).map { Data($0.prefix(65_536)) } ?? Data()
    }
}

actor ProgressCounter {
    private let total: Int
    private var completed: Int
    private let handler: @Sendable (Int, Int, String) -> Void

    init(total: Int, initial: Int, handler: @escaping @Sendable (Int, Int, String) -> Void) {
        self.total = max(total, 1)
        self.completed = initial
        self.handler = handler
    }

    func complete(_ label: String) {
        completed += 1
        handler(min(completed, total), total, label)
    }
}
