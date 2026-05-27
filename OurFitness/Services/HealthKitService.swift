// Single owner of HealthKit access. Views never touch HKHealthStore directly.
// Read: steps, body mass, resting HR, active energy, apple exercise time.
// Write: workouts, body mass (optional, mirrors in-app logs to Apple Health).

import Foundation
import HealthKit
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class HealthKitService: ObservableObject {
    public static let shared = HealthKitService()

    private let store = HKHealthStore()

    @Published public private(set) var isAuthorized: Bool = false

    private var stepObserver: HKObserverQuery?
    private var observerSink: ((Int) -> Void)?
    // (type identifier, frequency rawValue) pairs we've already armed this process.
    // enableBackgroundDelivery isn't idempotent at the system level — track to avoid re-calling.
    private var backgroundDeliveryArmed: Set<String> = []

    // Types we read
    private let readTypes: Set<HKObjectType> = {
        var s: Set<HKObjectType> = []
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount)            { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass)             { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .restingHeartRate)     { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)   { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .appleExerciseTime)    { s.insert(t) }
        return s
    }()

    // Types we (optionally) write
    private let writeTypes: Set<HKSampleType> = {
        var s: Set<HKSampleType> = []
        if let t = HKQuantityType.quantityType(forIdentifier: .bodyMass) { s.insert(t) }
        s.insert(HKObjectType.workoutType())
        return s
    }()

    private init() {}

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Request all permissions at once. Idempotent — calling again after grant is cheap.
    /// Returns true if the system sheet completed without error (HealthKit never tells us
    /// per-type read grants; the user toggles those in the sheet).
    @discardableResult
    public func requestAuthorization() async -> Bool {
        guard isAvailable else { isAuthorized = false; return false }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            return true
        } catch {
            print("[HealthKit] auth failed:", error.localizedDescription)
            isAuthorized = false
            return false
        }
    }

    /// Open iOS Settings → app entry. User adjusts per-metric Health toggles in Settings.app.
    public func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    // MARK: - Background step observer

    /// Register an HKObserverQuery for stepCount. On fire, fetches today's total
    /// and invokes `onUpdate` on the main actor. Idempotent — replaces any prior observer.
    public func beginStepObservation(onUpdate: @escaping (Int) -> Void) {
        guard isAvailable,
              let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }

        if let prior = stepObserver { store.stop(prior) }
        observerSink = onUpdate

        let q = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
            Task { @MainActor in
                guard let self else { completion(); return }
                let n = await self.steps()
                self.observerSink?(n)
                completion()
            }
        }
        store.execute(q)
        stepObserver = q

        let key = "\(type.identifier)#\(HKUpdateFrequency.hourly.rawValue)"
        if !backgroundDeliveryArmed.contains(key) {
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
            backgroundDeliveryArmed.insert(key)
        }
    }

    // MARK: - Steps

    /// Sum of steps for the given local-calendar day (defaults to today).
    public func steps(for date: Date = Date()) async -> Int {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }
        let (start, end) = Self.dayBounds(date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                let n = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                cont.resume(returning: Int(n))
            }
            store.execute(q)
        }
    }

    /// Daily step totals across the last `days` days, oldest first.
    /// Missing days fall through to 0 in the returned dict (keyed by dayKey).
    public func dailySteps(days: Int, end: Date = Date()) async -> [String: Int] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount),
              days > 0 else { return [:] }

        let cal = Calendar.current
        let endStart = cal.startOfDay(for: end)
        guard let startDay = cal.date(byAdding: .day, value: -(days - 1), to: endStart) else { return [:] }
        let endExclusive = cal.date(byAdding: .day, value: 1, to: endStart) ?? end

        var interval = DateComponents(); interval.day = 1
        let anchor = startDay

        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: startDay, end: endExclusive, options: [.strictStartDate]),
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, collection, _ in
                var out: [String: Int] = [:]
                collection?.enumerateStatistics(from: startDay, to: endExclusive) { stats, _ in
                    let n = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    out[Dates.dayKey(stats.startDate)] = Int(n)
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    // MARK: - Body mass

    /// Most recent body-mass reading in pounds, if any.
    public func latestWeightLb() async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let sample = (samples as? [HKQuantitySample])?.first
                let lb = sample?.quantity.doubleValue(for: .pound())
                cont.resume(returning: lb)
            }
            store.execute(q)
        }
    }

    public func writeWeightLb(_ lb: Double, date: Date = Date()) async {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let q = HKQuantity(unit: .pound(), doubleValue: lb)
        let sample = HKQuantitySample(type: type, quantity: q, start: date, end: date)
        do {
            try await store.save(sample)
        } catch {
            print("[HealthKit] write weight failed:", error.localizedDescription)
        }
    }

    // MARK: - Resting heart rate

    public func latestRestingHR() async -> Int? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                let sample = (samples as? [HKQuantitySample])?.first
                let bpm = sample?.quantity.doubleValue(for: HKUnit(from: "count/min"))
                cont.resume(returning: bpm.map(Int.init))
            }
            store.execute(q)
        }
    }

    // MARK: - Helpers

    // MARK: - Connect flow

    /// Shared "Connect Apple Health" sequence: prompt → persist grant → toast.
    /// The single `.task(id:)` in RootView's appShell re-arms the observer once
    /// the grant flips, so callers do not need to start the observer themselves.
    @discardableResult
    public func connectAndPersist(profileId: UUID, ctx: ModelContext, toasts: ToastCenter) async -> Bool {
        let ok = await requestAuthorization()
        Repos.setHealthGranted(ctx, profileId: profileId, granted: ok)
        if ok { toasts.show(.healthConnected) }
        return ok
    }

    private static func dayBounds(_ date: Date) -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }
}
