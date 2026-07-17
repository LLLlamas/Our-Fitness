// Root list: reminders grouped by their phone-side group (plant groups
// first, then alphabetical), sorted due-first within each group. Plain
// native watchOS List/Section -- no iOS Theme/Card dependency.

import SwiftUI
import UIKit

struct ReminderListView: View {
    @EnvironmentObject var store: WatchReminderStore

    private struct GroupSection {
        let name: String
        let isPlant: Bool
        let items: [ReminderSnapshot]
    }

    private var sections: [GroupSection] {
        let grouped = Dictionary(grouping: store.snapshots, by: { $0.groupName })
        return grouped
            .map { name, items in
                GroupSection(name: name, isPlant: items.first?.isPlant ?? false, items: sortedByDue(items))
            }
            .sorted { lhs, rhs in
                if lhs.isPlant != rhs.isPlant { return lhs.isPlant }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func sortedByDue(_ items: [ReminderSnapshot]) -> [ReminderSnapshot] {
        items.sorted { daysUntilDue($0) < daysUntilDue($1) }
    }

    private func daysUntilDue(_ snapshot: ReminderSnapshot) -> Int {
        let due = ReminderSchedule.nextDueDay(
            lastDone: snapshot.lastDoneAt, createdAt: snapshot.createdAt,
            intervalDays: snapshot.intervalDays, snoozedUntil: snapshot.snoozedUntil
        )
        return ReminderSchedule.daysUntilDue(dueDay: due)
    }

    var body: some View {
        Group {
            if store.snapshots.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(sections, id: \.name) { section in
                        Section(section.name) {
                            ForEach(section.items) { snapshot in
                                NavigationLink {
                                    ReminderDetailView(snapshot: snapshot)
                                } label: {
                                    ReminderRow(snapshot: snapshot)
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

    private var dueDay: Date {
        ReminderSchedule.nextDueDay(
            lastDone: snapshot.lastDoneAt, createdAt: snapshot.createdAt,
            intervalDays: snapshot.intervalDays, snoozedUntil: snapshot.snoozedUntil
        )
    }

    private var dueLabel: (text: String, isOverdue: Bool) {
        let days = ReminderSchedule.daysUntilDue(dueDay: dueDay)
        return (ReminderSchedule.dueLabel(daysUntilDue: days), days < 0)
    }

    var body: some View {
        HStack(spacing: 10) {
            thumbnailView
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(dueLabel.text)
                    .font(.caption2)
                    .foregroundStyle(dueLabel.isOverdue ? .red : .secondary)
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
