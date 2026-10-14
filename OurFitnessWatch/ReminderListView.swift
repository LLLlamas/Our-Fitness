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

struct ReminderListView: View {
    @EnvironmentObject var store: WatchSyncStore

    private struct Row: Identifiable {
        let snapshot: ReminderSnapshot
        let daysUntil: Int
        var id: UUID { snapshot.id }
    }

    private struct GroupSection {
        let name: String
        let kind: WatchReminderKind
        let items: [Row]
    }

    // Decorate-sort-undecorate: the calendar-heavy due-day math runs once per
    // snapshot per body pass, and rows receive the precomputed daysUntil.
    private var sections: [GroupSection] {
        let rows = store.reminders.map { s in
            Row(snapshot: s, daysUntil: ReminderSchedule.daysUntilDue(dueDay: ReminderSchedule.nextDueDay(
                lastDone: s.lastDoneAt, createdAt: s.createdAt,
                intervalDays: s.intervalDays, snoozedUntil: s.snoozedUntil
            )))
        }
        return Dictionary(grouping: rows, by: { $0.snapshot.groupName })
            .map { name, items in
                GroupSection(name: name,
                             kind: items.first.map { WatchReminderKind($0.snapshot) } ?? .custom,
                             items: items.sorted { $0.daysUntil < $1.daysUntil })
            }
            .sorted { lhs, rhs in
                if lhs.kind.sortRank != rhs.kind.sortRank { return lhs.kind.sortRank < rhs.kind.sortRank }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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
                                    ReminderRow(snapshot: row.snapshot, daysUntil: row.daysUntil)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Reminders")
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "drop.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No reminders yet")
                .font(.headline)
            Text("Add reminders on your phone")
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
    let daysUntil: Int

    var body: some View {
        HStack(spacing: 10) {
            thumbnailView
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(ReminderSchedule.dueLabel(daysUntilDue: daysUntil))
                    .font(.caption2)
                    .foregroundStyle(daysUntil < 0 ? .red : .secondary)
            }
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let data = store.thumbnails[snapshot.id], let uiImage = UIImage(data: data) {
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
