import Foundation

/// Earnable awards — deterministic, computed straight from stored trips
/// and events (nothing is granted or stored, so history always tells the
/// truth). Some awards unlock vehicles for the 3D scene; the everyday
/// cars are free from the start.
enum Awards {
    /// What an award measures.
    enum Metric {
        case miles
        case trips
        case bestCleanStreak
    }

    struct Award: Identifiable {
        let id: String
        let title: String
        let icon: String
        let metric: Metric
        let goal: Double
        /// Vehicle.id this award unlocks, if any.
        let unlocksVehicle: String?
    }

    /// Everything awards are computed from.
    struct Aggregates {
        var miles: Double = 0
        var tripCount: Int = 0
        var bestCleanStreak: Int = 0

        func value(for metric: Metric) -> Double {
            switch metric {
            case .miles: miles
            case .trips: Double(tripCount)
            case .bestCleanStreak: Double(bestCleanStreak)
            }
        }
    }

    struct Progress: Identifiable {
        let award: Award
        let value: Double
        var id: String { award.id }
        var earned: Bool { value >= award.goal }
        var fraction: Double { min(1, value / award.goal) }
    }

    static let all: [Award] = [
        Award(id: "firstDrive", title: "First Drive", icon: "flag.checkered",
              metric: .trips, goal: 1, unlocksVehicle: nil),
        Award(id: "tenTrips", title: "Regular", icon: "figure.skating",
              metric: .trips, goal: 10, unlocksVehicle: "skateboard"),
        Award(id: "commuter", title: "Commuter", icon: "tram",
              metric: .trips, goal: 25, unlocksVehicle: "trainLocomotiveC"),
        Award(id: "workhorse", title: "Workhorse", icon: "ferry",
              metric: .trips, goal: 50, unlocksVehicle: "waterBoatTugA"),
        Award(id: "centuryClub", title: "Century Club", icon: "train.side.front.car",
              metric: .miles, goal: 100, unlocksVehicle: "trainLocomotiveA"),
        Award(id: "roadWarrior", title: "Road Warrior", icon: "train.side.rear.car",
              metric: .miles, goal: 500, unlocksVehicle: "trainLocomotiveB"),
        Award(id: "longHaul", title: "Long Haul", icon: "house.and.flag",
              metric: .miles, goal: 1000, unlocksVehicle: "waterBoatHouseA"),
        Award(id: "toTheStars", title: "To the Stars", icon: "sparkles",
              metric: .miles, goal: 2000, unlocksVehicle: "speeder"),
        Award(id: "smoothOperator", title: "Smooth Operator", icon: "sailboat",
              metric: .bestCleanStreak, goal: 3, unlocksVehicle: "waterBoatSailA"),
        Award(id: "cleanWeek", title: "Ship Shape", icon: "flag.2.crossed",
              metric: .bestCleanStreak, goal: 5, unlocksVehicle: "pirateShip"),
        Award(id: "untouchable", title: "Untouchable", icon: "crown",
              metric: .bestCleanStreak, goal: 10, unlocksVehicle: "lightRail"),
    ]

    @MainActor
    static func aggregates(trips: [Trip], events: [DriveEvent]) -> Aggregates {
        var aggregates = Aggregates()
        for trip in trips where trip.endDate != nil {
            aggregates.tripCount += 1
            aggregates.miles += trip.distance / 1609.344
        }
        aggregates.bestCleanStreak = Streak.compute(trips: trips, events: events).best
        return aggregates
    }

    static func progress(for aggregates: Aggregates) -> [Progress] {
        all.map { Progress(award: $0, value: aggregates.value(for: $0.metric)) }
    }

    /// The award gating a vehicle, or nil if the vehicle is free.
    static func unlock(for vehicleId: String) -> Award? {
        all.first { $0.unlocksVehicle == vehicleId }
    }

    static func isUnlocked(_ vehicleId: String, aggregates: Aggregates) -> Bool {
        guard let award = unlock(for: vehicleId) else { return true }
        return aggregates.value(for: award.metric) >= award.goal
    }

    /// Short human text for a locked vehicle's requirement.
    static func requirementText(_ award: Award) -> String {
        switch award.metric {
        case .miles: "Drive \(Int(award.goal)) total miles"
        case .trips: "Finish \(Int(award.goal)) drives"
        case .bestCleanStreak: "Streak of \(Int(award.goal)) clean drives"
        }
    }
}
