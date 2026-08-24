import AVFoundation
import Speech

/// Tap-to-talk speech input for Roadie.
///
/// Recognition runs entirely on-device (`requiresOnDeviceRecognition`) — the
/// driver's voice never leaves the phone, matching the app's privacy posture.
/// Listening auto-finishes after a short silence so the driver never has to
/// tap twice.
@MainActor
@Observable
final class SpeechRecognizer {
    enum State: Equatable {
        case idle
        case listening
        case denied
        case unavailable
    }

    private(set) var state: State = .idle
    private(set) var transcript = ""

    /// Called with the final transcript when listening ends with content.
    var onFinalTranscript: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceGeneration = 0

    /// Seconds of silence after speech before the question auto-sends.
    private static let silenceTimeout: TimeInterval = 1.6

    var isListening: Bool { state == .listening }

    func toggle() async {
        if isListening {
            finish(sending: true)
        } else {
            await start()
        }
    }

    private func start() async {
        guard state != .listening else { return }

        guard await requestPermissions() else {
            state = .denied
            return
        }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            state = .unavailable
            return
        }

        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true // speech never leaves the phone
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .allowBluetooth, .defaultToSpeaker]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.removeTap(onBus: 0)
            // The tap fires on the audio thread; the closure must NOT inherit
            // main-actor isolation or the runtime isolation check traps.
            // Appending buffers to a recognition request off-main is the
            // documented pattern.
            nonisolated(unsafe) let liveRequest = request
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
                liveRequest.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            cleanupAudio()
            state = .unavailable
            return
        }

        state = .listening
        // The result handler runs on a speech-framework queue: keep the
        // closure explicitly @Sendable (no inherited main-actor isolation),
        // extract value types, then hop to the main actor.
        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in
                self?.handle(text: text, isFinal: isFinal, failed: failed)
            }
        }
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        guard state == .listening else { return }
        if let text {
            transcript = text
            scheduleSilenceTimeout()
            if isFinal {
                finish(sending: true)
                return
            }
        }
        if failed {
            // Recognition ended on its own — send whatever was heard.
            finish(sending: !transcript.isEmpty)
        }
    }

    private func scheduleSilenceTimeout() {
        silenceGeneration += 1
        let generation = silenceGeneration
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.silenceTimeout))
            guard let self, self.state == .listening,
                  self.silenceGeneration == generation,
                  !self.transcript.isEmpty else { return }
            self.finish(sending: true)
        }
    }

    private func finish(sending: Bool) {
        guard state == .listening else { return }
        state = .idle
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupAudio()
        if sending, !text.isEmpty {
            onFinalTranscript?(text)
        }
    }

    private func cleanupAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Shared by tap-to-talk and the "Hey Roadie" wake listener.
    static func requestPermissions() async -> Bool {
        guard await requestSpeechAuthorization() else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private func requestPermissions() async -> Bool {
        await Self.requestPermissions()
    }

    /// nonisolated on purpose: TCC invokes the callback on a background
    /// queue, so the closure must not carry main-actor isolation (it traps
    /// the runtime isolation check on device otherwise).
    private nonisolated static func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
