import RealityKit
import SwiftUI

/// The vehicle on the drive scene — Kenney's CC0 kits, user's choice.
/// Each case maps to a .usdc model bundled under Vehicles/; anything not
/// bundled yet falls back to the built-in primitive car, so the picker
/// can ship ahead of the assets.
enum Vehicle: String, CaseIterable, Identifiable {
    case classic       // the procedural primitive car
    case sedan
    case sportsCar
    case toyRacer
    case bulldozer
    case boat
    case train
    case skateboard
    case pirateShip
    case speeder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: "Classic (built-in)"
        case .sedan: "Sedan"
        case .sportsCar: "Sports Car"
        case .toyRacer: "Toy Racer"
        case .bulldozer: "Bulldozer"
        case .boat: "Speedboat"
        case .train: "Bullet Train"
        case .skateboard: "Skateboard"
        case .pirateShip: "Pirate Ship"
        case .speeder: "Hover Speeder"
        }
    }

    /// Bundled model resource name (Vehicles/<name>.usda), nil for classic.
    var modelName: String? {
        switch self {
        case .classic: nil
        case .sedan: "vehicle-sedan"
        case .sportsCar: "vehicle-sports"
        case .toyRacer: "vehicle-toy-racer"
        case .bulldozer: "vehicle-bulldozer"
        case .boat: "vehicle-boat"
        case .train: "vehicle-train"
        case .skateboard: "vehicle-skateboard"
        case .pirateShip: "vehicle-pirate"
        case .speeder: "vehicle-speeder"
        }
    }

    static let defaultsKey = "driveSceneVehicle"

    static var current: Vehicle {
        Vehicle(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .classic
    }

    /// The model is bundled and loadable — otherwise the picker row shows
    /// it as coming soon and the scene falls back to classic.
    var isAvailable: Bool {
        guard let modelName else { return true }
        return Bundle.main.url(forResource: modelName, withExtension: "usda") != nil
    }

    /// Loads the chosen vehicle, scaled and grounded; primitive car when
    /// no model is bundled.
    @MainActor
    func makeEntity() -> Entity {
        if let modelName,
           let url = Bundle.main.url(forResource: modelName, withExtension: "usda"),
           let model = try? Entity.load(contentsOf: url) {
            // Normalize: Kenney models vary in native size; scale so the
            // longest side is ~3.4m (our chase camera's frame of reference).
            let bounds = model.visualBounds(relativeTo: nil)
            let longest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
            if longest > 0 {
                model.scale *= SIMD3<Float>(repeating: 3.4 / longest)
            }
            let grounded = model.visualBounds(relativeTo: nil)
            model.position.y -= grounded.min.y
            // Kenney models face +z; our scene drives toward -z.
            model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            return model
        }
        return DriveSceneView.makeCar()
    }
}

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
    var vehicle: Vehicle = .classic

    /// Bridges live values into the per-frame update closure without
    /// re-subscribing, and retains the scene-update subscription.
    @State private var coordinator = Coordinator()

    var body: some View {
        RealityView { content in
            let root = Entity()
            content.add(root)
            coordinator.root = root

            let car = vehicle.makeEntity()
            root.addChild(car)
            coordinator.car = car
            coordinator.vehicle = vehicle

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
            if coordinator.vehicle != vehicle {
                coordinator.vehicle = vehicle
                coordinator.car?.removeFromParent()
                let fresh = vehicle.makeEntity()
                coordinator.root?.addChild(fresh)
                coordinator.car = fresh
            }
            if coordinator.isDriving != isDriving {
                coordinator.isDriving = isDriving
                coordinator.road?.isEnabled = isDriving
                if !isDriving { coordinator.resetStance() }
                if let camera = coordinator.camera {
                    Self.place(camera: camera, driving: isDriving, animated: true)
                }
            }
        }
        // Tesla-style: drag to spin around the parked vehicle. The idle
        // orbit pauses while you're in control and resumes a beat later.
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard !isDriving else { return }
                    coordinator.applyManualOrbit(drag: value.translation)
                }
                .onEnded { _ in
                    coordinator.endManualOrbit()
                }
        )
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
        var vehicle: Vehicle = .classic
        var root: Entity?
        var car: Entity?
        var camera: PerspectiveCamera?
        var road: Entity?
        var subscription: EventSubscription?
        /// Showroom camera: locked to the front three-quarter stance until
        /// the driver swipes — horizontal drags orbit around, vertical drags
        /// raise or lower the eye. No auto-drift; it stays where you put it.
        private var yaw: Float = -2.6
        private var pitch: Float = 0.28
        private var lastDrag: CGSize?

        func tick(deltaTime: TimeInterval) {
            guard isDriving, let road else { return }
            // Move stripes toward the camera at true speed; recycle.
            let dz = Float(speedMps * deltaTime)
            for stripe in road.children {
                stripe.position.z += dz
                if stripe.position.z > DriveSceneView.stripeRecycleZ {
                    stripe.position.z -= DriveSceneView.roadLength
                }
            }
        }

        func applyManualOrbit(drag: CGSize) {
            let last = lastDrag ?? drag
            lastDrag = drag
            yaw -= Float(drag.width - last.width) * 0.012
            pitch = min(1.25, max(0.08, pitch + Float(drag.height - last.height) * 0.008))
            pointCamera()
        }

        func endManualOrbit() {
            lastDrag = nil
        }

        /// Back to the locked front three-quarter stance (after a drive).
        func resetStance() {
            yaw = -2.6
            pitch = 0.28
        }

        func pointCamera() {
            guard let camera, !isDriving else { return }
            let radius: Float = 6.8
            camera.look(
                at: [0, 0.35, 0],
                from: [
                    sin(yaw) * radius * cos(pitch),
                    sin(pitch) * radius + 0.35,
                    cos(yaw) * radius * cos(pitch),
                ],
                relativeTo: nil
            )
        }
    }

    // MARK: - Camera

    private static func place(camera: PerspectiveCamera, driving: Bool, animated: Bool) {
        var transform = Transform()
        if driving {
            // Chase cam: above and behind, looking down the road.
            transform = Transform(matrix: float4x4.look(at: [0, 0.2, -8], from: [0, 3.2, 6.2]))
        } else {
            // The locked front three-quarter stance (yaw -2.6, pitch 0.28) —
            // must match Coordinator's defaults so the first swipe doesn't jump.
            let yaw: Float = -2.6, pitch: Float = 0.28, radius: Float = 6.8
            transform = Transform(matrix: float4x4.look(
                at: [0, 0.35, 0],
                from: [sin(yaw) * radius * cos(pitch), sin(pitch) * radius + 0.35, cos(yaw) * radius * cos(pitch)]
            ))
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

    /// No gray world — just a soft round shadow so the vehicle doesn't
    /// float. The app background is the sky.
    static func makeGround() -> Entity {
        var shadow = UnlitMaterial(color: UIColor(white: 0, alpha: 0.22))
        shadow.blending = .transparent(opacity: 0.22)
        let disc = ModelEntity(
            mesh: .generateCylinder(height: 0.004, radius: 2.3),
            materials: [shadow]
        )
        disc.position = [0, -0.01, 0]
        return disc
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
