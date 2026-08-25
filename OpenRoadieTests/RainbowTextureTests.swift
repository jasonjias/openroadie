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
        let road = DriveSceneView.makeRoad()
        #expect(road.children.count == 1)
    }
}
