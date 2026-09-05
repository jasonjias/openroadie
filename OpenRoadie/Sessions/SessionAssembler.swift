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
        // Ambient walk fragments (motion history) become OUTINGS: every
        // fragment inside one stay is a single walk — in, lunch, out — and
        // loose fragments merge across gaps under an hour. One card, one
        // trail, instead of a dozen three-minute shards.
        let recorded = walkPaths.filter { $0.startDate >= from && $0.startDate < to }
        let kept = SessionBuilder.walks(
            allWalks.map { ($0.start, $0.end) },
            notCoveredBy: workouts.map { ($0.start, $0.end) }
                // A "walk" overlapping a drive is a Core Motion misread —
                // a passenger's fidgeting is not a walk.
                + completed.map { ($0.startDate, $0.endDate ?? $0.startDate) }
        )
        let stopWindows = placedStops.map { ($0.start, $0.end) }
        // Every moment a trip pinned the phone somewhere — walk anchors when
        // no stay claims the outing.
        var fixes: [(date: Date, coordinate: Coordinate)] = []
        for trip in completed {
            if let first = trip.route.first {
                fixes.append((trip.startDate, Coordinate(latitude: first.latitude, longitude: first.longitude)))
            }
            if let last = trip.route.last, let end = trip.endDate {
                fixes.append((end, Coordinate(latitude: last.latitude, longitude: last.longitude)))
            }
        }
        var trailsUsed = Set<Date>()
        for group in SessionBuilder.bundleWalks(kept, stops: stopWindows) {
            let fragments = group.map { kept[$0] }
            guard let start = fragments.map(\.start).min(),
                  let end = fragments.map(\.end).max() else { continue }
            let walkingSeconds = fragments.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
            let records = fragments.compactMap { fragment in allWalks.first { $0.start == fragment.start } }
            var meters = 0.0
            var measured = false
            var steps = 0
            for record in records {
                if let m = SessionBuilder.walkMeters(pedometerMeters: record.meters, steps: record.steps) {
                    meters += m
                    measured = true
                }
                steps += record.steps ?? 0
            }
            // Where: the stay it happened in, else the nearest parked fix.
            let stopIndex = SessionBuilder.enclosingStop(of: start, in: stopWindows)
            let place = stopIndex.map { placedStops[$0].name } ?? nil
            var anchor = stopIndex.flatMap { placedStops[$0].coordinate }
                ?? SessionBuilder.nearestFix(to: start, in: fixes)
            // The trail: a recorded WalkPath overlapping the outing beats
            // wake-up crumbs; crumbs beat a bare anchor.
            var route: [Coordinate]?
            var coarse = false
            if let trail = recorded.first(where: { $0.startDate < end && $0.endDate > start && !trailsUsed.contains($0.startDate) }) {
                trailsUsed.insert(trail.startDate)
                let coordinates = trail.coordinates
                if coordinates.count >= 2 { route = coordinates }
                anchor = coordinates.first ?? anchor
                if !measured, trail.distance > 0 {
                    meters = trail.distance
                    measured = true
                }
            } else {
                let crumbs = SessionBuilder.crumbTrail(for: (start, end), crumbs: crumbs)
                if crumbs.count >= 2 {
                    route = crumbs
                    coarse = true
                }
                anchor = crumbs.first ?? anchor
            }
            let walked = DriveFormatting.compactDuration(walkingSeconds)
            var facts = ["walked \(walked)"]
            if steps > 0 { facts.append("\(steps) steps") }
            items.append(SessionItem(
                id: "walk-\(start.timeIntervalSince1970)",
                kind: .walk, symbol: "figure.walk", title: "Walk",
                placeName: place,
                metric: measured
                    ? DriveFormatting.shortDistance(fromMeters: meters).uppercased()
                    : walked.uppercased(),
                subtitle: facts.joined(separator: " · "),
                start: start, end: end,
                coordinate: anchor,
                meters: measured ? meters : nil,
                route: route,
                routeIsCoarse: coarse
            ))
        }

        // A recorded trail no ambient fragment claimed still stands alone.
        for path in recorded where !trailsUsed.contains(path.startDate) {
            let coordinates = path.coordinates
            var trailPlace: String?
            if let index = SessionBuilder.enclosingStop(of: path.startDate, in: stopWindows) {
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
                route: coordinates.count >= 2 ? coordinates : nil
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
