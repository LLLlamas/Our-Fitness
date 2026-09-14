// Reminders tab root — recurring household reminders. Plants ship as the one
// fully-fleshed group (species catalog, seeded interval/amount, care sheet);
// user-created groups are simpler (name + photo + interval). Medication is its
// own shape entirely: it sits above everything else in a section of its own and
// is deliberately kept OUT of the interval-driven Due/upcoming lists, because
// "every N days" says nothing useful about a daily medication and an app-side
// "overdue" badge would read as a missed-dose claim we can't stand behind.
//
// Per-profile @Query on all three reminder entities (hard rule: predicate-
// scoped, never client-side .filter — see TodayView/NutritionView/etc). "Last
// done" per reminder is folded once per render into a [UUID: Date] dict from
// the fetched event list; row bodies never call into Repos directly.

import SwiftUI
import SwiftData
import UIKit
import UserNotifications

struct RemindersView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var groupModels: [ReminderGroupModel]
    @Query private var reminderModels: [ReminderModel]
    // Unbounded by design: only the newest event per reminder is consumed, but
    // any fetch limit could drop the sole (old) event of a rarely-done reminder
    // and corrupt its overdue math. Bounding needs a denormalized lastDoneAt.
    @Query private var eventModels: [ReminderEventModel]

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var showAddSheet = false
    @State private var showAddMedicationSheet = false
    @State private var showMedicationHistory = false
    @State private var selectedReminder: ReminderDTO?
    @State private var loggingMedication: ReminderDTO?

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _groupModels = Query(
            filter: #Predicate<ReminderGroupModel> { $0.userId == uid },
            sort: \.createdAt, order: .forward
        )
        _reminderModels = Query(
            filter: #Predicate<ReminderModel> { $0.userId == uid },
            sort: \.createdAt, order: .forward
        )
        _eventModels = Query(
            filter: #Predicate<ReminderEventModel> { $0.userId == uid },
            sort: \.timestamp, order: .reverse
        )
    }

    private var groups: [ReminderGroupDTO] { groupModels.map(\.snapshot) }
    private var reminders: [ReminderDTO] { reminderModels.map(\.snapshot) }
    private var events: [ReminderEventDTO] { eventModels.map(\.snapshot) }

    private var groupsById: [UUID: ReminderGroupDTO] {
        Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0) })
    }

    /// Built-in groups first (medication, then plants — see
    /// `ReminderGroupKind.sortRank`), then custom groups alphabetically.
    private var orderedGroups: [ReminderGroupDTO] {
        groups.sorted {
            $0.kind.sortRank != $1.kind.sortRank
                ? $0.kind.sortRank < $1.kind.sortRank
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    /// Medication renders in its own always-visible section above Due, so it's
    /// excluded from the per-group upcoming sections below.
    private var intervalGroups: [ReminderGroupDTO] {
        orderedGroups.filter { $0.kind != .medication }
    }

    private var medicationGroup: ReminderGroupDTO? {
        groups.first(where: { $0.kind == .medication })
    }

    private var medications: [ReminderDTO] {
        guard let gid = medicationGroup?.id else { return [] }
        return reminders.filter { $0.groupId == gid }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Latest event timestamp per reminder, built once per render. Events
    /// arrive newest-first (query sort), so the first hit per id wins.
    private var lastDoneById: [UUID: Date] {
        var dict: [UUID: Date] = [:]
        for e in events where dict[e.reminderId] == nil {
            dict[e.reminderId] = e.timestamp
        }
        return dict
    }

    private struct ReminderStatus: Identifiable {
        let reminder: ReminderDTO
        let group: ReminderGroupDTO
        let daysUntil: Int
        var id: UUID { reminder.id }
    }

    /// Every interval-driven reminder's due-day math from the pre-built
    /// last-done dict. Evaluated exactly once per body pass (body-local `let`,
    /// threaded into the section builders) — never inside a ForEach row body.
    ///
    /// Medication is filtered out here, so it can't surface in Due or in a
    /// per-group upcoming list: repeat-interval semantics don't apply to it.
    private var statuses: [ReminderStatus] {
        let lastDone = lastDoneById
        let byId = groupsById
        return reminders.compactMap { r -> ReminderStatus? in
            guard let group = byId[r.groupId], group.kind != .medication else { return nil }
            let due = ReminderSchedule.nextDueDay(
                lastDone: lastDone[r.id], createdAt: r.createdAt,
                intervalDays: r.intervalDays, snoozedUntil: r.snoozedUntil
            )
            let daysUntil = ReminderSchedule.daysUntilDue(dueDay: due)
            return ReminderStatus(reminder: r, group: group, daysUntil: daysUntil)
        }
    }

    var body: some View {
        let statuses = self.statuses
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                header
                permissionBanner
                medicationSection
                dueSection(statuses)
                ForEach(intervalGroups) { group in
                    groupSection(group, statuses: statuses)
                }
                if reminders.isEmpty {
                    emptyState
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .scrollHapticTicks()
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showAddSheet) {
            AddReminderSheet(profile: profile)
                .themed(profile.mode)
        }
        .sheet(isPresented: $showMedicationHistory) {
            MedicationHistorySheet(profile: profile, medications: medications)
                .themed(profile.mode)
        }
        .sheet(isPresented: $showAddMedicationSheet) {
            if let group = medicationGroup {
                AddReminderSheet(profile: profile, defaultGroupId: group.id)
                    .themed(profile.mode)
            }
        }
        .sheet(item: $selectedReminder) { reminder in
            // The group kind is resolved here, once per presentation, rather
            // than per row — the detail sheet needs it for its medication
            // branch and ReminderDTO deliberately has no `isMedication`.
            ReminderDetailSheet(
                profile: profile, reminder: reminder,
                groupKind: groupsById[reminder.groupId]?.kind ?? .custom
            )
            .themed(profile.mode)
        }
        .sheet(item: $loggingMedication) { reminder in
            LogMedicationSheet(profile: profile, reminder: reminder)
                .themed(profile.mode)
        }
        .task { authStatus = await currentAuthStatus() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reminders")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Medication, plants, and household routines — one tap when they're done.")
                    .font(.callout).foregroundStyle(theme.dim)
            }
            Spacer()
            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add")
                }
            }
            .tactile(.pill, fill: theme.accent)
            .accessibilityLabel("Add reminder")
        }
    }

    // MARK: - Permission banner

    @ViewBuilder
    private var permissionBanner: some View {
        switch authStatus {
        case .denied:
            Banner(tone: .warn) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notifications are off, so reminders won't ping you — the Due list below still works.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .tactile(.secondary)
                }
            }
        case .notDetermined where !reminders.isEmpty:
            Banner(tone: .info) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Turn on notifications and I'll ping you when something's due.")
                    Button("Turn on reminders") { Task { await enableNotifications() } }
                        .tactile(.secondary)
                }
            }
        default:
            EmptyView()
        }
    }

    private func enableNotifications() async {
        let granted = await ReminderNotificationService.requestAuthorizationIfNeeded()
        authStatus = await currentAuthStatus()
        for r in reminders {
            ReminderNotificationService.reschedule(ctx, reminderId: r.id)
        }
        if granted {
            Haptics.success()
            toasts.show(Toast(title: "Reminders on", detail: "You'll be pinged when something's due.",
                              accent: .win, symbol: "bell.fill"))
        }
    }

    private func currentAuthStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Medication section
    //
    // Always visible (when the built-in group exists), always first, empty or
    // not: the whole point is that a medication is one scroll-free tap away.

    @ViewBuilder
    private var medicationSection: some View {
        if let group = medicationGroup {
            let meds = medications
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: group.sfSymbol)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accent)
                    Text(group.name.uppercased())
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                    Spacer()
                    if !meds.isEmpty {
                        // The full record, across every medication. The cards
                        // below only ever show the LAST log; this is the way
                        // to the rest of it without opening each one in turn.
                        Button("History") { showMedicationHistory = true }
                            .tactile(.ghost)
                        Button("+ Add") { showAddMedicationSheet = true }
                            .tactile(.ghost)
                    }
                }

                if meds.isEmpty {
                    medicationEmptyState
                } else {
                    let lastDone = lastDoneById
                    ForEach(meds) { med in
                        medicationCard(med, group: group, lastLogged: lastDone[med.id])
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func medicationCard(_ r: ReminderDTO, group: ReminderGroupDTO, lastLogged: Date?) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Button { selectedReminder = r } label: {
                    HStack(spacing: 12) {
                        // A fixed symbol, not `thumbnail` — the medication forms
                        // have no photo step, so there is never a picture to
                        // show and an empty camera circle would only invite a
                        // tap that does nothing.
                        medicationIcon(group: group)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.text)
                            if let dosage = r.dosage, !dosage.isEmpty {
                                Text("Recommended: \(dosage)")
                                    .font(.caption2).foregroundStyle(theme.dim)
                            }
                            if !r.scheduledMinutesOfDay.isEmpty {
                                Text("Set for \(MedicationPattern.clockList(r.scheduledMinutesOfDay))")
                                    .font(.caption2).foregroundStyle(theme.dim)
                            }
                            Text(lastLoggedLabel(lastLogged))
                                .font(.caption2).foregroundStyle(theme.dim)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Full-width and spelled out: logging a dose is the one action
                // on this card that has to be unmissable, so no icon-only
                // control here (unlike the plant/custom due rows).
                Button { loggingMedication = r } label: {
                    Text("Log Taken").frame(maxWidth: .infinity)
                }
                .tactile(.primary, fullWidth: true)
                .accessibilityLabel("Log a dose of \(r.name)")
            }
        }
    }

    private func medicationIcon(group: ReminderGroupDTO) -> some View {
        ZStack {
            Circle().fill(theme.card2)
            Image(systemName: group.sfSymbol)
                .font(.system(size: 16))
                .foregroundStyle(theme.accent)
        }
        .frame(width: 40, height: 40)
        .overlay(Circle().stroke(theme.line, lineWidth: 1))
    }

    /// "Last logged: Today • 8:12 AM" — deliberately about the LOG, not the
    /// dose. A missing entry means nothing was recorded, not that nothing was
    /// taken, so no "missed" phrasing anywhere on this surface.
    private func lastLoggedLabel(_ date: Date?) -> String {
        guard let date else { return "No doses logged yet" }
        let time = date.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Last logged: Today • \(time)" }
        if cal.isDateInYesterday(date) { return "Last logged: Yesterday • \(time)" }
        return "Last logged: \(date.formatted(date: .abbreviated, time: .omitted)) • \(time)"
    }

    private var medicationEmptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Keep medication logs organized in one place.")
                    .font(.callout).foregroundStyle(theme.dim)
                Button {
                    showAddMedicationSheet = true
                } label: {
                    Text("Add medication").frame(maxWidth: .infinity)
                }
                .tactile(.primary, fullWidth: true)
            }
        }
    }

    // MARK: - Due section

    @ViewBuilder
    private func dueSection(_ statuses: [ReminderStatus]) -> some View {
        let due = statuses.filter { $0.daysUntil <= 0 }.sorted { $0.daysUntil < $1.daysUntil }
        if !due.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("DUE")
                    .font(.system(size: 10, weight: .medium)).tracking(2)
                    .foregroundStyle(theme.dim)
                ForEach(due) { status in
                    dueRow(status)
                }
            }
        }
    }

    @ViewBuilder
    private func dueRow(_ status: ReminderStatus) -> some View {
        let r = status.reminder
        let plant = r.isPlant
        Card {
            HStack(spacing: 12) {
                Button { selectedReminder = r } label: {
                    HStack(spacing: 12) {
                        thumbnail(r, group: status.group)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(theme.text)
                            Text(subtitle(r, group: status.group))
                                .font(.caption2).foregroundStyle(theme.dim)
                            Text(ReminderSchedule.dueLabel(daysUntilDue: status.daysUntil))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.warn)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { logDone(r) } label: {
                    Image(systemName: plant ? "drop.fill" : "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                }
                .tactile(.primary)
                .accessibilityLabel(plant ? "Mark \(r.name) watered" : "Mark \(r.name) done")
            }
        }
    }

    private func logDone(_ r: ReminderDTO) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            guard ReminderNotificationService.logDone(ctx, reminderId: r.id) != nil else { return }
        }
        Haptics.success()
        let plant = r.isPlant
        toasts.show(Toast(
            title: r.name, detail: plant ? "Watered" : "Done",
            accent: .win, symbol: plant ? "drop.fill" : "checkmark.seal.fill"
        ))
    }

    // MARK: - Per-group sections

    @ViewBuilder
    private func groupSection(_ group: ReminderGroupDTO, statuses: [ReminderStatus]) -> some View {
        let upcoming = statuses.filter { $0.daysUntil > 0 && $0.group.id == group.id }
            .sorted { $0.daysUntil < $1.daysUntil }
        if !upcoming.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: group.sfSymbol)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accent)
                    Text(group.name.uppercased())
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }
                ForEach(upcoming) { status in
                    upcomingRow(status)
                }
            }
        }
    }

    @ViewBuilder
    private func upcomingRow(_ status: ReminderStatus) -> some View {
        let r = status.reminder
        PressableCard(action: { selectedReminder = r }) {
            HStack(spacing: 12) {
                thumbnail(r, group: status.group)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text(subtitle(r, group: status.group))
                        .font(.caption2).foregroundStyle(theme.dim)
                }
                Spacer(minLength: 0)
                Text("in \(status.daysUntil) day\(status.daysUntil == 1 ? "" : "s")")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(theme.dim)
            }
        }
    }

    private func subtitle(_ r: ReminderDTO, group: ReminderGroupDTO) -> String {
        var parts: [String] = [group.name]
        if let room = r.room, !room.isEmpty { parts.append(room) }
        if let amount = r.amountFlOz { parts.append("\(Int(amount.rounded())) fl oz") }
        parts.append(ReminderSchedule.intervalLabel(days: r.intervalDays))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func thumbnail(_ r: ReminderDTO, group: ReminderGroupDTO) -> some View {
        ZStack {
            Circle().fill(theme.card2)
            if let uiImage = ReminderPhotoCache.image(id: r.id, data: r.photoData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(Circle())
            } else {
                Image(systemName: group.sfSymbol)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.accent)
            }
        }
        .frame(width: 40, height: 40)
        .overlay(Circle().stroke(theme.line, lineWidth: 1))
    }

    // MARK: - Empty state

    private var emptyState: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nothing on the list yet.")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text("A plant, a sourdough starter, the air filter — anything on a repeat. Plants get their watering worked out for you; everything else, you pick the cadence.")
                    .font(.callout).foregroundStyle(theme.dim)
                Button {
                    showAddSheet = true
                } label: {
                    Text("Add your first reminder").frame(maxWidth: .infinity)
                }
                .tactile(.primary, fullWidth: true)
            }
        }
    }
}

// MARK: - Decoded photo cache

/// Shared by RemindersView (40×40 thumbnails) and ReminderDetailSheet (header)
/// so reminder photos aren't JPEG-decoded on every body pass. Entries revalidate
/// on byte count (photo edits re-encode, so a same-length swap is implausible);
/// ReminderDetailSheet also invalidates explicitly on photo update.
enum ReminderPhotoCache {
    private final class Entry {
        let byteCount: Int
        let image: UIImage
        init(byteCount: Int, image: UIImage) {
            self.byteCount = byteCount
            self.image = image
        }
    }

    private static let cache = NSCache<NSUUID, Entry>()

    static func image(id: UUID, data: Data?) -> UIImage? {
        guard let data else { return nil }
        let key = id as NSUUID
        if let entry = cache.object(forKey: key), entry.byteCount == data.count {
            return entry.image
        }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(Entry(byteCount: data.count, image: image), forKey: key)
        return image
    }

    static func invalidate(id: UUID) {
        cache.removeObject(forKey: id as NSUUID)
    }
}
