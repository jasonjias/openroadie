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
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("Factors") {
                    factorRow("Hard maneuvers", count: stats.hardEvents)
                    factorRow("Limit crossings", count: stats.overLimitCrossings)
                    factorRow("+5 mph over crossings", count: stats.wellOverCrossings)
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

    /// Tesla-style factor row: the count, and a three-segment severity bar
    /// (green / yellow / red) lit by how often it happened.
    private func factorRow(_ title: String, count: Int) -> some View {
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
