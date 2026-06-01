// Single owner of HealthKit access. Views never touch HKHealthStore directly.
// Read: steps, body mass, heart rate, resting HR, active energy, exercise time,
//       body fat %, waist, blood pressure, blood glucose.
// Write: workouts, body mass (optional, mirrors in-app logs to Apple Health).
// syncFromHealth() pulls latest body/marker readings into the app's logs.

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
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount)              { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass)               { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .restingHeartRate)       { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate)              { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)     { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .appleExerciseTime)      { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage)      { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .waistCircumference)     { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)  { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bloodGlucose)           { s.insert(t) }
        // NOTE: do NOT add the bloodPressure *correlation* type here. Authorizing
        // its component quantity types (systolic/diastolic, above) is sufficient to
        // run the correlation query in latestBloodPressure(); including the
        // correlation type in the auth request can trip HealthKit's request
        // validation and raise an uncatchable Obj-C exception.
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

    /// Result of a permission request — granted, unavailable on this device,
    /// or failed with an error message we can surface to the user.
    public enum AuthResult: Equatable, Sendable {
        case granted
        case unavailable                  // simulator, iPad without Health, etc.
        case failed(reason: String)       // entitlement missing, signing mismatch, etc.

        public var isGranted: Bool { self == .granted }
    }

    /// Request all permissions at once. Idempotent — calling again after grant is cheap.
    /// HealthKit never tells us per-type read grants; the user toggles those in the sheet.
    public func requestAuthorization() async -> AuthResult {
        guard isAvailable else {
            isAuthorized = false
            return .unavailable
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            isAuthorized = true
            return .granted
        } catch {
            print("[HealthKit] auth failed:", error.localizedDescription)
            isAuthorized = false
            return .failed(reason: error.localizedDescription)
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
                let bpm = sample?.quantity.doubleValue(for: Self.bpmUnit)
                cont.resume(returning: bpm.map(Int.init))
            }
            store.execute(q)
        }
    }

    // MARK: - Generic latest-sample read

    /// Most recent sample for a quantity type, with its end date. nil if none.
    private func latestQuantity(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> (value: Double, date: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                if let s = (samples as? [HKQuantitySample])?.first {
                    cont.resume(returning: (s.quantity.doubleValue(for: unit), s.endDate))
                } else {
                    cont.resume(returning: nil)
                }
            }
            store.execute(q)
        }
    }

    /// Most recent (non-resting) heart-rate reading in bpm.
    public func latestHeartRate() async -> Int? {
        let bpm = await latestQuantity(.heartRate, unit: Self.bpmUnit)
        return bpm.map { Int($0.value) }
    }

    /// Latest blood-pressure reading as a paired (systolic, diastolic) from the
    /// same correlation sample, so the two values can't come from different
    /// measurements.
    public func latestBloodPressure() async -> (sys: Double, dia: Double, date: Date)? {
        guard let corrType = HKObjectType.correlationType(forIdentifier: .bloodPressure),
              let sysType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diaType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else { return nil }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: corrType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let corr = (samples as? [HKCorrelation])?.first,
                      let sys = corr.objects(for: sysType).first as? HKQuantitySample,
                      let dia = corr.objects(for: diaType).first as? HKQuantitySample else {
                    cont.resume(returning: nil); return
                }
                let mmHg = HKUnit.millimeterOfMercury()
                cont.resume(returning: (sys.quantity.doubleValue(for: mmHg),
                                        dia.quantity.doubleValue(for: mmHg),
                                        corr.endDate))
            }
            store.execute(q)
        }
    }

    // MARK: - Active energy ("Move")

    /// Active energy burned (kcal) for a local-calendar day.
    public func activeEnergy(for date: Date = Date()) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return 0 }
        let (start, end) = Self.dayBounds(date)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            store.execute(q)
        }
    }

    /// Daily active-energy totals (kcal) across the last `days`, keyed by dayKey.
    public func dailyActiveEnergy(days: Int, end: Date = Date()) async -> [String: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned), days > 0 else { return [:] }
        let cal = Calendar.current
        let endStart = cal.startOfDay(for: end)
        guard let startDay = cal.date(byAdding: .day, value: -(days - 1), to: endStart) else { return [:] }
        let endExclusive = cal.date(byAdding: .day, value: 1, to: endStart) ?? end
        var interval = DateComponents(); interval.day = 1
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: startDay, end: endExclusive, options: [.strictStartDate]),
                options: .cumulativeSum,
                anchorDate: startDay,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, collection, _ in
                var out: [String: Double] = [:]
                collection?.enumerateStatistics(from: startDay, to: endExclusive) { stats, _ in
                    out[Dates.dayKey(stats.startDate)] = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    // MARK: - Body + marker sync

    /// Pulls the latest Health readings for body composition and cardiometabolic
    /// markers and writes any not-yet-recorded value into the app's logs, stamped
    /// with the sample's own day. Deduped by (day, field/kind) so repeated calls
    /// are cheap and idempotent. Resting HR, BP, and glucose land as markers;
    /// body fat % and waist land as body metrics.
    public func syncFromHealth(profileId: UUID, ctx: ModelContext) async {
        guard isAvailable else { return }

        if let bf = await latestQuantity(.bodyFatPercentage, unit: .percent()) {
            // HK stores body fat as a fraction (0.20 == 20%); the app stores the percent number.
            Repos.upsertBodyMetric(ctx, userId: profileId, day: Dates.dayKey(bf.date), bodyFatPct: bf.value * 100)
        }
        if let waist = await latestQuantity(.waistCircumference, unit: .inch()) {
            Repos.upsertBodyMetric(ctx, userId: profileId, day: Dates.dayKey(waist.date), waistIn: waist.value)
        }
        if let rhr = await latestQuantity(.restingHeartRate, unit: Self.bpmUnit) {
            upsertMarker(ctx, profileId: profileId, day: Dates.dayKey(rhr.date), kind: .restingHR, value: rhr.value)
        }
        if let bp = await latestBloodPressure() {
            let day = Dates.dayKey(bp.date)
            upsertMarker(ctx, profileId: profileId, day: day, kind: .bpSystolic, value: bp.sys)
            upsertMarker(ctx, profileId: profileId, day: day, kind: .bpDiastolic, value: bp.dia)
        }
        if let glu = await latestQuantity(.bloodGlucose, unit: Self.mgPerDLUnit) {
            upsertMarker(ctx, profileId: profileId, day: Dates.dayKey(glu.date), kind: .fastingGlucose, value: glu.value)
        }
    }

    private func upsertMarker(_ ctx: ModelContext, profileId: UUID, day: String,
                              kind: HealthMarkerKind, value: Double) {
        let existing = Repos.listMarkers(ctx, userId: profileId)
        if existing.contains(where: { $0.kind == kind && $0.date == day }) { return }
        Repos.addMarker(ctx, HealthMarkerDTO(userId: profileId, date: day, kind: kind, value: value, source: "healthkit"))
    }

    // Type-safe units (string-initialized HKUnit(from:) crashes on a typo).
    nonisolated private static let bpmUnit = HKUnit.count().unitDivided(by: .minute())
    nonisolated private static let mgPerDLUnit = HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))

    // MARK: - Helpers

    // MARK: - Connect flow

    /// Shared "Connect Apple Health" sequence: prompt → persist grant → toast.
    /// The single `.task(id:)` in RootView's appShell re-arms the observer once
    /// the grant flips, so callers do not need to start the observer themselves.
    @discardableResult
    public func connectAndPersist(profileId: UUID, ctx: ModelContext, toasts: ToastCenter) async -> Bool {
        let result = await requestAuthorization()
        switch result {
        case .granted:
            Repos.setHealthGranted(ctx, profileId: profileId, granted: true)
            toasts.show(.healthConnected)
            return true
        case .unavailable:
            Repos.setHealthGranted(ctx, profileId: profileId, granted: false)
            toasts.show(.healthConnectFailed("Apple Health isn't available on this device."))
            return false
        case .failed(let reason):
            Repos.setHealthGranted(ctx, profileId: profileId, granted: false)
            toasts.show(.healthConnectFailed(reason))
            return false
        }
    }

    private static func dayBounds(_ date: Date) -> (Date, Date) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? date
        return (start, end)
    }
}
