import Darwin
import Foundation

/// Incrementally decodes UTF-8 across arbitrary pipe-read boundaries. A
/// multi-byte character split between two `readabilityHandler` callbacks is
/// buffered instead of producing mojibake or being dropped.
private final class UTF8StreamDecoder: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = Data()

    /// Returns the decoded text for `chunk`, holding back any trailing bytes
    /// that form an incomplete UTF-8 sequence for the next call.
    func append(_ chunk: Data) -> String {
        lock.lock()
        pending.append(chunk)
        let validLength = Self.validUTF8PrefixLength(pending)
        let complete = pending.prefix(validLength)
        pending = Data(pending.suffix(from: pending.startIndex + validLength))
        lock.unlock()
        guard !complete.isEmpty else { return "" }
        return String(decoding: complete, as: UTF8.self)
    }

    func flush() -> String {
        lock.lock()
        defer { lock.unlock() }
        guard !pending.isEmpty else { return "" }
        let rest = pending
        pending = Data()
        return String(decoding: rest, as: UTF8.self)
    }

    /// Length of the longest prefix that ends on a complete UTF-8 boundary.
    private static func validUTF8PrefixLength(_ data: Data) -> Int {
        var index = data.count
        var continuations = 0
        // Walk back over trailing continuation bytes (10xxxxxx), max 3.
        while index > 0 && continuations < 3 {
            let byte = data[index - 1]
            guard byte & 0xC0 == 0x80 else { break }
            continuations += 1
            index -= 1
        }
        guard index > 0 else { return data.count }
        let lead = data[index - 1]
        let expectedTotal: Int
        switch lead {
        case 0x00...0x7F: expectedTotal = 1
        case 0xC0...0xDF: expectedTotal = 2
        case 0xE0...0xEF: expectedTotal = 3
        case 0xF0...0xF7: expectedTotal = 4
        default: return data.count // invalid lead byte — decode lossily downstream
        }
        // The trailing run holds `continuations` bytes belonging to the
        // sequence led by `lead`. If fewer than expected-1 are present, the
        // sequence is incomplete and the prefix must end before `lead`.
        let present = continuations + 1
        return present < expectedTotal ? index - 1 : data.count
    }
}

actor GameProcess {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutDecoder = UTF8StreamDecoder()
    private var stderrDecoder = UTF8StreamDecoder()
    private var outputHandler: (@Sendable (String, ConsoleLevel) -> Void)?
    private var exitCode: Int32?
    private var exitContinuation: CheckedContinuation<Int32, Never>?

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    func start(
        command: LaunchCommand,
        log: @escaping @Sendable (String, ConsoleLevel) -> Void
    ) throws {
        if process?.isRunning == true {
            throw AppError.alreadyRunning
        }

        try FileManager.default.createDirectory(at: command.workingDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        process.currentDirectoryURL = command.workingDirectory
        process.environment = command.environment
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutDecoder = UTF8StreamDecoder()
        let stderrDecoder = UTF8StreamDecoder()
        self.stdoutDecoder = stdoutDecoder
        self.stderrDecoder = stderrDecoder
        outputHandler = log
        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = stdoutDecoder.append(data)
            guard !text.isEmpty else { return }
            log(text, .game)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = stderrDecoder.append(data)
            guard !text.isEmpty else { return }
            log(text, .error)
        }

        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { await self?.handleTermination(status) }
        }

        self.process = process
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        exitCode = nil

        do {
            try process.run()
        } catch {
            self.process = nil
            outputHandler = nil
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
    }

    func waitForExit() async -> Int32 {
        if let exitCode {
            return exitCode
        }
        return await withCheckedContinuation { continuation in
            if let exitCode {
                continuation.resume(returning: exitCode)
            } else {
                exitContinuation = continuation
            }
        }
    }

    func terminate() async {
        guard let process, process.isRunning else { return }
        process.terminate()
        // Give Minecraft a chance to flush its worlds, but don't make the user
        // wait the full grace period if it exits sooner.
        for _ in 0..<80 {
            if !process.isRunning { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }

    private func handleTermination(_ status: Int32) {
        exitCode = status
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        // Drain whatever the child wrote right before exiting — the
        // readability handlers may not have delivered the final bytes yet —
        // then flush any incomplete trailing UTF-8 sequence.
        if let log = outputHandler {
            if let pipe = stdoutPipe {
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                let tail = stdoutDecoder.append(rest) + stdoutDecoder.flush()
                if !tail.isEmpty { log(tail, .game) }
            }
            if let pipe = stderrPipe {
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                let tail = stderrDecoder.append(rest) + stderrDecoder.flush()
                if !tail.isEmpty { log(tail, .error) }
            }
        }
        outputHandler = nil

        try? stdoutPipe?.fileHandleForReading.close()
        try? stderrPipe?.fileHandleForReading.close()
        stdoutPipe = nil
        stderrPipe = nil
        process = nil
        exitContinuation?.resume(returning: status)
        exitContinuation = nil
    }
}
