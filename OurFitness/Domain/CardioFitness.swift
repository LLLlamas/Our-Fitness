// Cardio fitness (VO₂ max): pure helpers for the Progress tracker and the
// Health history sync. Plan: docs/cardio-fitness-plan.md §4 (steps 1–4, and the
// `vo2Trend` half of step 6).
//
// The estimate is read-only — Apple Watch writes it to Health, we only read it —
// so nothing here classifies, targets or rates the number (plan §1.3–1.4). The
// trend compares the user with their own earlier estimates only.
//
// Phone-only pure Domain (Foundation only). NOT in the watch's source list.
// `now` is injected everywhere; never read the wall clock here.

import Foundation

public enum CardioFitness {

    /// How far back the history read goes when no estimate is stored yet.
    public static let historyYears = 2

    /// The trend compares the latest estimate with the newest one at least
    /// this many days before it (8 weeks): the estimate moves slowly.
    public static let trendGapDays = 56

    /// A change of this much or less reads "about the same". Not a sourced
    /// figure: it is the plan's copy rule that a change of a point or two is
    /// noise for this estimate (plan §2, accuracy).
    public static let noiseBand = 2.0

    /// Range Apple Watch supports, in ml/kg/min. Apple Support 108790 ("Apple
    /// Watch supports a VO2 max range of 14-65 mL/kg/min"), opened 2026-11-20.
    public static let supportedRange: ClosedRange<Double> = 14...65

    // MARK: - Health history sync

    /// One VO₂ max sample from Health: its end date and value in ml/kg/min.
    public struct Reading: Equatable, Sendable {
        public let date: Date
        public let value: Double
        public init(date: Date, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Where every sync's VO₂ max read starts: the newest stored `vo2_max` day
    /// (inclusive — that day is deduped below), or `historyYears` back when none
    /// is stored. Deliberately no one-shot flag: a read made before the user
    /// re-ran Connect returns nothing (a denied read looks empty), so the next
    /// sync after they reconnect must still reach the whole history (plan §9.2).
    public static func historyStart(existing: [HealthMarkerDTO], now: Date,
                                    calendar: Calendar = .current) -> Date {
        if let newest = existing.lazy.filter({ $0.kind == .vo2Max }).map(\.date).max(),
           let day = Dates.date(fromDayKey: newest) {
            return day
        }
        return calendar.date(byAdding: .year, value: -historyYears, to: now) ?? now
    }

    /// The readings to store: one per day (the newest sample of that day),
    /// skipping any day that already holds a `vo2_max` marker. Ascending by day.
    /// `existing` is the profile's markers, fetched ONCE by the caller, so a
    /// two-year backfill isn't one fetch per sample (plan §9.6).
    public static func newDailyReadings(_ samples: [Reading],
                                        existing: [HealthMarkerDTO]) -> [Trends.Point] {
        let stored = Set(existing.lazy.filter { $0.kind == .vo2Max }.map(\.date))
        var newestByDay: [String: Reading] = [:]
        for sample in samples {
            let day = Dates.dayKey(sample.date)
            guard !stored.contains(day) else { continue }
            if let kept = newestByDay[day], kept.date >= sample.date { continue }
            newestByDay[day] = sample
        }
        return newestByDay
            .map { Trends.Point(date: $0.key, value: $0.value.value) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Trend (own history only)

    public enum Trend: Equatable, Sendable {
        /// No estimate 8+ weeks before the latest yet. One reading gets no verdict.
        case tooSoon
        case aboutTheSame(since: String)
        /// Rounded to 0.1, always positive.
        case up(Double, since: String)
        /// Rounded to 0.1, always positive. Shown plainly, never as a warning.
        case down(Double, since: String)
    }

    /// Latest estimate vs the newest estimate at least `trendGapDays` before it.
    /// `samples` are day-keyed points (any order); days after `now` are ignored.
    public static func vo2Trend(samples: [Trends.Point], now: Date) -> Trend {
        let today = Dates.dayKey(now)
        let past = samples.filter { $0.date <= today }.sorted { $0.date < $1.date }
        guard let latest = past.last,
              let baseline = past.last(where: { Dates.daysBetween($0.date, latest.date) >= trendGapDays })
        else { return .tooSoon }
        let delta = ((latest.value - baseline.value) * 10).rounded() / 10
        if abs(delta) <= noiseBand { return .aboutTheSame(since: baseline.date) }
        return delta > 0 ? .up(delta, since: baseline.date) : .down(-delta, since: baseline.date)
    }

    /// Short chip for the Progress card. nil until there is a comparison.
    public static func chipText(_ trend: Trend) -> String? {
        switch trend {
        case .tooSoon:                    return nil
        case .aboutTheSame(let since):    return "≈ same vs \(Dates.formatShort(since))"
        case .up(let d, let since):       return String(format: "+%.1f vs %@", d, Dates.formatShort(since))
        case .down(let d, let since):     return String(format: "−%.1f vs %@", d, Dates.formatShort(since))
        }
    }

    /// One plain sentence for the detail sheet, comparing with the user's own past.
    public static func noteText(_ trend: Trend) -> String {
        switch trend {
        case .tooSoon:
            return "One estimate says little on its own. Once there is one from 8 or more weeks earlier, this compares the two."
        case .aboutTheSame(let since):
            return "Your estimate is about the same as on \(Dates.formatShort(since))."
        case .up(let d, let since):
            return String(format: "Your estimate is %.1f higher than on %@.", d, Dates.formatShort(since))
        case .down(let d, let since):
            return String(format: "Your estimate is %.1f lower than on %@.", d, Dates.formatShort(since))
        }
    }

    /// "as of Nov 18". Date only: a marker's date is a day key, so there is no
    /// time to show (`Freshness.label` takes a `Date` and prints one; plan §9.5).
    public static func asOfLabel(dayKey: String) -> String {
        "as of " + Dates.formatShort(dayKey)
    }

    // MARK: - Tracker visibility (one-time migration)

    /// The stored Progress tracker CSV with `raw` added, everything else kept as
    /// is. Used once per profile to put the VO₂ max tracker in front of people
    /// who had already customized their trackers (owner decision, plan §10).
    /// Empty = still on the defaults, which already include it; "none" (the
    /// "show nothing" sentinel) becomes just this tracker.
    public static func enabledTrackers(_ csv: String, adding raw: String) -> String {
        if csv.isEmpty { return csv }
        if csv == "none" { return raw }
        if csv.split(separator: ",").contains(where: { $0 == raw }) { return csv }
        return csv + "," + raw
    }
}
