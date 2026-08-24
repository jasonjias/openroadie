import Foundation
import Observation

/// Orchestrates hands-free "Hey Roadie" during active drives:
/// wake listener → (optional "Yes?" + question capture) → agent → spoken reply
/// → back to listening. Opt-in via Settings; off automatically when the
/// drive ends.
@MainActor
@Observable
final class WakeWordCoordinator {
    /// UserDefaults key for the Settings toggle. Defaults to off (opt-in).
    static let enabledKey = "heyRoadieEnabled"

    enum Status: Equatable {
        case off
        case listening
        case handling
    }

    private(set) var status: Status = .off

    private let drive: DriveSessionManager
    private let agent: RoadieAgent
    private let speaker: SpeechSpeaker
    private let listener = WakeWordListener()
    private let capture = SpeechRecognizer()
    private var manualSuspensions = 0

    init(drive: DriveSessionManager, agent: RoadieAgent, speaker: SpeechSpeaker) {
        self.drive = drive
        self.agent = agent
        self.speaker = speaker
        listener.onWake = { [weak self] question in
            self?.handleWake(question)
        }
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    /// Re-evaluates whether the wake listener should be running. Call on
    /// drive start/stop, toggle changes, and app start.
    func refresh() {
        let shouldListen = isEnabled && drive.isDriving && manualSuspensions == 0

        switch (shouldListen, status) {
        case (true, .off):
            Task { await startListening() }
        case (false, .listening):
            listener.stop()
            status = .off
        default:
            break // .handling finishes its own flow, then re-refreshes
        }
    }

    /// The tap-to-talk mic suspends wake listening so two audio engines
    /// never record at once.
    func beginManualVoice() {
        manualSuspensions += 1
        refresh()
    }

    func endManualVoice() {
        manualSuspensions = max(0, manualSuspensions - 1)
        refresh()
    }

    private func startListening() async {
        guard status == .off else { return }
        guard await SpeechRecognizer.requestPermissions() else { return }
        // Conditions may have changed while permissions were pending.
        guard isEnabled, drive.isDriving, manualSuspensions == 0, status == .off else { return }
        status = .listening
        listener.start()
    }

    private func handleWake(_ inlineQuestion: String?) {
        guard status == .listening else { return }
        status = .handling

        Task {
            var question = inlineQuestion
            if question == nil {
                // Bare "hey roadie": acknowledge, then listen for the ask.
                await speaker.speakAndWait("Yes?")
                question = await captureQuestion(timeout: 8)
            }

            if let question, !question.isEmpty {
                if let reply = await agent.ask(question) {
                    await speaker.speakAndWait(reply)
                }
            }

            status = .off
            refresh()
        }
    }

    /// One-shot question capture with an overall timeout so a silent cabin
    /// can't wedge the flow.
    private func captureQuestion(timeout: TimeInterval) async -> String? {
        await withCheckedContinuation { continuation in
            var resumed = false

            capture.onFinalTranscript = { text in
                guard !resumed else { return }
                resumed = true
                continuation.resume(returning: text)
            }
            Task { await self.capture.toggle() }

            Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard !resumed else { return }
                resumed = true
                let heard = self.capture.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                if self.capture.isListening {
                    await self.capture.toggle() // stops; its callback is now a no-op
                }
                continuation.resume(returning: heard.isEmpty ? nil : heard)
            }
        }
    }
}
