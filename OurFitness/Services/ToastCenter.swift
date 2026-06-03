// Lightweight one-toast-at-a-time confirmation system.
// Inject at the app root via .environmentObject; views call ToastCenter.show(...).
// Fires a matching haptic so feedback is multisensory: visible + felt at the same time.

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

    // Convenience constructors

    public func logged(_ name: String, calories: Int) {
        show(Toast(title: "Logged", detail: "\(name) · +\(calories) cal",
                   accent: .ok, symbol: "checkmark"))
    }

    public func goalHit(_ label: String) {
        show(Toast(title: "\(label) hit", detail: "Nice work — keep stacking.",
                   accent: .win, symbol: "flame.fill"), for: 2.4)
    }

    public func pilatesLogged(minutes: Int) {
        show(Toast(title: "Pilates logged",
                   detail: "\(minutes) min · locked in.",
                   accent: .ok, symbol: "checkmark"))
    }

    // Encouragement-engine driven toasts (Phase 1). The engine owns the copy;
    // these map a message's tone to the toast accent + duration.

    // Step milestone — mode-aware copy from EncouragementEngine
    public func stepMilestone(_ steps: Int, mode: Mode) {
        let msg = EncouragementEngine.stepMilestoneMessage(steps: steps, mode: mode)
        show(Toast(title: msg.headline, detail: msg.detail,
                   accent: .win, symbol: msg.sfSymbol), for: 2.4)
    }

    // Workout volume milestone
    public func workoutMilestone(_ msg: EncouragementMessage) {
        show(Toast(title: msg.headline, detail: msg.detail,
                   accent: msg.tone == .impressed ? .win : .ok,
                   symbol: msg.sfSymbol), for: 2.4)
    }

    // Pilates weekly goal
    public func pilatesGoalHit(_ msg: EncouragementMessage) {
        show(Toast(title: msg.headline, detail: msg.detail,
                   accent: .win, symbol: msg.sfSymbol), for: 2.4)
    }

    // Streak milestone
    public func streakMilestone(_ msg: EncouragementMessage) {
        show(Toast(title: msg.headline, detail: msg.detail,
                   accent: .win, symbol: msg.sfSymbol), for: 3.0)
    }

    // Macro goal hit
    public func macroGoalHit(_ msg: EncouragementMessage) {
        show(Toast(title: msg.headline, detail: msg.detail,
                   accent: .win, symbol: msg.sfSymbol), for: 2.4)
    }

    // Macro approaching (lighter — .ok not .win)
    public func macroApproaching(_ msg: EncouragementMessage) {
        show(Toast(title: msg.headline, detail: msg.detail,
                   accent: .ok, symbol: msg.sfSymbol), for: 2.0)
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
        show(Toast(title: msg.headline, detail: msg.detail,
                   accent: .info, symbol: msg.sfSymbol), for: 2.4)
    }

    public func waterReminder(currentOz: Double, goalOz: Double, hourOfDay: Int) {
        guard let msg = EncouragementEngine.waterNudge(
            currentOz: currentOz,
            goalOz: goalOz,
            hourOfDay: hourOfDay
        ) else { return }
        show(Toast(title: msg.headline, detail: msg.detail,
                   accent: .info, symbol: msg.sfSymbol), for: 2.4)
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
