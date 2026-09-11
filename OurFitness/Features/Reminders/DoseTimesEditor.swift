// Editing the set dose times for one medication — a medication taken morning
// and night holds two, so this is a list rather than a single picker.
//
// Shared by the add form and the detail sheet so both offer exactly the same
// control. Deliberately does NOT sort as you type: re-sorting on every tick of
// a time picker moves the row out from under the user's finger. Normalising
// (clamp, de-duplicate, sort) happens once at the save boundary, through
// `MedicationPattern.normalizedTimes`.

import SwiftUI

struct DoseTimesEditor: View {
    @Binding var minutes: [Int]
    /// Called after any edit that changed the list. The detail sheet commits
    /// immediately on change like its other non-text controls; the add form
    /// leaves it as the default no-op and saves with the rest of the form.
    var onChange: () -> Void = {}

    @Environment(\.theme) private var theme

    /// Where a first time opens, and what "add another" offers when it can't
    /// infer anything better — 8:00 AM, so the common case is one tap.
    static let defaultMinute = 8 * 60

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if minutes.isEmpty {
                emptyState
            } else {
                ForEach(Array(minutes.enumerated()), id: \.offset) { index, _ in
                    timeRow(index)
                }
                addButton(title: "Add another time")
            }

            Text(minutes.isEmpty
                 ? "Optional. Without one, timings come from when you actually log this."
                 : "A reminder fires at each time, every day. Your history reads each dose against the closest one.")
                .font(.caption2).foregroundStyle(theme.dim)
        }
        .padding(14)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    private var emptyState: some View {
        addButton(title: "Set a time to take this")
    }

    private func addButton(title: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                minutes.append(nextSuggestedMinute())
            }
            Haptics.selection()
            onChange()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text(title)
            }
        }
        .tactile(.ghost)
    }

    @ViewBuilder
    private func timeRow(_ index: Int) -> some View {
        HStack(spacing: 12) {
            DatePicker(
                "Dose time", selection: timeBinding(index), displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()
            .foregroundStyle(theme.text)

            Spacer(minLength: 0)

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    guard minutes.indices.contains(index) else { return }
                    minutes.remove(at: index)
                }
                Haptics.warn()
                onChange()
            } label: {
                Image(systemName: "minus.circle")
            }
            .tactile(.ghost)
            .accessibilityLabel("Remove this dose time")
        }
    }

    /// Guards the index on both sides: a removal can re-render a row before its
    /// binding is torn down, and an out-of-range read would trap.
    private func timeBinding(_ index: Int) -> Binding<Date> {
        Binding(
            get: {
                let minute = minutes.indices.contains(index) ? minutes[index] : Self.defaultMinute
                return MedicationPattern.date(minuteOfDay: minute, on: Date(), calendar: .current) ?? Date()
            },
            set: { newValue in
                guard minutes.indices.contains(index) else { return }
                minutes[index] = MedicationPattern.minuteOfDay(of: newValue, calendar: .current)
                onChange()
            }
        )
    }

    /// 8:00 AM for the first time; twelve hours after the latest one after that,
    /// which lands a second dose on a morning/evening split without scrolling.
    private func nextSuggestedMinute() -> Int {
        guard let latest = minutes.max() else { return Self.defaultMinute }
        return MedicationPattern.clampMinuteOfDay((latest + 12 * 60) % MedicationPattern.minutesPerDay)
    }
}
