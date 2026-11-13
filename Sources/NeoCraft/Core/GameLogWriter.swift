import Foundation

/// Writes the live game console to a per-launch log file without blocking the
/// main actor. The launcher keeps the console in memory for the UI and mirrors
/// it to disk so players can share a crash log after the game exits.
final class GameLogWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var closed = false

    let url: URL

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
    }

    func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        try? handle.write(contentsOf: data)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        try? handle.synchronize()
        try? handle.close()
    }

    deinit {
        close()
    }
}
