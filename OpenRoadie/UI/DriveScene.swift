import RealityKit
import SwiftUI

/// The 3D drive scene — a real engine this time, not a flat canvas.
///
/// Parked: the car sits under studio light, camera at a front three-quarter
/// hero angle. Driving: the camera sweeps to a Tesla-style chase position
/// and the rainbow road appears, scrolling at your actual GPS speed.
/// The car is built from primitives in code — no downloaded model, no
/// license baggage, deliberately low-poly.
struct DriveSceneView: View {
    let isDriving: Bool
    let speedMps: Double?

    /// Bridges live values into the per-frame update closure without
    /// re-subscribing, and retains the scene-update subscription.
    @State private var coordinator = Coordinator()

    var body: some View {
        RealityView { content in
            let root = Entity()
            content.add(root)

            let car = Self.makeCar()
            root.addChild(car)

            let road = Self.makeRoad()
            road.isEnabled = isDriving // rainbow is a driving-only spectacle
            root.addChild(road)
            coordinator.road = road

            root.addChild(Self.makeGround())
            root.addChild(Self.makeLights())

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 55
            root.addChild(camera)
            coordinator.camera = camera
            Self.place(camera: camera, driving: isDriving, animated: false)

            // Per-frame: scroll the rainbow at real speed, idle-orbit when
            // parked. RealityKit delivers scene updates on the main thread;
            // the closure just isn't statically annotated.
            coordinator.subscription = content.subscribe(to: SceneEvents.Update.self) { [weak coordinator] event in
                MainActor.assumeIsolated {
                    coordinator?.tick(deltaTime: event.deltaTime)
                }
            }
        } update: { _ in
            coordinator.speedMps = max(0, speedMps ?? 0)
            if coordinator.isDriving != isDriving {
                coordinator.isDriving = isDriving
                coordinator.road?.isEnabled = isDriving
                if let camera = coordinator.camera {
                    Self.place(camera: camera, driving: isDriving, animated: true)
                }
            }
        }
        .onAppear {
            coordinator.isDriving = isDriving
            coordinator.speedMps = max(0, speedMps ?? 0)
        }
    }

    // MARK: - Live state

    @MainActor
    @Observable
    final class Coordinator {
        var speedMps: Double = 0
        var isDriving = false
        var camera: PerspectiveCamera?
        var road: Entity?
        var subscription: EventSubscription?
        /// Parked-orbit angle, radians.
        private var orbit: Float = 0

        func tick(deltaTime: TimeInterval) {
            guard let road else { return }
            if isDriving {
                // Move stripes toward the camera at true speed; recycle.
                let dz = Float(speedMps * deltaTime)
                for stripe in road.children {
                    stripe.position.z += dz
                    if stripe.position.z > DriveSceneView.stripeRecycleZ {
                        stripe.position.z -= DriveSceneView.roadLength
                    }
                }
            } else if let camera {
                // Showroom: drift slowly around the parked car, framed wide
                // enough that the whole body stays in the short viewport.
                orbit += Float(deltaTime) * 0.12
                let radius: Float = 6.8
                let angle = orbit - 2.6 // start at the front three-quarter
                let x = sin(angle) * radius
                let z = cos(angle) * radius
                camera.look(at: [0, 0.35, 0], from: [x, 1.9, z], relativeTo: nil)
            }
        }
    }

    // MARK: - Camera

    private static func place(camera: PerspectiveCamera, driving: Bool, animated: Bool) {
        var transform = Transform()
        if driving {
            // Chase cam: above and behind, looking down the road.
            transform = Transform(matrix: float4x4.look(at: [0, 0.2, -8], from: [0, 3.2, 6.2]))
        } else {
            transform = Transform(matrix: float4x4.look(at: [0, 0.35, 0], from: [sin(-2.6) * 6.8, 1.9, cos(-2.6) * 6.8]))
        }
        if animated {
            camera.move(to: transform, relativeTo: nil, duration: 1.4, timingFunction: .easeInOut)
        } else {
            camera.transform = transform
        }
    }

    // MARK: - The car (all primitives, all code)

    static func makeCar() -> Entity {
        let car = Entity()
        let red = SimpleMaterial(color: UIColor(red: 0.86, green: 0.16, blue: 0.14, alpha: 1), roughness: 0.35, isMetallic: true)
        let glass = SimpleMaterial(color: UIColor(red: 0.35, green: 0.55, blue: 0.70, alpha: 1), roughness: 0.1, isMetallic: true)
        let dark = SimpleMaterial(color: UIColor(white: 0.12, alpha: 1), roughness: 0.8, isMetallic: false)

        // Chassis, cabin, glass band. Front is -z, rear is +z.
        let chassis = ModelEntity(mesh: .generateBox(size: [1.7, 0.5, 3.4], cornerRadius: 0.16), materials: [red])
        chassis.position = [0, 0.5, 0]
        car.addChild(chassis)

        // Greenhouse: a glass cabin with a thin body-color roof plate.
        let cabin = ModelEntity(mesh: .generateBox(size: [1.42, 0.44, 1.85], cornerRadius: 0.18), materials: [glass])
        cabin.position = [0, 0.95, 0.15]
        car.addChild(cabin)

        let roof = ModelEntity(mesh: .generateBox(size: [1.30, 0.08, 1.55], cornerRadius: 0.04), materials: [red])
        roof.position = [0, 1.19, 0.15]
        car.addChild(roof)

        // Wheels: cylinders rotated onto the x-axis.
        for (x, z) in [(-0.78, -1.05), (0.78, -1.05), (-0.78, 1.05), (0.78, 1.05)] {
            let wheel = ModelEntity(mesh: .generateCylinder(height: 0.24, radius: 0.34), materials: [dark])
            wheel.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            wheel.position = [Float(x), 0.34, Float(z)]
            car.addChild(wheel)
        }

        // Taillights (rear, glowing) and headlights (front).
        var tailGlow = UnlitMaterial(color: UIColor(red: 1.0, green: 0.22, blue: 0.18, alpha: 1))
        tailGlow.blending = .transparent(opacity: 1.0)
        for x in [-0.55, 0.55] {
            let light = ModelEntity(mesh: .generateBox(size: [0.34, 0.10, 0.06], cornerRadius: 0.03), materials: [tailGlow])
            light.position = [Float(x), 0.62, 1.71]
            car.addChild(light)
        }
        let headGlow = UnlitMaterial(color: UIColor(white: 0.95, alpha: 1))
        for x in [-0.55, 0.55] {
            let light = ModelEntity(mesh: .generateBox(size: [0.30, 0.10, 0.06], cornerRadius: 0.03), materials: [headGlow])
            light.position = [Float(x), 0.62, -1.71]
            car.addChild(light)
        }
        return car
    }

    // MARK: - The rainbow road

    static let roadLength: Float = 60
    static let stripeRecycleZ: Float = 8

    static func makeRoad() -> Entity {
        let road = Entity()
        let colors: [UIColor] = [
            UIColor(red: 0.94, green: 0.31, blue: 0.30, alpha: 1),
            UIColor(red: 0.98, green: 0.60, blue: 0.22, alpha: 1),
            UIColor(red: 0.99, green: 0.86, blue: 0.30, alpha: 1),
            UIColor(red: 0.42, green: 0.80, blue: 0.40, alpha: 1),
            UIColor(red: 0.31, green: 0.66, blue: 0.94, alpha: 1),
            UIColor(red: 0.46, green: 0.44, blue: 0.90, alpha: 1),
            UIColor(red: 0.72, green: 0.42, blue: 0.90, alpha: 1),
        ]
        let stripeDepth: Float = 1.5
        let count = Int(roadLength / stripeDepth)
        for i in 0..<count {
            let material = SimpleMaterial(color: colors[i % colors.count], roughness: 0.6, isMetallic: false)
            let stripe = ModelEntity(mesh: .generateBox(size: [3.4, 0.04, stripeDepth]), materials: [material])
            stripe.position = [0, 0.02, stripeRecycleZ - Float(i) * stripeDepth]
            road.addChild(stripe)
        }
        return road
    }

    static func makeGround() -> Entity {
        let ground = ModelEntity(
            mesh: .generatePlane(width: 80, depth: 80),
            materials: [SimpleMaterial(color: UIColor(white: 0.45, alpha: 1), roughness: 0.95, isMetallic: false)]
        )
        ground.position = [0, -0.02, 0]
        return ground
    }

    static func makeLights() -> Entity {
        let rig = Entity()
        let sun = DirectionalLight()
        sun.light.intensity = 4200
        sun.look(at: [0, 0, 0], from: [3, 6, 3], relativeTo: nil)
        rig.addChild(sun)
        let fill = DirectionalLight()
        fill.light.intensity = 1400
        fill.look(at: [0, 0, 0], from: [-4, 3, -2], relativeTo: nil)
        rig.addChild(fill)
        return rig
    }
}

extension float4x4 {
    /// A look-at matrix for placing cameras: right-handed, -z forward.
    static func look(at target: SIMD3<Float>, from position: SIMD3<Float>) -> float4x4 {
        let forward = simd_normalize(target - position)
        let right = simd_normalize(simd_cross([0, 1, 0], -forward))
        let up = simd_cross(-forward, right)
        return float4x4(
            SIMD4(right, 0),
            SIMD4(up, 0),
            SIMD4(-forward, 0),
            SIMD4(position, 1)
        )
    }
}
