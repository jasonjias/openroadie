import SwiftUI

/// The selected day's activities as Fitness-style cards, inline on the
/// Trips tab under Drives — deliberately redundant with the Story section
/// and the Sessions screen while the presentation gets chosen.
struct DaySessionsSection: View {
    /// The day's completed trips, oldest first.
    let trips: [Trip]
    let day: Date

    @State private var filter: SessionItem.Kind?
    @State private var items: [SessionItem] = []
    @State private var health = HealthSessions()
    @State private var walkHistory = WalkHistory()

    private static let accent = Color(red: 0.75, green: 0.95, blue: 0.1)

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip(nil, "All")
                    chip(.drive, "Drives")
                    chip(.walk, "Walks")
                    chip(.workout, "Workouts")
                    chip(.sleep, "Sleep")
                    chip(.stop, "Stops")
                }
            }
            .listRowSeparator(.hidden)

            let shown = items.filter { filter == nil || $0.kind == filter }
            if shown.isEmpty {
                Text("Nothing for this day yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { item in
                SessionCardLink(item: item, accent: Self.accent)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
        } header: {
            SectionHeader("Sessions")
        }
        .task(id: taskKey) {
            await health.requestAccess()
            await rebuild()
        }
    }

    /// Re-assemble when the day changes or its drives do.
    private var taskKey: String {
        "\(day.timeIntervalSinceReferenceDate)-\(trips.count)"
    }

    private func chip(_ kind: SessionItem.Kind?, _ label: String) -> some View {
        let selected = filter == kind
        return Button {
            filter = kind
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .fixedSize()
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(selected ? Self.accent : Color(.systemGray5), in: Capsule())
                .foregroundStyle(selected ? .black : .primary)
        }
        .buttonStyle(.plain)
    }

    private func rebuild() async {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: day)
        let to = calendar.date(byAdding: .day, value: 1, to: from) ?? from
        // Sleep looks 12 h back so last night belongs to this morning.
        let result = await SessionAssembler.assemble(
            trips: trips, from: from, to: to, sleepLookback: 12 * 3_600,
            health: health, walkHistory: walkHistory
        )
        items = result.items
        if !result.unresolved.isEmpty {
            await SessionAssembler.warmNames(result.unresolved)
            items = await SessionAssembler.assemble(
                trips: trips, from: from, to: to, sleepLookback: 12 * 3_600,
                health: health, walkHistory: walkHistory
            ).items
        }
    }
}
