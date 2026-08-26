import AVFoundation
import Foundation

/// The Tesla-style limit chime, through whatever the phone is playing to
/// (the car, usually), mixed over music without ducking it.
///
/// Sound source: a bundled audio file named `chime-limit` (wav/caf/mp3)
/// wins if present — drop one into OpenRoadie/Audio/ to replace the
/// sound with zero code changes. Fallback is the generated two-tone
/// ding below (no asset, fully deterministic).
@MainActor
final class ChimePlayer {
    private var player: AVAudioPlayer?

    /// The bundled custom chime, if the project carries one.
    static func customChimeURL() -> URL? {
        for ext in ["wav", "caf", "mp3", "m4a"] {
            if let url = Bundle.main.url(forResource: "chime-limit", withExtension: ext) {
                return url
            }
        }
        return nil
    }

    func play() {
        // Mix over music; a short chime shouldn't duck anything.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .default, options: [.mixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
        if player == nil {
            if let url = Self.customChimeURL() {
                player = try? AVAudioPlayer(contentsOf: url)
            }
            if player == nil {
                player = try? AVAudioPlayer(data: Self.chimeWAV())
            }
            player?.prepareToPlay()
        }
        player?.currentTime = 0
        player?.play()
    }

    /// A gentle two-note chime (A5 → E6) with exponential decay, rendered as
    /// a 16-bit mono WAV. Static and pure for testability.
    static func chimeWAV(sampleRate: Int = 44_100) -> Data {
        let noteDuration = 0.22
        let notes: [Double] = [880.0, 1318.5]
        var samples: [Int16] = []
        samples.reserveCapacity(Int(Double(sampleRate) * noteDuration) * notes.count)

        for (index, frequency) in notes.enumerated() {
            let count = Int(Double(sampleRate) * noteDuration)
            for n in 0..<count {
                let t = Double(n) / Double(sampleRate)
                let envelope = exp(-6.0 * t / noteDuration)
                // Slight overlap: the second note starts while the first rings.
                let value = sin(2 * .pi * frequency * t) * envelope * 0.6
                let sample = Int16(max(-1, min(1, value)) * 32_000)
                let position = index * (count * 3 / 4) + n
                if position < samples.count {
                    samples[position] = Int16(clamping: Int(samples[position]) + Int(sample))
                } else {
                    samples.append(sample)
                }
            }
        }

        return wav(samples: samples, sampleRate: sampleRate)
    }

    /// Minimal PCM WAV container around the samples.
    static func wav(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        let byteCount = samples.count * 2

        func append(_ string: String) { data.append(string.data(using: .ascii)!) }
        func append32(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: Int) { withUnsafeBytes(of: UInt16(value).littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF"); append32(36 + byteCount); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(sampleRate); append32(sampleRate * 2); append16(2); append16(16)
        append("data"); append32(byteCount)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
