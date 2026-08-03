// Reminder detail / edit sheet: photo, due-date stats, plant care card (when
// speciesId resolves to a catalog entry), watering/interval editing, history,
// snooze, and delete.
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

    @State private var showImagePicker = false
    @State private var showDeleteConfirm = false
    @State private var showCareSheet = false
    @FocusState private var isEditing: Bool

    init(profile: ProfileDTO, reminder: ReminderDTO) {
        self.profile = profile
        _reminder = State(initialValue: reminder)
        _name = State(initialValue: reminder.name)
        _room = State(initialValue: reminder.room ?? "")
        _intervalDays = State(initialValue: reminder.intervalDays)
        _amountFlOz = State(initialValue: reminder.amountFlOz ?? 0)
        _notes = State(initialValue: reminder.notes ?? "")
        _light = State(initialValue: reminder.light ?? .bright)
        _potDiameter = State(initialValue: reminder.potDiameterInches ?? 6)

        let uid = profile.id
        let rid = reminder.id
        _eventModels = Query(
            filter: #Predicate<ReminderEventModel> { $0.userId == uid && $0.reminderId == rid },
            sort: \.timestamp, order: .reverse
        )
    }

    private var events: [ReminderEventDTO] { eventModels.map(\.snapshot) }
    private var lastDone: Date? { events.first?.timestamp }

    /// Plant-specific fields are nil for reminders in a custom group — see
    /// ReminderDTO's doc comment.
    private var isPlant: Bool {
        reminder.light != nil || reminder.potDiameterInches != nil || reminder.speciesId != nil
    }

    /// Only resolves for a catalog-matched species — a "custom plant" (whose
    /// speciesId is PlantCatalog.customId) legitimately has no research entry.
    private var species: PlantSpecies? {
        reminder.speciesId.flatMap { PlantCatalog.species(id: $0) }
    }

    /// Synthetic species used only to recompute suggested interval/amount for
    /// a custom (non-cataloged) plant — mirrors AddReminderSheet's approach so
    /// "Reset to suggested" works the same way regardless of provenance.
    private var syntheticSpeciesForMath: PlantSpecies? {
        guard isPlant, species == nil else { return nil }
        return PlantSpecies(
            id: PlantCatalog.customId, commonName: reminder.name, botanicalName: "", aliases: [],
            baselineIntervalDays: 7, lowLightMultiplier: 1.5,
            soilCheck: "", overwateringSigns: "", underwateringSigns: "", winterNote: "",
            lowLightRating: .tolerates, petToxicity: "Unknown — check the species before keeping pets nearby.",
            waterClass: .average
        )
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

    private var amountDisplay: String {
        amountFlOz.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(amountFlOz)) : String(format: "%.1f", amountFlOz)
    }

    private var amountTextBinding: Binding<String> {
        Binding(
            get: { amountDisplay },
            set: { amountFlOz = Double($0) ?? amountFlOz }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reminder.name)
                        .font(.system(size: 32, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text(isPlant ? "PLANT REMINDER" : "REMINDER")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                photoHeader
                statsCard

                if let species {
                    careCardButton(species)
                }

                editableSection

                if isDue { snoozeButton }

                historySection

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
        Repos.updateReminder(ctx, updated)
        WatchSyncService.shared.pushSnapshot(ctx, userId: updated.userId)
        Haptics.bump()
        toasts.show(Toast(title: "Photo updated", accent: .ok, symbol: "photo.fill"))
    }

    // MARK: - Stats

    private var statsCard: some View {
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

            if isPlant {
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
                fieldBlock("REPEATS EVERY") {
                    Stepper(value: $intervalDays, in: PlantCatalog.minIntervalDays...PlantCatalog.maxIntervalDays) {
                        Text("\(intervalDays) day\(intervalDays == 1 ? "" : "s")")
                            .foregroundStyle(theme.text).monospacedDigit()
                    }
                    .onChange(of: intervalDays) { _, _ in commitEdits() }
                }

                fieldBlock("NOTES") { styledField("Any details", text: $notes) }
            }
        }
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

            HStack {
                Text("Amount").foregroundStyle(theme.dim)
                Spacer()
                TextField("fl oz", text: amountTextBinding)
                    .keyboardType(.decimalPad)
                    .focused($isEditing)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(theme.text)
                    .frame(width: 56)
                Text("fl oz").foregroundStyle(theme.dim)
            }

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

    private func commitEdits() {
        var updated = reminder
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        updated.name = trimmedName.isEmpty ? reminder.name : trimmedName

        if isPlant {
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
        ReminderNotificationService.update(ctx, updated)
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
        ReminderNotificationService.snooze(ctx, reminderId: reminder.id)
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
                        Button { deleteEvent(e) } label: {
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

    private func deleteEvent(_ e: ReminderEventDTO) {
        Repos.deleteReminderEvent(ctx, id: e.id)
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
        ReminderNotificationService.remove(ctx, reminderId: reminder.id, userId: profile.id)
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
