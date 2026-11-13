import os

extension Logger {
    static let session = Logger(subsystem: "dev.siliconbedrock", category: "session")
    static let install = Logger(subsystem: "dev.siliconbedrock", category: "install")
}
