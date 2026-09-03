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

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

enum SessionBuilder {
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
