import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct CoachTests {
    @Test func gentleNudgeUsesNameAndSpeed() {
        let text = Coach.message(
            for: .overPostedLimit(limitMph: 65),
            speedMph: 78, name: "Jason", style: .gentle, customTemplate: "", occurrence: 1
        )
        #expect(text == "Jason, you're at 78 mph — consider easing off a little.")
    }

    @Test func coachStyleMentionsTheLimit() {
        let text = Coach.message(
            for: .overPostedMargin(limitMph: 65, marginMph: 5),
            speedMph: 74, name: "Jason", style: .coach, customTemplate: "", occurrence: 1
        )
        #expect(text.contains("74 mph"))
        #expect(text.contains("65 mph"))
        #expect(text.hasPrefix("Hey Jason"))
    }

    @Test func customTemplateSubstitutesTokens() {
        let text = Coach.message(
            for: .overPostedLimit(limitMph: 65),
            speedMph: 78, name: "Jason", style: .custom,
            customTemplate: "Hey {name}, you were going {speed}. Please consider slowing down.",
            occurrence: 1
        )
        #expect(text == "Hey Jason, you were going 78 mph. Please consider slowing down.")
    }

    @Test func emptyCustomFallsBackToGentle() {
        let text = Coach.message(
            for: .overPostedLimit(limitMph: 65),
            speedMph: 78, name: nil, style: .custom, customTemplate: "  ", occurrence: 1
        )
        #expect(text.contains("consider easing off"))
        #expect(text.contains("there,")) // nameless fallback
    }

    @Test func thirdAlertEscalatesTone() {
        let text = Coach.message(
            for: .overPostedLimit(limitMph: 65),
            speedMph: 80, name: "Jason", style: .direct, customTemplate: "", occurrence: 3
        )
        #expect(text.contains("third time this drive"))
    }

    @Test func approachingMaxIsAHeadsUpNotAScold() {
        let text = Coach.message(
            for: .approachingMaxSpeed(maxMph: 80),
            speedMph: 78, name: "Jason", style: .direct, customTemplate: "", occurrence: 1
        )
        #expect(text == "Jason, you're getting close to your 80 mph max.")
    }
}
