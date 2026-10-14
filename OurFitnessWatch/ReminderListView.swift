// Root list: reminders grouped by their phone-side group (medication first,
// then plants, then alphabetical), sorted due-first within each group. Plain
// native watchOS List/Section -- no iOS Theme/Card dependency.

import SwiftUI
import UIKit

/// The reminder kinds the wrist renders differently, derived from the raw
/// `groupKind` string carried on the wire. `Shared/WatchSyncPayload.swift`
/// deliberately can't see Domain's `ReminderGroupKind`, so the string-to-kind
/// mapping lives here -- ONCE, rather than as another `isPlant`-style ternary
/// at every presentation site. Shared by this file and `ReminderDetailView`.
enum WatchReminderKind {
    case medication
    case plants
    case custom

    init(_ snapshot: ReminderSnapshot) {
        switch snapshot.groupKind {
        case "medication": self = .medication
        case "plants": self = .plants
        default: self = .custom
        }
    }

    /// Mirrors the phone's fixed `ReminderGroupKind.sortRank`, so the wrist
    /// lists groups in the same order the Reminders tab does.
    var sortRank: Int {
        switch self {
        case .medication: return 0
        case .plants: return 1
        case .custom: return 2
        }
    }

    /// Fallback glyph when a reminder has no photo thumbnail.
    var symbol: String {
        switch self {
        case .medication: return "pills.fill"
        case .plants: return "leaf.fill"
        case .custom: return "bell.fill"
        }
    }

    /// A flat system colour per glyph, matching how `leaf`/`bell` were picked.
    var tint: Color {
        switch self {
        case .medication: return .teal
        case .plants: return .green
        case .custom: return .orange
        }
    }
}

/// One reminder's resolved due status. The `nextDueDay → daysUntilDue → dueLabel`
/// chain was spelled out separately in this file and in `ReminderDetailView`,
/// which is exactly how a list row and the detail it opens start disagreeing
/// about the same reminder. Both now build this instead. Shared here for the
/// same reason `WatchReminderKind` is.
struct WatchDueStatus {
    let dueDay: Date
    let daysUntil: Int
    /// Kept so medication can report what was recorded instead of a due date.
    let lastDone: Date?

    init(_ snapshot: ReminderSnapshot, now: Date = Date()) {
        lastDone = snapshot.lastDoneAt
        dueDay = ReminderSchedule.nextDueDay(
            lastDone: snapshot.lastDoneAt, createdAt: snapshot.createdAt,
            intervalDays: snapshot.intervalDays, snoozedUntil: snapshot.snoozedUntil
        )
        daysUntil = ReminderSchedule.daysUntilDue(dueDay: dueDay, now: now)
    }

    var isDue: Bool { daysUntil <= 0 }
    var label: String { ReminderSchedule.dueLabel(daysUntilDue: daysUntil) }

    /// Status text for a row, and whether it may be shown in red.
    ///
    /// MEDICATION IS DELIBERATELY EXCLUDED from the interval-driven due/overdue
    /// wording. `RemindersView` on the phone makes the same exclusion and says
    /// why: an app-side "overdue" badge reads as a missed-dose claim we cannot
    /// stand behind. A daily medication carries a placeholder `intervalDays`,
    /// so the generic chain would render a med taken this morning as "23 days
    /// overdue" in red. The wrist is the surface most likely to be glanced at
    /// and believed, so it must not make that claim either.
    ///
    /// For medication we state only what was actually recorded: when the last
    /// dose was logged. Never a judgement about a dose that was missed.
    func status(for kind: WatchReminderKind, now: Date = Date()) -> (text: String, isAlarming: Bool) {
        guard kind == .medication else { return (label, daysUntil < 0) }
        guard let last = lastDone else { return ("No doses logged yet", false) }
        if Calendar.current.isDate(last, inSameDayAs: now) { return ("Logged today", false) }
        let days = Calendar.current.dateComponents([.day],
                                                   from: Calendar.current.startOfDay(for: last),
                                                   to: Calendar.current.startOfDay(for: now)).day ?? 0
        if days == 1 { return ("Last logged yesterday", false) }
        return ("Last logged \(days) days ago", false)
    }
}

struct ReminderListView: View {
    @EnvironmentObject var store: WatchSyncStore

    private struct Row: Identifiable {
        let snapshot: ReminderSnapshot
        let due: WatchDueStatus
        var id: UUID { snapshot.id }
    }

    private struct GroupSection {
        let name: String
        let kind: WatchReminderKind
        let items: [Row]
    }

    // Decorate-sort-undecorate: the calendar-heavy due-day math runs once per
    // snapshot per body pass, and rows receive the precomputed status.
    private var sections: [GroupSection] {
        // One `now` for the whole pass, so two rows can't be labelled against
        // clocks a millisecond apart across a midnight boundary.
        let now = Date()
        let rows = store.reminders.map { Row(snapshot: $0, due: WatchDueStatus($0, now: now)) }
        return Dictionary(grouping: rows, by: { $0.snapshot.groupName })
            .map { name, items in
                GroupSection(name: name,
                             kind: items.first.map { WatchReminderKind($0.snapshot) } ?? .custom,
                             // Medication has no meaningful due ordering (see
                             // WatchDueStatus.status) — sort it by name instead.
                             items: Self.sorted(items))
            }
            .sorted { lhs, rhs in
                if lhs.kind.sortRank != rhs.kind.sortRank { return lhs.kind.sortRank < rhs.kind.sortRank }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    /// Due-soonest first, except medication which sorts by name.
    private static func sorted(_ items: [Row]) -> [Row] {
        guard items.first.map({ WatchReminderKind($0.snapshot) }) == .medication else {
            return items.sorted { $0.due.daysUntil < $1.due.daysUntil }
        }
        return items.sorted {
            $0.snapshot.name.localizedCaseInsensitiveCompare($1.snapshot.name) == .orderedAscending
        }
    }

    var body: some View {
        Group {
            if store.reminders.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sections, id: \.name) { section in
                        Section(section.name) {
                            ForEach(section.items) { row in
                                NavigationLink {
                                    ReminderDetailView(snapshot: row.snapshot)
                                } label: {
                                    ReminderRow(snapshot: row.snapshot, due: row.due)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Reminders")
    }

    // "No reminders yet" is a CLAIM about the phone's data, and before the
    // first sync the watch knows nothing — so it says that instead, the same
    // way WatchQuickLogView and WatchTodayView do.
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: store.hasSynced ? "drop.fill" : "iphone.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(store.hasSynced ? "No reminders yet" : "Not synced yet")
                .font(.headline)
            Text(store.hasSynced
                 ? "Add reminders on your phone"
                 : "Open Our Fitness on your iPhone")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct ReminderRow: View {
    @EnvironmentObject var store: WatchSyncStore
    let snapshot: ReminderSnapshot
    let due: WatchDueStatus

    var body: some View {
        HStack(spacing: 10) {
            thumbnailView
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.name)
                    .font(.headline)
                    .lineLimit(1)
                let status = due.status(for: WatchReminderKind(snapshot))
                Text(status.text)
                    .font(.caption2)
                    .foregroundStyle(status.isAlarming ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        // Already decoded by WatchSyncStore — never decode in a body.
        if let uiImage = store.thumbnails[snapshot.id] {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            let kind = WatchReminderKind(snapshot)
            Image(systemName: kind.symbol)
                .font(.title3)
                .foregroundStyle(kind.tint)
                .frame(width: 32, height: 32)
        }
    }
}
