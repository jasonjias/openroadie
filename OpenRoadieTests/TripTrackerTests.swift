import Foundation
import Testing
@testable import OpenRoadie

/// Builds a plausible GPS fix; override only what a test cares about.
/// At latitude 37°, +0.0009° of latitude is roughly 100 m of travel.
private func fix(
    lat: Double = 37.0,
    lon: Double = -122.0,
    accuracy: Double = 5,
    speed: Double = 10,
    speedAccuracy: Double = 0.5,
    course: Double = 90,
    altitude: Double = 30,
    verticalAccuracy: Double = 4,
    at seconds: TimeInterval = 0
) -> LocationSample {
    LocationSample(
        latitude: lat,
        longitude: lon,
        horizontalAccuracy: accuracy,
        speed: speed,
        speedAccuracy: speedAccuracy,
        course: course,
        altitude: altitude,
        verticalAccuracy: verticalAccuracy,
        timestamp: Date(timeIntervalSinceReferenceDate: seconds)
    )
}

struct TripTrackerTests {
    @Test func startResetsContextAndActivates() {
        var tracker = TripTracker()
        let start = Date(timeIntervalSinceReferenceDate: 100)
        tracker.start(at: start)

        #expect(tracker.isActive)
        #expect(tracker.context.tripStart == start)
        #expect(tracker.context.tripEnd == nil)
        #expect(tracker.context.tripDistance == 0)
        #expect(tracker.context.coordinate == nil)
    }

    @Test func ignoresSamplesWhenNotActive() {
        var tracker = TripTracker()
        tracker.process(fix())
        #expect(tracker.context.coordinate == nil)
    }

    @Test func rejectsPoorAccuracySamples() {
        var tracker = TripTracker()
        tracker.start(at: Date(timeIntervalSinceReferenceDate: 0))

        tracker.process(fix(accuracy: TripTracker.maxHorizontalAccuracy + 1, at: 1))
        #expect(tracker.context.coordinate == nil)

        tracker.process(fix(accuracy: -1, at: 2))
        #expect(tracker.context.coordinate == nil)

        tracker.process(fix(accuracy: 5, at: 3))
        #expect(tracker.context.coordinate != nil)
    }

    @Test func unknownSpeedAndCourseStayUnknown() {
        var tracker = TripTracker()
        tracker.start(at: Date(timeIntervalSinceReferenceDate: 0))

        tracker.process(fix(speed: -1, course: -1, at: 1))
        #expect(tracker.context.speed == nil)
        #expect(tracker.context.course == nil)

        tracker.process(fix(speed: 12.5, course: 270, at: 2))
        #expect(tracker.context.speed == 12.5)
        #expect(tracker.context.course == 270)
    }

    @Test func accumulatesDistanceAcrossMovement() {
        var tracker = TripTracker()
        tracker.start(at: Date(timeIntervalSinceReferenceDate: 0))

        // Three fixes, each ~100 m further north, 10 s apart.
        tracker.process(fix(lat: 37.0000, at: 0))
        tracker.process(fix(lat: 37.0009, at: 10))
        tracker.process(fix(lat: 37.0018, at: 20))

        #expect(tracker.context.tripDistance > 150)
        #expect(tracker.context.tripDistance < 250)
    }

    @Test func stationaryDriftDoesNotAccumulate() {
        var tracker = TripTracker()
        tracker.start(at: Date(timeIntervalSinceReferenceDate: 0))

        // Jitter of a few meters around a fixed point, below the
        // max(minimumDistanceStep, accuracy) threshold every time.
        tracker.process(fix(lat: 37.00000, at: 0))
        tracker.process(fix(lat: 37.00004, at: 5))
        tracker.process(fix(lat: 36.99997, at: 10))
        tracker.process(fix(lat: 37.00003, at: 15))

        #expect(tracker.context.tripDistance == 0)
    }

    @Test func slowMovementEventuallyAccumulates() {
        var tracker = TripTracker()
        tracker.start(at: Date(timeIntervalSinceReferenceDate: 0))

        // ~5 m per sample: each step is below the 10 m threshold, but the
        // anchor doesn't advance, so real movement still gets counted.
        for step in 0...10 {
            tracker.process(fix(lat: 37.0 + Double(step) * 0.000045, at: TimeInterval(step)))
        }

        #expect(tracker.context.tripDistance > 30)
    }

    @Test func implausibleJumpIsNotCounted() {
        var tracker = TripTracker()
        tracker.start(at: Date(timeIntervalSinceReferenceDate: 0))

        tracker.process(fix(lat: 37.0, at: 0))
        // ~11 km in one second: a GPS glitch, not travel.
        tracker.process(fix(lat: 37.1, at: 1))
        #expect(tracker.context.tripDistance == 0)

        // Movement after the glitch is measured from the new position.
        tracker.process(fix(lat: 37.1009, at: 11))
        #expect(tracker.context.tripDistance > 50)
        #expect(tracker.context.tripDistance < 150)
    }

    @Test func stopFreezesDurationAndIgnoresLaterSamples() {
        var tracker = TripTracker()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let end = Date(timeIntervalSinceReferenceDate: 60)
        tracker.start(at: start)
        tracker.process(fix(at: 1))
        tracker.stop(at: end)

        #expect(!tracker.isActive)
        #expect(tracker.context.tripEnd == end)
        #expect(tracker.context.tripDuration(at: Date(timeIntervalSinceReferenceDate: 999)) == 60)

        let frozen = tracker.context
        tracker.process(fix(lat: 38.0, at: 70))
        #expect(tracker.context == frozen)
    }

    @Test func durationIsNilBeforeFirstStart() {
        let context = DrivingContext()
        #expect(context.tripDuration() == nil)
    }

    @Test func tracksMaxSpeedAcrossDrive() {
        var tracker = TripTracker()
        tracker.start(at: Date(timeIntervalSinceReferenceDate: 0))

        tracker.process(fix(speed: 10, at: 1))
        tracker.process(fix(speed: 25, at: 2))
        tracker.process(fix(speed: -1, at: 3))
        tracker.process(fix(speed: 15, at: 4))

        #expect(tracker.context.tripMaxSpeed == 25)
    }

    @Test func altitudeUnknownWhenVerticalAccuracyInvalid() {
        var tracker = TripTracker()
        tracker.start(at: Date(timeIntervalSinceReferenceDate: 0))

        tracker.process(fix(altitude: 120, verticalAccuracy: -1, at: 1))
        #expect(tracker.context.altitude == nil)

        tracker.process(fix(altitude: 120, verticalAccuracy: 3, at: 2))
        #expect(tracker.context.altitude == 120)
    }

    @Test func processReportsWhenPositionAdvances() {
        var tracker = TripTracker()
        tracker.start(at: Date(timeIntervalSinceReferenceDate: 0))

        // Rejected sample.
        #expect(tracker.process(fix(accuracy: 100, at: 0)) == .rejected)
        // First accepted fix establishes the route start.
        #expect(tracker.process(fix(lat: 37.0, at: 1)) == .accepted(movedFromLastPoint: true))
        // Stationary jitter: accepted, but not a new route point.
        #expect(tracker.process(fix(lat: 37.00002, at: 2)) == .accepted(movedFromLastPoint: false))
        // Real movement (~100 m).
        #expect(tracker.process(fix(lat: 37.0009, at: 12)) == .accepted(movedFromLastPoint: true))
    }
}

/// Walks need a finer scale than drives — and a stricter one.
struct WalkingScaleTests {
    @Test func walkingRecordsFinerStepsThanDriving() {
        // ~7 m of travel with a good fix: below the driving step, above
        // the walking one.
        var driving = TripTracker()
        driving.start(at: Date(timeIntervalSince1970: 0))
        _ = driving.process(fix(lat: 37.0, accuracy: 4, at: 0))
        let drivingMoved = driving.process(fix(lat: 37.00006, accuracy: 4, at: 5))
        #expect(drivingMoved == .accepted(movedFromLastPoint: false))

        var walking = TripTracker()
        walking.config = TripTracker.walking
        walking.start(at: Date(timeIntervalSince1970: 0))
        _ = walking.process(fix(lat: 37.0, accuracy: 4, at: 0))
        let walkingMoved = walking.process(fix(lat: 37.00006, accuracy: 4, at: 5))
        #expect(walkingMoved == .accepted(movedFromLastPoint: true))
    }

    /// The indoor case: a 40 m fix passes for a drive but is a scribble on
    /// a footpath, so the walking scale rejects it.
    @Test func walkingRejectsIndoorGradeAccuracy() {
        var walking = TripTracker()
        walking.config = TripTracker.walking
        walking.start(at: Date(timeIntervalSince1970: 0))
        #expect(walking.process(fix(accuracy: 40, at: 1)) == .rejected)

        var driving = TripTracker()
        driving.start(at: Date(timeIntervalSince1970: 0))
        #expect(driving.process(fix(accuracy: 40, at: 1)) != .rejected)
    }

    @Test func drivingDefaultsAreUnchanged() {
        #expect(TripTracker().config.maxHorizontalAccuracy == 50)
        #expect(TripTracker().config.minimumDistanceStep == 10)
        #expect(TripTracker().config.maxPlausibleSpeed == 90)
    }
}
