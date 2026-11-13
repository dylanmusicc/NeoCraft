import Foundation

enum OptionsTweaker {
    static func apply(mode: ThermalMode, settings: AppSettings, instance: GameInstance? = nil, to gameDirectory: URL) throws {
        try FileManager.default.createDirectory(at: gameDirectory, withIntermediateDirectories: true)
        let file = gameDirectory.appendingPathComponent("options.txt", isDirectory: false)
        var lines: [String] = []

        if FileManager.default.fileExists(atPath: file.path),
           let contents = try? String(contentsOf: file, encoding: .utf8) {
            lines = contents.components(separatedBy: .newlines)
        }

        var values: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            let value = String(line[line.index(after: colon)...])
            values[key] = value
        }

        switch mode {
        case .coolQuiet:
            values["maxFps"] = "60"
            values["renderDistance"] = "10"
            values["simulationDistance"] = "8"
            values["enableVsync"] = "true"
        case .maxPerformance:
            values["maxFps"] = "260"
            values["renderDistance"] = "12"
            values["simulationDistance"] = "10"
            values["enableVsync"] = "false"
        }

        // Manual render-distance override wins over the thermal profile —
        // e.g. 32 chunks on the MacBook Neo stays smooth with G1GC + capped heap.
        if settings.renderDistanceChunks > 0 {
            values["renderDistance"] = String(min(32, settings.renderDistanceChunks))
        }

        // GUI scale: 0 = auto, 1 = small, 2 = normal, 3 = large. Per-instance
        // override wins over the global setting; both trade interface
        // sharpness for GPU headroom on the fanless A18.
        let guiScale = instance?.guiScale ?? settings.guiScale
        if guiScale > 0 {
            values["guiScale"] = String(min(guiScale, 3))
        }

        var output: [String] = []
        var written = Set<String>()
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else {
                output.append(line)
                continue
            }
            let key = String(line[..<colon])
            if let value = values[key] {
                output.append("\(key):\(value)")
                written.insert(key)
            } else if !line.isEmpty {
                output.append(line)
            }
        }
        for (key, value) in values.sorted(by: { $0.key < $1.key }) where !written.contains(key) {
            output.append("\(key):\(value)")
        }

        let text = output.joined(separator: "\n") + "\n"
        try text.write(to: file, atomically: true, encoding: .utf8)
    }
}
