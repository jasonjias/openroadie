import CoreImage
import RealityKit
import SwiftUI

/// A vehicle for the drive scene — Kenney's CC0 kits (kenney.nl), the
/// user's choice from a grouped catalog. `chain` links several copies
/// nose-to-tail (the 3-car light rail); models are normalized to
/// `targetLength` meters.
struct Vehicle: Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let group: String
    var modelName: String?
    var chain: Int = 1
    var targetLength: Float = 3.4

    static let defaultsKey = "driveSceneVehicle"

    /// The built-in primitive car — also the fallback for anything missing.
    static var classic: Vehicle { all[0] }

    static let all: [Vehicle] = [
        Vehicle(id: "classic", title: "Car - Classic", group: "Cars", modelName: nil),
        Vehicle(id: "sportsCar", title: "Car - Sports", group: "Cars", modelName: "vehicle-sports"),
        Vehicle(id: "carTaxi", title: "Car - Taxi", group: "Cars", modelName: "vehicle-car-taxi"),
        Vehicle(id: "carPolice", title: "Car - Police", group: "Cars", modelName: "vehicle-car-police"),
        Vehicle(id: "carFiretruck", title: "Car - Firetruck", group: "Cars", modelName: "vehicle-car-firetruck"),
        Vehicle(id: "carGarbageTruck", title: "Car - Garbage Truck", group: "Cars", modelName: "vehicle-car-garbage-truck"),
        Vehicle(id: "bulldozer", title: "Car - Bulldozer", group: "Cars", modelName: "vehicle-bulldozer"),
        Vehicle(id: "skateboard", title: "Ground - Skateboard", group: "Cars", modelName: "vehicle-skateboard"),
        Vehicle(id: "trainLocomotiveB", title: "Train - Classic Red", group: "Trains", modelName: "vehicle-train-locomotive-b"),
        Vehicle(id: "trainLocomotiveA", title: "Train - Classic Green", group: "Trains", modelName: "vehicle-train-locomotive-a"),
        Vehicle(id: "trainLocomotiveC", title: "Train - Classic Blue", group: "Trains", modelName: "vehicle-train-locomotive-c"),
        Vehicle(id: "lightRail", title: "Train - Light Rail (3-car)", group: "Trains", modelName: "vehicle-train-tram-modern", chain: 3, targetLength: 6.5),
        Vehicle(id: "waterBoatSailA", title: "Boat - Sail", group: "Watercraft", modelName: "vehicle-water-boat-sail-a"),
        Vehicle(id: "waterBoatTugA", title: "Boat - Tug", group: "Watercraft", modelName: "vehicle-water-boat-tug-a"),
        Vehicle(id: "waterBoatHouseA", title: "Boat - House", group: "Watercraft", modelName: "vehicle-water-boat-house-a"),
        Vehicle(id: "pirateShip", title: "Boat - Pirate Ship", group: "Watercraft", modelName: "vehicle-pirate"),
        Vehicle(id: "speeder", title: "Space - Hover Speeder", group: "Spacecraft", modelName: "vehicle-speeder"),
    ]

    /// Groups in display order, derived from the catalog.
    static let groups: [String] = {
        var seen: [String] = []
        for vehicle in all where !seen.contains(vehicle.group) {
            seen.append(vehicle.group)
        }
        return seen
    }()

    /// Pre-rendered picker thumbnail (Tools/render-thumbnails.py).
    var thumbnailName: String {
        "thumb-\(modelName ?? "classic")"
    }

    static func find(_ id: String) -> Vehicle {
        all.first { $0.id == id } ?? classic
    }

    static var current: Vehicle {
        find(UserDefaults.standard.string(forKey: defaultsKey) ?? "")
    }

    var isAvailable: Bool {
        guard let modelName else { return true }
        return Bundle.main.url(forResource: modelName, withExtension: "usda") != nil
    }

    /// Loads the chosen vehicle, chained if asked, scaled and grounded;
    /// primitive car when no model is bundled.
    @MainActor
    func makeEntity() -> Entity {
        guard let modelName,
              let url = Bundle.main.url(forResource: modelName, withExtension: "usda"),
              let single = try? Entity.load(contentsOf: url) else {
            return DriveSceneView.makeCar()
        }
        let model = Entity()
        if chain > 1 {
            // Nose-to-tail copies with a whisker of coupling gap.
            let unitDepth = single.visualBounds(relativeTo: nil).extents.z
            for index in 0..<chain {
                let unit = single.clone(recursive: true)
                unit.position.z = Float(index) * unitDepth * 1.04
                model.addChild(unit)
            }
        } else {
            model.addChild(single)
        }
        // Center the CHILDREN on the entity origin, so the face-down-road
        // rotation below pivots the middle of the train, not its nose.
        let localBounds = model.visualBounds(relativeTo: nil)
        let centerX = (localBounds.min.x + localBounds.max.x) / 2
        let centerZ = (localBounds.min.z + localBounds.max.z) / 2
        for child in model.children {
            child.position.x -= centerX
            child.position.z -= centerZ
        }
        // Normalize: Kenney models vary in native size; scale so the
        // longest side matches the catalog's target length.
        let bounds = model.visualBounds(relativeTo: nil)
        let longest = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
        if longest > 0 {
            model.scale *= SIMD3<Float>(repeating: targetLength / longest)
        }
        let grounded = model.visualBounds(relativeTo: nil)
        model.position.y -= grounded.min.y
        // Face down-road (-z).
        model.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
        return model
    }
}

/// What the vehicle drives on. Standard is a plain asphalt ribbon with
/// dashed yellow center stripes; Rainbow Road is the Tesla-style party
/// mode it started as.
enum RoadStyle: String, CaseIterable, Identifiable {
    case standard
    case night
    case rainbow

    static let defaultsKey = "driveRoadStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Standard"
        case .night: "Night"
        case .rainbow: "Rainbow Road"
        }
    }

    static var current: RoadStyle {
        RoadStyle(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .standard
    }
}

/// Roadside season: which trees line the drive. Christmas swaps the
/// street lamps for lanterns and drops presents under the trees.
enum RoadSeason: String, CaseIterable, Identifiable {
    case off
    case spring
    case summer
    case fall
    case winter
    case christmas

    static let defaultsKey = "driveRoadSeason"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off"
        case .spring: "Spring"
        case .summer: "Summer"
        case .fall: "Fall"
        case .winter: "Winter"
        case .christmas: "Christmas"
        }
    }

    /// Bundled tree models + display heights (meters, toy scale). Seasons
    /// with several variants cycle through them slot by slot — fall gets
    /// the full golden-avenue mix (default, detailed, fat crowns).
    var trees: [(model: String, height: Float)] {
        switch self {
        case .off: []
        case .spring: [("scenery-tree-spring", 1.9)]
        case .summer: [("scenery-tree-summer", 2.6)]
        case .fall: [
            ("scenery-tree-fall-c", 2.2),
            ("scenery-tree-fall", 2.0),
            ("scenery-tree-fall-b", 2.3),
        ]
        case .winter: [("scenery-tree-winter", 2.0)]
        case .christmas: [("scenery-tree-christmas", 2.2)]
        }
    }

    static var current: RoadSeason {
        RoadSeason(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .off
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
    /// Live yaw rate (rad/s) from the gyroscope — polled per frame for
    /// turn lean, so it never churns SwiftUI.
    var yawProvider: (() -> Double)? = nil
    /// The real road's upcoming curve (lateral meters per 4 m step, from
    /// OSM geometry) — the scene's road bends to match. Nil = straight.
    var roadCurve: [Double]? = nil

    /// Bridges live values into the per-frame update closure without
    /// re-subscribing, and retains the scene-update subscription.
    @State private var coordinator = Coordinator()
    @AppStorage(RoadStyle.defaultsKey) private var roadStyleRaw = RoadStyle.standard.rawValue
    @AppStorage(DriveSceneView.lampsKey) private var roadLamps = false
    @AppStorage(RoadSeason.defaultsKey) private var roadSeasonRaw = RoadSeason.off.rawValue

    var body: some View {
        RealityView { content in
            let root = Entity()
            content.add(root)
            coordinator.root = root

            let car = vehicle.makeEntity()
            root.addChild(car)
            coordinator.car = car
            coordinator.carBase = car.orientation
            coordinator.vehicle = vehicle
            coordinator.sizeScale = max(1, vehicle.targetLength / 3.4)

            coordinator.roadStyle = RoadStyle(rawValue: roadStyleRaw) ?? .standard
            coordinator.roadLamps = roadLamps
            coordinator.roadSeason = RoadSeason(rawValue: roadSeasonRaw) ?? .off
            let road = Self.makeRoad(style: coordinator.roadStyle, lamps: roadLamps, season: coordinator.roadSeason)
            // The rainbow reveals itself only once the car has settled into
            // the driving position — the fade lives in Coordinator.tick.
            road.isEnabled = Self.debugRainbowParked
            road.components.set(OpacityComponent(opacity: Self.debugRainbowParked ? 1 : 0))
            root.addChild(road)
            coordinator.road = road
            coordinator.captureRoadParts()

            let ground = Self.makeGround()
            root.addChild(ground)
            coordinator.ground = ground
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
            coordinator.yawProvider = yawProvider
            coordinator.setCurveTarget(isDriving ? roadCurve : nil)
            if coordinator.vehicle != vehicle {
                coordinator.vehicle = vehicle
                coordinator.sizeScale = max(1, vehicle.targetLength / 3.4)
                coordinator.car?.removeFromParent()
                let fresh = vehicle.makeEntity()
                coordinator.root?.addChild(fresh)
                coordinator.car = fresh
                coordinator.carBase = fresh.orientation
            }
            let style = RoadStyle(rawValue: roadStyleRaw) ?? .standard
            let season = RoadSeason(rawValue: roadSeasonRaw) ?? .off
            if coordinator.roadStyle != style || coordinator.roadLamps != roadLamps || coordinator.roadSeason != season {
                coordinator.roadStyle = style
                coordinator.roadLamps = roadLamps
                coordinator.roadSeason = season
                coordinator.replaceRoad(with: Self.makeRoad(style: style, lamps: roadLamps, season: season))
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
        var yawProvider: (() -> Double)?
        /// Smoothed turn signal driving the car's lean and the road's bend.
        private var smoothedYaw: Float = 0
        var root: Entity?
        var car: Entity?
        /// The car's rest orientation, captured when the entity is built.
        /// Kenney models need a π flip to face down-road; the procedural
        /// classic is modeled facing down-road already — hard-coding π
        /// here is what once turned it backwards.
        var carBase = simd_quatf(angle: 0, axis: [0, 1, 0])
        var camera: PerspectiveCamera?
        var road: Entity?
        var ground: Entity?
        /// Curved-road plumbing (#22): the ribbon re-meshes against the
        /// eased curve; props slide sideways to hug the centerline.
        var ribbon: ModelEntity?
        var ribbonWidth: Float = DriveSceneView.ribbonWidth * 1.6
        var propsRoot: Entity?
        var props: [(entity: Entity, base: SIMD3<Float>)] = []
        var curveCurrent = [Float](repeating: 0, count: DriveSceneView.curveSampleCount)
        var curveTarget = [Float](repeating: 0, count: DriveSceneView.curveSampleCount)

        /// New GPS-derived curve (lateral meters per 4 m step) — nil or
        /// short arrays straighten the road.
        func setCurveTarget(_ laterals: [Double]?) {
            let count = DriveSceneView.curveSampleCount
            guard let laterals, laterals.count >= 2 else {
                curveTarget = [Float](repeating: 0, count: count)
                return
            }
            curveTarget = (0..<count).map { index in
                Float(laterals[min(index, laterals.count - 1)])
            }
        }
        var roadStyle: RoadStyle = .standard
        var roadLamps = false
        var roadSeason: RoadSeason = .off
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
        /// Long vehicles (the 3-car light rail) push the camera back
        /// proportionally so they stay framed.
        var sizeScale: Float = 1
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
        /// Showroom drags also drift home after a beat of stillness.
        private var parkedReturnAt: Date = .distantPast

        func applyPose(driving: Bool) {
            pose = driving ? .driving : .parked
            transitionFrom = nil
            applyCamera()
        }

        /// Swap the road entity in place (style change from Settings),
        /// carrying over the current fade so it doesn't blink.
        func replaceRoad(with fresh: Entity) {
            guard let old = road else { return }
            fresh.isEnabled = old.isEnabled
            fresh.components.set(OpacityComponent(opacity: roadFade))
            fresh.position = old.position
            fresh.orientation = old.orientation
            old.removeFromParent()
            root?.addChild(fresh)
            road = fresh
            captureRoadParts()
        }

        /// Cache the ribbon + prop references and each prop's laid-out
        /// position, so per-frame curve updates never search the tree.
        func captureRoadParts() {
            ribbon = road?.findEntity(named: "ribbon") as? ModelEntity
            ribbonWidth = {
                guard let bounds = ribbon?.model?.mesh.bounds else { return DriveSceneView.ribbonWidth * 1.6 }
                return bounds.max.x - bounds.min.x
            }()
            propsRoot = road?.findEntity(named: "props")
            props = propsRoot?.children.map { ($0, $0.position) } ?? []
            curveCurrent = [Float](repeating: 0, count: DriveSceneView.curveSampleCount)
            curveTarget = curveCurrent
        }

        /// Lateral offset of the road centerline at scene depth z,
        /// interpolated from the eased curve samples.
        private func lateral(atZ z: Float) -> Float {
            let position = (DriveSceneView.stripeRecycleZ - z) / DriveSceneView.curveStep
            let lower = Int(position.rounded(.down))
            guard lower >= 0 else { return curveCurrent.first ?? 0 }
            guard lower < curveCurrent.count - 1 else { return curveCurrent.last ?? 0 }
            let t = position - Float(lower)
            return curveCurrent[lower] * (1 - t) + curveCurrent[lower + 1] * t
        }

        func beginTransition(driving: Bool) {
            transitionFrom = pose
            transitionTo = driving ? .driving : .parked
            transitionStart = .now
            chaseYaw = 0
            chasePitch = 0
            // Straighten out: no leftover turn lean in the showroom, and
            // the road resets straight for the next drive (it's hidden
            // while parked, so the snap is invisible).
            smoothedYaw = 0
            car?.orientation = carBase
            road?.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            if !driving {
                curveTarget = [Float](repeating: 0, count: DriveSceneView.curveSampleCount)
                curveCurrent = curveTarget
                if let ribbon,
                   let mesh = DriveSceneView.curvedRibbonMesh(width: ribbonWidth, laterals: curveCurrent) {
                    ribbon.model?.mesh = mesh
                }
                for (prop, base) in props {
                    prop.position = base
                }
            }
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
                    // The showroom's soft shadow disc yields to the road —
                    // left on, it alpha-sorts over the asphalt as a pale
                    // ring that makes the car look like it's hovering.
                    ground?.components.set(OpacityComponent(opacity: 1 - roadFade))
                }
            }

            // Parked: after ~1.5s without touches, ease the showroom stance
            // back to the default front three-quarter — same manner as the
            // driving look-around's return.
            if !isDriving, transitionFrom == nil, Date.now > parkedReturnAt {
                let home = Pose.parked
                if abs(pose.yaw - home.yaw) > 0.002 || abs(pose.pitch - home.pitch) > 0.002 {
                    let k = Float(1 - exp(-4 * deltaTime))
                    pose.yaw += (home.yaw - pose.yaw) * k
                    pose.pitch += (home.pitch - pose.pitch) * k
                    applyCamera()
                }
            }

            guard isDriving, road != nil else { return }
            // Slide the road toward the camera at true speed. The ribbon
            // scrolls in TEXTURE space (so its curve stays anchored to the
            // car); the physical props scroll and recycle by one period.
            phase = (phase + Float(speedMps * deltaTime))
                .truncatingRemainder(dividingBy: DriveSceneView.rainbowPeriod)
            propsRoot?.position.z = phase
            if let ribbon, var model = ribbon.model,
               var material = model.materials.first as? UnlitMaterial {
                material.textureCoordinateTransform.offset = SIMD2(0, phase / DriveSceneView.rainbowPeriod)
                model.materials = [material]
                ribbon.model = model
            }

            // #22: bend the road to the real one. Ease toward the latest
            // GPS-derived curve, re-mesh the ribbon, and slide every prop
            // sideways to hug the new centerline.
            let maxDelta = zip(curveCurrent, curveTarget).map { abs($0 - $1) }.max() ?? 0
            if maxDelta > 0.01 {
                let k = Float(1 - exp(-2.5 * deltaTime))
                for index in curveCurrent.indices {
                    curveCurrent[index] += (curveTarget[index] - curveCurrent[index]) * k
                }
                if let ribbon,
                   let mesh = DriveSceneView.curvedRibbonMesh(width: ribbonWidth, laterals: curveCurrent) {
                    ribbon.model?.mesh = mesh
                }
                for (prop, base) in props {
                    prop.position.x = base.x + lateral(atZ: base.z + phase)
                }
            } else if !props.isEmpty, speedMps > 0.1 {
                // Curve steady but the props still stream past — keep them
                // pinned to the centerline at their moving positions.
                for (prop, base) in props {
                    prop.position.x = base.x + lateral(atZ: base.z + phase)
                }
            }

            // Turn lean (#22 v1): the gyroscope's yaw rate banks the car
            // into real turns and swings the road toward them — the scene
            // visibly steers with the actual vehicle.
            let rawYaw = Float(yawProvider?() ?? 0)
            smoothedYaw += (rawYaw - smoothedYaw) * Float(min(1, deltaTime * 6))
            // The car banks into real turns; the road itself stays put —
            // yawing a visibly straight ribbon read as broken, not as
            // steering (field feedback).
            if let car {
                let lean = max(-0.22, min(0.22, -smoothedYaw * 0.5))
                car.orientation = carBase * simd_quatf(angle: lean, axis: [0, 0, 1])
            }

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
                parkedReturnAt = .distantFuture
            }
            applyCamera()
        }

        func endManualOrbit() {
            lastDrag = nil
            if isDriving {
                chaseReturnAt = .now.addingTimeInterval(1.3)
            } else {
                parkedReturnAt = .now.addingTimeInterval(1.5)
            }
        }

        /// One camera formula for every state: pose plus (while driving)
        /// the look-around offsets, which pull the gaze back to the car.
        private func applyCamera() {
            guard let camera else { return }
            let yaw = pose.yaw + chaseYaw
            let pitch = min(1.45, max(0.05, pose.pitch + chasePitch))
            let radius = pose.radius * sizeScale
            let from: SIMD3<Float> = [
                sin(yaw) * radius * cos(pitch),
                sin(pitch) * radius + 0.35,
                cos(yaw) * radius * cos(pitch),
            ]
            // Any deliberate drag pins the gaze to the CAR — the vehicle is
            // the center point of the orbit, top/down/left/right. The tight
            // ramp (0.12 rad) means the pin engages almost immediately
            // without a hard jump.
            let offset = min(1, (abs(chaseYaw) + abs(chasePitch)) / 0.12)
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

    /// Road-curve sampling (#22): lateral offsets every `curveStep` meters,
    /// covering the full ribbon from z = stripeRecycleZ (behind the car)
    /// to the far end. Must agree with RoadMatcher.upcomingCurve's defaults
    /// (4 m steps, 8 m behind, 68 m ahead).
    static let curveStep: Float = 4
    static var curveSampleCount: Int {
        Int(((roadLength + rainbowPeriod) / curveStep).rounded()) + 1
    }

    /// A ribbon following the given centerline laterals: two vertices per
    /// sample row, straight edges between rows. UVs run 0…1 along the
    /// full depth so the material's (1, tiles) scale keeps the exact
    /// texture repeat the flat plane had.
    static func curvedRibbonMesh(width: Float, laterals: [Float]) -> MeshResource? {
        guard laterals.count >= 2 else { return nil }
        let depth = roadLength + rainbowPeriod
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        for (index, lateral) in laterals.enumerated() {
            let z = stripeRecycleZ - Float(index) * curveStep
            positions.append([lateral - width / 2, 0, z])
            positions.append([lateral + width / 2, 0, z])
            let v = Float(index) * curveStep / depth
            uvs.append([0, v])
            uvs.append([1, v])
            normals.append([0, 1, 0])
            normals.append([0, 1, 0])
        }
        var indices: [UInt32] = []
        for row in 0..<(laterals.count - 1) {
            let a = UInt32(row * 2), b = a + 1, c = a + 2, d = a + 3
            indices += [a, b, c, b, d, c]
        }
        var descriptor = MeshDescriptor(name: "ribbon")
        descriptor.positions = MeshBuffer(positions)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [descriptor])
    }

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

    /// One flat scrolling ribbon; the texture and finish come from the
    /// chosen style. Rainbow keeps the field-approved heavy Gaussian halo
    /// (soft watercolor bands bleeding wide past the vehicle); the asphalt
    /// styles render crisp — a road, not a glow.
    static func makeRoad(style: RoadStyle = .current, lamps: Bool = roadLampsEnabled, season: RoadSeason = .current) -> Entity {
        let road = Entity()
        let depth = roadLength + rainbowPeriod // slack so the wrap never shows
        let tiles = depth / rainbowPeriod

        let image: CGImage?
        let alpha: Float
        switch style {
        case .rainbow:
            image = rainbowBandImage().flatMap { blurred($0, radius: 34) }
            alpha = 0.42
        case .standard:
            image = asphaltImage(dark: false)
            alpha = 1
        case .night:
            image = asphaltImage(dark: true)
            alpha = 1
        }

        if let image,
           let texture = try? TextureResource(image: image, options: .init(semantic: .color)) {
            var material = UnlitMaterial()
            material.color = .init(tint: UIColor(white: 1, alpha: CGFloat(alpha)), texture: .init(texture))
            material.blending = .transparent(opacity: .init(floatLiteral: alpha))
            material.textureCoordinateTransform.scale = SIMD2(1, tiles)
            // Asphalt styles carry a sidewalk on each side for the lamps;
            // the rainbow stays a bare ribbon.
            let meshWidth = style == .rainbow ? ribbonWidth * 1.6 : ribbonWidth * 1.6 + sidewalkWidth * 2
            // Starts straight; the Coordinator re-meshes it against the
            // real road's curve while driving (#22). The geometry carries
            // its own z placement, and scrolling is done in TEXTURE space
            // so the curve stays anchored to the car.
            let mesh = curvedRibbonMesh(width: meshWidth, laterals: [Float](repeating: 0, count: curveSampleCount))
                ?? .generatePlane(width: meshWidth, depth: depth)
            let ribbon = ModelEntity(mesh: mesh, materials: [material])
            ribbon.name = "ribbon"
            ribbon.position = [0, 0.012, 0]
            road.addChild(ribbon)
        }

        // Everything that physically streams past (lamps, trees, presents)
        // lives under one scrolling root; the ribbon itself stays put.
        let props = Entity()
        props.name = "props"
        road.addChild(props)

        // Everything roadside repeats once per texture period, so the
        // scroll wrap (which jumps the road back by exactly one period)
        // lands every prop where its predecessor stood — the procession
        // never visibly resets.
        let count = Int(depth / rainbowPeriod)
        let laneEdge = ribbonWidth * 0.8

        if lamps {
            // Both sidewalks, alternating: right lamp on the period mark,
            // left lamp half a period later.
            for index in 0..<count {
                let baseZ = stripeRecycleZ - Float(index) * rainbowPeriod
                for (side, offset) in [(Float(1), Float(0)), (-1, -rainbowPeriod / 2)] {
                    let lamp = makeStreetLamp(lit: style == .night, christmas: season == .christmas, side: side)
                    lamp.position = [0, 0, baseZ + offset]
                    props.addChild(lamp)
                }
            }
        }

        let trees = season.trees
        if !trees.isEmpty, season == .spring || season == .fall {
            // Full forest: five checkerboarded columns deep on BOTH
            // shoulders, four trees per period per column. One template
            // entity, cloned per slot: loading from disk 200 times would
            // stall the scene.
            let columns = 5
            let tree = trees[0]
            if let template = loadScenery(tree.model, height: tree.height) {
                for index in 0..<count {
                    let baseZ = stripeRecycleZ - Float(index) * rainbowPeriod
                    for row in 0..<4 {
                        for column in 0..<columns {
                            for side in [Float(-1), 1] {
                                let entity = template.clone(recursive: true)
                                entity.position = [
                                    side * (laneEdge + 1.7 + Float(column) * 1.6),
                                    0,
                                    baseZ - Float(row) * rainbowPeriod / 4 - 1.5
                                        - Float(column % 2) * rainbowPeriod / 8,
                                ]
                                entity.orientation = simd_quatf(
                                    angle: Float(index * 4 + row + column * 7) * 1.7 + side,
                                    axis: [0, 1, 0]
                                )
                                props.addChild(entity)
                            }
                        }
                    }
                }
            }
        } else if !trees.isEmpty {
            for index in 0..<count {
                let baseZ = stripeRecycleZ - Float(index) * rainbowPeriod
                // Staggered pairs: one on each shoulder per period, offset
                // half a period so the drive alternates left-right.
                for (slot, (side, offset)) in [(Float(-1), Float(-3.5)), (1, -11.3)].enumerated() {
                    let tree = trees[(index * 2 + slot) % trees.count]
                    guard let entity = loadScenery(tree.model, height: tree.height) else { continue }
                    entity.position = [side * (laneEdge + 1.7), 0, baseZ + offset]
                    // A touch of yaw variety, deterministic per slot.
                    entity.orientation = simd_quatf(angle: Float(index) * 1.7 + side, axis: [0, 1, 0])
                    props.addChild(entity)

                    if season == .christmas {
                        let names = ["scenery-present-a", "scenery-present-b"]
                        if let present = loadScenery(names[(index + (side > 0 ? 1 : 0)) % 2], height: 0.42) {
                            // Beside the trunk, fully on the grass — well
                            // clear of the sidewalk.
                            present.position = entity.position + [side * -0.15, 0, 0.55]
                            present.orientation = simd_quatf(angle: Float(index) * 2.3, axis: [0, 1, 0])
                            props.addChild(present)
                        }
                    }
                }
            }
        }
        return road
    }

    /// Loads a bundled scenery model, scaled to the given height, centered
    /// on its footprint, feet on the ground.
    static func loadScenery(_ name: String, height: Float) -> Entity? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "usda"),
              let model = try? Entity.load(contentsOf: url) else { return nil }
        let wrap = Entity()
        wrap.addChild(model)
        let bounds = wrap.visualBounds(relativeTo: nil)
        if bounds.extents.y > 0 {
            model.scale *= SIMD3(repeating: height / bounds.extents.y)
        }
        let scaled = wrap.visualBounds(relativeTo: nil)
        model.position.x -= (scaled.min.x + scaled.max.x) / 2
        model.position.z -= (scaled.min.z + scaled.max.z) / 2
        model.position.y -= scaled.min.y
        return wrap
    }

    static let lampsKey = "driveRoadLamps"

    static var roadLampsEnabled: Bool {
        UserDefaults.standard.bool(forKey: lampsKey)
    }

    /// A street lamp standing on the sidewalk: Kenney's curved city light
    /// (arm rotated to reach over the lane), or the holiday lantern at
    /// Christmas. `side` is +1 for the right sidewalk, -1 for the left
    /// (mirrored so the arm always reaches toward the road). At night
    /// both throw a warm pool onto the asphalt. Falls back to the
    /// procedural cobra-head if the model won't load.
    static func makeStreetLamp(lit: Bool, christmas: Bool = false, side: Float = 1) -> Entity {
        let poleX: Float = ribbonWidth * 0.8 + sidewalkWidth / 2
        let model = christmas
            ? loadScenery("scenery-lantern", height: 1.5)
            : loadScenery("scenery-lamp-curved", height: 2.9)
        guard let model else { return makeProceduralLamp(lit: lit) }

        let lamp = Entity()
        // loadScenery centers the FOOTPRINT — pole plus arm — so the pole
        // itself sits half the arm's reach off-center. Compensate so the
        // pole base stands mid-sidewalk instead of straddling its edge.
        let poleOffset: Float = christmas ? 0 : 0.36
        model.position = [side * (poleX - poleOffset), 0, 0]
        if !christmas {
            // The city lamp's arm points -z natively; swing it over the
            // road — mirrored on the left sidewalk.
            model.orientation = simd_quatf(angle: side * .pi / 2, axis: [0, 1, 0])
        }
        lamp.addChild(model)
        if lit {
            var glow = UnlitMaterial(color: UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 0.16))
            glow.blending = .transparent(opacity: 0.16)
            let pool = ModelEntity(mesh: .generatePlane(width: 2.4, depth: 3.2, cornerRadius: 1.2), materials: [glow])
            pool.position = [side * (poleX - (christmas ? 0.4 : 1.0)), 0.02, 0]
            lamp.addChild(pool)
        }
        return lamp
    }

    /// A tall highway lamp: straight pole, single arm curving over the
    /// road (three progressively tilted segments fake the bend), cobra
    /// luminaire at the tip. Lit warm at night, off by day.
    static func makeProceduralLamp(lit: Bool) -> Entity {
        let lamp = Entity()
        let steel = SimpleMaterial(color: UIColor(white: 0.45, alpha: 1), roughness: 0.6, isMetallic: true)

        // Chunky proportions on purpose: the chase camera looks down from
        // ~60°, which forecloses thin vertical geometry to nearly nothing.
        let poleX: Float = ribbonWidth * 0.8 + 0.55
        let poleHeight: Float = 2.8
        let pole = ModelEntity(mesh: .generateCylinder(height: poleHeight, radius: 0.09), materials: [steel])
        pole.position = [poleX, poleHeight / 2, 0]
        lamp.addChild(pole)

        // The curve: short segments rotating from vertical toward
        // horizontal, each starting where the last ended.
        var cursor: SIMD3<Float> = [poleX, poleHeight, 0]
        let bendAngles: [Float] = [.pi * 0.12, .pi * 0.30, .pi * 0.44]
        for angle in bendAngles {
            let length: Float = 0.62
            let segment = ModelEntity(mesh: .generateCylinder(height: length, radius: 0.07), materials: [steel])
            // Tilt the segment toward the road (-x) around z.
            segment.orientation = simd_quatf(angle: angle, axis: [0, 0, 1])
            let step: SIMD3<Float> = [-sin(angle) * length, cos(angle) * length, 0]
            segment.position = cursor + step / 2
            cursor += step
            lamp.addChild(segment)
        }

        let headMaterial: RealityKit.Material = lit
            ? UnlitMaterial(color: UIColor(red: 1.0, green: 0.87, blue: 0.55, alpha: 1))
            : SimpleMaterial(color: UIColor(white: 0.28, alpha: 1), roughness: 0.5, isMetallic: false)
        let head = ModelEntity(mesh: .generateBox(size: [0.62, 0.13, 0.26], cornerRadius: 0.06), materials: [headMaterial])
        head.position = cursor + [-0.26, 0, 0]
        lamp.addChild(head)

        if lit {
            // A soft pool of light on the asphalt under the head.
            var glow = UnlitMaterial(color: UIColor(red: 1.0, green: 0.85, blue: 0.5, alpha: 0.16))
            glow.blending = .transparent(opacity: 0.16)
            let pool = ModelEntity(mesh: .generatePlane(width: 2.4, depth: 3.2, cornerRadius: 1.2), materials: [glow])
            pool.position = [cursor.x - 0.18, 0.02, 0]
            lamp.addChild(pool)
        }
        return lamp
    }

    /// Sidewalk width (meters, each side) on the asphalt road styles.
    static let sidewalkWidth: Float = 0.9

    /// A normal street: sidewalk, asphalt with dashed yellow center
    /// stripes and solid white edge lines, sidewalk. One texture tile
    /// spans one rainbowPeriod (15.6 m) of road, so each tile carries
    /// two dash cycles (~4.5 m paint, ~3.3 m gap).
    static func asphaltImage(dark: Bool, width: Int = 96, size: Int = 512) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: width, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let w = CGFloat(width)
        let h = CGFloat(size)
        // Horizontal layout must match the mesh: sidewalkWidth on each
        // side of a ribbonWidth*1.6 roadway.
        let roadFraction = CGFloat(ribbonWidth * 1.6 / (ribbonWidth * 1.6 + sidewalkWidth * 2))
        let roadStart = (1 - roadFraction) / 2

        // Sidewalks (full width first, road painted over the middle).
        context.setFillColor(UIColor(white: dark ? 0.24 : 0.62, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        context.setFillColor(UIColor(white: dark ? 0.13 : 0.42, alpha: 1).cgColor)
        context.fill(CGRect(x: w * roadStart, y: 0, width: w * roadFraction, height: h))

        context.setFillColor(UIColor(white: 0.92, alpha: 1).cgColor)
        for x in [roadStart + 0.008, 1 - roadStart - 0.022] {
            context.fill(CGRect(x: w * x, y: 0, width: w * 0.014, height: h))
        }

        context.setFillColor(UIColor(red: 0.99, green: 0.80, blue: 0.20, alpha: 1).cgColor)
        for y in [0.04, 0.54] {
            context.fill(CGRect(x: w * 0.488, y: h * y, width: w * 0.024, height: h * 0.196))
        }
        return context.makeImage()
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
