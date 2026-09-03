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
                SessionCard(item: item, accent: Self.accent)
            }
        }
    }

    /// Assembles the timeline from every source. Walks come from motion
    /// history (~a week); trips and Health reach back 30 days.
    private func rebuild() async {
        let calendar = Calendar.current
        let now = Date.now
        let from = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        var built: [SessionItem] = []

        let completed = trips.filter { $0.endDate != nil && $0.startDate >= from }

        for trip in completed {
            guard let end = trip.endDate else { continue }
            built.append(SessionItem(
                id: "drive-\(trip.startDate.timeIntervalSince1970)",
                kind: .drive, symbol: "car.fill", title: "Drive",
                metric: DriveFormatting.miles(fromMeters: trip.distance).uppercased(),
                start: trip.startDate, end: end
            ))
        }

        // Stops: the gaps between one day's drives, named by the geocoder.
        let byDay = Dictionary(grouping: completed) { calendar.startOfDay(for: $0.startDate) }
        for (_, dayTrips) in byDay {
            let ordered = dayTrips.sorted { $0.startDate < $1.startDate }
            let stops = DayStory.stops(between: ordered.map { trip in
                let last = trip.route.last
                return (trip.startDate, trip.endDate ?? trip.startDate,
                        last.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) })
            })
            for stop in stops {
                let start = ordered[stop.afterTrip].endDate ?? ordered[stop.afterTrip].startDate
                let name = await stop.coordinate.asyncFlatMap { await PlaceNamer.shared.name(for: $0) }
                built.append(SessionItem(
                    id: "stop-\(start.timeIntervalSince1970)",
                    kind: .stop,
                    symbol: SessionBuilder.stopSymbol(forPlaceName: name),
                    title: name ?? "Stop",
                    metric: DriveFormatting.compactDuration(stop.duration).uppercased(),
                    start: start, end: start.addingTimeInterval(stop.duration)
                ))
            }
        }

        let workouts = await health.workouts(from: from, to: now)
        for workout in workouts {
            let look = HealthSessions.workoutPresentation(activity: workout.activity)
            let metric: String = if let meters = workout.meters, meters > 150 {
                String(format: "%.2f MI", meters / 1609.344)
            } else if let kcal = workout.kilocalories {
                "\(Int(kcal.rounded())) CAL"
            } else {
                DriveFormatting.compactDuration(workout.end.timeIntervalSince(workout.start)).uppercased()
            }
            built.append(SessionItem(
                id: "workout-\(workout.start.timeIntervalSince1970)",
                kind: .workout, symbol: look.symbol, title: look.title,
                metric: metric, start: workout.start, end: workout.end
            ))
        }

        for night in await health.sleepNights(from: from, to: now) {
            built.append(SessionItem(
                id: "sleep-\(night.start.timeIntervalSince1970)",
                kind: .sleep, symbol: "bed.double.fill", title: "Sleep",
                metric: DriveFormatting.compactDuration(night.asleepSeconds).uppercased(),
                start: night.start, end: night.end
            ))
        }

        // Ambient walks last, minus any covered by a deliberate workout.
        var walkIntervals: [(start: Date, end: Date)] = []
        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { continue }
            walkIntervals += (await walkHistory.walks(on: day)).map { ($0.start, $0.end) }
        }
        let ambient = SessionBuilder.walks(
            walkIntervals,
            notCoveredBy: workouts.map { ($0.start, $0.end) }
        )
        for walk in ambient {
            built.append(SessionItem(
                id: "walk-\(walk.start.timeIntervalSince1970)",
                kind: .walk, symbol: "figure.walk", title: "Walk",
                metric: DriveFormatting.compactDuration(walk.end.timeIntervalSince(walk.start)).uppercased(),
                start: walk.start, end: walk.end
            ))
        }

        items = built.sorted { $0.start > $1.start }
    }
}

private extension Optional {
    func asyncFlatMap<T>(_ transform: (Wrapped) async -> T?) async -> T? {
        switch self {
        case .some(let value): await transform(value)
        case .none: nil
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
