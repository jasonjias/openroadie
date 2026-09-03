import Foundation

/// Builds the Sessions timeline from every on-device source. Never waits
/// on the network: stop names come from the geocoder's cache only (the
/// first Sessions screen hung for minutes serially geocoding a month of
/// stops) — misses are reported back so the caller can warm them in the
/// background and assemble again.
@MainActor
enum SessionAssembler {
    struct Result {
        var items: [SessionItem]
        /// Stop coordinates whose names weren't cached yet.
        var unresolved: [Coordinate]
    }

    static func assemble(
        trips: [Trip],
        from: Date,
        to: Date,
        sleepLookback: TimeInterval = 0,
        health: HealthSessions,
        walkHistory: WalkHistory
    ) async -> Result {
        let calendar = Calendar.current
        var items: [SessionItem] = []
        var unresolved: [Coordinate] = []

        let completed = trips.filter {
            $0.endDate != nil && $0.startDate >= from && $0.startDate < to
        }

        for trip in completed {
            guard let end = trip.endDate else { continue }
            // The card says where the drive WENT — same noun the Story uses.
            var title = "Drive"
            if let last = trip.route.last {
                let destination = Coordinate(latitude: last.latitude, longitude: last.longitude)
                if let name = PlaceNamer.shared.cachedName(for: destination) {
                    title = "→ \(name)"
                } else {
                    unresolved.append(destination)
                }
            }
            // Two facts fit a card; the rest live one tap away in the detail.
            var facts = [DriveFormatting.compactDuration(end.timeIntervalSince(trip.startDate))]
            if let weather = trip.weather {
                facts.append("\(DriveFormatting.fahrenheit(fromCelsius: weather.temperatureC))° \(WeatherCode.label(weather.wmoCode))")
            }
            items.append(SessionItem(
                id: "drive-\(trip.startDate.timeIntervalSince1970)",
                kind: .drive, symbol: "car.fill", title: title,
                metric: DriveFormatting.miles(fromMeters: trip.distance).uppercased(),
                subtitle: facts.joined(separator: " · "),
                start: trip.startDate, end: end,
                tripID: trip.persistentModelID
            ))
        }

        // Stops: gaps between one day's drives, named from cache only.
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
                var name: String?
                if let coordinate = stop.coordinate {
                    name = PlaceNamer.shared.cachedName(for: coordinate)
                    if name == nil { unresolved.append(coordinate) }
                }
                items.append(SessionItem(
                    id: "stop-\(start.timeIntervalSince1970)",
                    kind: .stop,
                    symbol: SessionBuilder.stopSymbol(forPlaceName: name),
                    title: name ?? "Stop",
                    metric: DriveFormatting.compactDuration(stop.duration).uppercased(),
                    start: start, end: start.addingTimeInterval(stop.duration),
                    coordinate: stop.coordinate
                ))
            }
        }

        let workouts = await health.workouts(from: from, to: to)
        for workout in workouts {
            let look = HealthSessions.workoutPresentation(activity: workout.activity)
            let metric: String = if let meters = workout.meters, meters > 150 {
                String(format: "%.2f MI", meters / 1609.344)
            } else if let kcal = workout.kilocalories {
                "\(Int(kcal.rounded())) CAL"
            } else {
                DriveFormatting.compactDuration(workout.end.timeIntervalSince(workout.start)).uppercased()
            }
            var workoutFacts = [DriveFormatting.compactDuration(workout.end.timeIntervalSince(workout.start))]
            if let kcal = workout.kilocalories, metric.hasSuffix("MI") {
                workoutFacts.append("\(Int(kcal.rounded())) cal")
            }
            items.append(SessionItem(
                id: "workout-\(workout.start.timeIntervalSince1970)",
                kind: .workout, symbol: look.symbol, title: look.title,
                metric: metric, subtitle: workoutFacts.joined(separator: " · "),
                start: workout.start, end: workout.end,
                workoutUUID: workout.uuid
            ))
        }

        for night in await health.sleepNights(from: from.addingTimeInterval(-sleepLookback), to: to) {
            items.append(SessionItem(
                id: "sleep-\(night.start.timeIntervalSince1970)",
                kind: .sleep, symbol: "bed.double.fill", title: "Sleep",
                metric: DriveFormatting.compactDuration(night.asleepSeconds).uppercased(),
                subtitle: "in bed \(DriveFormatting.compactDuration(night.end.timeIntervalSince(night.start)))",
                start: night.start, end: night.end
            ))
        }

        // Ambient walks (motion history reaches back ~a week), minus any
        // covered by a deliberate workout.
        var allWalks: [WalkHistory.Walk] = []
        var day = calendar.startOfDay(for: min(to, .now))
        while day >= calendar.startOfDay(for: from),
              day > calendar.startOfDay(for: .now.addingTimeInterval(-8 * 86_400)) {
            allWalks += (await walkHistory.walks(on: day)).filter { $0.start >= from && $0.start < to }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        let kept = SessionBuilder.walks(
            allWalks.map { ($0.start, $0.end) },
            notCoveredBy: workouts.map { ($0.start, $0.end) }
        )
        for interval in kept {
            let walk = allWalks.first { $0.start == interval.start }
            var walkFacts: [String] = []
            if let meters = walk?.meters {
                walkFacts.append(DriveFormatting.shortDistance(fromMeters: meters))
            }
            if let steps = walk?.steps {
                walkFacts.append("\(steps) steps")
            }
            items.append(SessionItem(
                id: "walk-\(interval.start.timeIntervalSince1970)",
                kind: .walk, symbol: "figure.walk", title: "Walk",
                metric: DriveFormatting.compactDuration(interval.end.timeIntervalSince(interval.start)).uppercased(),
                subtitle: walkFacts.isEmpty ? nil : walkFacts.joined(separator: " · "),
                start: interval.start, end: interval.end
            ))
        }

        return Result(items: items.sorted { $0.start > $1.start }, unresolved: unresolved)
    }

    /// Resolves missing stop names (politely, serially); call assemble
    /// again afterwards for the named version.
    static func warmNames(_ coordinates: [Coordinate]) async {
        for coordinate in coordinates.prefix(20) {
            _ = await PlaceNamer.shared.name(for: coordinate)
        }
    }
}
