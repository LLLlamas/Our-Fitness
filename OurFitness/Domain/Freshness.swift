// "As of …" freshness labels for point-in-time health readings.
//
// Pure Domain (Foundation only). Heart rate and other single-sample HealthKit
// reads carry their own sample timestamp; this turns that into an honest,
// absolute "as of 1:48 PM" string — but only once the reading is meaningfully
// stale, so a just-taken value isn't cluttered with a redundant timestamp.
//
// `now` is injectable for deterministic tests (never read the wall clock in
// time-sensitive Domain logic — see CLAUDE.md CI rules).

import Foundation

public enum Freshness {

    /// Default window under which a reading is treated as "now" and gets no label.
    public static let recentWindow: TimeInterval = 120  // 2 minutes

    /// An absolute "as of <time>" label for a sample, or nil when the sample is
    /// recent enough (within `staleAfter`) that a timestamp would just be noise.
    /// Same-day samples show the time; older samples include an abbreviated date.
    public static func label(
        for sampleDate: Date,
        now: Date = Date(),
        staleAfter: TimeInterval = recentWindow,
        calendar: Calendar = .current
    ) -> String? {
        // Future-dated or essentially-now samples: no label.
        guard now.timeIntervalSince(sampleDate) > staleAfter else { return nil }
        if calendar.isDate(sampleDate, inSameDayAs: now) {
            return "as of " + sampleDate.formatted(date: .omitted, time: .shortened)
        }
        return "as of " + sampleDate.formatted(date: .abbreviated, time: .shortened)
    }
}
