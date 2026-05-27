// Shared weekly-streak chip used by Reset Train cards (Steps & Cardio, Pilates).
// Renders nothing when `weeks <= 0` so callers can drop it in unconditionally.
//
// Tint is caller-supplied (theme.accent for steps, theme.accent2 for Pilates)
// so the chip reads as "this card's win" without inventing a third color slot.

import SwiftUI

public struct StreakChip: View {
    public let weeks: Int
    public let tint: Color

    public init(weeks: Int, tint: Color) {
        self.weeks = weeks
        self.tint = tint
    }

    public var body: some View {
        if weeks > 0 {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").font(.caption2)
                Text("\(weeks)w streak")
                    .font(.system(size: 10, weight: .medium)).tracking(2)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(tint)
            .overlay(Rectangle().stroke(tint.opacity(0.6), lineWidth: 1))
        }
    }
}
