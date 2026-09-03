import SwiftData
import SwiftUI

/// The Sessions timeline: everything the phone knows you did — drives,
/// walks, workouts, sleep, stops — as Fitness-style cards with filter
/// chips. Rendered dark like its inspiration; every source is on-device.
struct SessionsView: View {
    @Query(sort: \Trip.startDate, order: .reverse) private var trips: [Trip]

    @State private var filter: SessionItem.Kind?
    @State private var items: [SessionItem] = []
    @State private var loaded = false
    @State private var health = HealthSessions()
    @State private var walkHistory = WalkHistory()

    private static let accent = Color(red: 0.75, green: 0.95, blue: 0.1)

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
        .background(Color.black)
        .preferredColorScheme(.dark)
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
        let selected = filter == kind
        return Button {
            filter = kind
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .fixedSize()
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(selected ? Self.accent : Color(white: 0.14), in: Capsule())
                .foregroundStyle(selected ? .black : .white)
        }
        .buttonStyle(.plain)
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
                SessionCardLink(item: item, accent: Self.accent)
            }
        }
    }

    /// Assembles instantly from cache, then warms missing stop names in
    /// the background and assembles once more with them filled in.
    private func rebuild() async {
        let now = Date.now
        let from = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let result = await SessionAssembler.assemble(
            trips: trips, from: from, to: now, health: health, walkHistory: walkHistory
        )
        items = result.items
        loaded = true
        if !result.unresolved.isEmpty {
            await SessionAssembler.warmNames(result.unresolved)
            items = await SessionAssembler.assemble(
                trips: trips, from: from, to: now, health: health, walkHistory: walkHistory
            ).items
        }
    }
}


/// One Fitness-style card: dark rounded rectangle, circular icon, big
/// accent metric, date at the trailing edge.
struct SessionCard: View {
    let item: SessionItem
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.16))
                Image(systemName: item.symbol)
                    .font(.title3)
                    .foregroundStyle(accent)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(item.metric)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(accent)
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
        .padding(16)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: 22))
    }
}
