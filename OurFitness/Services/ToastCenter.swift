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

    public func stepsMilestone(_ steps: Int) {
        let kLabel = steps >= 1_000 ? "\(steps / 1_000)k" : "\(steps)"
        show(Toast(title: "\(kLabel) steps", detail: "Keep moving — momentum compounds.",
                   accent: .win, symbol: "figure.walk"), for: 2.0)
    }

    public func pilatesLogged(minutes: Int) {
        show(Toast(title: "Pilates logged",
                   detail: "\(minutes) min · locked in.",
                   accent: .ok, symbol: "checkmark"))
    }

    public func pr(_ exercise: String, weightLb: Double?, reps: Int) {
        let line = weightLb.map { "\(Int($0)) lb × \(reps)" } ?? "\(reps) reps"
        show(Toast(title: "New PR · \(exercise)", detail: line,
                   accent: .win, symbol: "trophy.fill"), for: 2.6)
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
