import Foundation
import HealthKit

/// Read-only window into HealthKit: the workouts and sleep the watch (or
/// any app) already recorded. Nothing is written, nothing leaves the
/// device; days without permission simply contribute no cards.
@MainActor
final class HealthSessions {
    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Ask once for read access to workouts + sleep. HealthKit never tells
    /// an app whether READ was granted (that itself would leak health
    /// info), so this returns whether the prompt flow completed — queries
    /// just come back empty when the user said no.
    func requestAccess() async {
        guard isAvailable else { return }
        let types: Set<HKObjectType> = [
            .workoutType(),
            HKSeriesType.workoutRoute(),
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]
        try? await store.requestAuthorization(toShare: [], read: types)
    }

    struct Workout: Equatable, Sendable {
        var uuid: UUID
        var start: Date
        var end: Date
        var activity: UInt   // HKWorkoutActivityType rawValue
        var kilocalories: Double?
        var meters: Double?
    }

    func workouts(from: Date, to: Date) async -> [Workout] {
        guard isAvailable else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: from, end: to))],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 200
        )
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { workout in
            Workout(
                uuid: workout.uuid,
                start: workout.startDate,
                end: workout.endDate,
                activity: workout.workoutActivityType.rawValue,
                kilocalories: workout.statistics(for: .init(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie()),
                meters: workout.statistics(for: .init(.distanceWalkingRunning))?
                    .sumQuantity()?.doubleValue(for: .meter())
            )
        }
    }

    /// The GPS trail the watch recorded with an outdoor workout, thinned
    /// for drawing. Empty when the workout has no route (indoor, or route
    /// access not granted).
    func route(forWorkoutWith uuid: UUID) async -> [Coordinate] {
        guard isAvailable else { return [] }
        // The workout itself, by identity.
        let workoutDescriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: uuid))],
            sortDescriptors: [], limit: 1
        )
        guard let workout = try? await workoutDescriptor.result(for: store).first else { return [] }
        // Its route sample(s)…
        let routeDescriptor = HKSampleQueryDescriptor(
            predicates: [.sample(
                type: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout)
            )],
            sortDescriptors: [], limit: HKObjectQueryNoLimit
        )
        guard let samples = try? await routeDescriptor.result(for: store) else { return [] }
        let routes = samples.compactMap { $0 as? HKWorkoutRoute }
        guard !routes.isEmpty else { return [] }
        // …streamed out as locations. The callback arrives repeatedly on
        // HealthKit's queue: accumulate in a locked box, resume once done.
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var coordinates: [Coordinate] = []
        }
        let box = Box()
        for routeSample in routes {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let query = HKWorkoutRouteQuery(route: routeSample) { @Sendable _, locations, done, _ in
                    if let locations {
                        box.lock.lock()
                        box.coordinates += locations.map {
                            Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
                        }
                        box.lock.unlock()
                    }
                    if done {
                        continuation.resume()
                    }
                }
                store.execute(query)
            }
        }
        return Self.thin(box.coordinates, to: 300)
    }

    /// Every Nth point plus the last — a watch walk records at 1 Hz and a
    /// map needs nothing like that. Pure and unit-tested.
    nonisolated static func thin(_ route: [Coordinate], to maximum: Int) -> [Coordinate] {
        guard route.count > maximum, maximum >= 2 else { return route }
        let stride = Double(route.count - 1) / Double(maximum - 1)
        return (0..<maximum).map { route[Int((Double($0) * stride).rounded())] }
    }

    struct SleepNight: Equatable, Sendable {
        var start: Date
        var end: Date
        /// Actual asleep time (the samples), not just the span.
        var asleepSeconds: TimeInterval
    }

    /// Asleep samples coalesced into nights: gaps under an hour merge
    /// (a 3 AM bathroom trip is the same night), spans under an hour drop.
    func sleepNights(from: Date, to: Date) async -> [SleepNight] {
        guard isAvailable,
              let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(
                type: HKCategoryType(.sleepAnalysis),
                predicate: HKQuery.predicateForSamples(withStart: from, end: to)
            )],
            sortDescriptors: [SortDescriptor(\.startDate)],
            limit: HKObjectQueryNoLimit
        )
        _ = sleepType
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        let intervals = samples
            .filter { asleepValues.contains($0.value) }
            .map { (start: $0.startDate, end: $0.endDate) }
        return Self.nights(from: intervals)
    }

    /// Pure coalescing, unit-tested.
    nonisolated static func nights(
        from intervals: [(start: Date, end: Date)],
        mergeGap: TimeInterval = 3_600,
        minimumSpan: TimeInterval = 3_600
    ) -> [SleepNight] {
        let ordered = intervals.sorted { $0.start < $1.start }
        var nights: [SleepNight] = []
        for interval in ordered {
            let seconds = interval.end.timeIntervalSince(interval.start)
            if var last = nights.last, interval.start.timeIntervalSince(last.end) < mergeGap {
                last.end = max(last.end, interval.end)
                last.asleepSeconds += seconds
                nights[nights.count - 1] = last
            } else {
                nights.append(SleepNight(start: interval.start, end: interval.end, asleepSeconds: seconds))
            }
        }
        return nights.filter { $0.end.timeIntervalSince($0.start) >= minimumSpan }
    }

    /// Fitness-style vocabulary for the workout types worth naming;
    /// everything else is honestly a "Workout".
    nonisolated static func workoutPresentation(activity: UInt) -> (title: String, symbol: String) {
        switch HKWorkoutActivityType(rawValue: activity) {
        case .walking: ("Outdoor Walk", "figure.walk")
        case .running: ("Run", "figure.run")
        case .traditionalStrengthTraining, .functionalStrengthTraining: ("Strength Training", "dumbbell")
        case .stairClimbing: ("Stair Stepper", "figure.stairs")
        case .cycling: ("Cycle", "figure.outdoor.cycle")
        case .hiking: ("Hike", "figure.hiking")
        case .yoga: ("Yoga", "figure.yoga")
        case .swimming: ("Swim", "figure.pool.swim")
        case .highIntensityIntervalTraining: ("HIIT", "bolt.heart")
        case .elliptical: ("Elliptical", "figure.elliptical")
        default: ("Workout", "figure.mixed.cardio")
        }
    }
}
