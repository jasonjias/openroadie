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
        let road = DriveSceneView.makeRoad(style: .rainbow, lamps: false)
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
            let road = DriveSceneView.makeRoad(style: style, lamps: false)
            #expect(road.children.count == 1, "style \(style.rawValue)")
        }
    }

    @Test func lampsLineTheRoadWhenEnabled() {
        let road = DriveSceneView.makeRoad(style: .night, lamps: true)
        // One ribbon plus a lamp per texture period.
        let expectedLamps = Int((DriveSceneView.roadLength + DriveSceneView.rainbowPeriod) / DriveSceneView.rainbowPeriod)
        #expect(road.children.count == 1 + expectedLamps)
        // Night lamps carry the glow pool; day lamps don't.
        let nightLamp = DriveSceneView.makeStreetLamp(lit: true)
        let dayLamp = DriveSceneView.makeStreetLamp(lit: false)
        #expect(nightLamp.children.count == dayLamp.children.count + 1)
    }

    @Test func unknownRoadStyleFallsBackToStandard() {
        #expect(RoadStyle(rawValue: "disco") == nil)
        #expect(RoadStyle(rawValue: RoadStyle.standard.rawValue) == .standard)
    }
}
