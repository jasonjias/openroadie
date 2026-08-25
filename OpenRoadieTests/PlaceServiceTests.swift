import Foundation
import Testing
@testable import OpenRoadie

struct PlaceParsingTests {
    @Test func parsesNodesAndWayCenters() throws {
        let json = """
        {"elements":[
          {"type":"node","id":101,"lat":37.44,"lon":-122.16,
           "tags":{"amenity":"cafe","name":"Blue Bottle"}},
          {"type":"way","id":202,"center":{"lat":37.45,"lon":-122.15},
           "tags":{"amenity":"cafe","brand":"Starbucks"}},
          {"type":"node","id":303,"tags":{"amenity":"cafe"}}
        ]}
        """
        let places = try OverpassClient.parsePlaces(Data(json.utf8), category: .coffee)

        // The coordinate-less node is dropped.
        #expect(places.count == 2)
        #expect(places[0].id == "node/101")
        #expect(places[0].name == "Blue Bottle")
        // A way's center becomes its coordinate; brand fills a missing name.
        #expect(places[1].id == "way/202")
        #expect(places[1].displayName == "Starbucks")
        #expect(places[1].coordinate == Coordinate(latitude: 37.45, longitude: -122.15))
    }

    @Test func unnamedPlaceGetsCategoryFallback() throws {
        let json = """
        {"elements":[{"type":"node","id":1,"lat":37.0,"lon":-122.0,"tags":{"amenity":"fuel"}}]}
        """
        let places = try OverpassClient.parsePlaces(Data(json.utf8), category: .fuel)
        #expect(places[0].displayName == "Unnamed gas station")
    }

    @Test func chargerFallsBackToBrandThenOperator() throws {
        let json = """
        {"elements":[
          {"type":"node","id":1,"lat":37.0,"lon":-122.0,
           "tags":{"amenity":"charging_station","brand":"Tesla Supercharger","operator":"Tesla, Inc."}},
          {"type":"node","id":2,"lat":37.0,"lon":-122.0,
           "tags":{"amenity":"charging_station","operator":"ChargePoint"}}
        ]}
        """
        let places = try OverpassClient.parsePlaces(Data(json.utf8), category: .charger)
        #expect(places[0].displayName == "Tesla Supercharger")
        #expect(places[1].displayName == "ChargePoint")
    }

    @Test func keywordMatchesAnyIdentityTag() {
        let supercharger = Place(
            id: "node/1", name: "Mountain View Supercharger", brand: "Tesla Supercharger",
            operatedBy: "Tesla, Inc.", address: nil, category: .charger,
            coordinate: Coordinate(latitude: 37, longitude: -122)
        )
        let blink = Place(
            id: "node/2", name: nil, brand: "Blink", operatedBy: nil,
            category: .charger, coordinate: Coordinate(latitude: 37, longitude: -122)
        )
        #expect(supercharger.matches(keyword: "tesla"))
        #expect(supercharger.matches(keyword: "TESLA"))
        #expect(!blink.matches(keyword: "tesla"))
        #expect(blink.matches(keyword: "blink"))
    }

    @Test func parsesStreetAddressFromAddrTags() throws {
        let json = """
        {"elements":[
          {"type":"node","id":1,"lat":37.44,"lon":-122.16,
           "tags":{"amenity":"charging_station","brand":"Tesla Supercharger",
                   "addr:housenumber":"550","addr:street":"High Street","addr:city":"Palo Alto"}},
          {"type":"node","id":2,"lat":37.44,"lon":-122.16,
           "tags":{"amenity":"charging_station","addr:street":"Emerson Street"}},
          {"type":"node","id":3,"lat":37.44,"lon":-122.16,
           "tags":{"amenity":"charging_station"}}
        ]}
        """
        let places = try OverpassClient.parsePlaces(Data(json.utf8), category: .charger)
        #expect(places[0].address == "550 High Street, Palo Alto")
        #expect(places[1].address == "Emerson Street")
        #expect(places[2].address == nil)
    }

    @Test func everyCategoryHasAValidFilter() {
        for category in PlaceCategory.allCases {
            #expect(category.overpassFilter.hasPrefix("[\""))
            #expect(category.overpassFilter.hasSuffix("]"))
        }
    }
}

struct PlaceGeometryTests {
    @Test func bearingPointsTheRightWay() {
        let origin = Coordinate(latitude: 37.0, longitude: -122.0)
        // Due north.
        let north = PlaceGeometry.bearing(from: origin, to: Coordinate(latitude: 37.01, longitude: -122.0))
        #expect(abs(north - 0) < 0.5 || abs(north - 360) < 0.5)
        // Due east.
        let east = PlaceGeometry.bearing(from: origin, to: Coordinate(latitude: 37.0, longitude: -121.99))
        #expect(abs(east - 90) < 0.5)
        // Due south.
        let south = PlaceGeometry.bearing(from: origin, to: Coordinate(latitude: 36.99, longitude: -122.0))
        #expect(abs(south - 180) < 0.5)
    }

    @Test func sortsNearestFirst() {
        let origin = Coordinate(latitude: 37.0, longitude: -122.0)
        let far = Place(id: "node/1", name: "Far", brand: nil, operatedBy: nil, address: nil, category: .food,
                        coordinate: Coordinate(latitude: 37.02, longitude: -122.0))
        let near = Place(id: "node/2", name: "Near", brand: nil, operatedBy: nil, address: nil, category: .food,
                         coordinate: Coordinate(latitude: 37.001, longitude: -122.0))

        let sorted = PlaceGeometry.sortedByDistance([far, near], from: origin)
        #expect(sorted.map(\.place.name) == ["Near", "Far"])
        // ~111 m for 0.001° of latitude.
        #expect(abs(sorted[0].distance - 111) < 5)
    }
}

@MainActor
struct SearchFormattingTests {
    @Test func describesSearchResultsWithAddresses() {
        let origin = Coordinate(latitude: 37.0, longitude: -122.0)
        let results = [
            (FoundPlace(id: "1", name: "Walgreens", address: "300 University Ave, Palo Alto",
                        coordinate: Coordinate(latitude: 37.001, longitude: -122.0)), 111.0),
        ]
        let text = RoadieToolFormatting.describeSearchResults(query: "pharmacy", results: results, origin: origin)
        #expect(text.contains("Walgreens"))
        #expect(text.contains("300 University Ave"))
        #expect(text.contains("pharmacy"))
    }

    @Test func emptySearchForbidsInvention() {
        let text = RoadieToolFormatting.describeSearchResults(
            query: "unicorn stables", results: [], origin: Coordinate(latitude: 0, longitude: 0)
        )
        #expect(text.contains("do not invent"))
    }
}
