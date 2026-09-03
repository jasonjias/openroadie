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

struct WalkHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)

    private func sample(_ offset: TimeInterval, _ walking: Bool) -> (date: Date, walking: Bool) {
        (t0 + offset, walking)
    }

    @Test func contiguousWalkingSamplesChainIntoOneWalk() {
        let intervals = WalkHistory.walkIntervals(
            from: [sample(0, true), sample(120, true), sample(300, false)],
            until: t0 + 600
        )
        #expect(intervals.count == 1)
        #expect(intervals[0].start == t0)
        #expect(intervals[0].end == t0 + 300)
    }

    /// A crosswalk light isn't the end of a walk: brief pauses merge.
    @Test func briefPausesMergeLongOnesSplit() {
        let merged = WalkHistory.walkIntervals(
            from: [sample(0, true), sample(200, false), sample(290, true), sample(500, false)],
            until: t0 + 900
        )
        #expect(merged.count == 1)
        #expect(merged[0].end == t0 + 500)

        let split = WalkHistory.walkIntervals(
            from: [sample(0, true), sample(200, false), sample(600, true), sample(900, false)],
            until: t0 + 1_200
        )
        #expect(split.count == 2)
    }

    /// A 40-second shuffle to the mailbox is not a walk worth a story line.
    @Test func blipsBelowTheMinimumDrop() {
        let intervals = WalkHistory.walkIntervals(
            from: [sample(0, true), sample(40, false)],
            until: t0 + 600
        )
        #expect(intervals.isEmpty)
    }

    @Test func aWalkStillInProgressRunsToTheQueryEnd() {
        let intervals = WalkHistory.walkIntervals(
            from: [sample(0, true)],
            until: t0 + 400
        )
        #expect(intervals.count == 1)
        #expect(intervals[0].start == t0)
        #expect(intervals[0].end == t0 + 400)
    }

    @Test func walksInsideDrivesAreMisreadsAndDrop() {
        let kept = DayStory.walksOutsideDrives(
            [(t0 + 100, t0 + 400), (t0 + 2_000, t0 + 2_400)],
            drives: [(t0, t0 + 1_000)]
        )
        #expect(kept.count == 1)
        #expect(kept[0].start == t0 + 2_000)
    }
}

struct SessionBuilderTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)

    @Test func stopIconsMatchThePlace() {
        #expect(SessionBuilder.stopSymbol(forPlaceName: "24 Hour Fitness · San Leandro") == "dumbbell")
        #expect(SessionBuilder.stopSymbol(forPlaceName: "Walmart Supercenter") == "cart")
        #expect(SessionBuilder.stopSymbol(forPlaceName: "Philz Coffee · Palo Alto") == "cup.and.saucer")
        #expect(SessionBuilder.stopSymbol(forPlaceName: "Chevron") == "fuelpump")
        #expect(SessionBuilder.stopSymbol(forPlaceName: "Oak Grove Ave · Menlo Park") == "mappin.circle")
        // A street named Park is not a park.
        #expect(SessionBuilder.stopSymbol(forPlaceName: "Park Blvd · Palo Alto") == "mappin.circle")
        #expect(SessionBuilder.stopSymbol(forPlaceName: nil) == "mappin.circle")
    }

    /// The same walk seen by two sensors is one event: the deliberate
    /// HealthKit workout wins over the ambient motion-history walk.
    @Test func ambientWalksCoveredByWorkoutsDrop() {
        let kept = SessionBuilder.walks(
            [(t0, t0 + 600), (t0 + 5_000, t0 + 5_600)],
            notCoveredBy: [(t0 - 60, t0 + 700)]
        )
        #expect(kept.count == 1)
        #expect(kept[0].start == t0 + 5_000)
    }

    @Test func sleepSamplesCoalesceIntoNights() {
        // Core sleep, brief 3 AM wake, more sleep: one night, asleep time
        // excludes the gap.
        let nights = HealthSessions.nights(from: [
            (t0, t0 + 3 * 3_600),
            (t0 + 3 * 3_600 + 900, t0 + 7 * 3_600),
        ])
        #expect(nights.count == 1)
        #expect(nights[0].start == t0)
        #expect(nights[0].end == t0 + 7 * 3_600)
        #expect(abs(nights[0].asleepSeconds - (7 * 3_600 - 900)) < 1)
    }

    @Test func aNapAndANightAreSeparate() {
        let nights = HealthSessions.nights(from: [
            (t0, t0 + 2 * 3_600),
            (t0 + 10 * 3_600, t0 + 17 * 3_600),
        ])
        #expect(nights.count == 2)
    }

    @Test func aTwentyMinuteDozeIsNotANight() {
        #expect(HealthSessions.nights(from: [(t0, t0 + 1_200)]).isEmpty)
    }
}

struct RouteThinningTests {
    private func coord(_ i: Int) -> Coordinate {
        Coordinate(latitude: Double(i), longitude: 0)
    }

    @Test func shortRoutesPassThroughUntouched() {
        let route = (0..<50).map(coord)
        #expect(HealthSessions.thin(route, to: 300) == route)
    }

    @Test func longRoutesKeepEndsAndSpreadEvenly() {
        let route = (0..<3_000).map(coord)
        let thinned = HealthSessions.thin(route, to: 300)
        #expect(thinned.count == 300)
        #expect(thinned.first == route.first)
        #expect(thinned.last == route.last)
    }
}

struct WalkDistanceSanityTests {
    /// The field case: 311 steps reported as 0.1 mi is inside ballpark and
    /// keeps the pedometer's number; a wild disagreement hands the answer
    /// to the step count.
    @Test func ballparkAgreementKeepsThePedometer() {
        #expect(SessionBuilder.walkMeters(pedometerMeters: 160, steps: 311) == 160)
    }

    @Test func wildDisagreementTrustsTheSteps() {
        // 40 m claimed for 400 steps (~300 m of walking): steps win.
        #expect(SessionBuilder.walkMeters(pedometerMeters: 40, steps: 400) == 300)
        // 2 km claimed for 200 steps: steps win again.
        #expect(SessionBuilder.walkMeters(pedometerMeters: 2_000, steps: 200) == 150)
    }

    @Test func missingHalvesFallBackHonestly() {
        #expect(SessionBuilder.walkMeters(pedometerMeters: 120, steps: nil) == 120)
        #expect(SessionBuilder.walkMeters(pedometerMeters: nil, steps: 100) == 75)
        #expect(SessionBuilder.walkMeters(pedometerMeters: nil, steps: nil) == nil)
    }
}

struct WalkEndDetectorTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)

    @Test func walkingKeepsRecording() {
        var detector = WalkEndDetector()
        for minute in 0...20 {
            let ended = detector.process(walking: true, speedMps: 1.4, at: t0 + Double(minute) * 60)
            #expect(!ended)
        }
    }

    /// Standing still in an aisle isn't the end; three minutes of not
    /// walking is.
    @Test func stoppingWalkingEndsAfterThreeMinutes() {
        var detector = WalkEndDetector()
        _ = detector.process(walking: true, speedMps: 1.2, at: t0)
        let early = detector.process(walking: false, speedMps: 0, at: t0 + 100)
        let late = detector.process(walking: false, speedMps: 0, at: t0 + 290)
        #expect(!early)
        #expect(late)
    }

    @Test func vehicleSpeedEndsImmediately() {
        var detector = WalkEndDetector()
        _ = detector.process(walking: true, speedMps: 1.2, at: t0)
        let ended = detector.process(walking: false, speedMps: 9, at: t0 + 30)
        #expect(ended)
    }

    @Test func theCapEndsEvenAPerpetualWalker() {
        var detector = WalkEndDetector()
        _ = detector.process(walking: true, speedMps: 1.4, at: t0)
        let ended = detector.process(walking: true, speedMps: 1.4, at: t0 + 46 * 60)
        #expect(ended)
    }
}

struct WalkPathModelTests {
    @Test func coordinatesRoundTrip() {
        let coords = [
            Coordinate(latitude: 37.1, longitude: -122.2),
            Coordinate(latitude: 37.2, longitude: -122.3),
        ]
        let path = WalkPath(
            startDate: .init(timeIntervalSince1970: 0),
            endDate: .init(timeIntervalSince1970: 600),
            distance: 400, coordinates: coords
        )
        #expect(path.coordinates == coords)
    }
}

struct WalkAttributionTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)

    @Test func aWalkInsideAStopWindowBelongsToThatStop() {
        let stops = [(t0, t0 + 1_000), (t0 + 5_000, t0 + 9_000)]
        #expect(SessionBuilder.enclosingStop(of: t0 + 500, in: stops) == 0)
        #expect(SessionBuilder.enclosingStop(of: t0 + 6_000, in: stops) == 1)
        // Walking between stops (mid-drive misread window) matches nothing.
        #expect(SessionBuilder.enclosingStop(of: t0 + 3_000, in: stops) == nil)
        // Boundaries: start inclusive, end exclusive.
        #expect(SessionBuilder.enclosingStop(of: t0 + 1_000, in: stops) == nil)
    }
}

struct CrumbTrailTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)
    private func c(_ i: Double) -> Coordinate { Coordinate(latitude: i, longitude: 0) }

    @Test func crumbsInsideTheWalkFormATrailInOrder() {
        let crumbs = [(t0 + 900, c(3)), (t0 + 100, c(1)), (t0 + 500, c(2)), (t0 + 9_000, c(9))]
        let trail = SessionBuilder.crumbTrail(for: (t0, t0 + 1_000), crumbs: crumbs)
        #expect(trail == [c(1), c(2), c(3)])
    }

    /// The wake that fired moments before the coprocessor called it a walk
    /// still belongs to the walk.
    @Test func slackCatchesTheEdgeCrumbs() {
        let crumbs = [(t0 - 60, c(1)), (t0 + 1_060, c(2)), (t0 - 500, c(9))]
        let trail = SessionBuilder.crumbTrail(for: (t0, t0 + 1_000), crumbs: crumbs)
        #expect(trail == [c(1), c(2)])
    }

    @Test func noCrumbsMeansNoTrail() {
        #expect(SessionBuilder.crumbTrail(for: (t0, t0 + 1_000), crumbs: []).isEmpty)
    }
}

struct WalkAnchorTests {
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)
    private let home = Coordinate(latitude: 37.0, longitude: -122.0)
    private let store = Coordinate(latitude: 37.05, longitude: -122.0)

    @Test func aWalkAnchorsToTheNearestFixInTime() {
        let fixes = [(t0, home), (t0 + 3_000, store)]
        #expect(SessionBuilder.nearestFix(to: t0 + 600, in: fixes) == home)
        #expect(SessionBuilder.nearestFix(to: t0 + 2_500, in: fixes) == store)
    }

    /// A fix hours away is a guess, not an anchor — better no map than a
    /// wrong one.
    @Test func fixesBeyondToleranceDoNotAnchor() {
        #expect(SessionBuilder.nearestFix(to: t0 + 5 * 3_600, in: [(t0, home)]) == nil)
        #expect(SessionBuilder.nearestFix(to: t0, in: []) == nil)
    }
}
