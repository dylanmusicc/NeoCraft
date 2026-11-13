import Foundation

enum ConsoleLevel: Sendable {
    case info
    case warning
    case error
    case game

    var symbol: String {
        switch self {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        case .game: "gamecontroller"
        }
    }
}

struct ConsoleEntry: Identifiable, Sendable {
    let id = UUID()
    var date: Date
    var text: String
    var level: ConsoleLevel

    init(_ text: String, level: ConsoleLevel = .info, date: Date = Date()) {
        self.text = text
        self.level = level
        self.date = date
    }
}

struct Activity: Identifiable, Sendable {
    enum State: Sendable {
        case running
        case success
        case failure
    }

    let id = UUID()
    var title: String
    var detail: String
    var progress: Double?
    var state: State
    var startedAt: Date

    init(title: String, detail: String = "Starting…", progress: Double? = nil, state: State = .running) {
        self.title = title
        self.detail = detail
        self.progress = progress
        self.state = state
        self.startedAt = Date()
    }
}

struct ProgressUpdate: Sendable {
    var fraction: Double?
    var detail: String

    init(fraction: Double?, detail: String) {
        self.fraction = fraction
        self.detail = detail
    }
}

struct AppAlert: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

enum AppError: LocalizedError, Sendable {
    case noInstance
    case noAccount
    case alreadyRunning
    case invalidJava(String)
    case javaTooOld(required: Int, found: Int)
    case missingFile(String)
    case install(String)
    case backupFailed(String)

    var errorDescription: String? {
        switch self {
        case .noInstance:
            return "Create or select an instance first."
        case .noAccount:
            return "Sign in with a Microsoft account to play Minecraft."
        case .alreadyRunning:
            return "Minecraft is already running."
        case .invalidJava(let path):
            return "The selected Java runtime is not executable: \(path)"
        case .javaTooOld(let required, let found):
            return "This version needs Java \(required) or newer, but the selected runtime is Java \(found). Choose Automatic in Settings to let NeoCraft install the correct runtime."
        case .missingFile(let path):
            return "A required file is missing: \(path)"
        case .install(let detail):
            return detail
        case .backupFailed(let detail):
            return "World backup failed: \(detail)"
        }
    }
}
