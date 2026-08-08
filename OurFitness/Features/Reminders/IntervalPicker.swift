// Cadence control for a reminder's repeat interval, shared by AddReminderSheet
// and ReminderDetailSheet so the two can't drift apart.
//
// The generic range is 1...365 days (ReminderSchedule), which a bare Stepper
// can't navigate — "yearly" would be 364 taps. So: one-tap preset pills for the
// cadences people actually pick, with the Stepper kept underneath for the
// in-between values (an air filter every 45 days matches no preset and is
// perfectly valid). Days remain the only stored value; a preset is just a
// shortcut to one.
//
// Plant watering deliberately does NOT use this — it stays on PlantCatalog's
// narrower 2...60 range, which its seeded-interval math is defined over.

import SwiftUI

struct IntervalPicker: View {
    @Binding var days: Int
    /// Fired after any change from either the pills or the stepper, so callers
    /// that commit-on-edit (the detail sheet) get one hook instead of two.
    var onChange: (() -> Void)?

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReminderSchedule.intervalPresets) { preset in
                        Button(preset.label) { select(preset.days) }
                            .tactile(.pill, fill: days == preset.days ? theme.accent : nil)
                    }
                }
            }

            Stepper(
                value: $days,
                in: ReminderSchedule.minIntervalDays...ReminderSchedule.maxIntervalDays
            ) {
                Text(ReminderSchedule.intervalLabel(days: days))
                    .foregroundStyle(theme.text)
                    .monospacedDigit()
            }
            // Observes the binding, so this covers stepper ticks AND pill taps
            // — one commit path rather than one per control.
            .onChange(of: days) { _, _ in onChange?() }
        }
    }

    private func select(_ value: Int) {
        guard days != value else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { days = value }
        Haptics.selection()
    }
}
