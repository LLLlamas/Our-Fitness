// The in-progress Live Session — a pure value type so the elapsed-time math is
// unit-testable in the hostless Domain test target.
//
// A Live Session is timestamp-anchored, NOT a running timer: iOS suspends a
// backgrounded app, so we never keep a clock ticking. We persist only the
// immutable `startDate` anchor + the plan; elapsed time is ALWAYS recomputed as
// now − startDate. This makes the session correctly survive app-switching,
// backgrounding, and a full app kill + relaunch. Persistence (UserDefaults) and
// the local end-notification live in Services/LiveSessionService.swift — Domain
// stays framework-free.

import Foundation

public struct LiveSessionState: Codable, Equatable, Sendable {
    public var startDate: Date
    public var activityId: String
    public var activityName: String
    public var met: Double
    public var expectedMinutes: Int
    public var profileId: UUID

    public init(startDate: Date = Date(), activityId: String, activityName: String,
                met: Double, expectedMinutes: Int, profileId: UUID) {
        self.startDate = startDate
        self.activityId = activityId
        self.activityName = activityName
        self.met = met
        self.expectedMinutes = expectedMinutes
        self.profileId = profileId
    }

    /// Seconds elapsed since the session started, derived from the anchor.
    public func elapsedSeconds(now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(startDate)))
    }
}
