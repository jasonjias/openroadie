import Foundation
import Testing
@testable import OpenRoadie

@MainActor
struct WakeWordTests {
    @Test func detectsBareWakePhrase() {
        let result = WakeWordListener.detectWake(in: "Hey Roadie")
        #expect(result.found)
        #expect(result.remainder.isEmpty)
    }

    @Test func extractsInlineQuestion() {
        let result = WakeWordListener.detectWake(in: "Hey, Roadie! How fast am I going?")
        #expect(result.found)
        #expect(result.remainder == "how fast am i going")
    }

    @Test func toleratesCommonMisrecognitions() {
        for heard in ["hey roady find me coffee", "Hey Rowdy find me coffee", "hey Brodie find me coffee"] {
            let result = WakeWordListener.detectWake(in: heard)
            #expect(result.found, "should wake on: \(heard)")
            #expect(result.remainder == "find me coffee")
        }
    }

    @Test func ignoresOrdinaryChatter() {
        for heard in ["let's get lunch after this", "the road is busy today", "hey how's it going"] {
            #expect(!WakeWordListener.detectWake(in: heard).found, "false wake on: \(heard)")
        }
    }

    @Test func wakeMidSentenceStillCatches() {
        let result = WakeWordListener.detectWake(in: "um okay hey roadie what's the speed limit")
        #expect(result.found)
        #expect(result.remainder == "what s the speed limit")
    }
}
