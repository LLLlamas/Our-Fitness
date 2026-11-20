// The optional "Felt dizzy" flag on a finished session (cardio plan §10, Q2).
//
// It records, never advises: no warning, no gate, no medical wording here —
// the one calm dizziness line lives in the VO₂ max ⓘ (plan §1 rule 2).
// Heart rate is stored only when Apple Health has real samples for a real
// session window; nothing is ever estimated. Pure Foundation so the mapping and
// the "which sessions get heart rate and a Health write" decision are hostless-tested.

import Foundation

public enum DizzinessSeverity: String, Codable, CaseIterable, Sendable {
    case mild, moderate, severe

    public var label: String {
        switch self {
        case .mild: return "Mild"
        case .moderate: return "Moderate"
        case .severe: return "Severe"
        }
    }
}

/// Present on a session only when the user flagged it. Severity is optional;
/// heart rate is nil unless Health returned samples for a live session's window.
public struct DizzinessReport: Codable, Equatable, Sendable {
    public var severity: DizzinessSeverity?
    public var averageHeartRateBpm: Double?
    public var peakHeartRateBpm: Double?

    public init(severity: DizzinessSeverity? = nil,
                averageHeartRateBpm: Double? = nil,
                peakHeartRateBpm: Double? = nil) {
        self.severity = severity
        self.averageHeartRateBpm = averageHeartRateBpm
        self.peakHeartRateBpm = peakHeartRateBpm
    }
}

public enum SessionDizziness {
    /// Where a session's times came from. A live session has a real start/end;
    /// a session logged after the fact is stamped at log time, so it has none.
    public enum Origin: Equatable, Sendable {
        case live(start: Date, end: Date)
        case loggedAfter
    }

    /// Mirrors Apple's `HKCategoryValueSeverity` cases used for the Dizziness
    /// symptom. Kept framework-free; `HealthKitService` maps it with an
    /// exhaustive switch.
    public enum HealthSeverity: Equatable, Sendable {
        case unspecified, mild, moderate, severe
    }

    public static func healthSeverity(_ severity: DizzinessSeverity?) -> HealthSeverity {
        switch severity {
        case .none: return .unspecified
        case .mild?: return .mild
        case .moderate?: return .moderate
        case .severe?: return .severe
        }
    }

    /// The window to read heart rate over and to stamp the Health symptom with,
    /// or nil for "neither": not flagged, logged after the fact (a fake time must
    /// not reach Health), or a live window with no length.
    public static func healthWindow(flagged: Bool, origin: Origin) -> DateInterval? {
        guard flagged, case let .live(start, end) = origin, end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Both values or neither: a statistics result with no samples has no
    /// average and no peak, and a half-filled pair would read as made up.
    public static func heartRate(average: Double?, peak: Double?) -> (average: Double, peak: Double)? {
        guard let average, let peak, average.isFinite, peak.isFinite, average > 0, peak > 0 else { return nil }
        return (average, peak)
    }

    public static let noHeartRateText = "No heart-rate data"

    /// The one history line: "Felt dizzy · Moderate · Heart rate: average 128, peak 151"
    /// or "Felt dizzy · No heart-rate data". Neutral, no advice.
    public static func summary(_ report: DizzinessReport) -> String {
        var parts = ["Felt dizzy"]
        if let severity = report.severity { parts.append(severity.label) }
        if let hr = heartRate(average: report.averageHeartRateBpm, peak: report.peakHeartRateBpm) {
            parts.append("Heart rate: average \(Int(hr.average.rounded())), peak \(Int(hr.peak.rounded()))")
        } else {
            parts.append(noHeartRateText)
        }
        return parts.joined(separator: " · ")
    }
}
