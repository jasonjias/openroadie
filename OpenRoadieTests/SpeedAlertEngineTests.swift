import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct SpeedAlertEngineTests {
    /// Clock anchor for the sustained-window tests.
    private let t0 = Date(timeIntervalSince1970: 1_724_500_000)

    private func engine(_ config: SpeedAlertEngine.Config) -> SpeedAlertEngine {
        var engine = SpeedAlertEngine()
        engine.config = config
        return engine
    }

    /// Alerts only after the speed has HELD past the threshold.
    @Test func firesOnlyAfterSustainedSpeeding() {
        var engine = engine(.init(alertOverPostedLimit: true))

        #expect(engine.process(speedMph: 60, postedLimitMph: 65, at: t0).isEmpty)
        // Just crossed: not yet — this is the noise the field test hated.
        #expect(engine.process(speedMph: 66, postedLimitMph: 65, at: t0).isEmpty)
        #expect(engine.process(speedMph: 66, postedLimitMph: 65, at: t0 + 5).isEmpty)
        // Held past the sustained window: now it's real.
        #expect(engine.process(speedMph: 66, postedLimitMph: 65, at: t0 + 11)
                == [.overPostedLimit(limitMph: 65)])
        // Still over: no repeat.
        #expect(engine.process(speedMph: 70, postedLimitMph: 65, at: t0 + 20).isEmpty)
    }

    /// A brief crossing — passing a truck, cresting a hill, a bad map
    /// match on an overpass — never says a word.
    @Test func briefCrossingsStaySilent() {
        var engine = engine(.init(alertOverPostedLimit: true))
        #expect(engine.process(speedMph: 68, postedLimitMph: 65, at: t0).isEmpty)
        #expect(engine.process(speedMph: 68, postedLimitMph: 65, at: t0 + 4).isEmpty)
        #expect(engine.process(speedMph: 63, postedLimitMph: 65, at: t0 + 6).isEmpty)
        // And the clock restarts on the next crossing.
        #expect(engine.process(speedMph: 68, postedLimitMph: 65, at: t0 + 8).isEmpty)
        #expect(engine.process(speedMph: 68, postedLimitMph: 65, at: t0 + 15).isEmpty)
        #expect(engine.process(speedMph: 68, postedLimitMph: 65, at: t0 + 19)
                == [.overPostedLimit(limitMph: 65)])
    }

    /// After firing, a rule keeps quiet for its cooldown even if the
    /// driver dips under and goes over again.
    @Test func cooldownKeepsARuleQuiet() {
        var engine = engine(.init(alertOverPostedLimit: true))
        _ = engine.process(speedMph: 66, postedLimitMph: 65, at: t0)
        #expect(engine.process(speedMph: 66, postedLimitMph: 65, at: t0 + 11)
                == [.overPostedLimit(limitMph: 65)])
        // Drop below to re-arm, then speed again: within the cooldown, silent.
        #expect(engine.process(speedMph: 60, postedLimitMph: 65, at: t0 + 20).isEmpty)
        #expect(engine.process(speedMph: 66, postedLimitMph: 65, at: t0 + 30).isEmpty)
        #expect(engine.process(speedMph: 66, postedLimitMph: 65, at: t0 + 60).isEmpty)
        // Past the cooldown it may speak again.
        #expect(engine.process(speedMph: 66, postedLimitMph: 65, at: t0 + 300)
                == [.overPostedLimit(limitMph: 65)])
    }

    /// Entering a new speed zone restarts the grace window — no scolding
    /// the instant a 25 zone appears while you're still slowing down.
    @Test func changingSpeedZoneRestartsTheWindow() {
        var engine = engine(.init(alertOverPostedLimit: true))
        // Nine seconds over on a 65 road: nearly ready to fire.
        _ = engine.process(speedMph: 66, postedLimitMph: 65, at: t0)
        #expect(engine.process(speedMph: 66, postedLimitMph: 65, at: t0 + 9).isEmpty)
        // The road becomes a 45: the window restarts rather than firing
        // immediately off the previous road's timer.
        #expect(engine.process(speedMph: 50, postedLimitMph: 45, at: t0 + 10).isEmpty)
        #expect(engine.process(speedMph: 50, postedLimitMph: 45, at: t0 + 15).isEmpty)
        // Still speeding in the new zone once the fresh window elapses.
        #expect(engine.process(speedMph: 50, postedLimitMph: 45, at: t0 + 22)
                == [.overPostedLimit(limitMph: 45)])
    }

    @Test func hysteresisPreventsJitterSpam() {
        var engine = engine(.init(alertOverPostedLimit: true))

        _ = engine.process(speedMph: 66, postedLimitMph: 65, at: t0)
        _ = engine.process(speedMph: 66, postedLimitMph: 65, at: t0 + 11) // fires, disarms
        // Bouncing right at the limit must NOT re-fire.
        #expect(engine.process(speedMph: 64.5, postedLimitMph: 65, at: t0 + 12).isEmpty)
        #expect(engine.process(speedMph: 65.5, postedLimitMph: 65, at: t0 + 13).isEmpty)
        #expect(engine.process(speedMph: 65.5, postedLimitMph: 65, at: t0 + 400).isEmpty)
    }

    @Test func marginAlertStacksOnTopOfLimitAlert() {
        var engine = engine(.init(alertOverPostedLimit: true, postedMarginMph: 5))

        _ = engine.process(speedMph: 66, postedLimitMph: 65, at: t0)
        #expect(engine.process(speedMph: 66, postedLimitMph: 65, at: t0 + 11)
                == [.overPostedLimit(limitMph: 65)])
        _ = engine.process(speedMph: 71, postedLimitMph: 65, at: t0 + 12)
        #expect(engine.process(speedMph: 71, postedLimitMph: 65, at: t0 + 23)
                == [.overPostedMargin(limitMph: 65, marginMph: 5)])
    }

    @Test func maxSpeedWarnsOnApproachThenCrossing() {
        var engine = engine(.init(maxSpeedMph: 80))

        #expect(engine.process(speedMph: 70, postedLimitMph: nil, at: t0).isEmpty)
        // Within 3 mph of the 80 max, held.
        _ = engine.process(speedMph: 78, postedLimitMph: nil, at: t0)
        #expect(engine.process(speedMph: 78, postedLimitMph: nil, at: t0 + 11)
                == [.approachingMaxSpeed(maxMph: 80)])
        _ = engine.process(speedMph: 81, postedLimitMph: nil, at: t0 + 12)
        #expect(engine.process(speedMph: 81, postedLimitMph: nil, at: t0 + 23)
                == [.overMaxSpeed(maxMph: 80)])
    }

    @Test func noLimitDataMeansNoPostedAlerts() {
        var engine = engine(.init(alertOverPostedLimit: true, postedMarginMph: 5))
        _ = engine.process(speedMph: 90, postedLimitMph: nil, at: t0)
        #expect(engine.process(speedMph: 90, postedLimitMph: nil, at: t0 + 30).isEmpty)
    }

    @Test func unknownSpeedNeverFires() {
        var engine = engine(.init(alertOverPostedLimit: true, maxSpeedMph: 80))
        #expect(engine.process(speedMph: nil, postedLimitMph: 65, at: t0).isEmpty)
    }

    @Test func resetRearmsEverything() {
        var engine = engine(.init(alertOverPostedLimit: true))
        _ = engine.process(speedMph: 70, postedLimitMph: 65, at: t0)
        _ = engine.process(speedMph: 70, postedLimitMph: 65, at: t0 + 11)
        engine.reset()
        _ = engine.process(speedMph: 70, postedLimitMph: 65, at: t0 + 12)
        #expect(engine.process(speedMph: 70, postedLimitMph: 65, at: t0 + 23)
                == [.overPostedLimit(limitMph: 65)])
    }
}

@MainActor
struct RoadLimitTests {
    @Test func extractsHighwayNumbers() {
        #expect(RoadLimitTool.searchTerm(from: "101") == "101")
        #expect(RoadLimitTool.searchTerm(from: "I-280") == "280")
        #expect(RoadLimitTool.searchTerm(from: "US 101") == "101")
        #expect(RoadLimitTool.searchTerm(from: "El Camino Real") == "El Camino Real")
    }

    @Test func summarizesUniformLimit() {
        let text = RoadieToolFormatting.describeRoadLimits(road: "101", mphValues: [65, 65, 65])
        #expect(text.contains("65 mph"))
        #expect(!text.contains("varies"))
    }

    @Test func summarizesVaryingLimits() {
        let text = RoadieToolFormatting.describeRoadLimits(road: "280", mphValues: [65, 70, 70, 55])
        #expect(text.contains("55 to 70"))
        #expect(text.contains("most segments are 70"))
    }

    @Test func missingDataForbidsGuessing() {
        let text = RoadieToolFormatting.describeRoadLimits(road: "Skyline Blvd", mphValues: [])
        #expect(text.contains("do not guess"))
    }
}

struct AdaptiveMarginTests {
    @Test func adaptiveMarginScalesWithTheRoad() {
        var config = SpeedAlertEngine.Config()
        config.postedMarginIsAdaptive = true
        // 25 zone: 15% is 3.75, floor wins → 5 (coach at 30+).
        #expect(config.effectiveMarginMph(forLimit: 25) == 5)
        // 65 zone: 15% → 9.75 (coach at ~75).
        #expect(config.effectiveMarginMph(forLimit: 65) == 9.75)
    }

    @Test func adaptiveOverridesFixedMph() {
        var config = SpeedAlertEngine.Config()
        config.postedMarginMph = 5
        config.postedMarginIsAdaptive = true
        #expect(config.effectiveMarginMph(forLimit: 65) == 9.75)
    }

    @Test func adaptiveMarginFiresAtTheRightSpeed() {
        var engine = SpeedAlertEngine()
        engine.config = .init(alertOverPostedLimit: false, postedMarginIsAdaptive: true)
        // 65 zone: nothing at 72 (needs ~74.75), fires at 76 once held.
        let t0 = Date(timeIntervalSince1970: 1_724_500_000)
        #expect(engine.process(speedMph: 72, postedLimitMph: 65, at: t0).isEmpty)
        _ = engine.process(speedMph: 76, postedLimitMph: 65, at: t0)
        let events = engine.process(speedMph: 76, postedLimitMph: 65, at: t0 + 11)
        #expect(events == [.overPostedMargin(limitMph: 65, marginMph: 10)])
    }
}
