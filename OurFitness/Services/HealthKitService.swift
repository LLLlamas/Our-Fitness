// Single owner of HealthKit access. Views never touch HKHealthStore directly.
// Read: steps, body mass, heart rate, resting HR, active energy, exercise time,
//       body fat %, waist, blood pressure, blood glucose (fasting-marked only),
//       VO₂ max (Apple Watch cardio fitness estimate, read-only, full history),
//       workouts (cardio minutes only — never burn or active energy).
// Write: workouts, body mass (optional, mirrors in-app logs to Apple Health),
//        the Dizziness symptom for a flagged live session (its real window only).
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

    /// Health workouts since `CardioFitness.healthWindowStart`, for the cardio
    /// minutes tracker only. Derived on read: re-fetched on every sync and when
    /// Progress appears, kept in memory, never stored, never fed into burn,
    /// `DailyBurn` or active energy (plan §7 Q5 b).
    @Published public private(set) var cardioWorkouts: [CardioFitness.HealthWorkout] = []
    /// Own-app bundle ids already logged this process (plan §9: which one
    /// HealthKit stamps on a watch-saved workout is not verified).
    private var loggedOwnSources: Set<String> = []

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
        if let t = HKObjectType.quantityType(forIdentifier: .flightsClimbed)         { s.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)  { s.insert(t) }
        // Cardio fitness. Apple Watch writes it; we only read. People connected
        // before this was added must run Connect again to grant it (plan §4.3).
        if let t = HKObjectType.quantityType(forIdentifier: .vo2Max)                 { s.insert(t) }
        // Workouts from other apps (Apple's Workout app) count toward cardio
        // minutes. Also in writeTypes for the watch's own workouts. People
        // connected before this was added must run Connect again (plan §8).
        s.insert(HKObjectType.workoutType())
        // MERGE: restored with `restingEnergy(for:)` below — the read is useless
        // without it. A *quantity* type, so it's safe to authorize (see the note).
        if let t = HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)      { s.insert(t) }
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
        // Symptom (category type, values are HKCategoryValueSeverity per Apple's
        // docs). Written only for a "Felt dizzy" live session. People connected
        // before this was added must run Connect again to grant it.
        s.insert(HKCategoryType(.dizziness))
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
        Int(await dailySum(.stepCount, unit: .count(), for: date))
    }

    /// Daily step totals across the last `days` days, keyed by dayKey.
    /// Days Health holds no step samples for are absent from the dict rather than
    /// present as 0 — see `dailySums`.
    public func dailySteps(days: Int, end: Date = Date()) async -> [String: Int] {
        await dailySums(.stepCount, unit: .count(), days: days, end: end)
            .mapValues(Int.init)
    }

    /// Cumulative step totals at each hour boundary of a local-calendar day —
    /// 24 entries, index 0 = end of the 12 AM hour … index 23 = end of the 11 PM
    /// hour. This is the shape `Movement.stepsDeltaVsYesterday` expects.
    /// Returns `[]` when Health holds no step samples for that day, so callers can
    /// hide the pace line instead of comparing against a fabricated zero.
    public func hourlyCumulativeSteps(for date: Date = Date()) async -> [Int] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return [] }
        let (start, end) = Self.dayBounds(date)
        var interval = DateComponents(); interval.hour = 1

        let perHour: [Int]? = await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate]),
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: interval
            )
            q.initialResultsHandler = { _, collection, _ in
                guard let collection else { cont.resume(returning: nil); return }
                let cal = Calendar.current
                var buckets = [Int](repeating: 0, count: 24)
                var sawSample = false
                collection.enumerateStatistics(from: start, to: end) { stats, _ in
                    guard let sum = stats.sumQuantity() else { return }
                    sawSample = true
                    // Index by the hour component so a DST day (23 or 25 hours)
                    // still lands inside the 24-slot array.
                    let h = cal.component(.hour, from: stats.startDate)
                    buckets[min(23, max(0, h))] += Int(sum.doubleValue(for: .count()))
                }
                cont.resume(returning: sawSample ? buckets : nil)
            }
            store.execute(q)
        }

        guard let perHour else { return [] }
        var running = 0
        return perHour.map { running += $0; return running }
    }

    // MARK: - Body mass

    /// Write a body-mass sample to Apple Health (so app-logged weights flow back to
    /// Health and feed `latestQuantity(.bodyMass, ...)` reads in `syncFromHealth`).
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

    // MARK: - "Felt dizzy" session (cardio plan §10 Q2)

    /// Average and peak heart rate from Health samples that start inside the
    /// window. nil when there are none — including when read access was never
    /// granted, which HealthKit reports as no data. Never estimated.
    public func heartRateSummary(start: Date, end: Date) async -> (average: Double, peak: Double)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let unit = Self.bpmUnit
        let stats: (Double?, Double?) = await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                      options: [.discreteAverage, .discreteMax]) { _, stats, _ in
                cont.resume(returning: (stats?.averageQuantity()?.doubleValue(for: unit),
                                        stats?.maximumQuantity()?.doubleValue(for: unit)))
            }
            store.execute(q)
        }
        return SessionDizziness.heartRate(average: stats.0, peak: stats.1)
    }

    /// Saves one Dizziness symptom sample over the session window. Returns false
    /// (no prompt, no throw) when sharing isn't authorized or the save fails —
    /// the local flag is already saved either way.
    @discardableResult
    public func writeDizziness(_ severity: SessionDizziness.HealthSeverity, start: Date, end: Date) async -> Bool {
        let type = HKCategoryType(.dizziness)
        guard isAvailable, store.authorizationStatus(for: type) == .sharingAuthorized else { return false }
        let value: HKCategoryValueSeverity
        switch severity {
        case .unspecified: value = .unspecified
        case .mild: value = .mild
        case .moderate: value = .moderate
        case .severe: value = .severe
        }
        let sample = HKCategorySample(type: type, value: value.rawValue, start: start, end: end)
        do {
            try await store.save(sample)
            return true
        } catch {
            print("[HealthKit] write dizziness failed:", error.localizedDescription)
            return false
        }
    }

    /// After a flagged live session is saved: read heart rate over its real
    /// window and store it, then write the Dizziness symptom to Health. Sessions
    /// logged after the fact never come here (`SessionDizziness.healthWindow`).
    /// Failures are quiet; the flag itself was saved with the session.
    public func recordDizzySession(_ ctx: ModelContext, state: LiveSessionState, end: Date,
                                   report: DizzinessReport, healthGranted: Bool) async {
        guard healthGranted,
              let window = SessionDizziness.healthWindow(
                flagged: true, origin: .live(start: state.startDate, end: end)) else { return }
        if let hr = await heartRateSummary(start: window.start, end: window.end) {
            _ = Repos.recordDizzyHeartRate(ctx, state: state, averageBpm: hr.average, peakBpm: hr.peak)
        }
        await writeDizziness(SessionDizziness.healthSeverity(report.severity),
                             start: window.start, end: window.end)
    }

    // MARK: - Resting heart rate

    public func latestRestingHR() async -> Int? {
        guard let rhr = await latestQuantity(.restingHeartRate, unit: Self.bpmUnit) else { return nil }
        return Int(rhr.value)
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

    /// Most recent heart-rate reading in bpm with its timestamp.
    public func latestHeartRateWithDate() async -> (value: Int, date: Date)? {
        guard let result = await latestQuantity(.heartRate, unit: Self.bpmUnit) else { return nil }
        return (Int(result.value), result.date)
    }

    /// Date of the most recent active-energy sample (not the daily sum). Used to
    /// detect staleness: if this is > 7 days ago, the Watch hasn't synced recently.
    public func latestActiveEnergySampleDate() async -> Date? {
        await latestQuantity(.activeEnergyBurned, unit: .kilocalorie())?.date
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

    // MARK: - Blood glucose (fasting only)

    /// Most recent blood-glucose reading (mg/dL) that HealthKit itself marks as a
    /// *pre-meal* measurement — the only kind that may be stored as
    /// `HealthMarkerKind.fastingGlucose`.
    ///
    /// HealthKit carries the meal context in `HKMetadataKeyBloodGlucoseMealTime`
    /// as an NSNumber wrapping `HKBloodGlucoseMealTime` (`.preprandial` = just
    /// before a meal, `.postprandial` = after). Mislabelling matters clinically:
    /// a post-meal 150 mg/dL is unremarkable, but filed as *fasting* glucose
    /// `HealthRanges.status(for:)` scores it >= 126 -> .high, i.e. the app would
    /// report the ADA diabetes cut-point off a normal reading. So two samples get
    /// skipped rather than mislabelled:
    ///   - samples marked `.postprandial`
    ///   - samples with no meal-time metadata at all (the common case: CGM feeds
    ///     and most manual entries carry none)
    /// Keeping those would need a separate non-fasting glucose `HealthMarkerKind`.
    ///
    /// The predicate asks Health for pre-meal samples only, so the newest *fasting*
    /// reading is found even when a later non-fasting one exists; the metadata is
    /// re-checked in the handler so nothing unmarked can slip through.
    private func latestFastingGlucoseMgDL() async -> (value: Double, date: Date)? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bloodGlucose) else { return nil }
        let unit = Self.mgPerDLUnit
        let preMealOnly = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyBloodGlucoseMealTime,
            // HKMetadata.h documents the stored value as an NSNumber wrapping the
            // enum — match that type exactly rather than relying on Int bridging.
            allowedValues: [NSNumber(value: HKBloodGlucoseMealTime.preprandial.rawValue)]
        )
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: preMealOnly, limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in
                guard let s = (samples as? [HKQuantitySample])?.first,
                      let raw = s.metadata?[HKMetadataKeyBloodGlucoseMealTime] as? NSNumber,
                      HKBloodGlucoseMealTime(rawValue: raw.intValue) == .preprandial else {
                    cont.resume(returning: nil); return
                }
                cont.resume(returning: (s.quantity.doubleValue(for: unit), s.endDate))
            }
            store.execute(q)
        }
    }

    // MARK: - Active energy ("Move")

    /// Active energy burned (kcal) for a local-calendar day.
    public func activeEnergy(for date: Date = Date()) async -> Double {
        await dailySum(.activeEnergyBurned, unit: .kilocalorie(), for: date)
    }

    /// Floors climbed (integer count) for a local-calendar day.
    public func flightsClimbed(for date: Date = Date()) async -> Int {
        Int(await dailySum(.flightsClimbed, unit: .count(), for: date))
    }

    /// Walking + running distance in miles for a local-calendar day.
    public func walkingRunningDistanceMiles(for date: Date = Date()) async -> Double {
        await dailySum(.distanceWalkingRunning, unit: .mile(), for: date)
    }

    /// Resting (basal) energy burned in kcal for a local-calendar day.
    public func restingEnergy(for date: Date = Date()) async -> Double {
        await dailySum(.basalEnergyBurned, unit: .kilocalorie(), for: date)
    }

    /// Daily active-energy totals (kcal) across the last `days`, keyed by dayKey.
    /// Days with no samples are absent from the dict, not 0 — see `dailySums`.
    public func dailyActiveEnergy(days: Int, end: Date = Date()) async -> [String: Double] {
        await dailySums(.activeEnergyBurned, unit: .kilocalorie(), days: days, end: end)
    }

    // MARK: - Week-to-date totals

    /// Active energy burned (cal) from the Monday-anchored (ISO) start of `now`'s week through
    /// `now`. nil when Health holds no active-energy samples in that window —
    /// callers hide the stat rather than showing a misleading 0.
    public func activeEnergyThisWeekCal(now: Date = Date()) async -> Int? {
        let (start, end) = Self.weekToDateBounds(now)
        guard let cal = await sumOrNil(.activeEnergyBurned, unit: .kilocalorie(), start: start, end: end)
        else { return nil }
        return Int(cal.rounded())
    }

    /// Apple "exercise minutes" (appleExerciseTime) from the Monday-anchored (ISO)
    /// start of `now`'s week through `now`. nil when Health has nothing in the window.
    public func exerciseMinutesThisWeek(now: Date = Date()) async -> Int? {
        let (start, end) = Self.weekToDateBounds(now)
        guard let minutes = await sumOrNil(.appleExerciseTime, unit: .minute(), start: start, end: end)
        else { return nil }
        return Int(minutes.rounded())
    }

    // MARK: - Cumulative-sum queries

    /// Cumulative sum of a quantity type over a window, or nil when Health holds
    /// no samples for it there (HealthKit reports an absent total as a nil
    /// `sumQuantity`, which is different from a real 0).
    ///
    /// Absent-data policy: absent stays absent, so the UI can hide the stat rather
    /// than show a misleading 0. `dailySums` below omits absent days for the same
    /// reason; `dailySum` is the single deliberate exception.
    private func sumOrNil(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                          start: Date, end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(q)
        }
    }

    /// Cumulative sum of a quantity type over one local-calendar day. 0 when absent.
    private func dailySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, for date: Date) async -> Double {
        let (start, end) = Self.dayBounds(date)
        return await sumOrNil(id, unit: unit, start: start, end: end) ?? 0
    }

    /// Per-day cumulative sums across the last `days` days, keyed by dayKey.
    ///
    /// Absent-data policy, shared with `sumOrNil` above: a day Health holds no
    /// samples for is **omitted from the dictionary**, never emitted as 0 — "never
    /// synced" and "genuinely zero" are different facts, and a chart or average fed
    /// fabricated zeros reads as a real crash in activity. Callers decide what a
    /// missing key means (`map[key] ?? 0` where a zero is the right default, or hide
    /// the value). `dailySum(_:unit:for:)` is the one place that deliberately
    /// collapses absent → 0, because its callers render a single day's total.
    private func dailySums(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                           days: Int, end: Date) async -> [String: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id), days > 0 else { return [:] }

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
                    // nil sumQuantity == no samples that day; leave the key out.
                    guard let sum = stats.sumQuantity() else { return }
                    out[Dates.dayKey(stats.startDate)] = sum.doubleValue(for: unit)
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
    /// body fat % and waist land as body metrics. Glucose only lands when Health
    /// marks the sample pre-meal (see `latestFastingGlucoseMgDL()`).
    public func syncFromHealth(profileId: UUID, ctx: ModelContext) async {
        guard isAvailable else { return }

        if let w = await latestQuantity(.bodyMass, unit: .pound()) {
            // Record under the reading's own day for history (upsert won't clobber a
            // value already logged that day), then re-point the profile (the source
            // all recommendations read) at this HealthKit value directly — it's the
            // authoritative latest measurement across sources (app-logged weights are
            // written back to Health too), so pass it explicitly rather than re-deriving
            // from the body-metric log, which the upsert may not have updated.
            Repos.upsertBodyMetric(ctx, userId: profileId, day: Dates.dayKey(w.date), weightLb: w.value)
            Repos.syncCurrentWeight(ctx, profileId: profileId, weightLb: w.value)
        }
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
        // Only a HealthKit-confirmed pre-meal sample may be filed as fasting
        // glucose — unmarked and post-meal readings are dropped on purpose.
        // See latestFastingGlucoseMgDL().
        if let glu = await latestFastingGlucoseMgDL() {
            upsertMarker(ctx, profileId: profileId, day: Dates.dayKey(glu.date), kind: .fastingGlucose, value: glu.value)
        }
        await syncVO2MaxHistory(ctx, profileId: profileId)
        await refreshCardioWorkouts()
    }

    /// Re-reads every workout that started since `CardioFitness.healthWindowStart`
    /// (this week and the 11 before it). The whole window every time — no
    /// one-shot flag — because a read made before the user re-ran Connect comes
    /// back empty (HealthKit hides denied reads). Filtering (cardio kinds, own
    /// app, overlap with logged sessions) happens in `CardioFitness.weeklyMinutes`.
    public func refreshCardioWorkouts(now: Date = Date()) async {
        guard isAvailable else { return }
        let start = CardioFitness.healthWindowStart(now: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [.strictStartDate])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let workouts: [CardioFitness.HealthWorkout] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let out = (samples as? [HKWorkout] ?? []).map {
                    CardioFitness.HealthWorkout(
                        start: $0.startDate, end: $0.endDate, durationSeconds: $0.duration,
                        kind: Self.workoutKind($0.workoutActivityType),
                        sourceBundleId: $0.sourceRevision.source.bundleIdentifier)
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
        for id in Set(workouts.map(\.sourceBundleId)) where CardioFitness.ownBundleIds.contains(id)
            && !loggedOwnSources.contains(id) {
            print("[HealthKit] own-app workouts in Health stamped with source:", id)
            loggedOwnSources.insert(id)
        }
        cardioWorkouts = workouts
    }

    /// The cardio set for Health workouts (plan §9 "Phase 2 must"). Anything not
    /// listed — strength, core, cooldown, mind and body, … — is `.other` and
    /// doesn't count; yoga, Pilates and flexibility are named so tests can pin them.
    nonisolated private static func workoutKind(_ type: HKWorkoutActivityType) -> CardioFitness.WorkoutKind {
        switch type {
        case .walking:                                    return .walking
        case .running:                                    return .running
        case .hiking:                                     return .hiking
        case .cycling, .handCycling:                      return .cycling
        case .swimming:                                   return .swimming
        case .rowing:                                     return .rowing
        case .elliptical:                                 return .elliptical
        case .stairClimbing, .stairs, .stepTraining:      return .stairs
        case .jumpRope:                                   return .jumpRope
        case .socialDance, .cardioDance:                  return .dance
        case .mixedCardio:                                return .mixedCardio
        case .highIntensityIntervalTraining:              return .intervals
        case .skatingSports:                              return .skating
        case .crossCountrySkiing:                         return .skiing
        case .paddleSports:                               return .paddling
        case .wheelchairWalkPace, .wheelchairRunPace:     return .wheelchair
        case .basketball, .soccer, .tennis:               return .ballSports
        case .swimBikeRun:                                return .multisport
        case .yoga:                                       return .yoga
        case .pilates:                                    return .pilates
        case .flexibility:                                return .flexibility
        default:                                          return .other
        }
    }

    /// VO₂ max history, not just the latest sample: estimates arrive only a few
    /// times a week, so `latestQuantity` alone would leave the chart empty.
    ///
    /// Every sync reads from the newest stored `vo2_max` day, or 2 years back if
    /// none — no one-shot flag, because a read made before the user re-ran Connect
    /// comes back empty (HealthKit hides denied reads) and must not end the
    /// backfill (plan §9.2). Existing markers are fetched once and deduped in
    /// memory, and the new days go in as one commit (plan §9.6).
    private func syncVO2MaxHistory(_ ctx: ModelContext, profileId: UUID) async {
        let existing = Repos.listMarkers(ctx, userId: profileId)
        let now = Date()
        let start = CardioFitness.historyStart(existing: existing, now: now)
        let samples = await quantitySamples(.vo2Max, unit: Self.vo2MaxUnit, start: start, end: now)
        let fresh = CardioFitness.newDailyReadings(samples, existing: existing)
        guard !fresh.isEmpty else { return }
        Repos.addMarkers(ctx, fresh.map {
            HealthMarkerDTO(userId: profileId, date: $0.date, kind: .vo2Max, value: $0.value, source: "healthkit")
        })
    }

    /// Every sample of a quantity type ending in [start, end], oldest first, with
    /// its end date (the date every other read here keys the day by).
    private func quantitySamples(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                                 start: Date, end: Date) async -> [CardioFitness.Reading] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, samples, _ in
                let readings = (samples as? [HKQuantitySample] ?? []).map {
                    CardioFitness.Reading(date: $0.endDate, value: $0.quantity.doubleValue(for: unit))
                }
                cont.resume(returning: readings)
            }
            store.execute(q)
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
    /// ml/(kg·min), the unit Apple documents for `.vo2Max`.
    nonisolated private static let vo2MaxUnit = HKUnit.literUnit(with: .milli)
        .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

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

    /// Monday-anchored (ISO) start of `date`'s week → `date`. Week-to-date, not a
    /// full week: "this week so far" is what the UI shows.
    ///
    /// Must stay on `Dates.startOfISOWeek` — the app defines a week as Monday→Sunday
    /// everywhere (Movement, RepCounter, CardioLogCard, TrainingHistory), while
    /// `Calendar.current` starts the week on Sunday in the US locale. Diverging here
    /// made the "Active cal · week" / "Exercise min · week" cells in StepsCard cover
    /// a different window from every other weekly figure in the app.
    private static func weekToDateBounds(_ date: Date) -> (Date, Date) {
        (Dates.startOfISOWeek(date), date)
    }
}
