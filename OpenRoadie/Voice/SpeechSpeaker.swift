import AVFoundation

/// Speaks Roadie's replies with the on-device synthesizer. Music or another
/// app's navigation audio ducks while Roadie talks and comes back after.
@MainActor
final class SpeechSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    /// UserDefaults key holding the user's chosen voice identifier.
    /// Empty/missing means "automatic": best installed voice wins.
    static let voiceDefaultsKey = "roadieVoiceIdentifier"

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.currentVoice()
        synthesizer.speak(utterance)
    }

    /// Resolved fresh on every utterance so a Settings change (or a newly
    /// downloaded voice) applies immediately, no relaunch.
    static func currentVoice() -> AVSpeechSynthesisVoice? {
        if let identifier = UserDefaults.standard.string(forKey: voiceDefaultsKey),
           !identifier.isEmpty,
           let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        return bestAvailableVoice()
    }

    /// Installed English voices, best-first — the Settings picker's data.
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { rank($0) > rank($1) }
    }

    /// The default voice is the robotic compact one. Prefer the best English
    /// voice installed: premium > enhanced > default, en-US over other
    /// English. Users can download more in Settings → Accessibility →
    /// Spoken Content → Voices; we pick them up automatically.
    private static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        availableVoices().first
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        var score = 0
        switch voice.quality {
        case .premium: score += 100
        case .enhanced: score += 50
        default: break
        }
        if voice.language == "en-US" { score += 10 }
        return score
    }

    static func qualityLabel(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: "Standard"
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Release the session so ducked audio returns to full volume.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
