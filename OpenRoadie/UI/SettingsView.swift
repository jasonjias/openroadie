import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(RoadService.enabledKey) private var roadAwarenessEnabled = true
    @AppStorage(SpeechSpeaker.voiceDefaultsKey) private var voiceIdentifier = ""
    @AppStorage(WakeWordCoordinator.modeKey) private var heyRoadieMode = WakeWordCoordinator.Mode.off.rawValue
    @AppStorage(AlertCenter.overLimitStyleKey) private var overLimitStyle = AlertCenter.overLimitStyle.rawValue
    @AppStorage(AlertCenter.marginKey) private var alertMargin = -1.0
    @AppStorage(AlertCenter.maxSpeedKey) private var alertMaxSpeed = 0.0
    @AppStorage(AlertCenter.autoEndKey) private var autoEndDrive = true
    @AppStorage(ModelProviderChoice.defaultsKey) private var modelProvider = ModelProviderChoice.apple.rawValue
    @AppStorage(ModelProviderChoice.customURLKey) private var customModelURL = ""
    @AppStorage(ModelProviderChoice.customModelKey) private var customModelName = ""
    @State private var customAPIKey = KeychainStore.get(ModelProviderChoice.customAPIKeyKeychainKey) ?? ""
    @State private var exportURL: URL?
    @State private var exportError: String?
    @AppStorage(DrivingBackground.defaultsKey) private var drivingBackground = DrivingBackground.green.rawValue
    @AppStorage(Vehicle.defaultsKey) private var sceneVehicle = Vehicle.classic.id
    @AppStorage("showGPSDetails") private var showGPSDetails = false
    @AppStorage("showHeading") private var showHeading = false
    @AppStorage(AutoDriveMonitor.modeKey) private var autoStartMode = AutoDriveMonitor.Mode.off.rawValue
    @AppStorage(Coach.nameKey) private var driverName = ""
    @AppStorage(Coach.spokenKey) private var coachingSpoken = false
    @AppStorage(Coach.styleKey) private var coachingStyle = CoachStyle.gentle.rawValue
    @AppStorage(Coach.customTemplateKey) private var coachingTemplate = ""
    @State private var chipOrder = NearbyChip.ordered
    @State private var faceOrder = OdometerStyle.ordered
    @State private var editingCustom: CustomCategory?
    @State private var photoSelection: PhotosPickerItem?
    @State private var showsPhotoActions = false
    private let profile = ProfileStore.shared
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var previewSpeaker = SpeechSpeaker()

    private let voices = SpeechSpeaker.availableVoices()

    var body: some View {
        NavigationStack {
            Form {
                // Contacts-style photo editing: tap the photo to reveal
                // Change Photo and a "−" badge; no photo means Add Photo.
                // Deleting is a quiet minus, not a red warning.
                Section {
                    VStack(spacing: 12) {
                        // Contacts-detail scale, with the "−" sitting on the
                        // circle's 45° edge like Contacts' edit mode.
                        ProfileAvatar(size: 200)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    withAnimation {
                                        profile.clear()
                                        showsPhotoActions = false
                                    }
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 30, height: 30)
                                        .background(Circle().fill(.gray.opacity(0.85)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: -16, y: 14)
                                .opacity(showsPhotoActions && profile.image != nil ? 1 : 0)
                                .allowsHitTesting(showsPhotoActions && profile.image != nil)
                            }
                            .contentShape(Circle())
                            .onTapGesture {
                                guard profile.image != nil else { return }
                                withAnimation(.easeInOut(duration: 0.15)) { showsPhotoActions.toggle() }
                            }

                        // Fixed-height slot: revealing the action must never
                        // push the rest of the form down.
                        Group {
                            if profile.image == nil {
                                PhotosPicker("Add Photo", selection: $photoSelection, matching: .images)
                            } else {
                                PhotosPicker("Change Photo", selection: $photoSelection, matching: .images)
                                    .opacity(showsPhotoActions ? 1 : 0)
                                    .allowsHitTesting(showsPhotoActions)
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(height: 22)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Stored on this device only. (Apple doesn't let apps read your Apple ID picture — that one's first-party only.)")
                }
                .onChange(of: photoSelection) { _, item in
                    guard let item else { return }
                    Task {
                        // The current photo stays until the new one actually
                        // loads — cancelling the picker changes nothing.
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            profile.set(imageData: data)
                            withAnimation { showsPhotoActions = false }
                        }
                        photoSelection = nil
                    }
                }

                Section {
                    Toggle("Road awareness", isOn: $roadAwarenessEnabled)
                } footer: {
                    Text("Shows the current road and speed limit using OpenStreetMap. While driving, your approximate location is sent to the public Overpass API (overpass-api.de) about once every few hundred meters. Turn off for a fully offline drive — everything else works identically.")
                }

                Section {
                    Picker("Detect drives", selection: $autoStartMode) {
                        ForEach(AutoDriveMonitor.Mode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Drive detection")
                } footer: {
                    Text("OpenRoadie watches for sustained car motion, confirms road speed with a quick GPS check, then starts the drive (\u{201C}Automatic\u{201D}) or sends a notification (\u{201C}Suggest\u{201D}). Works while the app is open or recently used; \u{201C}End drive when parked\u{201D} completes the loop. Uses Motion & Fitness — iOS will ask once.")
                }
                .onChange(of: autoStartMode) { _, mode in
                    if mode != AutoDriveMonitor.Mode.off.rawValue { AlertCenter.requestAuthorization() }
                }

                Section {
                    Picker("At the posted limit", selection: $overLimitStyle) {
                        ForEach(AlertCenter.OverLimitStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    Picker("Coach me when over by", selection: $alertMargin) {
                        Text("Off").tag(0.0)
                        Text("15% of the limit").tag(-1.0)
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
                    Text("Three tiers, calibrated like a car's: crossing the posted limit plays a soft chime (or a full coaching nudge — your pick). Real coaching waits for \u{201C}over by\u{201D} — 15% adapts to the road (~30 in a 25, ~75 in a 65) and is the recommended setting. \u{201C}My max speed\u{201D} warns as you approach it. Each fires once per crossing, with a grace band. Parked for 10 minutes ends and saves the drive.")
                }
                .onChange(of: overLimitStyle) { _, style in if style != AlertCenter.OverLimitStyle.off.rawValue { AlertCenter.requestAuthorization() } }
                .onChange(of: alertMargin) { _, value in if value != 0 { AlertCenter.requestAuthorization() } }
                .onChange(of: alertMaxSpeed) { _, value in if value > 0 { AlertCenter.requestAuthorization() } }

                Section {
                    TextField("Your name (for nudges)", text: $driverName)
                    Toggle("Speak nudges aloud", isOn: $coachingSpoken)
                    Picker("Nudge style", selection: $coachingStyle) {
                        ForEach(CoachStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    if coachingStyle == CoachStyle.custom.rawValue {
                        TextField("Custom message", text: $coachingTemplate, axis: .vertical)
                            .lineLimit(2...3)
                    }
                } header: {
                    Text("Coaching")
                } footer: {
                    Text(coachingStyle == CoachStyle.custom.rawValue
                        ? "Tokens: {name}, {speed}, {limit} — e.g. \u{201C}Hey {name}, you were going {speed}. Please consider slowing down.\u{201D}"
                        : "When a speed alert fires, the notification (and Roadie's voice, if enabled) uses this tone instead of a robotic report. Example: \u{201C}Hey Jason, 78 mph is past 65. Let's bring it back down.\u{201D}")
                }

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
                    ForEach(faceOrder) { style in
                        Toggle(style.title, isOn: Binding(
                            get: { OdometerStyle.isEnabled(style) },
                            set: { OdometerStyle.setEnabled(style, $0) }
                        ))
                    }
                    .onMove { source, destination in
                        faceOrder.move(fromOffsets: source, toOffset: destination)
                        OdometerStyle.setOrder(faceOrder)
                    }
                } header: {
                    Text("Odometer faces")
                } footer: {
                    Text("Swipe between the enabled faces on the Drive tab. Touch and hold to reorder — the top face is the first slide.")
                }

                Section {
                    // One flat, ordered list — the "Type - Variant" titles
                    // carry the grouping, so section headers would repeat it.
                    Picker("Vehicle", selection: $sceneVehicle) {
                        ForEach(Vehicle.all) { vehicle in
                            Text(vehicle.isAvailable ? vehicle.title : "\(vehicle.title) — soon")
                                .tag(vehicle.id)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    Picker("Background while driving", selection: $drivingBackground) {
                        ForEach(DrivingBackground.allCases) { choice in
                            Text(choice.title).tag(choice.rawValue)
                        }
                    }
                    Toggle("Show heading", isOn: $showHeading)
                    Toggle("Show GPS details", isOn: $showGPSDetails)
                } header: {
                    Text("Dashboard")
                } footer: {
                    Text("\u{201C}Vehicle\u{201D} is what appears on the Rainbow Road scene (models from Kenney's wonderful CC0 kits — kenney.nl); drag to spin it while parked. The background tints while a drive is live.")
                }

                Section {
                    ForEach(chipOrder) { chip in
                        switch chip {
                        case .builtin(let category):
                            Toggle(isOn: Binding(
                                get: { !PlaceCategory.isHidden(category) },
                                set: { PlaceCategory.setHidden(category, !$0) }
                            )) {
                                Label(category.title, systemImage: category.systemImage)
                            }
                            .deleteDisabled(true)
                        case .custom(let custom):
                            Button {
                                editingCustom = custom
                            } label: {
                                HStack {
                                    Label(custom.title, systemImage: custom.systemImage)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(custom.terms.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .onMove { source, destination in
                        chipOrder.move(fromOffsets: source, toOffset: destination)
                        NearbyChip.setOrder(chipOrder)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            if case .custom(let custom) = chipOrder[index] {
                                deleteCustom(custom)
                            }
                        }
                    }
                    Button {
                        editingCustom = CustomCategory(title: "", terms: [])
                    } label: {
                        Label("Add Category", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Nearby categories")
                } footer: {
                    Text("Choose what shows in the Nearby tab, and touch and hold to reorder. Create your own category from names or brands — if Chipotle is a landmark to you, make it one. Tap a custom category to edit it; swipe to delete.")
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
                    NavigationLink {
                        PracticeLogView()
                    } label: {
                        Label("Permit Practice Log", systemImage: "graduationcap")
                    }
                } footer: {
                    Text("Track supervised practice hours toward a learner's permit — total and night hours, with a printable log to sign.")
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
            // On the Form, not a Section — Section modifiers replicate
            // per-row, and presentation modifiers must exist exactly once.
            .sheet(item: $editingCustom) { custom in
                CustomCategoryEditor(custom: custom) { saved in
                    saveCustom(saved)
                }
            }
            .onDisappear { exportURL = nil }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Account-style full-screen page: close with the ✕.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func saveCustom(_ custom: CustomCategory) {
        var all = CustomCategory.load()
        if let index = all.firstIndex(where: { $0.id == custom.id }) {
            all[index] = custom
        } else {
            all.append(custom)
        }
        CustomCategory.save(all)
        // Re-derive: an edited chip keeps its position, a new one appends.
        chipOrder = NearbyChip.ordered
        NearbyChip.setOrder(chipOrder)
    }

    private func deleteCustom(_ custom: CustomCategory) {
        CustomCategory.save(CustomCategory.load().filter { $0.id != custom.id })
        chipOrder = NearbyChip.ordered
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

/// Create or edit a custom Nearby category: a name, comma-separated search
/// terms, and an icon.
struct CustomCategoryEditor: View {
    @State private var custom: CustomCategory
    @State private var termsText: String
    private let onSave: (CustomCategory) -> Void
    @Environment(\.dismiss) private var dismiss

    init(custom: CustomCategory, onSave: @escaping (CustomCategory) -> Void) {
        _custom = State(initialValue: custom)
        _termsText = State(initialValue: custom.terms.joined(separator: ", "))
        self.onSave = onSave
    }

    private var parsedTerms: [String] {
        termsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        !custom.title.trimmingCharacters(in: .whitespaces).isEmpty && !parsedTerms.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name — e.g. Landmarks (real)", text: $custom.title)
                }
                Section {
                    TextField("chipotle, in-n-out, raising canes", text: $termsText, axis: .vertical)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .lineLimit(2...4)
                } header: {
                    Text("Search terms")
                } footer: {
                    Text("Comma-separated searches, each run through Apple Maps — the same engine as the Nearby search bar. \u{201C}chipotle\u{201D} finds every Chipotle Mexican Grill.")
                }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 8) {
                        ForEach(CustomCategory.symbolChoices, id: \.self) { symbol in
                            Button {
                                custom.systemImage = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        Circle().fill(symbol == custom.systemImage
                                            ? AnyShapeStyle(.tint.opacity(0.2))
                                            : AnyShapeStyle(.clear))
                                    )
                                    .foregroundStyle(symbol == custom.systemImage
                                        ? AnyShapeStyle(.tint)
                                        : AnyShapeStyle(.secondary))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Custom Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        custom.terms = parsedTerms
                        onSave(custom)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}

#Preview {
    SettingsView()
}
