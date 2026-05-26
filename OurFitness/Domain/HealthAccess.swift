// Pure decisions about HealthKit access, surfaced to UI as a single source of truth.
// Lives in Domain so it stays testable without importing HealthKit.

import Foundation

public enum HealthAccess {

    /// Whether the "Connect Apple Health" CTA should appear for this profile.
    /// True when the user hasn't yet completed the system permission sheet.
    public static func shouldPromptConnect(healthGranted: Bool) -> Bool {
        !healthGranted
    }

    /// One-line status copy for the Today banner and Settings row.
    public static func statusLabel(healthGranted: Bool) -> String {
        healthGranted
            ? "Connected to Apple Health"
            : "Connect Apple Health to track steps automatically"
    }
}
