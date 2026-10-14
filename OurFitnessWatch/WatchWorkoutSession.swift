// On-wrist workout tracking: HKWorkoutSession + HKLiveWorkoutBuilder.
//
// This is what makes a live session started on the watch behave like a real
// workout rather than a stopwatch — the watch's own sensors supply heart rate
// and active energy, and the finished HKWorkout is saved to Health so it counts
// toward the Activity rings. None of that is possible from the phone.
//
// Relationship to the phone: this is PURELY additive telemetry. The phone
// remains the source of truth for the session itself (LiveSessionStore, the
// ActivitySessionDTO row, the calorie figure shown in the app, which stays the
// deterministic MET estimate per CLAUDE.md). If HealthKit is unavailable,
// unauthorised, or the session fails to start, the live session still runs
// exactly as before — every failure here is soft.
//
// ⚠️ HealthKit crash traps (CLAUDE.md, "caused SIGABRT in build 37"):
//   - `requestAuthorization` raises an UNCATCHABLE NSException. It is called
//     only from `startWorkout`, which is reached only by an explicit user tap.
//     Never call it from `.task`/`.onAppear`.
//   - Only QUANTITY types in the read/write sets. Correlation types crash auth.
//     HKObjectType.workoutType() is a workout type, not a correlation, and is
//     required to save a workout — the phone already ships it in writeTypes.

import Foundation
import HealthKit

@MainActor
final class WatchWorkoutSession: NSObject, ObservableObject {
    static let shared = WatchWorkoutSession()

    /// Live values for the runner UI. Nil while no workout is active.
    @Published private(set) var heartRateBpm: Int?
    @Published private(set) var activeEnergyKcal: Double?
    @Published private(set) var isRunning = false

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private override init() { super.init() }

    // MARK: - Types

    /// Quantity types only — see the crash-trap note above.
    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        for id in [HKQuantityTypeIdentifier.heartRate, .activeEnergyBurned, .distanceWalkingRunning] {
            if let t = HKObjectType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        return types
    }

    private var writeTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(energy)
        }
        return types
    }

    // MARK: - Lifecycle

    /// CALL ONLY FROM AN EXPLICIT USER ACTION (the Start button). Returns false
    /// if a workout could not be started, in which case the caller carries on
    /// with a plain timed session — this is never fatal.
    @discardableResult
    func startWorkout(activityId: String, startDate: Date) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return false }

        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        } catch {
            print("[WatchWorkout] authorization failed:", error.localizedDescription)
            return false
        }

        let config = HKWorkoutConfiguration()
        config.activityType = Self.hkActivityType(for: activityId)
        config.locationType = .unknown

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: config)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            session.delegate = self
            builder.delegate = self

            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            self.session = session
            self.builder = builder
            self.isRunning = true
            return true
        } catch {
            print("[WatchWorkout] could not start session:", error.localizedDescription)
            resetState()
            return false
        }
    }

    /// Ends and SAVES the workout. Safe to call when nothing is running.
    func endWorkout(at endDate: Date = Date()) async {
        guard let session, let builder else { return }
        session.end()
        do {
            try await builder.endCollection(at: endDate)
            // finishWorkout is what persists the HKWorkout — without it the
            // session is discarded and the rings get no credit.
            _ = try await builder.finishWorkout()
        } catch {
            print("[WatchWorkout] could not finish workout:", error.localizedDescription)
        }
        resetState()
    }

    private func resetState() {
        session = nil
        builder = nil
        isRunning = false
        heartRateBpm = nil
        activeEnergyKcal = nil
    }

    // MARK: - Activity mapping

    /// Maps an `ActivityCatalog` id to Apple's workout taxonomy. `.other` is a
    /// perfectly valid fallback — it still earns ring credit — so an unmapped
    /// or user-defined activity degrades rather than failing.
    static func hkActivityType(for activityId: String) -> HKWorkoutActivityType {
        switch activityId {
        case "activity-walking":     return .walking
        case "activity-running":     return .running
        case "activity-cycling":     return .cycling
        case "activity-swimming":    return .swimming
        case "activity-basketball":  return .basketball
        case "activity-soccer":      return .soccer
        case "activity-tennis":      return .tennis
        case "activity-hiking":      return .hiking
        case "activity-rowing":      return .rowing
        case "activity-elliptical":  return .elliptical
        case "activity-yoga":        return .yoga
        case "activity-dancing":     return .cardioDance
        case "activity-climbing":    return .climbing
        case "activity-boxing":      return .boxing
        case ActivityCatalog.pilatesId: return .pilates
        default:                     return .other
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            self.isRunning = (toState == .running)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("[WatchWorkout] session failed:", error.localizedDescription)
        Task { @MainActor in self.resetState() }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        // Read the statistics synchronously here — the builder mutates them as
        // more samples land, so capture the values before hopping actors.
        var bpm: Int?
        var kcal: Double?
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let stats = workoutBuilder.statistics(for: quantityType) else { continue }
            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                let unit = HKUnit.count().unitDivided(by: .minute())
                if let v = stats.mostRecentQuantity()?.doubleValue(for: unit) { bpm = Int(v.rounded()) }
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                if let v = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) { kcal = v }
            default:
                break
            }
        }
        guard bpm != nil || kcal != nil else { return }
        Task { @MainActor in
            if let bpm { self.heartRateBpm = bpm }
            if let kcal { self.activeEnergyKcal = kcal }
        }
    }
}
