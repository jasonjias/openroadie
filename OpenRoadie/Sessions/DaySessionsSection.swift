import SwiftData
import SwiftUI

/// The selected day's activities as Fitness-style cards, inline on the
/// Trips tab under Drives — deliberately redundant with the Story section
/// and the Sessions screen while the presentation gets chosen.
struct DaySessionsSection: View {
    /// The day's completed trips, oldest first.
    let trips: [Trip]
    let day: Date
    /// A drive still recording right now, shown as a live card up top.
    var recordingTrip: Trip? = nil

    @Environment(\.modelContext) private var modelContext

    @State private var filter: SessionItem.Kind?
    @State private var items: [SessionItem] = []
    @State private var health = HealthSessions()
    @State private var walkHistory = WalkHistory()

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

            if let recordingTrip {
                recordingCard(recordingTrip)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            let shown = items.filter { filter == nil || $0.kind == filter }
            if shown.isEmpty, recordingTrip == nil {
                Text("Nothing for this day yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(shown) { item in
                SessionCardLink(item: item)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .swipeActions(edge: .trailing) {
                        // Only drives are OURS to delete — walks, workouts
                        // and sleep belong to Health and motion history.
                        if item.kind == .drive, let tripID = item.tripID {
                            Button(role: .destructive) {
                                if let trip = modelContext.model(for: tripID) as? Trip {
                                    modelContext.delete(trip)
                                    try? modelContext.save()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
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

    /// A drive in progress — live pulse, started time, no navigation
    /// (its numbers live on the Drive tab until it saves).
    private func recordingCard(_ trip: Trip) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.red.opacity(0.14))
                Image(systemName: "record.circle")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Drive")
                    .font(.headline)
                Text("Recording…")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 4)
            Text("since \(trip.startDate.formatted(.dateTime.hour().minute()))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func chip(_ kind: SessionItem.Kind?, _ label: String) -> some View {
        SessionChip(kind: kind, label: label, selected: filter == kind) {
            filter = kind
        }
    }

    private func rebuild() async {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: day)
        let to = calendar.date(byAdding: .day, value: 1, to: from) ?? from
        // Sleep looks 12 h back so last night belongs to this morning.
        let paths = (try? modelContext.fetch(FetchDescriptor<WalkPath>(
            predicate: #Predicate { $0.startDate >= from && $0.startDate < to }
        ))) ?? []
        let crumbs = ((try? modelContext.fetch(FetchDescriptor<LocationCrumb>(
            predicate: #Predicate { $0.timestamp >= from && $0.timestamp < to }
        ))) ?? []).map { (date: $0.timestamp, coordinate: $0.coordinate) }
        let result = await SessionAssembler.assemble(
            trips: trips, walkPaths: paths, crumbs: crumbs, from: from, to: to, sleepLookback: 12 * 3_600,
            health: health, walkHistory: walkHistory
        )
        items = result.items
        if !result.unresolved.isEmpty {
            await SessionAssembler.warmNames(result.unresolved)
            items = await SessionAssembler.assemble(
                trips: trips, walkPaths: paths, crumbs: crumbs, from: from, to: to, sleepLookback: 12 * 3_600,
                health: health, walkHistory: walkHistory
            ).items
        }
    }
}
