import AVFoundation
import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(RoadService.enabledKey) private var roadAwarenessEnabled = true
    @AppStorage(SpeechSpeaker.voiceDefaultsKey) private var voiceIdentifier = ""
    @AppStorage(WakeWordCoordinator.modeKey) private var heyRoadieMode = WakeWordCoordinator.Mode.off.rawValue
    @AppStorage(AlertCenter.overLimitKey) private var alertOverLimit = false
    @AppStorage(AlertCenter.marginKey) private var alertMargin = 0.0
    @AppStorage(AlertCenter.maxSpeedKey) private var alertMaxSpeed = 0.0
    @AppStorage(AlertCenter.autoEndKey) private var autoEndDrive = true
    @AppStorage(ModelProviderChoice.defaultsKey) private var modelProvider = ModelProviderChoice.apple.rawValue
    @AppStorage(ModelProviderChoice.customURLKey) private var customModelURL = ""
    @AppStorage(ModelProviderChoice.customModelKey) private var customModelName = ""
    @State private var customAPIKey = KeychainStore.get(ModelProviderChoice.customAPIKeyKeychainKey) ?? ""
    @State private var exportURL: URL?
    @State private var exportError: String?
    @Environment(\.modelContext) private var modelContext
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
                    Toggle("Alert over the posted limit", isOn: $alertOverLimit)
                    Picker("Extra alert past the limit", selection: $alertMargin) {
                        Text("Off").tag(0.0)
                        ForEach([5.0, 10.0, 15.0], id: \.self) { margin in
                            Text("+\(Int(margin)) mph").tag(margin)
                        }
                    }
                    Picker("My max speed", selection: $alertMaxSpeed) {
                        Text("Off").tag(0.0)
                        ForEach(Array(stride(from: 55.0, through: 100.0, by: 5)), id: \.self) { speed in
                            Text("\(Int(speed)) mph").tag(speed)
                        }
                    }
                    Toggle("End drive when parked", isOn: $autoEndDrive)
                } header: {
                    Text("Speed alerts")
                } footer: {
                    Text("Alerts fire once per crossing with a small grace band, take effect on your next drive, and buzz a paired Apple Watch automatically. \u{201C}My max speed\u{201D} also warns when you're within 3 mph of it. Parked for 10 minutes ends and saves the drive.")
                }
                .onChange(of: alertOverLimit) { _, on in if on { AlertCenter.requestAuthorization() } }
                .onChange(of: alertMargin) { _, value in if value > 0 { AlertCenter.requestAuthorization() } }
                .onChange(of: alertMaxSpeed) { _, value in if value > 0 { AlertCenter.requestAuthorization() } }

                Section {
                    Picker("\u{201C}Hey Roadie\u{201D}", selection: $heyRoadieMode) {
                        ForEach(WakeWordCoordinator.Mode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Listens on this device for \u{201C}Hey Roadie\u{201D} so you can ask anything hands-free. Your voice never leaves the phone, and music keeps playing while it listens. \u{201C}Always\u{201D} keeps the microphone on whenever OpenRoadie is open, even parked — more battery, and iOS shows the mic indicator the whole time.")
                }

                Section {
                    ForEach(PlaceCategory.allCases) { category in
                        Toggle(category.title, isOn: Binding(
                            get: { !PlaceCategory.isHidden(category) },
                            set: { PlaceCategory.setHidden(category, !$0) }
                        ))
                    }
                } header: {
                    Text("Nearby categories")
                } footer: {
                    Text("Choose which categories show in the Nearby tab. Drive electric? Hide Gas. Anything hidden stays searchable.")
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
                    Picker("Roadie's model", selection: $modelProvider) {
                        ForEach(ModelProviderChoice.allCases) { choice in
                            Text(choice.title).tag(choice.rawValue)
                        }
                    }
                    if modelProvider == ModelProviderChoice.custom.rawValue {
                        TextField("Base URL (…/v1)", text: $customModelURL)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        TextField("Model name", text: $customModelName)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        SecureField("API key (stored in Keychain)", text: $customAPIKey)
                            .onChange(of: customAPIKey) { _, key in
                                KeychainStore.set(key, for: ModelProviderChoice.customAPIKeyKeychainKey)
                            }
                    }
                } header: {
                    Text("AI model")
                } footer: {
                    Text(modelProvider == ModelProviderChoice.custom.rawValue
                        ? "Works with any OpenAI-compatible endpoint (OpenAI, Anthropic, Gemini, a local Ollama server, …). Your questions and the driving details needed to answer them are sent to that endpoint. The API key is stored in the Keychain."
                        : "Apple's on-device model: questions and driving data never leave the phone.")
                }

                Section {
                    LabeledContent("Driving data", value: "On this device only")
                    if let exportURL {
                        ShareLink("Share anonymized events", item: exportURL)
                    } else {
                        Button("Export anonymized driving events") {
                            exportEvents()
                        }
                    }
                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Trips, routes, and speeds are stored locally and never uploaded. OpenRoadie has no server: community contribution today means exporting a file you choose to share — hard-braking and acceleration events only, locations coarsened to ~110 m, times reduced to the hour, no identity and no routes.")
                }
            }
            .navigationTitle("Settings")
            .onDisappear { exportURL = nil }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func exportEvents() {
        exportError = nil
        do {
            let events = try modelContext.fetch(FetchDescriptor<DriveEvent>())
            guard !events.isEmpty else {
                exportError = "No hard-braking or acceleration events recorded yet."
                return
            }
            let data = try CommunityExport.json(events)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("openroadie-events.json")
            try data.write(to: url)
            exportURL = url
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }
}

#Preview {
    SettingsView()
}
