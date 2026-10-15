// Shared streak chip — the one streak pill in the app.
//
// Used by the Steps and Pilates cards for weekly streaks
// and by the Water card for a daily streak; `unit` picks the wording. Renders
// nothing when `count <= 0` so callers can drop it in unconditionally (callers
// with a higher bar, e.g. "only brag from 2 days", still gate themselves).
//
// Tint is caller-supplied (theme.accent for steps/water, theme.accent2 for
// Pilates) so the chip reads as "this card's win" without inventing a third
// color slot.

import SwiftUI

public struct StreakChip: View {

    /// What the number counts. Drives the terse suffix and the spoken label.
    public enum Unit: Sendable {
        case days
        case weeks

        /// Terse suffix for the chip itself ("7d streak" / "3w streak").
        var suffix: String {
            switch self {
            case .days:  return "d"
            case .weeks: return "w"
            }
        }

        /// Spelled-out noun for VoiceOver.
        var spokenNoun: String {
            switch self {
            case .days:  return "day"
            case .weeks: return "week"
            }
        }
    }

    public let count: Int
    public let unit: Unit
    public let tint: Color

    public init(count: Int, unit: Unit, tint: Color) {
        self.count = count
        self.unit = unit
        self.tint = tint
    }

    /// Weekly streak (Steps & Cardio, Pilates).
    public init(weeks: Int, tint: Color) {
        self.init(count: weeks, unit: .weeks, tint: tint)
    }

    /// Daily streak (water, meal logging).
    public init(days: Int, tint: Color) {
        self.init(count: days, unit: .days, tint: tint)
    }

    public var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").font(.caption2)
                Text("\(count)\(unit.suffix) streak")
                    .font(.system(size: 10, weight: .medium)).tracking(2)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(tint)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1))
            .accessibilityElement()
            .accessibilityLabel("\(count) \(unit.spokenNoun) streak")
        }
    }
}
