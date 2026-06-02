// Shared ActivityKit attributes for the Live Sessions Live Activity.
//
// Compiled into BOTH the OurFitness app target (to start/update/end the
// activity) AND the OurFitnessWidgets extension target (to render it). It is the
// ONE file in both targets' `sources:` in project.yml — keep it tiny and
// framework-light so duplicating it across targets stays cheap.
//
// Not in Domain/: Domain must stay free of any non-Foundation framework, and
// `ActivityAttributes` is an ActivityKit type. The whole file is gated behind
// `canImport(ActivityKit)` so a target/platform without ActivityKit (or an older
// SDK) simply compiles nothing here rather than failing.
//
// Timestamp-anchored, like the rest of Live Sessions: the widget renders the
// timer with `Text(timerInterval:)`, which the SYSTEM advances on its own clock
// without waking the app. The attributes therefore carry only the immutable plan
// (start anchor + expected length + label/icon). There is no per-second state to
// push — ContentState stays effectively empty (a single nonce we bump only when
// the expected end shifts via ±5 min, so an update re-renders the target time).

#if canImport(ActivityKit)
import ActivityKit
import Foundation

@available(iOS 16.2, *)
public struct LiveSessionAttributes: ActivityAttributes {
    /// Per-update state. The timer is interval-driven (system-side), so there is
    /// no live elapsed value here. `expectedMinutes` lives in state (not the
    /// static attributes) so a ±5 min adjustment can be pushed via
    /// `Activity.update(...)` without ending and re-requesting the activity.
    public struct ContentState: Codable, Hashable {
        public var expectedMinutes: Int

        public init(expectedMinutes: Int) {
            self.expectedMinutes = expectedMinutes
        }
    }

    /// Immutable for the life of the activity.
    public var activityName: String
    public var symbol: String      // SF Symbol name, mirrors Activity.symbol
    public var startDate: Date

    public init(activityName: String, symbol: String, startDate: Date) {
        self.activityName = activityName
        self.symbol = symbol
        self.startDate = startDate
    }

    /// The instant the plan is reached, derived from the start anchor + the
    /// current expected length. Drives `Text(timerInterval: startDate...end)`.
    public func expectedEnd(expectedMinutes: Int) -> Date {
        startDate.addingTimeInterval(Double(expectedMinutes) * 60)
    }
}
#endif
