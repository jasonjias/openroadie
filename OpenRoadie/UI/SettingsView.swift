import AVFoundation
import SwiftUI

struct SettingsView: View {
    @AppStorage(RoadService.enabledKey) private var roadAwarenessEnabled = true
    @AppStorage(SpeechSpeaker.voiceDefaultsKey) private var voiceIdentifier = ""
    @AppStorage(WakeWordCoordinator.enabledKey) private var heyRoadieEnabled = false
    @Environment(\.dismiss) private var dismiss
    @State private var previewSpeaker = SpeechSpeaker()

    private let voices = SpeechSpeaker.availableVoices()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Road awareness", isOn: $roadAwarenessEnabled)
                } footer: {
                    Text("Shows the current road and speed limit using OpenStreetMap. While driving, your approximate location is sent to the public Overpass API (overpass-api.de) about once every few hundred meters. Turn off for a fully offline drive — everything else works identically.")
                }

                Section {
                    Toggle("\u{201C}Hey Roadie\u{201D} during drives", isOn: $heyRoadieEnabled)
                } footer: {
                    Text("While a drive is active, OpenRoadie keeps the microphone on and listens on this device for \u{201C}Hey Roadie\u{201D} — ask anything hands-free. Your voice never leaves the phone and music keeps playing while it listens. Uses some extra battery; iOS shows the microphone indicator the whole time.")
                }

                Section {
                    Picker("Roadie's voice", selection: $voiceIdentifier) {
                        Text("Automatic (best installed)").tag("")
                        ForEach(voices, id: \.identifier) { voice in
                            Text("\(voice.name) — \(SpeechSpeaker.qualityLabel(for: voice))")
                                .tag(voice.identifier)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .onChange(of: voiceIdentifier) { _, _ in
                        previewSpeaker.speak("Hi, I'm Roadie. This is how I sound.")
                    }
                } footer: {
                    Text("Download more voices in Settings → Accessibility → Spoken Content → Voices — they appear here automatically.")
                }

                Section {
                    LabeledContent("Driving data", value: "On this device only")
                } footer: {
                    Text("Trips, routes, and speeds are stored locally and never uploaded.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    SettingsView()
}
