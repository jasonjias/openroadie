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
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]
        try? await store.requestAuthorization(toShare: [], read: types)
    }

    struct Workout: Equatable, Sendable {
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
