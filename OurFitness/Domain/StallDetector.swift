// Detects an activity / progress STALL from the user's logs — the input to a
// gentle "keep going" nudge (Phase 4 of docs/encouragement-system-plan.md →
// "Stall Detection Logic").
//
// Pure Domain: no SwiftUI / SwiftData. Fully unit-tested (hostless).
//
// Returns the SINGLE most relevant stall (priority-ordered) so callers surface one
// nudge, never a pile. Returns nil when the user is active OR has no prior history
// to stall from — a brand-new profile is never nagged. Copy lives in
// `EncouragementEngine.stallMessage`; this file only decides *whether* there's a stall.

import Foundation

public enum StallDetector {

    public enum Stall: Equatable, Sendable {
        case stepsGap(days: Int)
        case workoutGap(days: Int)
        case pilatesGap(days: Int)              // Circuit only
        case weightStall(weeks: Int)            // Circuit only
        case markerStall(HealthMarkerKind, weeks: Int)
    }

    // Thresholds (spec). Public so tests + callers read the same numbers.
    public static let stepsGapDays = 2
    public static let workoutGapBuildDays = 5
    public static let workoutGapCircuitDays = 7
    public static let pilatesGapDays = 7
    public static let weightStallDays = 14
    public static let weightStallMinLossLbPerWeek = 0.1
    public static let markerStallWeeks = 6

    /// Cardiometabolic markers where "no movement" is worth a nudge (lower = better).
    public static let stallMarkerKinds: [HealthMarkerKind] =
        [.bpSystolic, .ldl, .triglycerides, .a1c, .fastingGlucose]

    /// The most relevant stall right now, or nil if the user is active / has no
    /// history. Priority: steps → workout → pilates → weight → marker.
    public static func detect(
        mode: Mode,
        steps: [StepCountDTO] = [],
        sets: [WorkoutSetDTO] = [],
        pilates: [PilatesSessionDTO] = [],
        weights: [BodyMetricDTO] = [],
        markers: [HealthMarkerDTO] = [],
        now: Date = Date()
    ) -> Stall? {
        let today = Dates.dayKey(now)

        // 1) Steps — last day with steps > 500 is ≥ 2 days back. (No active day ever
        //    → nothing to stall from, so no nudge.)
        if let lastActive = steps.filter({ $0.steps > 500 }).map(\.date).max() {
            let gap = Dates.daysBetween(lastActive, today)
            if gap >= stepsGapDays { return .stepsGap(days: gap) }
        }

        // 2) Workout — last logged set ≥ N days back (N depends on mode).
        let workoutThreshold = mode == .build ? workoutGapBuildDays : workoutGapCircuitDays
        if let lastSet = sets.map(\.timestamp).max() {
            let gap = daysAgo(lastSet, now: now)
            if gap >= workoutThreshold { return .workoutGap(days: gap) }
        }

        // 3) Pilates — Circuit only.
        if mode == .circuit, let lastPilates = pilates.map(\.date).max() {
            let gap = daysAgo(lastPilates, now: now)
            if gap >= pilatesGapDays { return .pilatesGap(days: gap) }
        }

        // 4) Weight — Circuit only: the recent trend isn't losing fast enough.
        if mode == .circuit, let weeks = weightStallWeeks(weights, now: now) {
            return .weightStall(weeks: weeks)
        }

        // 5) Marker — a tracked cardiometabolic number flat for ≥ 6 weeks.
        for kind in stallMarkerKinds {
            if let weeks = flatMarkerWeeks(markers, kind: kind, now: now) {
                return .markerStall(kind, weeks: weeks)
            }
        }

        return nil
    }

    // MARK: - Helpers

    /// Whole calendar days between a past `date` and `now` (0 if same day or future).
    private static func daysAgo(_ date: Date, now: Date) -> Int {
        let cal = Calendar.current
        let days = cal.dateComponents([.day],
                                      from: cal.startOfDay(for: date),
                                      to: cal.startOfDay(for: now)).day ?? 0
        return max(0, days)
    }

    /// If the most recent ~14 days of weight readings aren't trending DOWN by at
    /// least 0.1 lb/week (flat or gaining), returns the weeks of data spanned; nil
    /// when there isn't enough data to judge (need ≥2 readings spanning ≥7 days).
    private static func weightStallWeeks(_ weights: [BodyMetricDTO], now: Date) -> Int? {
        let cutoff = Dates.dayKey(Calendar.current.date(byAdding: .day, value: -weightStallDays, to: now) ?? now)
        let window = weights
            .compactMap { w -> (date: String, lb: Double)? in w.weightLb.map { (w.date, $0) } }
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
        guard let first = window.first, let last = window.last, first.date != last.date else { return nil }
        let spanDays = Dates.daysBetween(first.date, last.date)
        guard spanDays >= 7 else { return nil }
        let lbPerWeek = (last.lb - first.lb) / (Double(spanDays) / 7.0)
        // Stall = losing slower than the target (loss < 0.1 lb/wk ⇒ lbPerWeek > −0.1).
        guard lbPerWeek > -weightStallMinLossLbPerWeek else { return nil }
        return max(1, spanDays / 7)
    }

    /// Weeks a marker has sat flat (< 5% drift) versus its most recent reading that's
    /// at least `markerStallWeeks` old. nil when there's no old-enough reading to
    /// compare against, or the marker actually moved ≥ 5% (improved or worsened).
    ///
    /// Not `Trends.weeksStalled`: that returns the span back to the last ≥5% move, so
    /// a marker that *improved* recently would read as "stalled for that span". Here a
    /// ≥6-week-old baseline is required and a real move (either direction) returns nil.
    private static func flatMarkerWeeks(_ markers: [HealthMarkerDTO], kind: HealthMarkerKind, now: Date) -> Int? {
        let series = Trends.markerSeries(markers, kind: kind)   // ascending by date
        guard let latest = series.last else { return nil }
        let cutoff = Dates.dayKey(Calendar.current.date(byAdding: .day, value: -markerStallWeeks * 7, to: now) ?? now)
        guard let baseline = series.last(where: { $0.date <= cutoff }), baseline.date != latest.date else { return nil }
        let drift = abs(latest.value - baseline.value) / max(1, baseline.value)
        guard drift < 0.05 else { return nil }
        return max(markerStallWeeks, Dates.daysBetween(baseline.date, latest.date) / 7)
    }
}
