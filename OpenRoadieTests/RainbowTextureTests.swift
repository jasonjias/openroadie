import RealityKit
import Testing
@testable import OpenRoadie

@MainActor
struct RainbowTextureTests {
    @Test func bandImageGenerates() {
        let image = DriveSceneView.rainbowBandImage()
        #expect(image != nil)
        #expect(image?.height == 512)
    }

    @Test func blurredHaloGenerates() {
        let sharp = DriveSceneView.rainbowBandImage()
        #expect(sharp != nil)
        let halo = sharp.flatMap { DriveSceneView.blurred($0, radius: 22) }
        #expect(halo != nil)
    }

    @Test func textureResourcesBuild() {
        guard let sharp = DriveSceneView.rainbowBandImage() else {
            Issue.record("no band image")
            return
        }
        do {
            _ = try TextureResource(image: sharp, options: .init(semantic: .color))
        } catch {
            Issue.record("sharp texture failed: \(error)")
        }
        if let halo = DriveSceneView.blurred(sharp, radius: 22) {
            do {
                _ = try TextureResource(image: halo, options: .init(semantic: .color))
            } catch {
                Issue.record("halo texture failed: \(error)")
            }
        }
    }

    @Test func roadHasTheBlurRibbon() {
        // Pin every option — defaulted parameters read live UserDefaults,
        // which the simulator's manual test-drives may have customized.
        let road = DriveSceneView.makeRoad(style: .rainbow, lamps: false, season: .off)
        #expect(road.children.count == 1)
    }

    @Test func asphaltImagesGenerate() {
        for dark in [false, true] {
            let image = DriveSceneView.asphaltImage(dark: dark)
            #expect(image != nil)
            #expect(image?.height == 512)
        }
    }

    @Test func everyRoadStyleBuildsARibbon() {
        for style in RoadStyle.allCases {
            let road = DriveSceneView.makeRoad(style: style, lamps: false, season: .off)
            #expect(road.children.count == 1, "style \(style.rawValue)")
        }
    }

    @Test func lampsLineTheRoadWhenEnabled() {
        let road = DriveSceneView.makeRoad(style: .night, lamps: true, season: .off)
        // One ribbon plus two lamps (one per sidewalk) per texture period.
        let periods = Int((DriveSceneView.roadLength + DriveSceneView.rainbowPeriod) / DriveSceneView.rainbowPeriod)
        #expect(road.children.count == 1 + periods * 2)
        // Night lamps carry the glow pool; day lamps don't.
        let nightLamp = DriveSceneView.makeStreetLamp(lit: true)
        let dayLamp = DriveSceneView.makeStreetLamp(lit: false)
        #expect(nightLamp.children.count == dayLamp.children.count + 1)
    }

    @Test func everySeasonPlantsTrees() {
        for season in RoadSeason.allCases where season != .off {
            let road = DriveSceneView.makeRoad(style: .standard, lamps: false, season: season)
            // One ribbon + two trees per period (presents double Christmas;
            // spring runs the dense 4-per-side avenue).
            let periods = Int((DriveSceneView.roadLength + DriveSceneView.rainbowPeriod) / DriveSceneView.rainbowPeriod)
            let expected = switch season {
            case .christmas: 1 + periods * 4
            case .spring, .fall: 1 + periods * 40  // 4 rows × 2 sides × 5 columns
            default: 1 + periods * 2
            }
            #expect(road.children.count == expected, "season \(season.rawValue)")
        }
    }

    @Test func sceneryModelsLoad() {
        for name in ["scenery-tree-spring", "scenery-tree-summer", "scenery-tree-fall",
                     "scenery-tree-fall-b", "scenery-tree-fall-c",
                     "scenery-tree-winter", "scenery-tree-christmas", "scenery-lamp-curved",
                     "scenery-lantern", "scenery-present-a", "scenery-present-b"] {
            let entity = DriveSceneView.loadScenery(name, height: 2)
            #expect(entity != nil, "\(name) failed to load")
            if let entity {
                let height = entity.visualBounds(relativeTo: nil).extents.y
                #expect(abs(height - 2) < 0.05, "\(name) height \(height)")
            }
        }
    }

    @Test func unknownRoadStyleFallsBackToStandard() {
        #expect(RoadStyle(rawValue: "disco") == nil)
        #expect(RoadStyle(rawValue: RoadStyle.standard.rawValue) == .standard)
    }
}
