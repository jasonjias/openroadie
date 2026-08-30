import AVFoundation
import Foundation
import Observation
import os

/// Orchestrates hands-free "Hey Roadie" during active drives:
/// wake listener → (optional "Yes?" + question capture) → agent → spoken reply
/// → back to listening. Opt-in via Settings; off automatically when the
/// drive ends.
@MainActor
@Observable
final class WakeWordCoordinator {
    /// UserDefaults key for the listening mode. Defaults to off (opt-in).
    static let modeKey = "heyRoadieMode"

    enum Mode: String, CaseIterable, Identifiable {
        case off
        case duringDrives
        case always

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "Off"
            case .duringDrives: "During drives"
            case .always: "Always"
            }
        }
    }

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

    private let log = Logger(subsystem: "com.openroadie", category: "wake")

    init(drive: DriveSessionManager, agent: RoadieAgent, speaker: SpeechSpeaker) {
        self.drive = drive
        self.agent = agent
        self.speaker = speaker
        Self.migrateLegacyToggle()
        listener.onWake = { [weak self] question in
            self?.handleWake(question)
        }
    }

    /// The pre-mode releases stored a bool under "heyRoadieEnabled"; carry an
    /// enabled toggle forward as "during drives" rather than silently off.
    private static func migrateLegacyToggle() {
        let defaults = UserDefaults.standard
        defer { standDownOnce() }
        guard defaults.string(forKey: modeKey) == nil else { return }
        if defaults.bool(forKey: "heyRoadieEnabled") {
            defaults.set(Mode.duringDrives.rawValue, forKey: modeKey)
        }
        defaults.removeObject(forKey: "heyRoadieEnabled")
    }

    /// One-time stand-down: passive listening held a `.playAndRecord`
    /// session, which iOS answers by attenuating every other app's audio
    /// — music at half volume for as long as OpenRoadie lived in the
    /// background. Wake listening is now off until deliberately switched
    /// back on, and only listens in the foreground or during a drive.
    private static func standDownOnce() {
        let defaults = UserDefaults.standard
        let flag = "heyRoadieStoodDownForAudio"
        guard !defaults.bool(forKey: flag) else { return }
        defaults.set(true, forKey: flag)
        defaults.set(Mode.off.rawValue, forKey: modeKey)
    }

    var mode: Mode {
        Mode(rawValue: UserDefaults.standard.string(forKey: Self.modeKey) ?? "") ?? .off
    }

    /// True while the app is foregrounded. A wake listener needs a
    /// `.playAndRecord` session, and iOS attenuates every other app's
    /// audio for as long as one is active — the field symptom was music
    /// stuck at half volume whenever OpenRoadie sat in the background.
    /// So passive listening is a foreground-or-driving privilege.
    private var appIsActive = true

    func setAppActive(_ active: Bool) {
        guard appIsActive != active else { return }
        appIsActive = active
        refresh()
    }

    private var wantsListening: Bool {
        switch mode {
        case .off: false
        // A live drive earns background listening; idle backgrounding
        // does not, so the mic (and the volume dip) goes away with it.
        case .duringDrives: drive.isDriving
        case .always: appIsActive || drive.isDriving
        }
    }

    /// Re-evaluates whether the wake listener should be running. Call on
    /// drive start/stop, mode changes, and app start.
    func refresh() {
        let shouldListen = wantsListening && manualSuspensions == 0

        log.info("refresh: mode=\(self.mode.rawValue, privacy: .public) driving=\(self.drive.isDriving) suspensions=\(self.manualSuspensions) status=\(String(describing: self.status), privacy: .public)")

        switch (shouldListen, status) {
        case (true, .off):
            Task { await startListening() }
        case (false, .listening):
            listener.stop()
            status = .off
            // Hand the audio session back so other apps return to full
            // volume the moment we stop listening.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        default:
            break // .handling finishes its own flow, then re-refreshes
        }
    }

    /// Speaks a coaching nudge, pausing the wake listener around it so the
    /// mic engine and TTS never fight over the audio session.
    func announce(_ text: String) {
        Task {
            beginManualVoice()
            await speaker.speakAndWait(text)
            endManualVoice()
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
        guard await SpeechRecognizer.requestPermissions() else {
            log.error("wake listening blocked: speech/mic permission denied")
            return
        }
        // Conditions may have changed while permissions were pending.
        guard wantsListening, manualSuspensions == 0, status == .off else { return }
        status = .listening
        listener.start()
        log.info("wake listening armed")
    }

    private func handleWake(_ inlineQuestion: String?) {
        guard status == .listening else { return }
        status = .handling
        log.info("wake fired, inline question: \(inlineQuestion ?? "<none>", privacy: .public)")

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
