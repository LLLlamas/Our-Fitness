// Reminders tab root — recurring household reminders. Plants ship as the one
// fully-fleshed group (species catalog, seeded interval/amount, care sheet);
// user-created groups are simpler (name + photo + interval).
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
    @State private var selectedReminder: ReminderDTO?

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

    /// Plants first, then custom groups alphabetically.
    private var orderedGroups: [ReminderGroupDTO] {
        let plants = groups.filter { $0.kind == .plants }
        let custom = groups.filter { $0.kind == .custom }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return plants + custom
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

    /// Every reminder's due-day math from the pre-built last-done dict.
    /// Evaluated exactly once per body pass (body-local `let`, threaded into
    /// the section builders) — never inside a ForEach row body.
    private var statuses: [ReminderStatus] {
        let lastDone = lastDoneById
        let byId = groupsById
        return reminders.compactMap { r -> ReminderStatus? in
            guard let group = byId[r.groupId] else { return nil }
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
                dueSection(statuses)
                ForEach(orderedGroups) { group in
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
        .sheet(item: $selectedReminder) { reminder in
            ReminderDetailSheet(profile: profile, reminder: reminder)
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
                Text("Plants and household routines — one tap when they're done.")
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
            _ = ReminderNotificationService.logDone(ctx, reminderId: r.id)
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
