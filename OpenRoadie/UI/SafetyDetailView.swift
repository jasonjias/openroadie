import SwiftUI

/// The Drive Score, shown its work: the day's deductions line by line, the
/// 30-day overall, and every event behind the numbers. Deterministic math,
/// fully inspectable — the anti-black-box safety score.
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
                    VStack(spacing: 10) {
                        ScoreRing(score: stats.score, lineWidth: 11)
                            .frame(width: 120, height: 120)
                            .overlay {
                                if let score = stats.score {
                                    Text("\(score)")
                                        .font(.system(size: 38, weight: .bold, design: .rounded))
                                        .monospacedDigit()
                                } else {
                                    Text("—").font(.title).foregroundStyle(.tertiary)
                                }
                            }
                        if let overallScore {
                            Label("30-day average: \(overallScore)", systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("How it's calculated") {
                    breakdownRow("Starting score", detail: nil, points: "100")
                    breakdownRow(
                        "Hard maneuvers",
                        detail: "\(stats.hardEvents) × −8",
                        points: stats.hardEvents > 0 ? "−\(stats.hardEvents * 8)" : "0"
                    )
                    breakdownRow(
                        "Limit crossings",
                        detail: "\(stats.overLimitCrossings) × −3",
                        points: stats.overLimitCrossings > 0 ? "−\(stats.overLimitCrossings * 3)" : "0"
                    )
                    breakdownRow(
                        "+5 mph over crossings",
                        detail: "\(stats.wellOverCrossings) × −8",
                        points: stats.wellOverCrossings > 0 ? "−\(stats.wellOverCrossings * 8)" : "0"
                    )
                    HStack {
                        Text("Drive Score").fontWeight(.semibold)
                        Spacer()
                        Text(stats.score.map(String.init) ?? "—")
                            .fontWeight(.bold)
                            .monospacedDigit()
                    }
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func breakdownRow(_ title: String, detail: String?, points: String) -> some View {
        HStack {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(points)
                .monospacedDigit()
                .foregroundStyle(points.hasPrefix("−") ? .red : .primary)
        }
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
