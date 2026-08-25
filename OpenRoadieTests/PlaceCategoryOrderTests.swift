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

    // Defaults-touching tests live in this serialized suite — parallel
    // suites sharing UserDefaults wipe each other's state.
    @Test func matchingFindsCustomsByTitleTermAndLoosely() {
        clearState()
        let chipotle = CustomCategory(title: "Landmarks (real)", terms: ["chipotle", "in-n-out"])
        CustomCategory.save([chipotle])
        #expect(CustomCategory.matching("landmarks (real)") == chipotle)
        #expect(CustomCategory.matching("chipotle") == chipotle)
        #expect(CustomCategory.matching("my landmarks (real)") == chipotle)
        #expect(CustomCategory.matching("food") == nil)     // built-ins stay built-in
        #expect(CustomCategory.matching("gas") == nil)      // too short for loose match
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

struct PlaceCategoryAliasTests {
    @Test func gasMeansFuel() {
        #expect(PlaceCategory(alias: "gas") == .fuel)
        #expect(PlaceCategory(alias: "Gas Stations") == .fuel)
    }

    @Test func rawValuesAndPluralsResolve() {
        #expect(PlaceCategory(alias: "food") == .food)
        #expect(PlaceCategory(alias: "chargers") == .charger)
        #expect(PlaceCategory(alias: "Landmarks") == .landmark)
        #expect(PlaceCategory(alias: "supercharger") == .supercharger)
    }

    @Test func unknownAliasIsNil() {
        #expect(PlaceCategory(alias: "heliport") == nil)
    }
}

struct CustomCategoryTests {
    @Test func foundPlaceConvertsToPlace() {
        let found = FoundPlace(
            id: "Chipotle@37.42,-122.14",
            name: "Chipotle Mexican Grill",
            address: "2675 El Camino Real, Palo Alto",
            coordinate: Coordinate(latitude: 37.42, longitude: -122.14)
        )
        let place = Place(found)
        #expect(place.displayName == "Chipotle Mexican Grill")
        #expect(place.address == "2675 El Camino Real, Palo Alto")
        #expect(place.id == found.id)
        #expect(place.matches(keyword: "chipotle"))
    }
}
