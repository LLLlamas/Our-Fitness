// App-side driver for the Live Sessions ActivityKit Live Activity.
//
// Starts / updates / ends the Lock Screen + Dynamic Island activity that mirrors
// an in-progress Live Session. This is purely additive: the Live Session itself
// (timestamp anchor in LiveSessionStore + local end-notification) works fully
// WITHOUT a Live Activity. Every call here is best-effort and must fail soft —
// if Live Activities are disabled, unsupported, or `request` throws, the session
// continues unaffected.
//
// Why no auth/entitlement: requesting a Live Activity needs NO user prompt and
// NO special entitlement. The app only needs `NSSupportsLiveActivities = YES` in
// Info.plist. We still check `ActivityAuthorizationInfo().areActivitiesEnabled`
// (the user can switch Live Activities off in Settings) and degrade silently.
//
// Runtime-gated: deployment target is iOS 17, but ActivityKit Live Activities
// need iOS 16.2+ — always true here, but we still guard with #available so the
// code is correct if the floor ever drops, and behind #if canImport(ActivityKit)
// so a platform without the framework compiles cleanly.

import Foundation

#if canImport(ActivityKit)
import ActivityKit

// NOTE: the app already declares `struct Activity` in Domain/ActivityCatalog.swift,
// which shadows ActivityKit's `Activity` inside this module. Every ActivityKit
// reference below is fully qualified as `ActivityKit.Activity` to disambiguate.

@available(iOS 16.2, *)
enum LiveSessionActivityController {

    /// Start (or replace) the Live Activity for a session. Safe to call from the
    /// Start tap; no-op when Live Activities are unavailable or disabled.
    static func start(activityName: String, symbol: String, startDate: Date, expectedMinutes: Int) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        // Only one live session exists at a time. Clear any stale activity (e.g.
        // a previous session whose end we missed) before requesting a new one.
        endAllSync()

        let attributes = LiveSessionAttributes(
            activityName: activityName,
            symbol: symbol,
            startDate: startDate
        )
        let state = LiveSessionAttributes.ContentState(expectedMinutes: expectedMinutes)

        do {
            _ = try ActivityKit.Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            // Disabled mid-flight, budget exhausted, etc. Session continues.
        }
    }

    /// Push a new expected length (±5 min) to the running activity so the target
    /// time on the Lock Screen / Dynamic Island re-renders. No-op if none active.
    static func update(expectedMinutes: Int) {
        Task {
            let state = LiveSessionAttributes.ContentState(expectedMinutes: expectedMinutes)
            for activity in ActivityKit.Activity<LiveSessionAttributes>.activities {
                await activity.update(.init(state: state, staleDate: nil))
            }
        }
    }

    /// End every live-session activity (session ended or finished). Async so the
    /// activity dismisses immediately rather than lingering on the Lock Screen.
    static func end() {
        Task {
            for activity in ActivityKit.Activity<LiveSessionAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Fire-and-forget end used before requesting a fresh activity, to guarantee
    /// at most one. Detached so it doesn't block the synchronous start path.
    private static func endAllSync() {
        Task {
            for activity in ActivityKit.Activity<LiveSessionAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
