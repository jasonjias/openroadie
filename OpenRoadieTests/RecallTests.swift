import Foundation
import Testing
@testable import OpenRoadie

struct PlaceNameFormattingTests {
    @Test func pointOfInterestBeatsStreetAddress() {
        let name = PlaceNamer.displayName(
            areaOfInterest: "Draeger's Market",
            name: "1010 University Dr", thoroughfare: "University Dr", locality: "Menlo Park"
        )
        #expect(name == "Draeger's Market · Menlo Park")
    }

    /// CLPlacemark's `name` is usually a house-number address; the street
    /// alone reads better for "where the car sat".
    @Test func houseNumbersGetStripped() {
        let name = PlaceNamer.displayName(
            areaOfInterest: nil,
            name: "851 Oak Grove Ave", thoroughfare: "Oak Grove Ave", locality: "Menlo Park"
        )
        #expect(name == "Oak Grove Ave · Menlo Park")
    }

    @Test func cityAloneWhenThatIsAllThereIs() {
        #expect(PlaceNamer.displayName(areaOfInterest: nil, name: nil, thoroughfare: nil, locality: "Gilroy") == "Gilroy")
        #expect(PlaceNamer.displayName(areaOfInterest: nil, name: "Gilroy", thoroughfare: nil, locality: "Gilroy") == "Gilroy")
        #expect(PlaceNamer.displayName(areaOfInterest: nil, name: nil, thoroughfare: nil, locality: nil) == nil)
    }

    @Test func cacheKeysGroupByHundredMeters() {
        let a = Coordinate(latitude: 37.45061, longitude: -122.18321)
        let b = Coordinate(latitude: 37.45072, longitude: -122.18337)
        let far = Coordinate(latitude: 37.46101, longitude: -122.18321)
        #expect(PlaceNamer.cacheKey(for: a) == PlaceNamer.cacheKey(for: b))
        #expect(PlaceNamer.cacheKey(for: a) != PlaceNamer.cacheKey(for: far))
    }
}

struct DayStoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)
    private let home = Coordinate(latitude: 37.0, longitude: -122.0)

    @Test func stopsFillTheGapsBetweenDrives() {
        let stops = DayStory.stops(between: [
            (t0, t0 + 1_000, home),
            (t0 + 4_600, t0 + 5_600, nil),
            (t0 + 9_200, t0 + 10_000, home),
        ])
        #expect(stops.count == 2)
        #expect(stops[0] == DayStory.Stop(afterTrip: 0, duration: 3_600, coordinate: home))
        #expect(stops[1].afterTrip == 1)
        #expect(stops[1].coordinate == nil)
    }

    @Test func unsortedTripsStillTellTheStoryInOrder() {
        let stops = DayStory.stops(between: [
            (t0 + 9_200, t0 + 10_000, nil),
            (t0, t0 + 1_000, home),
        ])
        #expect(stops.count == 1)
        #expect(stops[0].afterTrip == 0)
        #expect(stops[0].coordinate == home)
    }

    /// Overlapping records (a data bug upstream) produce no negative stop.
    @Test func overlapsYieldNoStop() {
        let stops = DayStory.stops(between: [
            (t0, t0 + 2_000, home),
            (t0 + 1_000, t0 + 3_000, nil),
        ])
        #expect(stops.isEmpty)
    }

    @Test func totalsTieOut() {
        let totals = DayStory.totals(of: [
            (t0, t0 + 600, 5_000),
            (t0 + 4_000, t0 + 4_900, 7_000),
        ])
        #expect(totals.meters == 12_000)
        #expect(totals.seconds == 1_500)
    }
}

struct AirQualityAndAlertTests {
    @Test func aqiBandsAreTheEPABreakpoints() {
        #expect(AirQuality.label(12) == "Good")
        #expect(AirQuality.label(75) == "Moderate")
        #expect(AirQuality.label(120) == "Unhealthy for some")
        #expect(AirQuality.label(180) == "Unhealthy")
        #expect(AirQuality.label(250) == "Very unhealthy")
        #expect(AirQuality.label(400) == "Hazardous")
    }

    @Test func aqiParsePicksNearestHour() throws {
        let data = """
        {"hourly":{"time":[1000,4600],"us_aqi":[42,88]}}
        """.data(using: .utf8)!
        let response = try JSONDecoder().decode(WeatherService.AirQualityResponse.self, from: data)
        #expect(WeatherService.nearestAQI(to: Date(timeIntervalSince1970: 4_000), in: response) == 88)
        #expect(WeatherService.nearestAQI(to: Date(timeIntervalSince1970: 90_000), in: response) == nil)
    }

    @Test func nwsParseKeepsOnlySevereAndExtreme() {
        let data = """
        {"features":[
          {"id":"urn:1","properties":{"event":"Tornado Warning","headline":"Tornado Warning until 3PM","severity":"Extreme"}},
          {"id":"urn:2","properties":{"event":"High Wind Warning","headline":"High winds","severity":"Severe"}},
          {"id":"urn:3","properties":{"event":"Small Craft Advisory","headline":"Choppy","severity":"Minor"}},
          {"id":null,"properties":{"event":"Flood Warning","headline":"Flooding","severity":"Severe"}}
        ]}
        """.data(using: .utf8)!
        let alerts = SevereWeatherWatch.parse(data)
        #expect(alerts.map(\.event) == ["Tornado Warning", "High Wind Warning"])
        #expect(alerts[0].id == "urn:1")
    }

    @Test func malformedAlertPayloadsYieldNothing() {
        #expect(SevereWeatherWatch.parse(Data("not json".utf8)).isEmpty)
        #expect(SevereWeatherWatch.parse(Data("{}".utf8)).isEmpty)
    }
}
