import SwiftData
import SwiftUI

/// The Sessions timeline: everything the phone knows you did — drives,
/// walks, workouts, sleep, stops — as Fitness-style cards with filter
/// chips. Rendered dark like its inspiration; every source is on-device.
struct SessionsView: View {
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]

    @Environment(\.modelContext) private var modelContext

    @State private var filter: SessionItem.Kind?
    @State private var items: [SessionItem] = []
    @State private var loaded = false
    @State private var health = HealthSessions()
    @State private var walkHistory = WalkHistory()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                chips
                if !loaded {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    cards
                }
            }
            .padding(.horizontal)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Sessions")
        .task {
            await health.requestAccess()
            await rebuild()
            loaded = true
        }
    }

    private var chips: some View {
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
    }

    private func chip(_ kind: SessionItem.Kind?, _ label: String) -> some View {
        SessionChip(kind: kind, label: label, selected: filter == kind) {
            filter = kind
        }
    }

    @ViewBuilder
    private var cards: some View {
        let shown = items.filter { filter == nil || $0.kind == filter }
        let months = Dictionary(grouping: shown) { item in
            Calendar.current.dateInterval(of: .month, for: item.start)?.start ?? item.start
        }
        if shown.isEmpty {
            Text(filter == .sleep || filter == .workout
                 ? "Nothing here yet — this comes from Health, so it needs Health access and a watch (or app) that records it."
                 : "Nothing here yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 40)
                .frame(maxWidth: .infinity)
        }
        ForEach(months.keys.sorted(by: >), id: \.self) { month in
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title.bold())
                .padding(.top, 6)
            ForEach(months[month] ?? []) { item in
                SessionCardLink(item: item)
            }
        }
    }

    /// Assembles instantly from cache, then warms missing stop names in
    /// the background and assembles once more with them filled in.
    private func rebuild() async {
        let now = Date.now
        let from = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let paths = (try? modelContext.fetch(FetchDescriptor<WalkPath>(
            predicate: #Predicate { $0.startDate >= from && $0.startDate < now }
        ))) ?? []
        let crumbs = ((try? modelContext.fetch(FetchDescriptor<LocationCrumb>(
            predicate: #Predicate { $0.timestamp >= from && $0.timestamp < now }
        ))) ?? []).map { (date: $0.timestamp, coordinate: $0.coordinate) }
        let result = await SessionAssembler.assemble(
            trips: trips, walkPaths: paths, crumbs: crumbs, from: from, to: now, health: health, walkHistory: walkHistory
        )
        items = result.items
        loaded = true
        if !result.unresolved.isEmpty {
            await SessionAssembler.warmNames(result.unresolved)
            items = await SessionAssembler.assemble(
                trips: trips, walkPaths: paths, crumbs: crumbs, from: from, to: now, health: health, walkHistory: walkHistory
            ).items
        }
    }
}


/// One Fitness-style card: dark rounded rectangle, circular icon, big
/// accent metric, date at the trailing edge.
struct SessionCard: View {
    let item: SessionItem

    var body: some View {
        let tint = item.kind.tint
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                    Image(systemName: item.symbol)
                        .font(.title3)
                        .foregroundStyle(tint)
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(item.metric)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(item.start.formatted(.dateTime.month(.defaultDigits).day().year(.twoDigits)))
                    Text(item.start.formatted(.dateTime.hour().minute()))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let subtitle = item.subtitle {
                // Its own full-width row under the header, aligned with the
                // text column — long street names get the whole card width
                // instead of squeezing beside the date.
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 66)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}

/// A filter chip that shows its kind's color when selected — "All" gets
/// the app accent.
struct SessionChip: View {
    let kind: SessionItem.Kind?
    let label: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    selected ? (kind?.tint ?? .accentColor) : Color(.secondarySystemGroupedBackground),
                    in: Capsule()
                )
                .foregroundStyle(selected ? Color.white : .primary)
        }
        .buttonStyle(.plain)
    }
}
