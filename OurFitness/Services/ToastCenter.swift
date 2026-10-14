// Lightweight one-toast-at-a-time confirmation system.
// Inject at the app root via .environmentObject; views call ToastCenter.show(...).
// Fires a matching haptic so feedback is multisensory: visible + felt at the same time.
//
// IMPORTANT: `show` already fires the outcome haptic (see `fireHaptic`). Call sites
// must NOT call `Haptics.*` for the same outcome right before showing a toast —
// that's two haptics for one action. Press-feedback haptics (`.tactile(...)`,
// scroll ticks) are a different thing and stay.

import SwiftUI

public enum ToastAccent: Sendable {
    case ok        // logged a meal, hit a target, friendly action
    case win       // PR beaten, daily goal completed — the big ones
    case warn      // destructive confirm, cap breach
    case info      // neutral update
}

public struct Toast: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let detail: String?
    public let accent: ToastAccent
    public let symbol: String?     // SF Symbol name

    public init(id: UUID = UUID(), title: String, detail: String? = nil,
                accent: ToastAccent = .ok, symbol: String? = nil) {
        self.id = id; self.title = title; self.detail = detail
        self.accent = accent; self.symbol = symbol
    }
}

extension Toast {
    public static var healthConnected: Toast {
        Toast(title: "Apple Health connected",
              detail: "Steps will sync automatically.",
              accent: .ok, symbol: "heart.fill")
    }

    public static func healthConnectFailed(_ reason: String) -> Toast {
        Toast(title: "Couldn't connect Apple Health",
              detail: reason,
              accent: .warn, symbol: "exclamationmark.triangle.fill")
    }
}

@MainActor
public final class ToastCenter: ObservableObject {
    @Published public private(set) var current: Toast?

    private var dismissTask: Task<Void, Never>?

    public init() {}

    /// Show a toast. Replaces any current toast. Auto-dismisses after `seconds`.
    public func show(_ toast: Toast, for seconds: Double = 1.8) {
        dismissTask?.cancel()
        current = toast
        fireHaptic(for: toast.accent)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            if !Task.isCancelled {
                await MainActor.run { self?.current = nil }
            }
        }
    }

    /// Show an `EncouragementMessage`. The engine owns the copy; the caller picks
    /// the accent (which also picks the haptic) and how long it lingers.
    ///
    /// Every encouragement wrapper below is a one-liner over this — add a wrapper
    /// only when it needs to call the engine itself or gate on a nil message.
    public func show(_ msg: EncouragementMessage, accent: ToastAccent, for seconds: Double = 2.4) {
        show(Toast(title: msg.headline, detail: msg.detail,
                   accent: accent, symbol: msg.sfSymbol), for: seconds)
    }

    // Convenience constructors

    public func logged(_ name: String, calories: Int) {
        show(Toast(title: "Logged", detail: "\(name) · +\(calories) cal",
                   accent: .ok, symbol: "checkmark"))
    }

    // MERGE: kept from feature/reminders-plants — PilatesCard (Circuit) calls this.
    public func pilatesLogged(minutes: Int) {
        show(Toast(title: "Pilates logged",
                   detail: "\(minutes) min · locked in.",
                   accent: .ok, symbol: "checkmark"))
    }

    // Encouragement-engine driven toasts (Phase 1). All of these are thin wrappers
    // over `show(_:accent:for:)` — they exist because they either call the engine
    // themselves, gate on a nil message, or pick the accent from the message tone.

    // Step milestone — mode-aware copy from EncouragementEngine
    public func stepMilestone(_ steps: Int, mode: Mode) {
        show(EncouragementEngine.stepMilestoneMessage(steps: steps, mode: mode), accent: .win)
    }

    // Workout volume milestone — accent follows the message's tone
    public func workoutMilestone(_ msg: EncouragementMessage) {
        show(msg, accent: msg.tone == .impressed ? .win : .ok)
    }

    // Meal-logging streak milestone — self-gating: only shows at a milestone day.
    public func mealStreak(days: Int, mode: Mode) {
        guard let msg = EncouragementEngine.mealStreakMessage(days: days, mode: mode) else { return }
        show(msg, accent: .win, for: 3.0)
    }

    // Macro goal hit
    public func macroGoalHit(_ msg: EncouragementMessage) {
        show(msg, accent: .win)
    }

    // Macro approaching (lighter — .ok not .win)
    public func macroApproaching(_ msg: EncouragementMessage) {
        show(msg, accent: .ok, for: 2.0)
    }

    // Time-based nudge toasts — fired from TodayView's periodic timer.
    // Each method calls the engine and only shows a toast when the engine
    // returns a non-nil message (avoids spamming during quiet periods).

    public func mealNudge(mealsLoggedToday: Int, hourOfDay: Int, mode: Mode) {
        guard let msg = EncouragementEngine.mealLoggingNudge(
            mealsLoggedToday: mealsLoggedToday,
            hourOfDay: hourOfDay,
            mode: mode
        ) else { return }
        show(msg, accent: .info)
    }

    public func waterReminder(currentOz: Double, goalOz: Double, hourOfDay: Int) {
        guard let msg = EncouragementEngine.waterNudge(
            currentOz: currentOz,
            goalOz: goalOz,
            hourOfDay: hourOfDay
        ) else { return }
        show(msg, accent: .info)
    }

    // Stall nudge — a once-per-day "keep going" prompt when the user has gone quiet
    // on steps / workouts / Pilates, or a tracked number has flatlined.
    public func stallNudge(_ msg: EncouragementMessage) {
        show(msg, accent: .info, for: 3.0)
    }

    public func warn(_ msg: String) {
        show(Toast(title: msg, accent: .warn, symbol: "exclamationmark.triangle.fill"))
    }

    private func fireHaptic(for accent: ToastAccent) {
        switch accent {
        case .ok:    Haptics.bump()
        case .win:   Haptics.success()
        case .warn:  Haptics.warn()
        case .info:  Haptics.tap()
        }
    }
}
