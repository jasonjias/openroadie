import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct AwardsTests {
    private func finishedTrip(miles: Double, daysAgo: Int = 0) -> Trip {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        let trip = Trip(startDate: start)
        trip.endDate = start.addingTimeInterval(600)
        trip.distance = miles * 1609.344
        return trip
    }

    @Test func aggregatesCountOnlyFinishedTrips() {
        let unfinished = Trip(startDate: .now)
        let aggregates = Awards.aggregates(
            trips: [finishedTrip(miles: 30), finishedTrip(miles: 90), unfinished],
            events: []
        )
        #expect(aggregates.tripCount == 2)
        #expect(abs(aggregates.miles - 120) < 0.01)
    }

    @Test func freeVehiclesAreAlwaysUnlocked() {
        let nothing = Awards.Aggregates()
        for id in ["classic", "sportsCar", "carTaxi", "carPolice", "carFiretruck", "carGarbageTruck", "bulldozer"] {
            #expect(Awards.isUnlocked(id, aggregates: nothing), "\(id) should be free")
        }
    }

    @Test func earnedVehiclesUnlockAtTheGoal() {
        var aggregates = Awards.Aggregates()
        #expect(!Awards.isUnlocked("trainLocomotiveA", aggregates: aggregates))
        aggregates.miles = 100
        #expect(Awards.isUnlocked("trainLocomotiveA", aggregates: aggregates))
        #expect(!Awards.isUnlocked("trainLocomotiveB", aggregates: aggregates)) // 500 mi
        aggregates.bestCleanStreak = 5
        #expect(Awards.isUnlocked("pirateShip", aggregates: aggregates))
        #expect(!Awards.isUnlocked("lightRail", aggregates: aggregates)) // streak 10
    }

    @Test func everyLockedVehicleHasARealAward() {
        for award in Awards.all {
            if let vehicleId = award.unlocksVehicle {
                #expect(Vehicle.all.contains { $0.id == vehicleId }, "\(award.id) unlocks unknown vehicle \(vehicleId)")
            }
        }
    }

    @Test func everyVehicleHasABundledThumbnail() {
        for vehicle in Vehicle.all {
            let url = Bundle.main.url(forResource: vehicle.thumbnailName, withExtension: "png")
            #expect(url != nil, "missing \(vehicle.thumbnailName).png")
        }
    }

    @Test func progressFractionClamps() {
        var aggregates = Awards.Aggregates()
        aggregates.tripCount = 500
        let first = Awards.progress(for: aggregates).first { $0.award.id == "firstDrive" }!
        #expect(first.earned)
        #expect(first.fraction == 1)
    }
}
