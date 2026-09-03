import AVFoundation
import PhotosUI
import SwiftData
import SwiftUI

struct SettingsView: View {
    @AppStorage(RoadService.enabledKey) private var roadAwarenessEnabled = true
    @AppStorage(HazardService.enabledKey) private var crashWarnings = true
    @AppStorage(SpeechSpeaker.voiceDefaultsKey) private var voiceIdentifier = ""
    @AppStorage(WakeWordCoordinator.modeKey) private var heyRoadieMode = WakeWordCoordinator.Mode.off.rawValue
    @AppStorage(AlertCenter.overLimitStyleKey) private var overLimitStyle = AlertCenter.overLimitStyle.rawValue
    @AppStorage(AlertCenter.marginKey) private var alertMargin = -1.0
    @AppStorage(AlertCenter.maxSpeedKey) private var alertMaxSpeed = 0.0
    @AppStorage(AlertCenter.autoEndKey) private var autoEndDrive = true
    @AppStorage(AutoDriveMonitor.handsFreeKey) private var handsFree = false
    @AppStorage(WeatherService.enabledKey) private var tripWeatherEnabled = true
    @AppStorage(SevereWeatherWatch.enabledKey) private var weatherAlertsEnabled = true
    @AppStorage(DriveActivityController.enabledKey) private var liveActivityEnabled = true
    @AppStorage(WalkRecorder.enabledKey) private var walkBreadcrumbs = true
    @AppStorage(ModelProviderChoice.defaultsKey) private var modelProvider = ModelProviderChoice.apple.rawValue
    @AppStorage(ModelProviderChoice.customURLKey) private var customModelURL = ""
    @AppStorage(ModelProviderChoice.customModelKey) private var customModelName = ""
    @State private var customAPIKey = KeychainStore.get(ModelProviderChoice.customAPIKeyKeychainKey) ?? ""
    @State private var exportURL: URL?
    @State private var personalExportURL: URL?
    @State private var gpxExportURL: URL?
    @State private var exportError: String?
    @AppStorage(DrivingBackground.defaultsKey) private var drivingBackground = DrivingBackground.green.rawValue
    @AppStorage(RoadStyle.defaultsKey) private var roadStyle = RoadStyle.standard.rawValue
    @AppStorage(DriveSceneView.lampsKey) private var roadLamps = false
    @AppStorage(RoadSeason.defaultsKey) private var roadSeason = RoadSeason.off.rawValue
    @AppStorage(Vehicle.defaultsKey) private var sceneVehicle = Vehicle.classic.id
    @AppStorage("showGPSDetails") private var showGPSDetails = false
    @AppStorage("showHeading") private var showHeading = false
    @AppStorage(AutoDriveMonitor.modeKey) private var autoStartMode = AutoDriveMonitor.Mode.off.rawValue
    @AppStorage(BackgroundDriveWatcher.enabledKey) private var alwaysOnDetection = false
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
                    Toggle("Crash-data road warnings", isOn: $crashWarnings)
                } footer: {
                    Text("Chimes and notifies when approaching a spot with multiple fatal crashes on record (U.S. DOT / NHTSA data, bundled — works offline, nothing is sent anywhere). Once per zone per drive.")
                }

                Section {
                    Toggle("Road awareness", isOn: $roadAwarenessEnabled)
                } footer: {
                    Text("Shows the current road and speed limit using OpenStreetMap. While driving, your approximate location is sent to the public Overpass API (overpass-api.de) about once every few hundred meters. Turn off for a fully offline drive — everything else works identically.")
                }

                Section {
                    Toggle("Trip weather", isOn: $tripWeatherEnabled)
                    Toggle("Severe weather alerts", isOn: $weatherAlertsEnabled)
                } footer: {
                    Text("Trip weather records conditions and air quality on each drive using Open-Meteo (open-meteo.com), free open weather data; one coordinate and a date are sent when a drive ends, and older drives fill in a few per launch. Severe weather alerts check the U.S. National Weather Service (weather.gov) every few minutes while driving and chime once per Severe or Extreme alert. Nothing else leaves the device.")
                }

                Section {
                    Picker("Detect drives", selection: $autoStartMode) {
                        ForEach(AutoDriveMonitor.Mode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Always on", isOn: $alwaysOnDetection)
                        .disabled(autoStartMode == AutoDriveMonitor.Mode.off.rawValue)
                    Toggle("Hands-free (no Start Drive button)", isOn: $handsFree)
                        .disabled(autoStartMode != AutoDriveMonitor.Mode.automatic.rawValue)
                    // What detection last did, so a missed drive explains
                    // itself instead of failing silently.
                    if let events = UserDefaults.standard.stringArray(forKey: AutoDriveMonitor.eventLogKey), !events.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(events.reversed(), id: \.self) { event in
                                Text(event)
                            }
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Drive detection")
                } footer: {
                    Text("OpenRoadie watches for sustained car motion, confirms road speed with a quick GPS check, then starts the drive (\u{201C}Automatic\u{201D}) or sends a notification (\u{201C}Suggest\u{201D}). \u{201C}Always on\u{201D} lets iOS wake OpenRoadie once you've traveled a few hundred meters, so drives record themselves without opening the app — it needs Always location access, which iOS will ask for. Uses Motion & Fitness too. Each wake-up also drops a breadcrumb (roughly one per 500 m), so walks get a coarse trail on their map.  \u{201C}Hands-free\u{201D} removes the Start Drive button entirely, so a drive is never something you remember to begin \u{2014} it needs Automatic detection, and a drive in progress still shows Stop so you can end one early. With \u{201C}Always on\u{201D} OFF, closing OpenRoadie really closes it \u{2014} nothing keeps running, nothing shows in the Dynamic Island, and drives record only while the app is open or recently backgrounded.")
                }
                .onChange(of: autoStartMode) { _, mode in
                    if mode != AutoDriveMonitor.Mode.off.rawValue { AlertCenter.requestAuthorization() }
                    if mode == AutoDriveMonitor.Mode.off.rawValue { alwaysOnDetection = false }
                    // Never leave the dashboard with no way to start a drive.
                    if mode != AutoDriveMonitor.Mode.automatic.rawValue { handsFree = false }
                }

                Section {
                    Toggle("End drive when settled", isOn: $autoEndDrive)
                    Toggle("Live Activity", isOn: $liveActivityEnabled)
                    Toggle("Record walks after parking", isOn: $walkBreadcrumbs)
                } header: {
                    Text("Recording")
                } footer: {
                    Text("A drive keeps recording through stops. Sit still for 5 minutes and it pauses \u{2014} a gas stop, a drive-thru, a jam \u{2014} then resumes on its own when you move, all as one drive. After 25 minutes settled it ends and saves. Trip detail splits a drive into legs at any stop over 10 minutes, so \u{201C}there and back\u{201D} still reads as two runs without ever risking a lost trip. Live Activity puts the drive in the Dynamic Island and on the Lock Screen while recording \u{2014} speed, distance, and the trip timer at a glance. When a drive ends because you walked away, OpenRoadie can keep GPS for that walk and record its trail \u{2014} it stops within minutes of you stopping, and the walk appears with its own map. Everything stays on this device.")
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
                } header: {
                    Text("Speed alerts")
                } footer: {
                    Text("Three tiers, calibrated like a car's: crossing the posted limit plays a soft chime (or a full coaching nudge — your pick). Real coaching waits for \u{201C}over by\u{201D} — 15% adapts to the road (~30 in a 25, ~75 in a 65) and is the recommended setting. \u{201C}My max speed\u{201D} warns as you approach it. Each fires once per crossing, with a grace band.")
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
                    Text("Listens on this device for \u{201C}Hey Roadie\u{201D} so you can ask anything hands-free. Your voice never leaves the phone. Off by default: an open microphone makes iOS lower every other app's volume, so listening now happens only while OpenRoadie is on screen or a drive is recording — never in the background. \u{201C}Always\u{201D} adds parked listening while the app is open, at the cost of battery and a mic indicator.")
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
                    NavigationLink {
                        VehiclePickerView()
                    } label: {
                        HStack {
                            Text("Vehicle")
                            Spacer()
                            VehicleThumbnail(vehicle: Vehicle.find(sceneVehicle))
                                .frame(width: 44, height: 30)
                            Text(Vehicle.find(sceneVehicle).title)
                                .foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink("Driving History") {
                        DrivingHistoryView()
                    }
                    Picker("Road", selection: $roadStyle) {
                        ForEach(RoadStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    Toggle("Street lamps", isOn: $roadLamps)
                    Picker("Season", selection: $roadSeason) {
                        ForEach(RoadSeason.allCases) { season in
                            Text(season.title).tag(season.rawValue)
                        }
                    }
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
                    Text("\u{201C}Vehicle\u{201D} is what appears on the Vehicle odometer face (models from Kenney's wonderful CC0 kits — kenney.nl); drag to spin it while parked. \u{201C}Road\u{201D} is what it drives on. The background tints while a drive is live.")
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
                    if let personalExportURL {
                        ShareLink("Share everything (JSON)", item: personalExportURL)
                    } else {
                        Button("Export all my data (JSON)") {
                            exportEverything(asGPX: false)
                        }
                    }
                    if let gpxExportURL {
                        ShareLink("Share routes (GPX)", item: gpxExportURL)
                    } else {
                        Button("Export routes (GPX)") {
                            exportEverything(asGPX: true)
                        }
                    }
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
                    Text("Trips, routes, and speeds are stored locally and never uploaded. Export everything as JSON (full fidelity — trips, routes, events, notes) or routes as GPX for any mapping tool; both are yours, complete, whenever you want them. The anonymized export is the community one: hard-braking and acceleration events only, locations coarsened to ~110 m, times reduced to the hour, no identity and no routes.")
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
            .onDisappear {
                exportURL = nil
                personalExportURL = nil
                gpxExportURL = nil
            }
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

    /// The user's own complete record — everything the app stores, in a
    /// format they can take anywhere.
    private func exportEverything(asGPX: Bool) {
        exportError = nil
        do {
            let trips = try modelContext.fetch(FetchDescriptor<Trip>())
            guard !trips.isEmpty else {
                exportError = "No drives recorded yet."
                return
            }
            let url: URL
            if asGPX {
                let gpx = PersonalExport.gpx(trips: trips)
                url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("openroadie-routes.gpx")
                try gpx.write(to: url, atomically: true, encoding: .utf8)
                gpxExportURL = url
            } else {
                let events = try modelContext.fetch(FetchDescriptor<DriveEvent>())
                let notes = try modelContext.fetch(FetchDescriptor<DriveNote>())
                let data = try PersonalExport.json(trips: trips, events: events, notes: notes)
                url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("openroadie-my-driving-data.json")
                try data.write(to: url)
                personalExportURL = url
            }
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
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
