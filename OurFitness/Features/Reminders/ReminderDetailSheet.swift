// Reminder detail / edit sheet: photo, due-date stats, plant care card (when
// speciesId resolves to a catalog entry), watering/interval editing, history,
// snooze, and delete.
//
// Medication swaps the interval half of this sheet out entirely: recommended
// dosage instead of REPEATS, an observed timing pattern instead of a due date,
// per-dose history rows, and no snooze (there's no scheduled due day to push).
// Its kind comes in from the caller — ReminderDTO has `isPlant` but
// deliberately no `isMedication`, so the group is the only source of truth.
//
// Field edits commit immediately (Stepper/Picker/pot pills on change, text
// fields on submit or on losing focus) rather than behind a separate "Save"
// button — each commit calls Repos.updateReminder + reschedule + pushSnapshot
// together, same as every other mutation in this feature.

import SwiftUI
import SwiftData
import UIKit

struct ReminderDetailSheet: View {
    let profile: ProfileDTO
    let groupKind: ReminderGroupKind

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    // Per-profile AND per-reminder scoped — never a client-side .filter.
    @Query private var eventModels: [ReminderEventModel]

    @State private var reminder: ReminderDTO
    @State private var name: String
    @State private var room: String
    @State private var intervalDays: Int
    @State private var amountFlOz: Double
    @State private var notes: String
    @State private var light: PlantLightLevel
    @State private var potDiameter: Int
    @State private var dosage: String
    @State private var patternReminderEnabled: Bool
    @State private var doseTimes: [Int]

    @State private var showImagePicker = false
    @State private var showDeleteConfirm = false
    @State private var showCareSheet = false
    @State private var showLogSheet = false
    @State private var showFullHistory = false
    @FocusState private var isEditing: Bool

    init(profile: ProfileDTO, reminder: ReminderDTO, groupKind: ReminderGroupKind) {
        self.profile = profile
        self.groupKind = groupKind
        _reminder = State(initialValue: reminder)
        _name = State(initialValue: reminder.name)
        _room = State(initialValue: reminder.room ?? "")
        _intervalDays = State(initialValue: reminder.intervalDays)
        _amountFlOz = State(initialValue: reminder.amountFlOz ?? 0)
        _notes = State(initialValue: reminder.notes ?? "")
        _light = State(initialValue: reminder.light ?? .bright)
        _potDiameter = State(initialValue: reminder.potDiameterInches ?? 6)
        _dosage = State(initialValue: reminder.dosage ?? "")
        _patternReminderEnabled = State(initialValue: reminder.patternReminderEnabled ?? false)
        _doseTimes = State(initialValue: reminder.scheduledMinutesOfDay)

        let uid = profile.id
        let rid = reminder.id
        _eventModels = Query(
            filter: #Predicate<ReminderEventModel> { $0.userId == uid && $0.reminderId == rid },
            sort: \.timestamp, order: .reverse
        )
    }

    private var events: [ReminderEventDTO] { eventModels.map(\.snapshot) }
    private var lastDone: Date? { events.first?.timestamp }

    private var isMedication: Bool { groupKind == .medication }

    /// Only resolves for a catalog-matched species — a "custom plant" (whose
    /// speciesId is PlantCatalog.customId) legitimately has no research entry.
    private var species: PlantSpecies? {
        reminder.speciesId.flatMap { PlantCatalog.species(id: $0) }
    }

    /// Synthetic species used only to recompute suggested interval/amount for
    /// a custom (non-cataloged) plant, so "Reset to suggested" works the same
    /// way regardless of provenance.
    private var syntheticSpeciesForMath: PlantSpecies? {
        guard reminder.isPlant, species == nil else { return nil }
        return PlantCatalog.customSpecies(named: reminder.name)
    }

    private var dueDay: Date {
        ReminderSchedule.nextDueDay(
            lastDone: lastDone, createdAt: reminder.createdAt,
            intervalDays: reminder.intervalDays, snoozedUntil: reminder.snoozedUntil
        )
    }
    private var daysUntil: Int { ReminderSchedule.daysUntilDue(dueDay: dueDay) }
    private var isDue: Bool { ReminderSchedule.isDue(dueDay: dueDay) }

    private var dueLabel: String { ReminderSchedule.dueLabel(daysUntilDue: daysUntil) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.name)
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text(kicker)
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                // Medication is identified by name and dosage, not by sight —
                // its forms have no photo step, so there's nothing to show or
                // tap here.
                if !isMedication { photoHeader }
                statsCard

                if let species {
                    careCardButton(species)
                }

                if isMedication { logTakenButton }

                editableSection

                // Snooze pushes a due DAY — medication has none, so it's a
                // plant/custom-only control.
                if isDue && !isMedication { snoozeButton }

                historySection

                if isMedication { medicationFooterNote }

                deleteButton
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .presentationDragIndicator(.visible)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }
            }
        }
        .onChange(of: isEditing) { _, editing in
            if !editing { commitEdits() }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(onCapture: { img in updatePhoto(img) }, onCancel: { showImagePicker = false })
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showCareSheet) {
            if let species {
                PlantCareInfoSheet(species: species).themed(profile.mode)
            }
        }
        .sheet(isPresented: $showLogSheet) {
            LogMedicationSheet(profile: profile, reminder: reminder)
                .themed(profile.mode)
        }
        .sheet(isPresented: $showFullHistory) {
            // Scoped to this one medication: with a single entry in
            // `medications` the sheet's filter chips stay hidden and the join
            // narrows to it.
            MedicationHistorySheet(profile: profile, medications: [reminder])
                .themed(profile.mode)
        }
        .confirmationDialog(
            "Delete \(reminder.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible
        ) {
            Button("Delete reminder and its history", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Photo

    private var photoHeader: some View {
        Button { showImagePicker = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.card2)
                if let img = ReminderPhotoCache.image(id: reminder.id, data: reminder.photoData) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(theme.dim)
                }
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(theme.accent)
                            .background(Circle().fill(theme.bg))
                    }
                    Spacer()
                }
                .padding(10)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Change photo")
    }

    private func updatePhoto(_ img: UIImage) {
        showImagePicker = false
        guard let data = ImageDownscale.jpegData(img, maxDimension: 1024) else { return }
        ReminderPhotoCache.invalidate(id: reminder.id)
        var updated = reminder
        updated.photoData = data
        reminder = updated
        guard Repos.updateReminder(ctx, updated) else { return }
        WatchSyncService.shared.pushSnapshot(ctx, userId: updated.userId)
        Haptics.bump()
        toasts.show(Toast(title: "Photo updated", accent: .ok, symbol: "photo.fill"))
    }

    // MARK: - Stats

    private var kicker: String {
        if isMedication { return "MEDICATION" }
        return reminder.isPlant ? "PLANT REMINDER" : "REMINDER"
    }

    @ViewBuilder
    private var statsCard: some View {
        if isMedication {
            medicationStatsCard
        } else {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Last done").foregroundStyle(theme.dim)
                        Spacer()
                        Text(lastDone.map { Dates.formatRelative($0) } ?? "Never")
                            .foregroundStyle(theme.text).fontWeight(.medium)
                    }
                    HStack {
                        Text(isDue ? "Status" : "Next due").foregroundStyle(theme.dim)
                        Spacer()
                        Text(dueLabel)
                            .foregroundStyle(isDue ? theme.warn : theme.text)
                            .fontWeight(.semibold)
                    }
                }
                .font(.callout)
            }
        }
    }

    private var medicationStatsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Last logged").foregroundStyle(theme.dim)
                    Spacer()
                    Text(lastDone.map { Dates.formatRelative($0) } ?? "Never")
                        .foregroundStyle(theme.text).fontWeight(.medium)
                }
                if !reminder.scheduledMinutesOfDay.isEmpty {
                    HStack(alignment: .top) {
                        Text("Set for").foregroundStyle(theme.dim)
                        Spacer()
                        Text(MedicationPattern.clockList(reminder.scheduledMinutesOfDay))
                            .foregroundStyle(theme.text).fontWeight(.medium)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Text(patternLine)
                    .font(.caption).foregroundStyle(theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout)
        }
    }

    /// Describes what the LOG shows, never a prescription: "usually logged
    /// around", not "scheduled for". Stays quiet until MedicationPattern says
    /// there's enough history to claim a routine at all. This stays the OBSERVED
    /// timing even when a dose time is set — the set time has its own row above,
    /// and the value of showing both is seeing where they differ.
    private var patternLine: String {
        let now = Date()
        let calendar = Calendar.current
        let stamps = events.map(\.timestamp)
        guard MedicationPattern.hasDisplayablePattern(stamps, now: now, calendar: calendar),
              let minuteOfDay = MedicationPattern.typicalMinuteOfDay(stamps, now: now, calendar: calendar),
              // Set the wall-clock time rather than adding minutes to midnight:
              // on a DST day the elapsed-minutes form reads an hour off, the
              // same way it once did in MedicationPattern.fireInstant.
              let typical = calendar.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60,
                                          second: 0, of: now)
        else { return "Keep logging this medication to see your recent timing pattern." }
        return "Usually logged around \(typical.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: - Log a dose

    private var logTakenButton: some View {
        Button {
            showLogSheet = true
        } label: {
            HStack {
                Image(systemName: "pills.fill")
                Text("Log taken")
            }
            .frame(maxWidth: .infinity)
        }
        .tactile(.primary, fullWidth: true)
        .accessibilityLabel("Log a dose of \(reminder.name)")
    }

    private var medicationFooterNote: some View {
        Text("OurFitness helps you track what you log. It does not replace medication instructions from your doctor, pharmacist, or medication label.")
            .font(.caption2)
            .foregroundStyle(theme.dim)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Plant care

    @ViewBuilder
    private func careCardButton(_ species: PlantSpecies) -> some View {
        Button { showCareSheet = true } label: {
            HStack {
                Image(systemName: "leaf.fill").foregroundStyle(theme.accent)
                Text("Plant care & toxicity").foregroundStyle(theme.text)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(theme.dim)
            }
            .padding(14)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        }
        .tactile(.ghost)
    }

    // MARK: - Editable fields

    private var editableSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            fieldBlock("NAME") { styledField("Name", text: $name) }

            if isMedication {
                fieldBlock("RECOMMENDED DOSAGE") {
                    styledField("e.g. 1 tablet, 10 mg, 5 mL", text: $dosage)
                }

                fieldBlock("TIMES") {
                    DoseTimesEditor(minutes: $doseTimes, onChange: {
                        commitEdits()
                        // Adding a time switches the nudge on (see commitEdits),
                        // so this is the same explicit moment as the toggle.
                        if !doseTimes.isEmpty { requestAuthorizationThenSync() }
                    })
                }

                fieldBlock("NOTES") { styledField("Any details", text: $notes) }

                patternReminderToggle
            } else if reminder.isPlant {
                fieldBlock("ROOM") { styledField("Room", text: $room) }

                fieldBlock("LIGHT") {
                    Picker("Light", selection: $light) {
                        ForEach(PlantLightLevel.allCases, id: \.self) { l in Text(l.label).tag(l) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: light) { _, _ in commitEdits() }
                }

                fieldBlock("POT SIZE") {
                    HStack(spacing: 8) {
                        ForEach(PlantCatalog.potDiameterOptions, id: \.self) { d in
                            Button("\(d)\"") {
                                potDiameter = d
                                Haptics.selection()
                                commitEdits()
                            }
                            .tactile(.pill, fill: potDiameter == d ? theme.accent : nil)
                        }
                    }
                }

                wateringBlock
            } else {
                fieldBlock("REPEATS") {
                    // The picker's own label already reads "Daily"/"Every 5
                    // days", and its onChange covers both pills and stepper
                    // ticks — so no second .onChange here (that would
                    // double-commit).
                    IntervalPicker(days: $intervalDays, onChange: { commitEdits() })
                }

                fieldBlock("NOTES") { styledField("Any details", text: $notes) }
            }
        }
    }

    /// Same opt-in toggle as the add sheet, committing on change like every
    /// other non-text control here.
    private var patternReminderToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $patternReminderEnabled) {
                Text(doseTimes.isEmpty
                     ? "Remind me if I haven't logged this around my usual time"
                     : "Remind me at each time above")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.text)
            }
            .onChange(of: patternReminderEnabled) { _, enabled in
                commitEdits()
                if enabled { requestAuthorizationThenSync() }
            }

            Text(doseTimes.isEmpty
                 ? "The nudge goes by when you usually log this — and only if nothing's been logged that day."
                 : "Fires every day at each time you set, whether or not the app is open.")
                .font(.caption2).foregroundStyle(theme.dim)
        }
        .padding(14)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    private var wateringBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("WATERING")
                    .font(.system(size: 10, weight: .medium)).tracking(2)
                    .foregroundStyle(theme.dim)
                Spacer()
                if syntheticSpeciesForMath != nil || species != nil {
                    Button("Reset to suggested") { resetToSuggested() }
                        .tactile(.ghost)
                }
            }

            Stepper(value: $intervalDays, in: PlantCatalog.minIntervalDays...PlantCatalog.maxIntervalDays) {
                HStack {
                    Text("Every").foregroundStyle(theme.dim)
                    Spacer()
                    Text("\(intervalDays) day\(intervalDays == 1 ? "" : "s")")
                        .foregroundStyle(theme.text).monospacedDigit()
                }
            }
            .onChange(of: intervalDays) { _, _ in commitEdits() }

            AmountFlOzRow(amountFlOz: $amountFlOz, isEditing: $isEditing)

            Text("Water \(PlantCatalog.drainageCopy).")
                .font(.caption2).foregroundStyle(theme.dim)
        }
        .padding(14)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    private func resetToSuggested() {
        guard let sp = species ?? syntheticSpeciesForMath else { return }
        intervalDays = PlantCatalog.seededIntervalDays(for: sp, light: light)
        amountFlOz = PlantCatalog.suggestedAmountFlOz(waterClass: sp.waterClass, potDiameterInches: potDiameter)
        commitEdits()
    }

    /// Switching a reminder on is an explicit user action, and the only moment
    /// on this sheet where asking for notification permission is allowed (never
    /// `.onAppear`/`.task` — see CLAUDE.md).
    ///
    /// Without it, someone who declined the prompt when they saved their first
    /// reminder could turn this on, watch the switch stay on, and receive
    /// nothing at all — `reschedule` deliberately doesn't check authorization,
    /// so an unauthorized `add()` is a silent no-op.
    private func requestAuthorizationThenSync() {
        Task { @MainActor in
            await ReminderNotificationService.requestAuthorizationIfNeeded()
            ReminderNotificationService.syncAfterChange(ctx, reminderId: reminder.id, userId: profile.id)
        }
    }

    private func commitEdits() {
        var updated = reminder
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        updated.name = trimmedName.isEmpty ? reminder.name : trimmedName

        if isMedication {
            // No intervalDays write: medication was stored with 1 and nothing
            // in its UI can change it.
            let trimmedDosage = dosage.trimmingCharacters(in: .whitespaces)
            updated.dosage = trimmedDosage.isEmpty ? nil : trimmedDosage
            let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
            updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            // Normalise here rather than in the editor: sorting mid-edit would
            // move a row out from under the user's finger.
            let times = MedicationPattern.normalizedTimes(doseTimes)
            updated.scheduledMinutesOfDay = times
            // Adding a time is asking to be reminded at it. Never the reverse —
            // removing every time leaves the switch as the user last set it.
            updated.patternReminderEnabled = times.isEmpty ? patternReminderEnabled : true
        } else if reminder.isPlant {
            let trimmedRoom = room.trimmingCharacters(in: .whitespaces)
            updated.room = trimmedRoom.isEmpty ? nil : trimmedRoom
            updated.intervalDays = intervalDays
            updated.amountFlOz = amountFlOz
            updated.light = light
            updated.potDiameterInches = potDiameter
        } else {
            updated.intervalDays = intervalDays
            let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
            updated.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
        }

        guard updated != reminder else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            reminder = updated
        }
        guard ReminderNotificationService.update(ctx, updated) else { return }
        Haptics.bump()
    }

    // MARK: - Snooze

    private var snoozeButton: some View {
        Button {
            snooze()
        } label: {
            HStack {
                Image(systemName: "moon.zzz.fill")
                Text("Snooze 1 day")
            }
            .frame(maxWidth: .infinity)
        }
        .tactile(.secondary, fullWidth: true)
    }

    private func snooze() {
        guard ReminderNotificationService.snooze(ctx, reminderId: reminder.id) != nil else { return }
        Haptics.success()
        toasts.show(Toast(
            title: "Snoozed", detail: "\(reminder.name) · back tomorrow",
            accent: .ok, symbol: "moon.zzz.fill"
        ))
        dismiss()
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("HISTORY")
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)

            if events.isEmpty {
                Text("No history yet.")
                    .font(.caption).foregroundStyle(theme.dim)
            } else if isMedication {
                // One pipeline run for both the inline list and the
                // more-to-see button underneath it.
                let allDays = allMedicationHistoryDays
                ForEach(medicationHistoryDays(allDays)) { day in
                    Text(MedicationHistory.dayTitle(day.id, now: Date(), calendar: .current))
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(theme.dim)
                        .padding(.top, 6)
                    ForEach(day.entries) { e in
                        medicationHistoryRow(e)
                    }
                }
                fullHistoryButton(allDays: allDays)
            } else {
                ForEach(events.prefix(30)) { e in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.timestamp, style: .date)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(theme.text)
                            if let amt = e.amountFlOz {
                                Text("\(Int(amt.rounded())) fl oz")
                                    .font(.caption2).foregroundStyle(theme.dim)
                            }
                        }
                        Spacer()
                        Button { deleteEvent(id: e.id) } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .tactile(.ghost)
                        .accessibilityLabel("Undo entry from \(e.timestamp.formatted(date: .abbreviated, time: .omitted))")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    /// How many recent DAYS of doses this sheet shows inline. Everything older
    /// is one tap away in the full history rather than absent — nothing is
    /// dropped, only deferred.
    ///
    /// A window rather than a row count because this sheet's ScrollView holds an
    /// eager VStack (photo, stats, editable fields, history, delete are one
    /// column, not a list). Years of three-a-day doses rendered eagerly here
    /// would build every row up front; `MedicationHistorySheet` is a LazyVStack
    /// and carries the uncapped record.
    private static let inlineHistoryDays = 14

    private var allMedicationHistoryDays: [MedicationLogDay] {
        MedicationHistory.byDay(
            MedicationHistory.entries(events: events, medications: [reminder]),
            calendar: .current
        )
    }

    private func medicationHistoryDays(_ all: [MedicationLogDay]) -> [MedicationLogDay] {
        Array(all.prefix(Self.inlineHistoryDays))
    }

    /// The button only appears when there is genuinely more to see, so it never
    /// promises a fuller record than exists.
    @ViewBuilder
    private func fullHistoryButton(allDays all: [MedicationLogDay]) -> some View {
        if all.count > Self.inlineHistoryDays {
            let totals = MedicationHistory.totals(all)
            Button {
                showFullHistory = true
            } label: {
                HStack {
                    Image(systemName: "list.bullet.rectangle")
                    Text("See all \(totals.doses) doses")
                }
                .frame(maxWidth: .infinity)
            }
            .tactile(.secondary, fullWidth: true)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private func medicationHistoryRow(_ e: MedicationLogEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(medicationRowLabel(e))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.text)
                if let timing = MedicationHistory.timingLabel(e, calendar: .current) {
                    Text(timing)
                        .font(.caption2).foregroundStyle(theme.dim)
                }
            }
            Spacer()
            Button { deleteEvent(id: e.id) } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .tactile(.ghost)
            .accessibilityLabel("Undo log from \(e.timestamp.formatted(date: .abbreviated, time: .shortened))")
        }
        .padding(.vertical, 4)
    }

    private func medicationRowLabel(_ e: MedicationLogEntry) -> String {
        let time = e.timestamp.formatted(date: .omitted, time: .shortened)
        guard let taken = e.dosageTaken, !taken.isEmpty else { return time }
        return "\(time) — \(taken)"
    }

    private func deleteEvent(id: UUID) {
        guard Repos.deleteReminderEvent(ctx, id: id) else { return }
        ReminderNotificationService.syncAfterChange(ctx, reminderId: reminder.id, userId: profile.id)
        Haptics.warn()
        toasts.show(Toast(title: "Removed", detail: "Log entry undone", accent: .warn, symbol: "arrow.uturn.backward"))
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            showDeleteConfirm = true
        } label: {
            HStack {
                Image(systemName: "trash")
                Text("Delete reminder")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tactile(.secondary, fullWidth: true)
    }

    private func delete() {
        guard ReminderNotificationService.remove(ctx, reminderId: reminder.id, userId: profile.id) else { return }
        Haptics.warn()
        toasts.show(Toast(title: "\(reminder.name) deleted", accent: .warn, symbol: "trash.fill"))
        dismiss()
    }

    // MARK: - Shared bits

    @ViewBuilder
    private func fieldBlock<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            content()
        }
    }

    @ViewBuilder
    private func styledField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .focused($isEditing)
            .onSubmit { commitEdits() }
            .padding(12)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
            .foregroundStyle(theme.text)
    }
}

// MARK: - Plant care info sheet

/// Nested ⓘ-style sheet: research copy for a cataloged species (soil check,
/// over/underwatering signs, winter note, pet toxicity). House rule: info
/// sheets use `.sheet` + `.presentationDetents([.medium])`, never `.popover`.
private struct PlantCareInfoSheet: View {
    let species: PlantSpecies

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(species.commonName)
                        .font(.system(size: 30, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text(species.botanicalName)
                        .font(.caption).italic().foregroundStyle(theme.dim)
                }

                infoBlock(icon: "drop.circle", title: "Soil check", body: species.soilCheck)
                infoBlock(icon: "exclamationmark.triangle", title: "Overwatering signs", body: species.overwateringSigns)
                infoBlock(icon: "sun.max", title: "Underwatering signs", body: species.underwateringSigns)
                infoBlock(icon: "snowflake", title: "Winter", body: species.winterNote)
                infoBlock(icon: "pawprint", title: "Pet safety", body: species.petToxicity)
            }
            .padding(20)
        }
        .presentationDetents([.medium])
        .presentationBackground(theme.bg)
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func infoBlock(icon: String, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11)).foregroundStyle(theme.accent)
                Text(title.uppercased()).font(.caption).tracking(2).foregroundStyle(theme.dim)
            }
            Text(body).font(.callout).foregroundStyle(theme.text)
        }
    }
}
