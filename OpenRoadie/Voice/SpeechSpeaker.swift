import AVFoundation

/// Speaks Roadie's replies with the on-device synthesizer. Music or another
/// app's navigation audio ducks while Roadie talks and comes back after.
@MainActor
final class SpeechSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    /// UserDefaults key holding the user's chosen voice identifier.
    /// Empty/missing means "automatic": best installed voice wins.
    static let voiceDefaultsKey = "roadieVoiceIdentifier"

    private let synthesizer = AVSpeechSynthesizer()
    /// Belt and braces for the duck: the delegate normally releases the
    /// session, but a dropped callback (interrupted utterance, route
    /// change, app backgrounded mid-sentence) would otherwise leave every
    /// other app's audio at half volume until OpenRoadie was force-quit.
    private var releaseWatchdog: Task<Void, Never>?

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

        // Generous estimate: ~12 characters a second, floor 4 s, plus slack.
        let estimate = max(4, Double(text.count) / 12 + 3)
        releaseWatchdog?.cancel()
        releaseWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(estimate))
            guard !Task.isCancelled else { return }
            self?.releaseSessionIfIdle()
        }
    }

    /// Hands audio back to whatever was playing. Safe to call any time.
    func releaseSessionIfIdle() {
        guard !synthesizer.isSpeaking else { return }
        releaseWatchdog?.cancel()
        releaseWatchdog = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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

    /// Speaks and suspends until the utterance finishes (or is cancelled) —
    /// lets voice flows sequence speech and listening without overlap.
    func speakAndWait(_ text: String) async {
        guard !text.isEmpty else { return }
        speak(text)
        await withCheckedContinuation { continuation in
            finishContinuation?.resume()
            finishContinuation = continuation
        }
    }

    private var finishContinuation: CheckedContinuation<Void, Never>?

    private func utteranceEnded() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Release the session so ducked audio returns to full volume.
        Task { @MainActor in
            self.releaseSessionIfIdle()
            self.utteranceEnded()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.releaseSessionIfIdle()
            self.utteranceEnded()
        }
    }
}
