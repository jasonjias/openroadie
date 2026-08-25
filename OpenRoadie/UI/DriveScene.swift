import CoreImage
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
            // The rainbow reveals itself only once the car has settled into
            // the driving position — the fade lives in Coordinator.tick.
            road.isEnabled = Self.debugRainbowParked
            road.components.set(OpacityComponent(opacity: Self.debugRainbowParked ? 1 : 0))
            root.addChild(road)
            coordinator.road = road

            root.addChild(Self.makeGround())
            root.addChild(Self.makeLights())

            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 55
            root.addChild(camera)
            coordinator.camera = camera
            coordinator.applyPose(driving: isDriving)

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
                coordinator.beginTransition(driving: isDriving)
            }
        }
        // Tesla-style: drag on the vehicle to orbit — but only the upper
        // region. The bottom strip stays gesture-free so swiping there
        // pages between odometer faces instead of spinning the car.
        .overlay {
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .frame(height: geo.size.height * 0.72)
                    .gesture(
                        DragGesture(minimumDistance: 2)
                            .onChanged { value in
                                coordinator.applyManualOrbit(drag: value.translation)
                            }
                            .onEnded { _ in
                                coordinator.endManualOrbit()
                            }
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
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
        var vehicle: Vehicle = .classic
        var root: Entity?
        var car: Entity?
        var camera: PerspectiveCamera?
        var road: Entity?
        var subscription: EventSubscription?
        /// The camera lives on a sphere around the car (yaw, pitch, fixed
        /// radius) looking at a target that slides from the car (parked) to
        /// the road ahead (driving). Transitions animate these PARAMETERS —
        /// the camera orbits around the vehicle and never loses it, unlike
        /// a raw transform lerp (which swung wide and off-screen).
        struct Pose {
            var yaw: Float
            var pitch: Float
            var radius: Float
            var targetY: Float
            var targetZ: Float

            static let parked = Pose(yaw: -2.6, pitch: 0.28, radius: 6.8, targetY: 0.35, targetZ: 0)
            /// Driving: mostly top-down (~76°), zoomed out, gaze just ahead
            /// of the car so it settles low in frame — the toy-street-map
            /// view. The transition reads as: spin the car to face forward
            /// in place, then set it down on the map.
            static let driving = Pose(yaw: 0, pitch: 1.047, radius: 8.4, targetY: 0.2, targetZ: -2.2) // ~60°

            static func mix(_ a: Pose, _ b: Pose, _ t: Float) -> Pose {
                Pose(
                    yaw: a.yaw + (b.yaw - a.yaw) * t,
                    pitch: a.pitch + (b.pitch - a.pitch) * t,
                    radius: a.radius + (b.radius - a.radius) * t,
                    targetY: a.targetY + (b.targetY - a.targetY) * t,
                    targetZ: a.targetZ + (b.targetZ - a.targetZ) * t
                )
            }
        }
        private var pose = Pose.parked
        private var transitionFrom: Pose?
        private var transitionTo = Pose.parked
        private var transitionStart = Date.distantPast
        private let transitionDuration: TimeInterval = 1.05
        private var lastDrag: CGSize?

        /// Ribbon scroll position, meters into the current rainbow cycle.
        private var phase: Float = 0
        /// Rainbow reveal: 0…1, eased toward its target each frame.
        private var roadFade: Float = 0
        /// Drive-mode look-around: temporary camera offsets that ease back
        /// to the chase position ~1.3s after the finger lifts.
        private var chaseYaw: Float = 0
        private var chasePitch: Float = 0
        private var chaseReturnAt: Date = .distantPast

        func applyPose(driving: Bool) {
            pose = driving ? .driving : .parked
            transitionFrom = nil
            applyCamera()
        }

        func beginTransition(driving: Bool) {
            transitionFrom = pose
            transitionTo = driving ? .driving : .parked
            transitionStart = .now
            chaseYaw = 0
            chasePitch = 0
        }

        func tick(deltaTime: TimeInterval) {
            // Camera transition: orbit smoothly between stances.
            if let from = transitionFrom {
                let raw = Float(Date.now.timeIntervalSince(transitionStart) / transitionDuration)
                let t = min(1, max(0, raw))
                // One continuous ease for every parameter — the earlier
                // two-phase gaze choreography put a visible kink mid-move.
                let eased = t * t * (3 - 2 * t) // smoothstep
                pose = Pose.mix(from, transitionTo, eased)
                if t >= 1 { transitionFrom = nil }
                applyCamera()
            }

            // The rainbow appears gently only AFTER the car settles into
            // the driving position, and slips away the moment a stop
            // begins — the kid lifts the car off a bare floor.
            if let road {
                let wantRoad = (isDriving && transitionFrom == nil) || DriveSceneView.debugRainbowParked
                let target: Float = wantRoad ? 1 : 0
                if roadFade != target {
                    let rate = Float(deltaTime) / (wantRoad ? 0.8 : 0.35)
                    roadFade = wantRoad ? min(1, roadFade + rate) : max(0, roadFade - rate)
                    road.isEnabled = roadFade > 0.001
                    road.components.set(OpacityComponent(opacity: roadFade))
                }
            }

            guard isDriving, let road else { return }
            // Slide the textured ribbon toward the camera at true speed;
            // wrapping by one texture period is invisible.
            phase = (phase + Float(speedMps * deltaTime))
                .truncatingRemainder(dividingBy: DriveSceneView.rainbowPeriod)
            road.position.z = phase

            if chaseYaw != 0 || chasePitch != 0 {
                if Date.now > chaseReturnAt {
                    let decay = Float(exp(-4 * deltaTime))
                    chaseYaw *= decay
                    chasePitch *= decay
                    if abs(chaseYaw) < 0.004, abs(chasePitch) < 0.004 {
                        chaseYaw = 0
                        chasePitch = 0
                    }
                }
                applyCamera()
            }
        }

        func applyManualOrbit(drag: CGSize) {
            let last = lastDrag ?? drag
            lastDrag = drag
            let dx = Float(drag.width - last.width)
            let dy = Float(drag.height - last.height)
            if isDriving {
                chaseYaw = min(1.2, max(-1.2, chaseYaw - dx * 0.008))
                chasePitch = min(0.55, max(-0.12, chasePitch + dy * 0.006))
                chaseReturnAt = .distantFuture
            } else {
                pose.yaw -= dx * 0.012
                pose.pitch = min(1.25, max(0.08, pose.pitch + dy * 0.008))
            }
            applyCamera()
        }

        func endManualOrbit() {
            lastDrag = nil
            if isDriving {
                chaseReturnAt = .now.addingTimeInterval(1.3)
            }
        }

        /// One camera formula for every state: pose plus (while driving)
        /// the look-around offsets, which pull the gaze back to the car.
        private func applyCamera() {
            guard let camera else { return }
            let yaw = pose.yaw + chaseYaw
            let pitch = min(1.45, max(0.05, pose.pitch + chasePitch))
            let radius = pose.radius
            let from: SIMD3<Float> = [
                sin(yaw) * radius * cos(pitch),
                sin(pitch) * radius + 0.35,
                cos(yaw) * radius * cos(pitch),
            ]
            let offset = min(1, (abs(chaseYaw) + abs(chasePitch)) / 0.5)
            let at: SIMD3<Float> = [0, pose.targetY + 0.15 * offset, pose.targetZ * (1 - offset)]
            camera.look(at: at, from: from, relativeTo: nil)
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

    /// One rainbow cycle along the road: six car-half-length bands.
    static let rainbowPeriod: Float = 15.6
    /// Ribbon width — a lane's worth; the vehicle overlaps its edges and
    /// the halo bleeds past them, like the reference shots.
    static let ribbonWidth: Float = 2.2

    /// Hidden defaults flag so the rainbow can be inspected while parked
    /// (design iteration without a test drive). No UI on purpose.
    static var debugRainbowParked: Bool {
        UserDefaults.standard.bool(forKey: "debugRainbowParked")
    }

    /// The rainbow, field-approved: a single flat ribbon carrying a
    /// Gaussian-blurred copy of the band texture — soft watercolor bands
    /// bleeding wide past the vehicle. (An earlier build layered sharp
    /// bands on top; the blur alone looked better and won.)
    static func makeRoad() -> Entity {
        let road = Entity()
        let depth = roadLength + rainbowPeriod // slack so the wrap never shows
        let tiles = depth / rainbowPeriod

        if let sharp = rainbowBandImage(),
           let haloImage = blurred(sharp, radius: 34),
           let haloTexture = try? TextureResource(image: haloImage, options: .init(semantic: .color)) {
            var halo = UnlitMaterial()
            halo.color = .init(tint: UIColor(white: 1, alpha: 0.42), texture: .init(haloTexture))
            halo.blending = .transparent(opacity: 0.42)
            halo.textureCoordinateTransform.scale = SIMD2(1, tiles)
            let ribbon = ModelEntity(mesh: .generatePlane(width: ribbonWidth * 1.6, depth: depth), materials: [halo])
            ribbon.position = [0, 0.012, stripeRecycleZ - depth / 2]
            road.addChild(ribbon)
        }
        return road
    }

    /// The band texture: six vivid rectangles, solid centers, a soft ~30%
    /// transition at each seam — blurred edges, not blended hues. Wraps
    /// purple back to red so tiling is seamless.
    static func rainbowBandImage(size: Int = 512) -> CGImage? {
        let bands: [UIColor] = [
            UIColor(red: 0.96, green: 0.22, blue: 0.21, alpha: 1),
            UIColor(red: 1.00, green: 0.58, blue: 0.10, alpha: 1),
            UIColor(red: 1.00, green: 0.90, blue: 0.16, alpha: 1),
            UIColor(red: 0.28, green: 0.83, blue: 0.35, alpha: 1),
            UIColor(red: 0.20, green: 0.55, blue: 0.97, alpha: 1),
            UIColor(red: 0.63, green: 0.32, blue: 0.90, alpha: 1),
        ]
        // CGGradient requires locations in [0, 1] — it silently returns nil
        // otherwise. The purple→red wrap is handled with an explicit
        // half-blend color at both ends, so the tile seam is seamless.
        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        bands[0].getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        bands[bands.count - 1].getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        let seam = UIColor(red: (fr + lr) / 2, green: (fg + lg) / 2, blue: (fb + lb) / 2, alpha: 1)
        var colors: [CGColor] = [seam.cgColor]
        var locations: [CGFloat] = [0]
        let n = CGFloat(bands.count)
        for (i, band) in bands.enumerated() {
            let start = CGFloat(i) / n
            colors.append(band.cgColor)
            locations.append(start + 0.15 / n)
            colors.append(band.cgColor)
            locations.append(start + 0.85 / n)
        }
        colors.append(seam.cgColor)
        locations.append(1)

        guard let context = CGContext(
            data: nil, width: 8, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray, locations: locations
        ) else { return nil }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: size),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        return context.makeImage()
    }

    /// Gaussian blur for the halo layer, at texture-generation time.
    static func blurred(_ image: CGImage, radius: Double) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: input.extent)
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
