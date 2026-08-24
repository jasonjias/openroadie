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
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            cleanupAudio()
            state = .unavailable
            return
        }

        state = .listening
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handle(result: result, error: error)
            }
        }
    }

    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        guard state == .listening else { return }
        if let result {
            transcript = result.bestTranscription.formattedString
            scheduleSilenceTimeout()
            if result.isFinal {
                finish(sending: true)
                return
            }
        }
        if error != nil {
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

    private func requestPermissions() async -> Bool {
        let speechAllowed = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard speechAllowed else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}
