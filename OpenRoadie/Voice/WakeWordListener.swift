import AVFoundation
import Speech

/// Continuously listens for "Hey Roadie" using on-device recognition.
///
/// Runs only while a drive is active and the user has opted in. The audio
/// session mixes with other audio (music keeps playing, un-ducked) — only
/// Roadie's spoken replies duck. Recognition cycles restart themselves when
/// the system ends a task, so listening survives a whole drive.
@MainActor
@Observable
final class WakeWordListener {
    private(set) var isActive = false

    /// Fired on wake. The payload is the question spoken in the same breath
    /// ("hey roadie, how fast am I going") or `nil` for a bare "hey roadie".
    var onWake: ((String?) -> Void)?

    /// What on-device recognition tends to hear instead of "Roadie".
    static let wakePhrases = [
        "hey roadie", "hey roady", "hey rowdy", "hey brodie", "hey brody",
        "hey rody", "hey rhodey", "a roadie", "hey roadies",
    ]

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var wakeDetected = false
    private var remainder = ""
    private var settleGeneration = 0
    private var restartGeneration = 0

    /// After the wake phrase, wait this long for the sentence to finish
    /// growing before treating it as the complete question.
    private static let settleDelay: TimeInterval = 1.2

    func start() {
        guard !isActive else { return }
        isActive = true
        beginCycle()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        teardownRecognition()
    }

    // MARK: - Recognition cycle

    private func beginCycle() {
        guard isActive else { return }
        wakeDetected = false
        remainder = ""

        guard let recognizer, recognizer.isAvailable else {
            scheduleRestart(delay: 2)
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            // mixWithOthers, NOT duckOthers: passive listening must not
            // touch the driver's music.
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            nonisolated(unsafe) let liveRequest = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                liveRequest.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            teardownRecognition()
            scheduleRestart(delay: 2)
            return
        }

        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let ended = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                self?.handle(text: text, ended: ended)
            }
        }
    }

    private func handle(text: String?, ended: Bool) {
        guard isActive else { return }

        if let text {
            let (found, rest) = Self.detectWake(in: text)
            if found {
                wakeDetected = true
                remainder = rest
                scheduleSettle()
            } else if text.count > 300 {
                // Keep the rolling transcript short so old chatter can't
                // confuse detection; start a fresh cycle.
                teardownRecognition()
                scheduleRestart(delay: 0.2)
                return
            }
        }

        if ended {
            if wakeDetected {
                fireWake()
            } else {
                teardownRecognition()
                scheduleRestart(delay: 0.4)
            }
        }
    }

    private func scheduleSettle() {
        settleGeneration += 1
        let generation = settleGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settleDelay))
            guard let self, self.isActive, self.wakeDetected,
                  self.settleGeneration == generation else { return }
            self.fireWake()
        }
    }

    private func fireWake() {
        let question = remainder.trimmingCharacters(in: .whitespaces)
        stop()
        onWake?(question.isEmpty ? nil : question)
    }

    private func scheduleRestart(delay: TimeInterval) {
        restartGeneration += 1
        let generation = restartGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.isActive,
                  self.restartGeneration == generation,
                  self.task == nil else { return }
            self.beginCycle()
        }
    }

    private func teardownRecognition() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Wake detection (pure, tested)

    /// Finds a wake phrase in a transcript; returns whatever followed it.
    static func detectWake(in transcript: String) -> (found: Bool, remainder: String) {
        var normalized = ""
        for character in transcript.lowercased() {
            normalized.append(character.isLetter || character.isNumber ? character : " ")
        }
        let squashed = normalized.split(separator: " ").joined(separator: " ")

        for phrase in wakePhrases {
            if let range = squashed.range(of: phrase) {
                let rest = String(squashed[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                return (true, rest)
            }
        }
        return (false, "")
    }
}
