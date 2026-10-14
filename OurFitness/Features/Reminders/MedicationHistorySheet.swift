// The full medication record: every dose ever logged, across every medication,
// newest day first.
//
// The per-medication history on ReminderDetailSheet answers "how has THIS one
// been going". This sheet answers the other question — "what did I take, and
// when" — which is the one asked at a doctor's appointment, and which no
// per-medication view can answer without opening each medication in turn.
//
// Deliberately uncapped. Both lists it replaces the need for are complete:
// nothing here truncates to a recent window, because a medication record that
// silently stops reads as "that's all there was". LazyVStack keeps the cost to
// the rows actually on screen.

import SwiftUI
import SwiftData

struct MedicationHistorySheet: View {
    let profile: ProfileDTO
    /// The medication group's reminders, passed in from the Reminders tab,
    /// which already has them queried. Doubles as the join table: an event
    /// whose reminder isn't in here isn't a medication and drops out.
    let medications: [ReminderDTO]

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Per-profile scoped in the predicate — never a client-side filter.
    /// Unscoped by reminder on purpose: this is the cross-medication view.
    @Query private var eventModels: [ReminderEventModel]

    /// nil = every medication. Kept as an id rather than a DTO so a rename or
    /// edit behind the sheet can't strand the selection.
    @State private var focusedId: UUID?

    init(profile: ProfileDTO, medications: [ReminderDTO]) {
        self.profile = profile
        self.medications = medications
        let uid = profile.id
        _eventModels = Query(
            filter: #Predicate<ReminderEventModel> { $0.userId == uid },
            sort: \.timestamp, order: .reverse
        )
    }

    private var entries: [MedicationLogEntry] {
        let all = MedicationHistory.entries(events: eventModels.map(\.snapshot), medications: medications)
        guard let focusedId else { return all }
        return all.filter { $0.reminderId == focusedId }
    }

    private var days: [MedicationLogDay] {
        MedicationHistory.byDay(entries, calendar: .current)
    }

    var body: some View {
        // Once per pass: `days` runs the whole join+group pipeline over an
        // unbounded event query, and this is the surface that deliberately
        // carries the full record.
        let days = self.days
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                header(days: days)

                if medications.count > 1 { filterChips }

                if days.isEmpty {
                    Text(focusedId == nil
                         ? "No doses logged yet. Every dose you log lands here, with the day and time."
                         : "No doses logged for this medication yet.")
                        .font(.callout).foregroundStyle(theme.dim)
                        .padding(.top, 8)
                } else {
                    ForEach(days) { day in
                        daySection(day)
                    }
                }

                footerNote
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private func header(days: [MedicationLogDay]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Medication history")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(theme.text)
            Text(totalsLine(days: days))
                .font(.caption).foregroundStyle(theme.dim)
        }
    }

    /// "142 doses logged across 37 days". Counted off the same grouped days the
    /// list renders, so the two can never disagree.
    private func totalsLine(days: [MedicationLogDay]) -> String {
        let t = MedicationHistory.totals(days)
        guard t.doses > 0 else { return "Nothing logged yet" }
        return "\(t.doses) dose\(t.doses == 1 ? "" : "s") logged across \(t.days) day\(t.days == 1 ? "" : "s")"
    }

    // MARK: - Filter

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", selected: focusedId == nil) { focusedId = nil }
                ForEach(medications) { med in
                    chip(title: med.name, selected: focusedId == med.id) { focusedId = med.id }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { action() }
            Haptics.selection()
        }
        .tactile(.pill, fill: selected ? theme.accent : nil)
    }

    // MARK: - A day

    @ViewBuilder
    private func daySection(_ day: MedicationLogDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(MedicationHistory.dayTitle(day.id, now: Date(), calendar: .current))
                    .font(.system(size: 10, weight: .medium)).tracking(2)
                    .foregroundStyle(theme.dim)
                Spacer()
                Text(dayCountLabel(day))
                    .font(.caption2).foregroundStyle(theme.dim)
            }
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().overlay(theme.line)
                        }
                        row(entry)
                    }
                }
            }
        }
    }

    /// Doses, plus how many distinct medications they span — "3 doses" alone
    /// reads as three of the same thing on a multi-medication day.
    private func dayCountLabel(_ day: MedicationLogDay) -> String {
        let doses = "\(day.doseCount) dose\(day.doseCount == 1 ? "" : "s")"
        guard focusedId == nil, day.medicationCount > 1 else { return doses }
        return "\(doses) · \(day.medicationCount) medications"
    }

    /// Time first and monospaced: a day's rows are read as a column of times,
    /// and proportional digits make that column ragged.
    private func row(_ entry: MedicationLogEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .frame(width: 72, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.medicationName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                if let taken = entry.dosageTaken, !taken.isEmpty {
                    Text(taken)
                        .font(.caption2).foregroundStyle(theme.dim)
                }
                if let timing = MedicationHistory.timingLabel(entry, calendar: .current) {
                    Text(timing)
                        .font(.caption2).foregroundStyle(theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footerNote: some View {
        Text("OurFitness helps you track what you log. It does not replace medication instructions from your doctor, pharmacist, or medication label.")
            .font(.caption2)
            .foregroundStyle(theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}
