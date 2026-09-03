import Foundation
import SwiftData

/// One entry in the Sessions timeline — a drive, a walk, a workout, a
/// night's sleep, or a stop at a place. The unifying shape behind the
/// Fitness-style cards: icon, title, one big metric, a moment in time.
struct SessionItem: Identifiable, Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case drive
        case walk
        case workout
        case sleep
        case stop
    }

    var id: String
    var kind: Kind
    /// SF Symbol for the card's circular icon.
    var symbol: String
    var title: String
    /// Where — shown in the facts line on cards, in full on the detail.
    var placeName: String?
    /// The big lime number — "1.9 MI", "152 CAL", "7h 12m".
    var metric: String
    /// Small secondary facts under the metric — "27 min · 74° Clear".
    var subtitle: String?
    var start: Date
    var end: Date
    /// The backing trip, for drive cards — tapping opens the full trip
    /// detail, same as the Drives list.
    var tripID: PersistentIdentifier?
    /// The backing HealthKit workout, for fetching its recorded route.
    var workoutUUID: UUID?
    /// Where it happened — exact for stops; for ambient walks, the nearest
    /// known fix (usually where the car parked just before).
    var coordinate: Coordinate?
    /// Distance covered, when known — sizes a walk's approximate area.
    var meters: Double?
    /// The drive's stamped weather and air quality, for the detail view.
    var weather: TripWeather?
    var usAqi: Int?
    /// A recorded trail (walk breadcrumbs) to draw in the detail.
    var route: [Coordinate]?
    /// True when the trail is wake-up crumbs (~one point per 500 m), not a
    /// continuous recording — the detail says so.
    var routeIsCoarse: Bool = false

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum SessionBuilder {
    /// Every moment between drives is a STAY somewhere — computed across
    /// day boundaries (the overnight at home is one stay), with the final
    /// gap running to `until` (where you are right now). This is what makes
    /// the day a continuous stream instead of cards with holes. Pure.
    static func stays(
        between trips: [(start: Date, end: Date, lastCoordinate: Coordinate?)],
        until: Date,
        minimumDuration: TimeInterval = 180
    ) -> [(start: Date, end: Date, coordinate: Coordinate?)] {
        let ordered = trips.sorted { $0.start < $1.start }
        var stays: [(start: Date, end: Date, coordinate: Coordinate?)] = []
        for (earlier, later) in zip(ordered, ordered.dropFirst()) {
            let gap = later.start.timeIntervalSince(earlier.end)
            if gap >= minimumDuration {
                stays.append((earlier.end, later.start, earlier.lastCoordinate))
            }
        }
        if let last = ordered.last, until.timeIntervalSince(last.end) >= minimumDuration {
            stays.append((last.end, until, last.lastCoordinate))
        }
        return stays
    }

    /// What a stay at a place most likely WAS — the "I shouldn't have to
    /// record this" guess: a restaurant stop is a meal, a gym stop is a
    /// workout. Guessed from the place name; unrecognized places stay an
    /// honest "Parked". Pure and tested.
    static func stopActivity(forPlaceName name: String?) -> (title: String, symbol: String) {
        switch stopSymbol(forPlaceName: name) {
        case "fork.knife": ("Meal", "fork.knife")
        case "cup.and.saucer": ("Coffee", "cup.and.saucer")
        case "cart": ("Shopping", "cart")
        case "bag": ("Shopping", "bag")
        case "dumbbell": ("Gym", "dumbbell")
        case "fuelpump": ("Fuel stop", "fuelpump")
        case "books.vertical": ("School", "books.vertical")
        case "tree": ("Outdoors", "tree")
        case "cross.case": ("Appointment", "cross.case")
        case let symbol: ("Parked", symbol)
        }
    }

    /// Which icon a stop's place name earns. Keyword heuristics, pure and
    /// tested; anything unrecognized gets an honest map pin.
    static func stopSymbol(forPlaceName name: String?) -> String {
        // Match only the base name — "Oak Grove Ave · Menlo Park" must not
        // hit the park keyword via its CITY. And match whole words, so
        // "Parkside" or "760 El Camino" can't false-positive either.
        guard let full = name?.lowercased() else { return "mappin.circle" }
        let name = full.components(separatedBy: " · ").first ?? full
        let words = Set(name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
        func hits(_ keyword: String) -> Bool {
            keyword.contains(" ") ? name.contains(keyword) : words.contains(keyword)
        }
        let matches: [(keywords: [String], symbol: String)] = [
            (["gym", "fitness", "athletic", "crossfit", "24 hour"], "dumbbell"),
            (["walmart", "target", "costco", "grocery", "market", "safeway", "trader joe", "whole foods", "99 ranch", "supermarket", "h mart"], "cart"),
            (["coffee", "cafe", "café", "starbucks", "peet", "philz", "boba", "tea"], "cup.and.saucer"),
            (["restaurant", "grill", "kitchen", "pizza", "sushi", "ramen", "bbq", "taqueria", "diner"], "fork.knife"),
            (["gas", "chevron", "shell", "76", "arco", "supercharger", "charging"], "fuelpump"),
            (["school", "university", "college", "library"], "books.vertical"),
            (["trail", "beach"], "tree"),
            (["hospital", "medical", "clinic", "dental"], "cross.case"),
            (["mall", "plaza", "shopping"], "bag"),
        ]
        for match in matches where match.keywords.contains(where: hits) {
            return match.symbol
        }
        return "mappin.circle"
    }

    /// A walk's believable distance. The pedometer sometimes reports a
    /// distance wildly out of step (sorry) with its own step count; when
    /// the two disagree beyond ballpark (2× either way against a 0.75 m
    /// stride), the steps win — they're the direct measurement.
    static func walkMeters(pedometerMeters: Double?, steps: Int?) -> Double? {
        let strideMeters = 0.75
        let fromSteps = steps.map { Double($0) * strideMeters }
        guard let pedometerMeters else { return fromSteps }
        guard let fromSteps, fromSteps > 0 else { return pedometerMeters }
        let ratio = pedometerMeters / fromSteps
        return (0.5...2.0).contains(ratio) ? pedometerMeters : fromSteps
    }

    /// The stop whose window contains this moment — a walk that happened
    /// while parked at Walmart happened AT Walmart. Pure and unit-tested.
    static func enclosingStop(of date: Date, in stops: [(start: Date, end: Date)]) -> Int? {
        stops.firstIndex { $0.start <= date && date < $0.end }
    }

    /// The crumbs that fell during a walk, in order — its coarse trail.
    /// A little slack either side catches the wake that fired just before
    /// the coprocessor decided the walking had started. Pure, tested.
    static func crumbTrail(
        for interval: (start: Date, end: Date),
        crumbs: [(date: Date, coordinate: Coordinate)],
        slack: TimeInterval = 120
    ) -> [Coordinate] {
        crumbs
            .filter { $0.date >= interval.start - slack && $0.date <= interval.end + slack }
            .sorted { $0.date < $1.date }
            .map(\.coordinate)
    }

    /// The known position nearest in time to a moment — how an ambient
    /// walk (recorded without location) gets anchored to the parking spot
    /// it started from. Pure and unit-tested; nil beyond the tolerance,
    /// because a fix from hours away would be a guess, not an anchor.
    static func nearestFix(
        to date: Date,
        in fixes: [(date: Date, coordinate: Coordinate)],
        tolerance: TimeInterval = 3 * 3_600
    ) -> Coordinate? {
        let best = fixes.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        guard let best, abs(best.date.timeIntervalSince(date)) <= tolerance else { return nil }
        return best.coordinate
    }

    /// Ambient walks that overlap a deliberate HealthKit workout are the
    /// same event seen by two sensors — the workout (richer) wins.
    static func walks(
        _ walks: [(start: Date, end: Date)],
        notCoveredBy workouts: [(start: Date, end: Date)]
    ) -> [(start: Date, end: Date)] {
        walks.filter { walk in
            !workouts.contains { workout in
                max(walk.start, workout.start) < min(walk.end, workout.end)
            }
        }
    }
}
