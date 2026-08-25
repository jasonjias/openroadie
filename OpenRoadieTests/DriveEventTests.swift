import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct GForceDetectorTests {
    @Test func sustainedBurstFiresOnceWithPeak() {
        var detector = GForceDetector()
        let base = Date(timeIntervalSinceReferenceDate: 0)

        #expect(detector.process(magnitudeG: 0.4, at: base) == nil)
        #expect(detector.process(magnitudeG: 0.5, at: base.addingTimeInterval(0.1)) == nil)
        // Third consecutive sample fires, reporting the burst's peak.
        #expect(detector.process(magnitudeG: 0.45, at: base.addingTimeInterval(0.2)) == 0.5)
    }

    @Test func singleSpikeIsIgnored() {
        var detector = GForceDetector()
        let base = Date(timeIntervalSinceReferenceDate: 0)

        // A pothole: one hot sample surrounded by calm.
        #expect(detector.process(magnitudeG: 0.8, at: base) == nil)
        #expect(detector.process(magnitudeG: 0.05, at: base.addingTimeInterval(0.1)) == nil)
        #expect(detector.process(magnitudeG: 0.05, at: base.addingTimeInterval(0.2)) == nil)
    }

    @Test func holdOffPreventsRepeatFiring() {
        var detector = GForceDetector()
        let base = Date(timeIntervalSinceReferenceDate: 0)

        for step in 0..<3 {
            _ = detector.process(magnitudeG: 0.5, at: base.addingTimeInterval(Double(step) * 0.1))
        }
        // Still in the same continuous burst: no second event, ever.
        for step in 0..<5 {
            #expect(detector.process(magnitudeG: 0.5, at: base.addingTimeInterval(1 + Double(step) * 0.1)) == nil)
        }
        // Calm re-arms; a burst inside the hold-off window still stays quiet.
        #expect(detector.process(magnitudeG: 0.05, at: base.addingTimeInterval(2)) == nil)
        for step in 0..<3 {
            #expect(detector.process(magnitudeG: 0.5, at: base.addingTimeInterval(2.5 + Double(step) * 0.1)) == nil)
        }
        // Calm again, then a fresh burst well past hold-off fires.
        #expect(detector.process(magnitudeG: 0.05, at: base.addingTimeInterval(9)) == nil)
        for step in 0..<2 {
            _ = detector.process(magnitudeG: 0.6, at: base.addingTimeInterval(10 + Double(step) * 0.1))
        }
        #expect(detector.process(magnitudeG: 0.6, at: base.addingTimeInterval(10.2)) == 0.6)
    }
}

@MainActor
struct CommunityExportTests {
    @Test func anonymizesCoordinatesAndTime() {
        let event = DriveEvent(
            kind: "hardBraking",
            peakG: 0.4567,
            coordinate: Coordinate(latitude: 37.441912, longitude: -122.143087),
            speedMph: 47,
            timestamp: Date(timeIntervalSince1970: 1_724_500_000)
        )
        let entries = CommunityExport.anonymized([event])

        #expect(entries.count == 1)
        // ~110 m grid: three decimals, nothing finer survives.
        #expect(entries[0]["lat"] as? Double == 37.442)
        #expect(entries[0]["lon"] as? Double == -122.143)
        #expect(entries[0]["peakG"] as? Double == 0.46)
        // Hour granularity, no minutes or seconds.
        let dateHour = entries[0]["dateHour"] as? String
        #expect(dateHour?.count == 13)
        // Speeds bucket to 10 mph.
        #expect(entries[0]["speedMphBucket"] as? Int == 40)
    }

    @Test func eventsWithoutLocationAreDropped() {
        let event = DriveEvent(kind: "hardBraking", peakG: 0.5, coordinate: nil, speedMph: nil)
        #expect(CommunityExport.anonymized([event]).isEmpty)
    }

    @Test func jsonCarriesFormatHeader() throws {
        let data = try CommunityExport.json([])
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["format"] as? String == "openroadie-community-events")
        #expect(decoded?["version"] as? Int == 1)
    }
}
