import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct RoadieFormattingTests {
    @Test func describesAFullDrive() {
        var context = DrivingContext()
        context.coordinate = Coordinate(latitude: 37.4272, longitude: -122.1376)
        context.speed = 29.06 // 65 mph
        context.course = 315
        context.road = RoadInfo(name: "Alma Street", ref: nil, speedLimit: 15.6464) // 35 mph
        context.tripStart = Date(timeIntervalSinceReferenceDate: 0)
        context.tripEnd = Date(timeIntervalSinceReferenceDate: 23 * 60)
        context.tripDistance = 29_611 // 18.4 mi
        context.tripMaxSpeed = 31.3 // 70 mph

        let text = RoadieToolFormatting.describeDrive(context, isDriving: true)

        #expect(text.contains("Drive status: active"))
        #expect(text.contains("65 mph"))
        #expect(text.contains("NW"))
        #expect(text.contains("Alma Street, speed limit 35 mph"))
        #expect(text.contains("23 min"))
        #expect(text.contains("18.4 mi"))
        #expect(text.contains("Top speed this trip: 70 mph"))
    }

    @Test func unknownsStayUnknown() {
        let text = RoadieToolFormatting.describeDrive(DrivingContext(), isDriving: false)
        #expect(text.contains("no active drive"))
        #expect(text.contains("Position: unknown"))
        #expect(text.contains("Speed: unknown"))
        #expect(text.contains("Road: unknown"))
        // No trip lines when there was never a trip.
        #expect(!text.contains("Trip so far"))
    }

    @Test func describesPlacesWithDistanceAndDirection() {
        let origin = Coordinate(latitude: 37.0, longitude: -122.0)
        let results = [
            (Place(id: "node/1", name: "Blue Bottle", brand: nil, operatedBy: nil, category: .coffee,
                   coordinate: Coordinate(latitude: 37.001, longitude: -122.0)), 111.0),
            (Place(id: "node/2", name: nil, brand: nil, operatedBy: nil, category: .coffee,
                   coordinate: Coordinate(latitude: 36.99, longitude: -122.0)), 1113.0),
        ]
        let text = RoadieToolFormatting.describePlaces(results, category: .coffee, origin: origin)
        #expect(text.contains("Blue Bottle"))
        #expect(text.contains("N")) // due north of origin
        #expect(text.contains("0.7 mi")) // the far one
        #expect(text.contains("Unnamed cafe"))
    }

    @Test func emptyPlacesSayNothingFound() {
        let text = RoadieToolFormatting.describePlaces(
            [], category: .charger, origin: Coordinate(latitude: 0, longitude: 0)
        )
        #expect(text.contains("No chargers found"))
    }

    @Test func describesTripHistory() {
        let trip = Trip(startDate: Date(timeIntervalSinceReferenceDate: 0))
        trip.endDate = Date(timeIntervalSinceReferenceDate: 240)
        trip.distance = 965 // 0.6 mi
        trip.maxSpeed = 16.1 // 36 mph

        let text = RoadieToolFormatting.describeTrips([trip])
        #expect(text.contains("0.6 mi"))
        #expect(text.contains("4 min"))
        #expect(text.contains("top speed 36 mph"))
    }

    @Test func emptyHistoryIsHonest() {
        #expect(RoadieToolFormatting.describeTrips([]) == "No recorded trips yet.")
    }

    @Test func spokenDurations() {
        #expect(RoadieToolFormatting.spokenDuration(30) == "under a minute")
        #expect(RoadieToolFormatting.spokenDuration(23 * 60) == "23 min")
        #expect(RoadieToolFormatting.spokenDuration(3900) == "1 hr 5 min")
        #expect(RoadieToolFormatting.spokenDuration(7200) == "2 hr")
    }
}
