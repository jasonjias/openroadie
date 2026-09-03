import Foundation
import SwiftData

/// A completed (or in-progress) drive, persisted locally with SwiftData.
/// Driving history never leaves the device.
@Model
final class Trip {
    var startDate: Date
    /// `nil` while the drive is still recording (or if the app died mid-drive;
    /// see `TripStore.closeDanglingTrips`).
    var endDate: Date?
    /// Meters, as accumulated by `TripTracker`.
    var distance: Double
    /// Meters per second.
    var maxSpeed: Double?
    /// Weather during the drive (Open-Meteo, stamped once at drive end and
    /// backfilled for older trips). All nil when unknown or disabled —
    /// optional so existing stores migrate in place.
    var weatherCode: Int?
    var temperatureC: Double?
    var precipitationMm: Double?
    var windKph: Double?
    /// Daylight during the drive — drives the weather card's sun-or-moon.
    /// nil on rows stamped before the field existed (hour heuristic then).
    var weatherIsDay: Bool?
    /// US AQI during the drive; nil when unknown (or the drive predates
    /// Open-Meteo's recent-window air-quality data).
    var usAqi: Int?

    @Relationship(deleteRule: .cascade, inverse: \TripPoint.trip)
    var points: [TripPoint]

    init(startDate: Date) {
        self.startDate = startDate
        self.endDate = nil
        self.distance = 0
        self.maxSpeed = nil
        self.points = []
    }

    var weather: TripWeather? {
        guard let weatherCode, let temperatureC else { return nil }
        // Rows stamped before day/night was stored fall back to the hour.
        let hour = Calendar.current.component(.hour, from: startDate)
        return TripWeather(
            wmoCode: weatherCode,
            temperatureC: temperatureC,
            precipitationMm: precipitationMm ?? 0,
            windKph: windKph ?? 0,
            isDay: weatherIsDay ?? (6..<20).contains(hour)
        )
    }

    /// The moment and place to ask the weather about: mid-drive, at the
    /// last known position.
    var weatherAnchor: (date: Date, coordinate: Coordinate)? {
        guard let last = route.last else { return nil }
        let mid = startDate.addingTimeInterval((endDate ?? last.timestamp).timeIntervalSince(startDate) / 2)
        return (mid, Coordinate(latitude: last.latitude, longitude: last.longitude))
    }

    var duration: TimeInterval? {
        guard let endDate else { return nil }
        return endDate.timeIntervalSince(startDate)
    }

    /// Meters per second, from stored distance and duration.
    var averageSpeed: Double? {
        guard let duration, duration > 0 else { return nil }
        return distance / duration
    }

    /// SwiftData relationships are unordered; the route is points by time.
    var route: [TripPoint] {
        points.sorted { $0.timestamp < $1.timestamp }
    }
}

/// One recorded position along a trip's route — appended whenever the
/// tracker's position meaningfully advances (roughly every 10 m or more).
@Model
final class TripPoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    /// Meters per second; `nil` when GPS didn't know.
    var speed: Double?
    /// Meters above sea level; `nil` when GPS didn't know.
    var altitude: Double?
    /// Posted limit here (m/s) when road awareness knew it — powers the
    /// "vs Limit" map coloring.
    var speedLimit: Double?
    var trip: Trip?

    init(timestamp: Date, latitude: Double, longitude: Double, speed: Double?, altitude: Double?, speedLimit: Double? = nil) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.altitude = altitude
        self.speedLimit = speedLimit
    }
}

/// All writes to trip history go through here. Reads in SwiftUI use `@Query`.
@MainActor
final class TripStore {
    let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer) {
        self.container = container
    }

    static func persistent() throws -> TripStore {
        TripStore(container: try ModelContainer(for: Trip.self, TripPoint.self, DriveNote.self, DriveEvent.self, WalkPath.self, LocationCrumb.self))
    }

    static func inMemory() throws -> TripStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return TripStore(container: try ModelContainer(for: Trip.self, TripPoint.self, DriveNote.self, DriveEvent.self, WalkPath.self, LocationCrumb.self, configurations: config))
    }

    func beginTrip(at date: Date = .now) -> Trip {
        let trip = Trip(startDate: date)
        context.insert(trip)
        return trip
    }

    /// Records the context's current position as a route point.
    /// No-op if the context has no fix yet.
    func recordPoint(from drivingContext: DrivingContext, in trip: Trip) {
        guard let coordinate = drivingContext.coordinate,
              let timestamp = drivingContext.timestamp else { return }
        let point = TripPoint(
            timestamp: timestamp,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            speed: drivingContext.speed,
            altitude: drivingContext.altitude,
            speedLimit: drivingContext.road?.speedLimit
        )
        point.trip = trip
        context.insert(point)
    }

    /// Finalizes a trip. Trips with fewer than two points carry no route worth
    /// keeping (a Start/Stop tap in a parking spot) and are discarded.
    func endTrip(_ trip: Trip, at date: Date, distance: Double, maxSpeed: Double?) {
        // Points after the end are parked GPS drift recorded while the
        // auto-end detectors were still deciding — not route.
        for point in trip.points where point.timestamp > date.addingTimeInterval(1) {
            context.delete(point)
        }
        if trip.points.count < 2 {
            context.delete(trip)
            return
        }
        trip.endDate = date
        trip.distance = distance
        trip.maxSpeed = maxSpeed
        try? context.save()
    }

    /// Most recent completed trips, newest first — used by the agent's
    /// trip-history tool. SwiftUI reads use `@Query` instead.
    func recentTrips(limit: Int) -> [Trip] {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endDate != nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Current and best clean-drive streaks across all history.
    func streak() -> Streak.Summary {
        let completed = (try? context.fetch(FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endDate != nil }
        ))) ?? []
        return Streak.compute(trips: completed, events: allEvents())
    }

    // MARK: - Walk trails

    func saveWalkPath(start: Date, end: Date, distance: Double, coordinates: [Coordinate]) {
        context.insert(WalkPath(startDate: start, endDate: end, distance: distance, coordinates: coordinates))
        try? context.save()
    }

    func saveCrumb(_ coordinate: Coordinate, accuracy: Double, at date: Date = .now) {
        context.insert(LocationCrumb(timestamp: date, coordinate: coordinate, accuracy: accuracy))
        try? context.save()
    }

    /// Crumbs older than the motion-history window have nothing to attach
    /// to — prune them at launch.
    func pruneCrumbs(olderThan cutoff: Date) {
        let stale = (try? context.fetch(FetchDescriptor<LocationCrumb>(
            predicate: #Predicate { $0.timestamp < cutoff }
        ))) ?? []
        for crumb in stale {
            context.delete(crumb)
        }
        if !stale.isEmpty {
            try? context.save()
        }
    }

    // MARK: - Weather

    func setWeather(_ weather: TripWeather, airQuality: Int? = nil, on trip: Trip) {
        trip.weatherCode = weather.wmoCode
        trip.temperatureC = weather.temperatureC
        trip.precipitationMm = weather.precipitationMm
        trip.windKph = weather.windKph
        trip.weatherIsDay = weather.isDay
        if let airQuality {
            trip.usAqi = airQuality
        }
        try? context.save()
    }

    /// Completed trips still missing weather, oldest last so recent drives
    /// (the ones being looked at) backfill first.
    func tripsNeedingWeather(limit: Int) -> [Trip] {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endDate != nil && $0.weatherCode == nil },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).filter { !$0.points.isEmpty }
    }

    // MARK: - Driving events

    func saveEvent(kind: String, peakG: Double, coordinate: Coordinate?, speedMph: Double?) {
        context.insert(DriveEvent(kind: kind, peakG: peakG, coordinate: coordinate, speedMph: speedMph))
        try? context.save()
    }

    func allEvents() -> [DriveEvent] {
        (try? context.fetch(FetchDescriptor<DriveEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        ))) ?? []
    }

    // MARK: - Driving memory

    @discardableResult
    func saveNote(_ text: String, at coordinate: Coordinate?, timestamp: Date = .now) -> DriveNote {
        let note = DriveNote(text: text, coordinate: coordinate, timestamp: timestamp)
        context.insert(note)
        try? context.save()
        return note
    }

    func recentNotes(limit: Int) -> [DriveNote] {
        var descriptor = FetchDescriptor<DriveNote>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Notes anchored within `radiusMeters` of a position, nearest first.
    /// Note counts stay small, so fetch-then-filter is fine.
    func notes(near coordinate: Coordinate, radiusMeters: Double) -> [DriveNote] {
        let all = (try? context.fetch(FetchDescriptor<DriveNote>())) ?? []
        return all
            .compactMap { note -> (DriveNote, Double)? in
                guard let anchor = note.coordinate else { return nil }
                let distance = TripTracker.distance(from: coordinate, to: anchor)
                return distance <= radiusMeters ? (note, distance) : nil
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Recovers from an app death mid-drive: any trip still open from a prior
    /// launch is closed at its last recorded point (with distance rebuilt from
    /// the route), or discarded if it never really went anywhere.
    func closeDanglingTrips() {
        let openTrips = (try? context.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.endDate == nil })
        )) ?? []

        for trip in openTrips {
            let route = trip.route
            guard route.count >= 2, let last = route.last else {
                context.delete(trip)
                continue
            }
            trip.endDate = last.timestamp
            trip.distance = zip(route, route.dropFirst()).reduce(0) { total, pair in
                total + TripTracker.distance(
                    from: Coordinate(latitude: pair.0.latitude, longitude: pair.0.longitude),
                    to: Coordinate(latitude: pair.1.latitude, longitude: pair.1.longitude)
                )
            }
            trip.maxSpeed = route.compactMap(\.speed).max()
        }
        try? context.save()
    }
}
