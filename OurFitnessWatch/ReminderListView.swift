// Root list: reminders grouped by their phone-side group (plant groups
// first, then alphabetical), sorted due-first within each group. Plain
// native watchOS List/Section -- no iOS Theme/Card dependency.

import SwiftUI
import UIKit

struct ReminderListView: View {
    @EnvironmentObject var store: WatchReminderStore

    private struct Row: Identifiable {
        let snapshot: ReminderSnapshot
        let daysUntil: Int
        var id: UUID { snapshot.id }
    }

    private struct GroupSection {
        let name: String
        let isPlant: Bool
        let items: [Row]
    }

    // Decorate-sort-undecorate: the calendar-heavy due-day math runs once per
    // snapshot per body pass, and rows receive the precomputed daysUntil.
    private var sections: [GroupSection] {
        let rows = store.snapshots.map { s in
            Row(snapshot: s, daysUntil: ReminderSchedule.daysUntilDue(dueDay: ReminderSchedule.nextDueDay(
                lastDone: s.lastDoneAt, createdAt: s.createdAt,
                intervalDays: s.intervalDays, snoozedUntil: s.snoozedUntil
            )))
        }
        return Dictionary(grouping: rows, by: { $0.snapshot.groupName })
            .map { name, items in
                GroupSection(name: name, isPlant: items.first?.snapshot.isPlant ?? false,
                             items: items.sorted { $0.daysUntil < $1.daysUntil })
            }
            .sorted { lhs, rhs in
                if lhs.isPlant != rhs.isPlant { return lhs.isPlant }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    var body: some View {
        Group {
            if store.snapshots.isEmpty {
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
            Text("Add plants on your phone")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

private struct ReminderRow: View {
    @EnvironmentObject var store: WatchReminderStore
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
            Image(systemName: snapshot.isPlant ? "leaf.fill" : "bell.fill")
                .font(.title3)
                .foregroundStyle(snapshot.isPlant ? .green : .orange)
                .frame(width: 32, height: 32)
        }
    }
}
