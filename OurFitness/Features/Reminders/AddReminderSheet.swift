// Add-reminder flow: pick (or create) a group, then a form tailored to that
// group's kind. Plants get the full research-backed flow (catalog search →
// seeded interval/amount from PlantCatalog, editable before saving); custom
// groups get a plain name/photo/interval/notes form.
//
// A single progressive-disclosure ScrollView (matches the house pattern in
// WorkoutGoalSheet/MoodMealSheet) rather than a multi-page wizard.

import SwiftUI
import SwiftData
import UIKit

struct AddReminderSheet: View {
    let profile: ProfileDTO
    let defaultGroupId: UUID?

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var groupModels: [ReminderGroupModel]

    @State private var selectedGroupId: UUID?
    @State private var showNewGroupForm = false
    @State private var newGroupName = ""
    @State private var newGroupSymbol = "bell.fill"

    @State private var speciesQuery = ""
    @State private var selectedSpecies: PlantSpecies?
    @State private var isCustomPlant = false

    @State private var name = ""
    @State private var photo: UIImage?
    @State private var showImagePicker = false
    @State private var room = ""
    @State private var light: PlantLightLevel = .bright
    @State private var potDiameter = 6
    @State private var intervalDays = 7
    @State private var amountFlOz: Double = 14
    @State private var notes = ""
    @State private var lastWateredPick: LastWateredPick = .today

    @FocusState private var isEditing: Bool

    private static let symbolChoices = [
        "bell.fill", "pawprint.fill", "car.fill", "wrench.and.screwdriver.fill",
        "house.fill", "heart.fill", "gift.fill", "calendar"
    ]

    init(profile: ProfileDTO, defaultGroupId: UUID? = nil) {
        self.profile = profile
        self.defaultGroupId = defaultGroupId
        let uid = profile.id
        _groupModels = Query(
            filter: #Predicate<ReminderGroupModel> { $0.userId == uid },
            sort: \.createdAt, order: .forward
        )
    }

    private var groups: [ReminderGroupDTO] { groupModels.map(\.snapshot) }

    private var orderedGroups: [ReminderGroupDTO] {
        let plants = groups.filter { $0.kind == .plants }
        let custom = groups.filter { $0.kind == .custom }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return plants + custom
    }

    /// Falls back to the Plants group (or the first group) until the user
    /// explicitly taps a chip — avoids needing an onAppear to seed state.
    private var resolvedGroupId: UUID? {
        selectedGroupId ?? defaultGroupId ?? groups.first(where: { $0.kind == .plants })?.id ?? groups.first?.id
    }

    private var selectedGroup: ReminderGroupDTO? {
        groups.first(where: { $0.id == resolvedGroupId })
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var canSave: Bool {
        guard let group = selectedGroup, !trimmedName.isEmpty else { return false }
        if group.kind == .plants { return selectedSpecies != nil || isCustomPlant }
        return true
    }

    /// A synthetic species used only to run the same seeded-interval/amount
    /// math for a "custom plant" (no catalog match) as for a cataloged one —
    /// avoids duplicating PlantCatalog's formulas. Uses PlantCatalog.customId
    /// as its id, matching that constant's documented purpose.
    private var speciesForMath: PlantSpecies? {
        if let selectedSpecies { return selectedSpecies }
        guard isCustomPlant else { return nil }
        return PlantSpecies(
            id: PlantCatalog.customId, commonName: trimmedName.isEmpty ? "Custom plant" : trimmedName,
            botanicalName: "", aliases: [],
            baselineIntervalDays: 7, lowLightMultiplier: 1.5,
            soilCheck: "Check the top inch of soil; water when it's dry.",
            overwateringSigns: "Yellow leaves, mushy stems, or soil that stays wet for days.",
            underwateringSigns: "Drooping, dry, crispy leaves.",
            winterNote: "Most houseplants need water less often in winter.",
            lowLightRating: .tolerates,
            petToxicity: "Unknown — check the species before keeping pets nearby.",
            waterClass: .average
        )
    }

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
                    Text("Add reminder")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("RECURRING · ONE TAP WHEN DONE")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                groupPickerSection

                if let group = selectedGroup {
                    if group.kind == .plants {
                        if selectedSpecies == nil && !isCustomPlant {
                            speciesSearchSection
                        } else {
                            plantFormSection
                        }
                    } else {
                        customFormSection
                    }
                }
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
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(
                onCapture: { img in photo = img; showImagePicker = false },
                onCancel: { showImagePicker = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: light) { _, _ in recomputeSuggestion() }
        .onChange(of: potDiameter) { _, _ in recomputeSuggestion() }
    }

    // MARK: - Group picker

    private var groupPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GROUP")
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(orderedGroups) { g in
                        chip(title: g.name, symbol: g.sfSymbol, selected: g.id == resolvedGroupId) {
                            selectedGroupId = g.id
                            showNewGroupForm = false
                            resetSpeciesSelection()
                            Haptics.selection()
                        }
                    }
                    chip(title: "New group…", symbol: "plus", selected: showNewGroupForm) {
                        showNewGroupForm.toggle()
                        Haptics.selection()
                    }
                }
            }
            if showNewGroupForm {
                newGroupForm
            }
        }
    }

    @ViewBuilder
    private func chip(title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(.system(size: 13, weight: .medium))
            }
        }
        .tactile(.pill, fill: selected ? theme.accent : nil)
    }

    private var newGroupForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            styledField("Group name (e.g. Car)", text: $newGroupName)

            HStack(spacing: 8) {
                ForEach(Self.symbolChoices, id: \.self) { sym in
                    Button {
                        newGroupSymbol = sym
                        Haptics.selection()
                    } label: {
                        Image(systemName: sym)
                            .font(.system(size: 15))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(newGroupSymbol == sym ? theme.bg : theme.text)
                            .background(newGroupSymbol == sym ? theme.accent : theme.card)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(theme.line, lineWidth: newGroupSymbol == sym ? 0 : 1))
                    }
                    .tactile(.ghost)
                }
            }

            Button {
                createGroup()
            } label: {
                Text("Create group").frame(maxWidth: .infinity)
            }
            .tactile(.secondary, fullWidth: true)
            .disabled(newGroupName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(14)
        .background(theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func createGroup() {
        let trimmed = newGroupName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let dto = ReminderGroupDTO(userId: profile.id, name: trimmed, sfSymbol: newGroupSymbol, kind: .custom)
        Repos.addReminderGroup(ctx, dto)
        selectedGroupId = dto.id
        showNewGroupForm = false
        newGroupName = ""
        Haptics.bump()
        toasts.show(Toast(title: trimmed, detail: "Group added", accent: .win, symbol: newGroupSymbol))
    }

    private func resetSpeciesSelection() {
        selectedSpecies = nil
        isCustomPlant = false
        speciesQuery = ""
        name = ""
    }

    // MARK: - Plant species search

    /// At most 8 results, matched against PlantCatalog.searchIndex with early
    /// termination — no per-keystroke re-lowercasing of the catalog.
    private var filteredSpecies: [PlantSpecies] {
        let q = speciesQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Array(PlantCatalog.all.prefix(8)) }
        var hits: [PlantSpecies] = []
        for (i, terms) in PlantCatalog.searchIndex.enumerated() where terms.contains(where: { $0.contains(q) }) {
            hits.append(PlantCatalog.all[i])
            if hits.count == 8 { break }
        }
        return hits
    }

    private var speciesSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("WHAT PLANT?")
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)

            styledField("Search plants (e.g. pothos, snake plant)…", text: $speciesQuery)
                .submitLabel(.search)
                .onSubmit {
                    if let match = PlantCatalog.entry(named: speciesQuery) { selectSpecies(match) }
                }

            VStack(spacing: 8) {
                ForEach(filteredSpecies) { sp in
                    Button { selectSpecies(sp) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: sp.sfSymbol).foregroundStyle(theme.accent)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sp.commonName).font(.system(size: 15, weight: .medium)).foregroundStyle(theme.text)
                                Text(sp.botanicalName).font(.caption2).italic().foregroundStyle(theme.dim)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    }
                    .tactile(.ghost)
                }

                Button { selectCustomPlant() } label: {
                    HStack {
                        Image(systemName: "questionmark.circle").foregroundStyle(theme.dim)
                        Text("Custom plant (not in the list)").foregroundStyle(theme.text)
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                }
                .tactile(.ghost)
            }
        }
    }

    private func selectSpecies(_ sp: PlantSpecies) {
        selectedSpecies = sp
        isCustomPlant = false
        name = "Water \(sp.commonName)"
        light = .bright
        potDiameter = 6
        recomputeSuggestion()
        Haptics.selection()
    }

    private func selectCustomPlant() {
        selectedSpecies = nil
        isCustomPlant = true
        name = "Water my plant"
        light = .bright
        potDiameter = 6
        recomputeSuggestion()
        Haptics.selection()
    }

    private func recomputeSuggestion() {
        guard let sp = speciesForMath else { return }
        intervalDays = PlantCatalog.seededIntervalDays(for: sp, light: light)
        amountFlOz = PlantCatalog.suggestedAmountFlOz(waterClass: sp.waterClass, potDiameterInches: potDiameter)
    }

    // MARK: - Plant form (species chosen or custom plant)

    private var plantFormSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(selectedSpecies?.commonName ?? "Custom plant")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Change") { resetSpeciesSelection() }
                    .tactile(.ghost)
            }

            fieldBlock(title: "NAME") { styledField("Reminder name", text: $name) }

            photoStep

            fieldBlock(title: "ROOM") { styledField("e.g. Living room", text: $room) }

            fieldBlock(title: "LIGHT") {
                Picker("Light", selection: $light) {
                    ForEach(PlantLightLevel.allCases, id: \.self) { l in Text(l.label).tag(l) }
                }
                .pickerStyle(.segmented)
            }

            fieldBlock(title: "POT SIZE") {
                HStack(spacing: 8) {
                    ForEach(PlantCatalog.potDiameterOptions, id: \.self) { d in
                        Button("\(d)\"") {
                            potDiameter = d
                            Haptics.selection()
                        }
                        .tactile(.pill, fill: potDiameter == d ? theme.accent : nil)
                    }
                }
            }

            if let sp = selectedSpecies, sp.lowLightRating == .struggles, light == .low {
                Banner(tone: .warn) {
                    Text("\(sp.commonName) typically struggles in low light — the soil will dry more slowly, so watch for overwatering: \(sp.overwateringSigns)")
                }
            }

            readoutSection

            fieldBlock(title: "LAST WATERED") {
                Picker("Last watered", selection: $lastWateredPick) {
                    ForEach(LastWateredPick.allCases) { p in Text(p.label).tag(p) }
                }
                .pickerStyle(.segmented)
            }

            saveButton
        }
    }

    private var readoutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Water ~\(amountDisplay) fl oz every \(intervalDays) day\(intervalDays == 1 ? "" : "s")")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.text)

            Stepper(value: $intervalDays, in: PlantCatalog.minIntervalDays...PlantCatalog.maxIntervalDays) {
                HStack {
                    Text("Every").foregroundStyle(theme.dim)
                    Spacer()
                    Text("\(intervalDays) day\(intervalDays == 1 ? "" : "s")")
                        .foregroundStyle(theme.text)
                        .monospacedDigit()
                }
            }

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

    // MARK: - Custom (non-plant) form

    private var customFormSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            fieldBlock(title: "NAME") { styledField("e.g. Change air filter", text: $name) }

            photoStep

            fieldBlock(title: "REPEATS EVERY") {
                Stepper(value: $intervalDays, in: PlantCatalog.minIntervalDays...PlantCatalog.maxIntervalDays) {
                    Text("\(intervalDays) day\(intervalDays == 1 ? "" : "s")")
                        .foregroundStyle(theme.text)
                        .monospacedDigit()
                }
            }

            fieldBlock(title: "NOTES · OPTIONAL") { styledField("Any details", text: $notes) }

            saveButton
        }
    }

    // MARK: - Shared bits

    private var photoStep: some View {
        fieldBlock(title: "PHOTO · OPTIONAL") {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(theme.card2)
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill().clipShape(Circle())
                    } else {
                        Image(systemName: "camera.fill").foregroundStyle(theme.dim)
                    }
                }
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(theme.line, lineWidth: 1))

                Button(photo == nil ? "Add photo" : "Retake") { showImagePicker = true }
                    .tactile(.secondary)

                if photo != nil {
                    Button("Remove") { photo = nil }.tactile(.ghost)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func fieldBlock<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
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
            .padding(12)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
            .foregroundStyle(theme.text)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text("Save reminder").frame(maxWidth: .infinity)
        }
        .tactile(.primary, fullWidth: true)
        .disabled(!canSave)
        .padding(.top, 4)
    }

    private func save() {
        guard let groupId = resolvedGroupId, let group = groups.first(where: { $0.id == groupId }) else { return }
        guard !trimmedName.isEmpty else { return }
        let reminderId = UUID()
        let photoBytes = photo.flatMap { ImageDownscale.jpegData($0, maxDimension: 1024) }

        let dto: ReminderDTO
        if group.kind == .plants {
            let speciesIdValue = isCustomPlant ? PlantCatalog.customId : selectedSpecies?.id
            let trimmedRoom = room.trimmingCharacters(in: .whitespaces)
            dto = ReminderDTO(
                id: reminderId, userId: profile.id, groupId: groupId, name: trimmedName,
                photoData: photoBytes, intervalDays: intervalDays, amountFlOz: amountFlOz,
                speciesId: speciesIdValue, room: trimmedRoom.isEmpty ? nil : trimmedRoom,
                light: light, potDiameterInches: potDiameter
            )
        } else {
            let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
            dto = ReminderDTO(
                id: reminderId, userId: profile.id, groupId: groupId, name: trimmedName,
                photoData: photoBytes, intervalDays: intervalDays,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
        }
        Repos.addReminder(ctx, dto)

        if group.kind == .plants, let backdate = lastWateredPick.date() {
            Repos.logReminderDone(ctx, ReminderEventDTO(
                userId: profile.id, reminderId: reminderId, date: Dates.dayKey(backdate),
                amountFlOz: dto.amountFlOz, timestamp: backdate
            ))
        }

        Task { @MainActor in
            await ReminderNotificationService.requestAuthorizationIfNeeded()
            ReminderNotificationService.syncAfterChange(ctx, reminderId: reminderId, userId: profile.id)
        }

        Haptics.success()
        toasts.show(Toast(
            title: trimmedName, detail: "Reminder added",
            accent: .win, symbol: group.kind == .plants ? "drop.fill" : "checkmark.seal.fill"
        ))
        dismiss()
    }
}

// MARK: - Last watered quick-pick

private enum LastWateredPick: String, CaseIterable, Identifiable {
    case today, threeDaysAgo, aWeek, unsure
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today:        return "Today"
        case .threeDaysAgo: return "3 days ago"
        case .aWeek:        return "A week ago"
        case .unsure:       return "Unsure"
        }
    }

    /// nil for `.unsure` — caller skips logging a backdated event.
    func date(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .today:        return now
        case .threeDaysAgo: return calendar.date(byAdding: .day, value: -3, to: now)
        case .aWeek:        return calendar.date(byAdding: .day, value: -7, to: now)
        case .unsure:       return nil
        }
    }
}
