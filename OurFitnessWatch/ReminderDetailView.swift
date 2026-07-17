// Detail screen for one reminder: photo, plant-care stats (for catalog
// species), due-date math, and the three wrist actions (done / interval /
// snooze). Plain native watchOS SwiftUI -- no iOS Theme/Card/Haptics.

import SwiftUI
import UIKit
import WatchKit

struct ReminderDetailView: View {
    @EnvironmentObject var store: WatchReminderStore
    let snapshot: ReminderSnapshot

    @State private var intervalDays: Int

    init(snapshot: ReminderSnapshot) {
        self.snapshot = snapshot
        _intervalDays = State(initialValue: snapshot.intervalDays)
    }

    /// The freshest known copy of this reminder -- reflects optimistic
    /// updates and phone round-trips even though `snapshot` itself is a
    /// value-type snapshot from when this view was pushed.
    private var live: ReminderSnapshot {
        store.snapshots.first(where: { $0.id == snapshot.id }) ?? snapshot
    }

    private var species: PlantSpecies? {
        guard live.isPlant, let speciesId = live.speciesId else { return nil }
        return PlantCatalog.species(id: speciesId)
    }

    private var dueDay: Date {
        ReminderSchedule.nextDueDay(
            lastDone: live.lastDoneAt, createdAt: live.createdAt,
            intervalDays: live.intervalDays, snoozedUntil: live.snoozedUntil
        )
    }

    private var dueText: String {
        ReminderSchedule.dueLabel(daysUntilDue: ReminderSchedule.daysUntilDue(dueDay: dueDay))
    }

    private var lastDoneText: String {
        guard let last = live.lastDoneAt else { return "Never" }
        return last.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                photoView

                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.name)
                        .font(.title3.bold())
                    if let room = live.room, !room.isEmpty {
                        Text(room)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(live.isPlant ? "Last watered: \(lastDoneText)" : "Last done: \(lastDoneText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(dueText)
                        .font(.caption.bold())
                        .foregroundStyle(ReminderSchedule.isDue(dueDay: dueDay) ? .red : .primary)
                }

                if let species {
                    speciesInfo(species)
                }

                Button {
                    WKInterfaceDevice.current().play(.success)
                    store.send(.done(reminderId: snapshot.id, date: Date()))
                } label: {
                    Label(live.isPlant ? "Watered" : "Done", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                Stepper(
                    "Every \(intervalDays) day\(intervalDays == 1 ? "" : "s")",
                    value: $intervalDays, in: PlantCatalog.minIntervalDays...PlantCatalog.maxIntervalDays
                )
                .onChange(of: intervalDays) { _, newValue in
                    store.send(.setInterval(reminderId: snapshot.id, days: newValue))
                }

                Button {
                    store.send(.snooze(reminderId: snapshot.id))
                } label: {
                    Label("Snooze 1 day", systemImage: "moon.zzz.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle(snapshot.name)
    }

    @ViewBuilder
    private var photoView: some View {
        if let data = store.thumbnails[snapshot.id], let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: live.isPlant ? "leaf.fill" : "bell.fill")
                .font(.system(size: 36))
                .foregroundStyle(live.isPlant ? .green : .orange)
                .frame(height: 84)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func speciesInfo(_ species: PlantSpecies) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(species.botanicalName)
                .font(.caption2)
                .italic()
                .foregroundStyle(.secondary)
            infoRow(title: "Soil check", text: species.soilCheck)
            infoRow(title: "Overwatering", text: species.overwateringSigns)
            infoRow(title: "Underwatering", text: species.underwateringSigns)
            infoRow(title: "Pet safety", text: species.petToxicity)
        }
        .padding(8)
        .background(Color.gray.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func infoRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption2)
        }
    }
}
