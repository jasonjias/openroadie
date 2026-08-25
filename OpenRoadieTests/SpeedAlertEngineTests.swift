import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct SpeedAlertEngineTests {
    private func engine(_ config: SpeedAlertEngine.Config) -> SpeedAlertEngine {
        var engine = SpeedAlertEngine()
        engine.config = config
        return engine
    }

    @Test func firesOnceWhenCrossingPostedLimit() {
        var engine = engine(.init(alertOverPostedLimit: true))

        #expect(engine.process(speedMph: 60, postedLimitMph: 65).isEmpty)
        #expect(engine.process(speedMph: 66, postedLimitMph: 65) == [.overPostedLimit(limitMph: 65)])
        // Still over: no repeat.
        #expect(engine.process(speedMph: 70, postedLimitMph: 65).isEmpty)
    }

    @Test func hysteresisPreventsJitterSpam() {
        var engine = engine(.init(alertOverPostedLimit: true))

        _ = engine.process(speedMph: 66, postedLimitMph: 65) // fires, disarms
        // Bouncing right at the limit must NOT re-fire...
        #expect(engine.process(speedMph: 64.5, postedLimitMph: 65).isEmpty)
        #expect(engine.process(speedMph: 65.5, postedLimitMph: 65).isEmpty)
        // ...but dropping clearly below re-arms, and crossing fires again.
        #expect(engine.process(speedMph: 62, postedLimitMph: 65).isEmpty)
        #expect(engine.process(speedMph: 66, postedLimitMph: 65) == [.overPostedLimit(limitMph: 65)])
    }

    @Test func marginAlertStacksOnTopOfLimitAlert() {
        var engine = engine(.init(alertOverPostedLimit: true, postedMarginMph: 5))

        #expect(engine.process(speedMph: 66, postedLimitMph: 65) == [.overPostedLimit(limitMph: 65)])
        #expect(engine.process(speedMph: 71, postedLimitMph: 65) == [.overPostedMargin(limitMph: 65, marginMph: 5)])
    }

    @Test func maxSpeedWarnsOnApproachThenCrossing() {
        var engine = engine(.init(maxSpeedMph: 80))

        #expect(engine.process(speedMph: 70, postedLimitMph: nil).isEmpty)
        // Within 3 mph of the 80 max.
        #expect(engine.process(speedMph: 78, postedLimitMph: nil) == [.approachingMaxSpeed(maxMph: 80)])
        #expect(engine.process(speedMph: 81, postedLimitMph: nil) == [.overMaxSpeed(maxMph: 80)])
    }

    @Test func noLimitDataMeansNoPostedAlerts() {
        var engine = engine(.init(alertOverPostedLimit: true, postedMarginMph: 5))
        #expect(engine.process(speedMph: 90, postedLimitMph: nil).isEmpty)
    }

    @Test func unknownSpeedNeverFires() {
        var engine = engine(.init(alertOverPostedLimit: true, maxSpeedMph: 80))
        #expect(engine.process(speedMph: nil, postedLimitMph: 65).isEmpty)
    }

    @Test func resetRearmsEverything() {
        var engine = engine(.init(alertOverPostedLimit: true))
        _ = engine.process(speedMph: 70, postedLimitMph: 65)
        engine.reset()
        #expect(engine.process(speedMph: 70, postedLimitMph: 65) == [.overPostedLimit(limitMph: 65)])
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
        // 65 zone: nothing at 72 (needs ~74.75), fires at 76.
        #expect(engine.process(speedMph: 72, postedLimitMph: 65).isEmpty)
        let events = engine.process(speedMph: 76, postedLimitMph: 65)
        #expect(events == [.overPostedMargin(limitMph: 65, marginMph: 10)])
    }
}
