import Foundation
import Testing
@testable import OpenRoadie

/// Serialized: these tests share UserDefaults state.
@Suite(.serialized)
struct NearbyChipOrderTests {
    private func clearState() {
        UserDefaults.standard.removeObject(forKey: PlaceCategory.orderDefaultsKey)
        UserDefaults.standard.removeObject(forKey: CustomCategory.defaultsKey)
    }

    @Test func defaultOrderIsBuiltinsThenCustoms() {
        clearState()
        let chipotle = CustomCategory(title: "Landmarks (real)", terms: ["chipotle"])
        CustomCategory.save([chipotle])
        let ordered = NearbyChip.ordered
        #expect(Array(ordered.prefix(PlaceCategory.allCases.count)) == PlaceCategory.allCases.map { .builtin($0) })
        #expect(ordered.last == .custom(chipotle))
        clearState()
    }

    @Test func storedOrderInterleavesCustomsWithBuiltins() {
        clearState()
        let chipotle = CustomCategory(title: "Landmarks (real)", terms: ["chipotle", "in-n-out"])
        CustomCategory.save([chipotle])
        let wanted: [NearbyChip] = [.builtin(.supercharger), .custom(chipotle), .builtin(.food)]
        NearbyChip.setOrder(wanted)
        let ordered = NearbyChip.ordered
        #expect(Array(ordered.prefix(3)) == wanted)
        #expect(Set(ordered.map(\.id)).count == PlaceCategory.allCases.count + 1)
        clearState()
    }

    @Test func deletedCustomDisappearsFromStoredOrder() {
        clearState()
        let chipotle = CustomCategory(title: "Chipotle", terms: ["chipotle"])
        CustomCategory.save([chipotle])
        NearbyChip.setOrder([.custom(chipotle), .builtin(.food)])
        CustomCategory.save([]) // deleted
        #expect(!NearbyChip.ordered.contains { $0.id == chipotle.key })
        #expect(NearbyChip.ordered.first == .builtin(.food))
        clearState()
    }

    @Test func unknownStoredIDsAreIgnored() {
        clearState()
        UserDefaults.standard.set(["heliport", "food"], forKey: PlaceCategory.orderDefaultsKey)
        let ordered = NearbyChip.ordered
        #expect(ordered.first == .builtin(.food))
        #expect(ordered.count == PlaceCategory.allCases.count)
        clearState()
    }

    @Test func hiddenBuiltinsAreInvisibleButCustomsAlwaysShow() {
        clearState()
        let chipotle = CustomCategory(title: "Chipotle", terms: ["chipotle"])
        CustomCategory.save([chipotle])
        PlaceCategory.setHidden(.fuel, true)
        let visible = NearbyChip.visible
        #expect(!visible.contains(.builtin(.fuel)))
        #expect(visible.contains(.custom(chipotle)))
        PlaceCategory.setHidden(.fuel, false)
        clearState()
    }

    // In this suite (not CustomCategoryTests) because it touches the shared
    // UserDefaults key — suites run in parallel; only this one is serialized.
    @Test func customCategoriesRoundTripThroughDefaults() {
        clearState()
        let custom = CustomCategory(title: "Chipotle", systemImage: "fork.knife", terms: ["chipotle"])
        CustomCategory.save([custom])
        #expect(CustomCategory.load() == [custom])
        clearState()
    }
}

struct CustomCategoryTests {
    @Test func regexJoinsTermsWithPipe() {
        let custom = CustomCategory(title: "Favorites", terms: ["chipotle", "in-n-out", "raising canes"])
        #expect(custom.overpassRegex == "chipotle|in-n-out|raising canes")
    }

    @Test func regexEscapesMetacharacters() {
        let custom = CustomCategory(title: "Odd", terms: ["In-N-Out (Lathrop)", "a.b*c"])
        #expect(custom.overpassRegex == #"In-N-Out \(Lathrop\)|a\.b\*c"#)
    }

    @Test func regexSkipsBlankTerms() {
        let custom = CustomCategory(title: "Sparse", terms: [" chipotle ", "", "   "])
        #expect(custom.overpassRegex == "chipotle")
    }
}
