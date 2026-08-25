import Foundation
import Testing
@testable import OpenRoadie

/// Serialized: these tests share UserDefaults state.
@Suite(.serialized)
struct PlaceCategoryOrderTests {
    private func clearOrder() {
        UserDefaults.standard.removeObject(forKey: PlaceCategory.orderDefaultsKey)
    }

    @Test func defaultOrderIsDeclarationOrder() {
        clearOrder()
        #expect(PlaceCategory.ordered == PlaceCategory.allCases)
    }

    @Test func storedOrderIsRespected() {
        clearOrder()
        let custom: [PlaceCategory] = [.supercharger, .food, .coffee, .fuel, .charger, .landmark]
        PlaceCategory.setOrder(custom)
        #expect(PlaceCategory.ordered == custom)
        clearOrder()
    }

    @Test func categoriesMissingFromStoredOrderAreAppended() {
        clearOrder()
        // Simulates an order saved before a new category existed.
        UserDefaults.standard.set(["supercharger", "coffee"], forKey: PlaceCategory.orderDefaultsKey)
        let ordered = PlaceCategory.ordered
        #expect(ordered.prefix(2) == [.supercharger, .coffee])
        #expect(Set(ordered) == Set(PlaceCategory.allCases))
        clearOrder()
    }

    @Test func unknownRawValuesAreIgnored() {
        clearOrder()
        UserDefaults.standard.set(["heliport", "food"], forKey: PlaceCategory.orderDefaultsKey)
        let ordered = PlaceCategory.ordered
        #expect(ordered.first == .food)
        #expect(Set(ordered) == Set(PlaceCategory.allCases))
        clearOrder()
    }
}
