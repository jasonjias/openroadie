import SwiftUI

/// The Drive Score, Tesla-gauge style: a semicircle from Unsafe to Safe,
/// factor occurrence counts (no point-deduction math — drive well and keep
/// the green, rather than watch points bleed), and the day's events.
struct SafetyDetailView: View {
    let dayTitle: String
    let stats: DayStats
    let dayEvents: [DriveEvent]
    let overallScore: Int?

    @Environment(\.dismiss) private var dismiss
    @State private var showsLearnMore = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        SemicircleGauge(
                            fraction: Double(stats.score ?? 0) / 100,
                            color: gaugeColor,
                            lineWidth: 18
                        ) {
                            if let score = stats.score {
                                Text("\(score)")
                                    .font(.system(size: 54, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                            } else {
                                Text("—").font(.largeTitle).foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: 300)
                        HStack {
                            Text("Unsafe")
                            Spacer()
                            Text("Safe")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 300)

                        if let overallScore {
                            Label("30-day average: \(overallScore)", systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 6)
                        }
                        Button("Learn More") { showsLearnMore = true }
                            .font(.subheadline.weight(.medium))
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Factors") {
                    factorRow(
                        "Hard Braking",
                        description: "Sudden, forceful slowing — smooth, early braking keeps this at zero.",
                        count: stats.hardBraking
                    )
                    factorRow(
                        "Hard Acceleration",
                        description: "Forceful take-offs — easing onto the pedal keeps this green.",
                        count: stats.hardAcceleration
                    )
                    factorRow(
                        "Exceeded Speed Limit",
                        description: "Times your speed went over the road's posted limit.",
                        count: stats.overLimitCrossings
                    )
                    factorRow(
                        "Exceeded Limit by 5+ mph",
                        description: "Times you went more than 5 mph past the posted limit.",
                        count: stats.wellOverCrossings
                    )
                }

                if !dayEvents.isEmpty {
                    Section("Events") {
                        ForEach(dayEvents) { event in
                            HStack(spacing: 10) {
                                Image(systemName: icon(for: event.kind))
                                    .foregroundStyle(color(for: event.kind))
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(label(for: event.kind))
                                        .font(.subheadline.weight(.medium))
                                    Text(detailLine(for: event))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(dayTitle) · Drive Score")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showsLearnMore) {
                LearnMoreView()
            }
            .toolbar {
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

    private var gaugeColor: Color {
        switch stats.score ?? 0 {
        case 90...: .green
        case 70..<90: .yellow
        default: .red
        }
    }

    /// Tesla-style factor row: the count, a three-segment severity bar
    /// (green / yellow / red), and a plain-English description.
    private func factorRow(_ title: String, description: String, count: Int) -> some View {
        let severity = count == 0 ? 0 : (count <= 2 ? 1 : 2)
        let colors: [Color] = [.green, .yellow, .red]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(count == 0 ? "none" : "\(count)×")
                    .monospacedDigit()
                    .foregroundStyle(count == 0 ? .secondary : .primary)
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { segment in
                    Capsule()
                        .fill(segment == severity ? colors[segment] : Color(.systemFill))
                        .frame(height: 4)
                }
            }
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func icon(for kind: String) -> String {
        switch kind {
        case "hardBraking", "hardAcceleration": "exclamationmark.triangle.fill"
        default: "gauge.high"
        }
    }

    private func color(for kind: String) -> Color {
        switch kind {
        case "hardBraking": .red
        case "hardAcceleration": .orange
        case "wellOverLimit": .red
        default: .yellow
        }
    }

    private func label(for kind: String) -> String {
        switch kind {
        case "hardBraking": "Hard braking"
        case "hardAcceleration": "Hard acceleration"
        case "overLimit": "Crossed the posted limit"
        case "wellOverLimit": "More than 5 over the limit"
        default: kind
        }
    }

    private func detailLine(for event: DriveEvent) -> String {
        var parts = [event.timestamp.formatted(.dateTime.hour().minute())]
        if let speed = event.speedMph {
            parts.append("\(Int(speed.rounded())) mph")
        }
        if event.peakG > 0 {
            parts.append(String(format: "%.2f g", event.peakG))
        }
        return parts.joined(separator: " · ")
    }
}

/// The Tesla-style explainer: what each factor is, how to keep it green,
/// and what the indicators mean — written for what an iPhone can honestly
/// measure.
struct LearnMoreView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case factors = "Factors"
        case tips = "Driving Tips"
        case indicators = "Indicators"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .factors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 20) {
                    switch tab {
                    case .factors: factors
                    case .tips: tips
                    case .indicators: indicators
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Learn More")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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

    @ViewBuilder private var factors: some View {
        Text("Everything is measured on this iPhone — motion sensors for force, GPS for speed, OpenStreetMap for posted limits. Nothing leaves your phone.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        entry("Hard Braking",
              "Sudden slowing with force above about 0.35g, sustained for a moment — a pothole or phone bump doesn't count, a real slam does.")
        entry("Hard Acceleration",
              "A forceful take-off measured the same way. Classified as braking or acceleration by whether your GPS speed was falling or rising.")
        entry("Exceeded Speed Limit",
              "Each time your GPS speed crossed the road's posted limit, from OpenStreetMap's signed-limit data. Counted once per crossing — hovering at the line doesn't stack.")
        entry("Exceeded Limit by 5+ mph",
              "Each time you went more than 5 mph past the posted limit. Weighs more than a plain crossing.")
    }

    @ViewBuilder private var tips: some View {
        Text("Keep the score green by driving the way you'd want the car behind you to.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        entry("Hard Braking",
              "Leave more following distance — most hard braking is a following-distance problem arriving on schedule.")
        entry("Hard Acceleration",
              "Ease onto the pedal from lights and stop signs; arriving two seconds later costs nothing.")
        entry("Speed Limits",
              "Watch the posted-limit sign on the Drive tab — the speed readout turns red the moment you're over. The vs-Limit trip map shows exactly where it happens.")
        entry("Alerts",
              "Set your own max speed or a +5 alert in Settings (or just tell Roadie: \u{201C}warn me if I go 5 over\u{201D}) and your watch will buzz before it becomes a score event.")
    }

    @ViewBuilder private var indicators: some View {
        Text("Each factor shows a three-segment indicator for the day. Fewer events, greener day — the goal is driving at expected, not perfection theater.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

        indicator(.green, "Clean", "None today. This is the goal state.")
        indicator(.yellow, "A few", "One or two events — worth a glance at where they happened on the trip map.")
        indicator(.red, "Several", "Three or more — the day's map and events list will show the pattern.")

        Text("The Drive Score itself is deterministic: it starts each day at 100 and reflects these counts. No fleet comparison, no black box — your driving against the road's own rules.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func entry(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func indicator(_ color: Color, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { segment in
                    Capsule()
                        .fill(segmentColor(color, segment: segment) )
                        .frame(height: 5)
                }
            }
            .frame(width: 150)
            Text(title).font(.headline)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func segmentColor(_ color: Color, segment: Int) -> Color {
        let position = color == .green ? 0 : (color == .yellow ? 1 : 2)
        return segment == position ? color : Color(.systemFill)
    }
}
