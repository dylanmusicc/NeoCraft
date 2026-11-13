import AVFoundation
import Foundation

enum NeoSound: Sendable {
    /// Subtle tactile tick for buttons and navigation.
    case click
    /// Soft XP-orb style chime for completed downloads/installs.
    case chime
    /// Low two-tone alert for errors and failed launches.
    case error
    /// Gentle rising blip when Minecraft starts.
    case launch
}

/// Lightweight UI sound engine. Tones are synthesized as 16-bit PCM and
/// wrapped in a minimal WAV container, so no audio assets are bundled.
/// Everything stays quiet and short — feedback, not notification.
@MainActor
final class SoundManager {
    static let shared = SoundManager()

    var enabled = true
    /// Playback volume 0…1 applied to every synthesized sound.
    var volume: Double = 0.35

    private var players: [AVAudioPlayer] = []

    func play(_ sound: NeoSound) {
        guard enabled else { return }
        let samples: [Float]
        switch sound {
        case .click: samples = Self.click()
        case .chime: samples = Self.chime()
        case .error: samples = Self.error()
        case .launch: samples = Self.launch()
        }
        guard let data = Self.wav(samples: samples, sampleRate: 22_050) else { return }
        guard let player = try? AVAudioPlayer(data: data) else { return }
        player.volume = Float(max(0, min(1, volume)))
        players.append(player)
        player.play()
        // AVAudioPlayer keeps itself alive while playing; prune finished ones.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.players.removeAll { !$0.isPlaying }
        }
    }

    // MARK: - Synthesized tones

    private static func click() -> [Float] {
        // 35 ms filtered tick: fast-decaying sine + tiny noise transient.
        let rate = 22_050.0
        let duration = 0.035
        let count = Int(rate * duration)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / rate
            let envelope = exp(-t * 160)
            let tone = sin(2 * .pi * 1900 * t) * 0.5
            let noiseSample = Float.random(in: -1...1) * 0.35
            let noise = noiseSample * Float(exp(-t * 500))
            out[i] = Float((tone + Double(noise)) * envelope * 0.5)
        }
        return out
    }

    private static func chime() -> [Float] {
        // Soft two-note XP-orb arpeggio (E6 -> B6), bell-like decay.
        let rate = 22_050.0
        let notes: [(freq: Double, start: Double, dur: Double)] = [
            (1318.5, 0.0, 0.55),
            (1975.5, 0.09, 0.6)
        ]
        let total = Int(rate * 0.75)
        var out = [Float](repeating: 0, count: total)
        for note in notes {
            let start = Int(rate * note.start)
            let len = Int(rate * note.dur)
            for i in 0..<len where start + i < total {
                let t = Double(i) / rate
                let envelope = exp(-t * 7.5) * min(1, t * 220)
                // Slight harmonic makes it bell-like instead of pure sine.
                let value = sin(2 * .pi * note.freq * t)
                    + 0.25 * sin(2 * .pi * note.freq * 2.76 * t)
                out[start + i] += Float(value * envelope * 0.28)
            }
        }
        return out
    }

    private static func error() -> [Float] {
        // Low descending square-ish buzz, clearly "negative" but soft.
        let rate = 22_050.0
        let duration = 0.28
        let count = Int(rate * duration)
        var out = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / rate
            let freq = 220.0 - 60.0 * (t / duration)
            let envelope = exp(-t * 9) * min(1, t * 160)
            // Soft-clipped sine reads as a muted buzzer.
            let raw = sin(2 * .pi * freq * t)
            let value = raw >= 0 ? 1.0 : -1.0
            out[i] = Float((value * 0.35 + raw * 0.25) * envelope * 0.5)
        }
        return out
    }

    private static func launch() -> [Float] {
        // Gentle rising "whoosh" blip: filtered noise sweep upward.
        let rate = 22_050.0
        let duration = 0.22
        let count = Int(rate * duration)
        var out = [Float](repeating: 0, count: count)
        var phase = 0.0
        for i in 0..<count {
            let t = Double(i) / rate
            let progress = t / duration
            let freq = 300.0 + 900.0 * progress
            phase += 2 * .pi * freq / rate
            let envelope = sin(.pi * progress) * 0.8
            let value = sin(phase) * 0.4 + sin(phase * 2) * 0.12
            out[i] = Float(value * envelope * 0.45)
        }
        return out
    }

    // MARK: - WAV container

    private static func wav(samples: [Float], sampleRate: Int) -> Data? {
        guard !samples.isEmpty else { return nil }
        var data = Data()
        let dataSize = UInt32(samples.count * 2)

        func appendASCII(_ string: String) {
            data.append(contentsOf: string.utf8)
        }
        func appendUInt32(_ value: UInt32) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func appendUInt16(_ value: UInt16) {
            var v = value.littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }

        appendASCII("RIFF")
        appendUInt32(36 + dataSize)
        appendASCII("WAVE")
        appendASCII("fmt ")
        appendUInt32(16)          // PCM chunk size
        appendUInt16(1)           // PCM format
        appendUInt16(1)           // mono
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(sampleRate * 2)) // byte rate
        appendUInt16(2)           // block align
        appendUInt16(16)          // bits per sample
        appendASCII("data")
        appendUInt32(dataSize)

        for sample in samples {
            let clamped = max(-1, min(1, sample))
            var pcm = Int16((clamped * 32767).rounded()).littleEndian
            withUnsafeBytes(of: &pcm) { data.append(contentsOf: $0) }
        }
        return data
    }
}
