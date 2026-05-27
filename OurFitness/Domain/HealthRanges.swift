// Medical reference ranges for the markers shown on the Progress tab.
// These are population-level ranges (ACC/AHA, ADA, NCEP ATP III); they are not
// personalised targets and intentionally do not flex with profile vitals.
// Used by the Progress UI to tint the latest value and show a one-line
// "Optimal: …" caption inside the detail sheet.
//
// Pure Swift — no SwiftUI / SwiftData. The view layer maps `RangeStatus`
// to `theme.ok` / `theme.warn` so colour stays a presentation concern.

import Foundation

public enum HealthRanges {

    public enum RangeStatus: Equatable, Sendable {
        case optimal
        case borderline
        case high
        case unknown
    }

    /// One-line "what's healthy" caption shown under the marker chart.
    /// Source: ACC/AHA 2017 BP, NCEP ATP III lipids, ADA 2024 glycaemia,
    /// AHA resting heart-rate reference.
    public static func context(for kind: HealthMarkerKind) -> String {
        switch kind {
        case .bpSystolic:       return "Optimal: <120 mmHg (ACC/AHA)"
        case .bpDiastolic:      return "Optimal: <80 mmHg (ACC/AHA)"
        case .ldl:              return "Optimal: <100 mg/dL (NCEP)"
        case .hdl:              return "Optimal: ≥60 mg/dL (NCEP)"
        case .triglycerides:    return "Optimal: <150 mg/dL (NCEP)"
        case .totalCholesterol: return "Desirable: <200 mg/dL (NCEP)"
        case .a1c:              return "Normal: <5.7% · Pre-diabetes: 5.7–6.4% (ADA)"
        case .fastingGlucose:   return "Normal: <100 mg/dL · Pre-diabetes: 100–125 (ADA)"
        case .restingHR:        return "Healthy adult: 60–80 bpm (AHA)"
        }
    }

    /// Composite caption for the BP pair, used by the BP detail sheet header.
    public static var bpContext: String {
        "Optimal: <120 / <80 mmHg (ACC/AHA)"
    }

    public static func status(for kind: HealthMarkerKind, value: Double) -> RangeStatus {
        switch kind {
        case .bpSystolic:
            // <120 normal · 120–129 elevated · ≥130 hypertension stage 1+
            if value < 120 { return .optimal }
            if value < 130 { return .borderline }
            return .high
        case .bpDiastolic:
            // <80 normal · 80–89 stage 1 · ≥90 stage 2
            if value < 80 { return .optimal }
            if value < 90 { return .borderline }
            return .high
        case .ldl:
            // <100 optimal · 100–129 near-optimal · ≥130 high
            if value < 100 { return .optimal }
            if value < 130 { return .borderline }
            return .high
        case .hdl:
            // ≥60 protective · 40–59 acceptable · <40 low (risk factor)
            if value >= 60 { return .optimal }
            if value >= 40 { return .borderline }
            return .high
        case .triglycerides:
            if value < 150 { return .optimal }
            if value < 200 { return .borderline }
            return .high
        case .totalCholesterol:
            if value < 200 { return .optimal }
            if value < 240 { return .borderline }
            return .high
        case .a1c:
            // <5.7 normal · 5.7–6.4 pre-diabetes · ≥6.5 diabetes
            if value < 5.7 { return .optimal }
            if value < 6.5 { return .borderline }
            return .high
        case .fastingGlucose:
            // <100 normal · 100–125 pre-diabetes · ≥126 diabetes
            if value < 100 { return .optimal }
            if value < 126 { return .borderline }
            return .high
        case .restingHR:
            // 60–80 healthy · 50–59 or 81–90 borderline · else flag
            if value >= 60 && value <= 80 { return .optimal }
            if value >= 50 && value <= 90 { return .borderline }
            return .high
        }
    }

    /// Convenience: worse of systolic/diastolic, for the composite BP card.
    public static func bpStatus(systolic: Double?, diastolic: Double?) -> RangeStatus {
        let s = systolic.map { status(for: .bpSystolic, value: $0) } ?? .unknown
        let d = diastolic.map { status(for: .bpDiastolic, value: $0) } ?? .unknown
        return worst(s, d)
    }

    private static func worst(_ a: RangeStatus, _ b: RangeStatus) -> RangeStatus {
        let rank: (RangeStatus) -> Int = {
            switch $0 {
            case .high:       return 3
            case .borderline: return 2
            case .optimal:    return 1
            case .unknown:    return 0
            }
        }
        return rank(a) >= rank(b) ? a : b
    }
}
