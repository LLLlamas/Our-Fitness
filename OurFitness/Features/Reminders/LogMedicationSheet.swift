// Fast-logging sheet for one medication: confirm the dosage, confirm the time,
// save. Reached from the medication card on the Reminders tab and from the
// detail sheet's "Log taken" button.
//
// The dosage field is PREFILLED with the medication's recommended dosage but
// writes to the event only (ReminderEventDTO.dosageTaken). Someone who takes
// one tablet where two are recommended records that fact on today's log without
// rewriting the medication's recommendation — see ReminderEventDTO's doc note.

import SwiftUI
import SwiftData

struct LogMedicationSheet: View {
    let profile: ProfileDTO
    let reminder: ReminderDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var dosageTaken: String
    @State private var takenAt = Date()
    @FocusState private var isEditing: Bool

    init(profile: ProfileDTO, reminder: ReminderDTO) {
        self.profile = profile
        self.reminder = reminder
        _dosageTaken = State(initialValue: reminder.dosage ?? "")
    }

    private var trimmedDosage: String { dosageTaken.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Log \(reminder.name)")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(theme.text)

                if let recommended = reminder.dosage, !recommended.isEmpty {
                    fieldBlock("RECOMMENDED") {
                        Text(recommended)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(theme.text)
                    }
                }

                fieldBlock("DOSAGE TAKEN") {
                    TextField("e.g. 1 tablet", text: $dosageTaken)
                        .focused($isEditing)
                        .padding(12)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                        .foregroundStyle(theme.text)
                }

                fieldBlock("TIME") {
                    // Bounded at `now`: a dose can be logged late, never ahead
                    // of itself — a future timestamp would also poison the
                    // MedicationPattern median.
                    DatePicker(
                        "Taken at", selection: $takenAt, in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    .foregroundStyle(theme.text)
                }

                Button {
                    save()
                } label: {
                    Text("Save log").frame(maxWidth: .infinity)
                }
                .tactile(.primary, fullWidth: true)
                .accessibilityLabel("Save log for \(reminder.name)")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium])
        .presentationBackground(theme.bg)
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }
            }
        }
    }

    private func save() {
        let when = takenAt
        guard ReminderNotificationService.logDone(
            ctx, reminderId: reminder.id, date: when,
            dosageTaken: trimmedDosage.isEmpty ? nil : trimmedDosage
        ) != nil else { return }
        Haptics.success()
        toasts.show(Toast(
            title: reminder.name,
            detail: "Logged at \(when.formatted(date: .omitted, time: .shortened))",
            accent: .win, symbol: "pills.fill"
        ))
        dismiss()
    }

    @ViewBuilder
    private func fieldBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            content()
        }
    }
}
