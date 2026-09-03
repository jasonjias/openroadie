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
        walkPaths: [WalkPath] = [],
        crumbs: [(date: Date, coordinate: Coordinate)] = [],
        from: Date,
        to: Date,
        sleepLookback: TimeInterval = 0,
        health: HealthSessions,
        walkHistory: WalkHistory
    ) async -> Result {
        let calendar = Calendar.current
        var items: [SessionItem] = []
        var unresolved: [Coordinate] = []

        // Drives shown are the window's; stays are computed over ALL
        // completed trips so the overnight at home is one stay, not a hole.
        let allCompleted = trips.filter { $0.endDate != nil }
        let completed = allCompleted.filter {
            $0.startDate >= from && $0.startDate < to
        }

        for trip in completed {
            guard let end = trip.endDate else { continue }
            // Kind is the title; where it went joins the facts line —
            // long street names were truncating the headline.
            var placeName: String?
            if let last = trip.route.last {
                let destination = Coordinate(latitude: last.latitude, longitude: last.longitude)
                placeName = PlaceNamer.shared.cachedName(for: destination)
                if placeName == nil { unresolved.append(destination) }
            }
            var facts = [DriveFormatting.compactDuration(end.timeIntervalSince(trip.startDate))]
            if let base = placeName?.components(separatedBy: " · ").first {
                facts.append("→ \(base)")
            }
            items.append(SessionItem(
                id: "drive-\(trip.startDate.timeIntervalSince1970)",
                kind: .drive, symbol: "car.fill", title: "Drive",
                placeName: placeName,
                metric: DriveFormatting.miles(fromMeters: trip.distance).uppercased(),
                subtitle: facts.joined(separator: " · "),
                start: trip.startDate, end: end,
                tripID: trip.persistentModelID,
                weather: trip.weather,
                usAqi: trip.usAqi
            ))
        }

        // Stays: every moment between drives, across day boundaries and up
        // to now — the continuous stream. Named from cache; the place name
        // decides what the stay most likely WAS (Meal, Gym, Shopping…).
        var placedStops: [(start: Date, end: Date, name: String?, coordinate: Coordinate?)] = []
        let stays = SessionBuilder.stays(
            between: allCompleted.map { trip in
                let last = trip.route.last
                return (trip.startDate, trip.endDate ?? trip.startDate,
                        last.map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) })
            },
            until: min(to, .now)
        )
        for stay in stays where stay.end > from && stay.start < to {
            var name: String?
            if let coordinate = stay.coordinate {
                name = PlaceNamer.shared.cachedName(for: coordinate)
                if name == nil { unresolved.append(coordinate) }
            }
            placedStops.append((stay.start, stay.end, name, stay.coordinate))
            let activity = SessionBuilder.stopActivity(forPlaceName: name)
            items.append(SessionItem(
                id: "stop-\(stay.start.timeIntervalSince1970)",
                kind: .stop,
                symbol: activity.symbol,
                title: activity.title,
                placeName: name,
                metric: DriveFormatting.compactDuration(stay.end.timeIntervalSince(stay.start)).uppercased(),
                subtitle: name?.components(separatedBy: " · ").first,
                start: stay.start, end: stay.end,
                coordinate: stay.coordinate
            ))
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
        // Recorded trails first: real breadcrumbs beat inferred intervals.
        let recorded = walkPaths.filter { $0.startDate >= from && $0.startDate < to }
        let kept = SessionBuilder.walks(
            allWalks.map { ($0.start, $0.end) },
            notCoveredBy: workouts.map { ($0.start, $0.end) }
                + recorded.map { ($0.startDate, $0.endDate) }
                // A "walk" overlapping a drive is a Core Motion misread —
                // a passenger's fidgeting is not a walk.
                + completed.map { ($0.startDate, $0.endDate ?? $0.startDate) }
        )
        // Every moment a trip pinned the phone somewhere — walk anchors.
        var fixes: [(date: Date, coordinate: Coordinate)] = []
        for trip in completed {
            if let first = trip.route.first {
                fixes.append((trip.startDate, Coordinate(latitude: first.latitude, longitude: first.longitude)))
            }
            if let last = trip.route.last, let end = trip.endDate {
                fixes.append((end, Coordinate(latitude: last.latitude, longitude: last.longitude)))
            }
        }
        for interval in kept {
            let walk = allWalks.first { $0.start == interval.start }
            let duration = DriveFormatting.compactDuration(interval.end.timeIntervalSince(interval.start))
            // Same emphasis as a drive card: distance big, time in the
            // facts line. Only a walk the pedometer couldn't measure leads
            // with its duration.
            var metric = duration.uppercased()
            var walkFacts: [String] = []
            let meters = SessionBuilder.walkMeters(pedometerMeters: walk?.meters, steps: walk?.steps)
            if let meters {
                metric = DriveFormatting.shortDistance(fromMeters: meters).uppercased()
                walkFacts.append(duration)
            }
            if let steps = walk?.steps {
                walkFacts.append("\(steps) steps")
            }
            // A walk inside a stop's window happened AT that place — "where
            // was I shopping" answered from time-window logic alone.
            var walkPlace: String?
            var anchor = SessionBuilder.nearestFix(to: interval.start, in: fixes)
            // Always-on wake crumbs that fell during this walk: two or more
            // make a coarse trail; even one beats a nearest-fix guess.
            let trail = SessionBuilder.crumbTrail(for: interval, crumbs: crumbs)
            if let first = trail.first {
                anchor = first
            }
            if let index = SessionBuilder.enclosingStop(
                of: interval.start,
                in: placedStops.map { ($0.start, $0.end) }
            ) {
                let stop = placedStops[index]
                walkPlace = stop.name
                anchor = stop.coordinate ?? anchor
            }
            items.append(SessionItem(
                id: "walk-\(interval.start.timeIntervalSince1970)",
                kind: .walk, symbol: "figure.walk", title: "Walk",
                placeName: walkPlace,
                metric: metric,
                subtitle: walkFacts.isEmpty ? nil : walkFacts.joined(separator: " · "),
                start: interval.start, end: interval.end,
                coordinate: anchor,
                meters: meters,
                route: trail.count >= 2 ? trail : nil,
                routeIsCoarse: trail.count >= 2
            ))
        }

        for path in recorded {
            let coordinates = path.coordinates
            var trailPlace: String?
            if let index = SessionBuilder.enclosingStop(
                of: path.startDate,
                in: placedStops.map { ($0.start, $0.end) }
            ) {
                trailPlace = placedStops[index].name
            }
            let duration = DriveFormatting.compactDuration(path.endDate.timeIntervalSince(path.startDate))
            items.append(SessionItem(
                id: "walkpath-\(path.startDate.timeIntervalSince1970)",
                kind: .walk, symbol: "figure.walk", title: "Walk",
                placeName: trailPlace,
                metric: DriveFormatting.shortDistance(fromMeters: path.distance).uppercased(),
                subtitle: duration,
                start: path.startDate, end: path.endDate,
                coordinate: coordinates.first,
                meters: path.distance,
                route: coordinates
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
