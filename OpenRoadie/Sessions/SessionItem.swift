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
    /// The big lime number — "1.9 MI", "152 CAL", "7h 12m".
    var metric: String
    var start: Date
    var end: Date
    /// The backing trip, for drive cards — tapping opens the full trip
    /// detail, same as the Drives list.
    var tripID: PersistentIdentifier?
    /// Where it happened, for stops — the detail view pins it.
    var coordinate: Coordinate?

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
            (["park", "trail", "beach"], "tree"),
            (["hospital", "medical", "clinic", "dental"], "cross.case"),
            (["mall", "plaza", "shopping"], "bag"),
        ]
        for match in matches where match.keywords.contains(where: hits) {
            return match.symbol
        }
        return "mappin.circle"
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
