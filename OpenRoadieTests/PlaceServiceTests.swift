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
        #expect(places[1].name == "Starbucks")
        #expect(places[1].coordinate == Coordinate(latitude: 37.45, longitude: -122.15))
    }

    @Test func unnamedPlaceGetsCategoryFallback() throws {
        let json = """
        {"elements":[{"type":"node","id":1,"lat":37.0,"lon":-122.0,"tags":{"amenity":"fuel"}}]}
        """
        let places = try OverpassClient.parsePlaces(Data(json.utf8), category: .fuel)
        #expect(places[0].displayName == "Unnamed gas")
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
        let far = Place(id: "node/1", name: "Far", brand: nil, category: .food,
                        coordinate: Coordinate(latitude: 37.02, longitude: -122.0))
        let near = Place(id: "node/2", name: "Near", brand: nil, category: .food,
                         coordinate: Coordinate(latitude: 37.001, longitude: -122.0))

        let sorted = PlaceGeometry.sortedByDistance([far, near], from: origin)
        #expect(sorted.map(\.place.name) == ["Near", "Far"])
        // ~111 m for 0.001° of latitude.
        #expect(abs(sorted[0].distance - 111) < 5)
    }
}
