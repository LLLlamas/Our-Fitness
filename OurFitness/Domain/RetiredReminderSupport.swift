// What survives of the removed Reminders feature (plants, reminders,
// medication) — see docs/removed-reminders.md.
//
// The Reminder* DTOs in Models.swift and the Reminder* @Model classes in
// PersistenceModels.swift are kept so existing installs keep their stored
// rows. These two small types are the only things those retained declarations
// still reference. Delete this file in the same change that removes them
// (which needs a Schema.swift version bump + migration stage).

import Foundation

/// Raw values are persisted (`ReminderModel.lightRaw`) — do not change them.
public enum PlantLightLevel: String, Codable, CaseIterable, Sendable {
    case bright, medium, low

    public var label: String {
        switch self {
        case .bright: return "Bright indirect"
        case .medium: return "Medium light"
        case .low:    return "Low light"
        }
    }
}

/// Only `ReminderDTO.init` still calls into this (to clamp/sort stored dose
/// times). The scheduling, pattern-inference and timing-label code is gone;
/// recover it from git history at/after d284700.
public enum MedicationPattern {
    public static let minutesPerDay = 24 * 60

    /// Valid range for a stored minute-of-day.
    public static func clampMinuteOfDay(_ minute: Int) -> Int {
        min(max(minute, 0), minutesPerDay - 1)
    }

    /// Clamped, de-duplicated and sorted.
    public static func normalizedTimes(_ times: [Int]) -> [Int] {
        Array(Set(times.map(clampMinuteOfDay))).sorted()
    }
}
