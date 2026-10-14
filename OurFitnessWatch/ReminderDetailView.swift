// Detail screen for one reminder: photo, plant-care stats (for catalog
// species), due-date math, and the three wrist actions (done / interval /
// snooze). Plain native watchOS SwiftUI -- no iOS Theme/Card/Haptics.
//
// Everything that reads differently per kind goes through `WatchReminderKind`
// (declared in ReminderListView.swift) rather than another `isPlant` ternary:
// with three kinds the ternaries stopped being readable, and the copy, glyph,
// and which controls even appear all key off the same one value.

import SwiftUI
import UIKit
import WatchKit

struct ReminderDetailView: View {
    @EnvironmentObject var store: WatchSyncStore
    let snapshot: ReminderSnapshot

    @State private var intervalDays: Int
    @State private var pendingIntervalSend: Task<Void, Never>?

    init(snapshot: ReminderSnapshot) {
        self.snapshot = snapshot
        _intervalDays = State(initialValue: snapshot.intervalDays)
    }

    /// The freshest known copy of this reminder -- reflects optimistic
    /// updates and phone round-trips even though `snapshot` itself is a
    /// value-type snapshot from when this view was pushed.
    ///
    /// Resolved ONCE per body pass and threaded down, not read from a dozen
    /// computed properties: each read is a linear scan of every reminder, and
    /// the stat/label/due/species properties between them used to perform ten
    /// of them for a single render.
    private var live: ReminderSnapshot {
        store.reminders.first(where: { $0.id == snapshot.id }) ?? snapshot
    }

    private func species(_ live: ReminderSnapshot, kind: WatchReminderKind) -> PlantSpecies? {
        guard kind == .plants, let speciesId = live.speciesId else { return nil }
        return PlantCatalog.species(id: speciesId)
    }

    private func lastDoneLabel(_ kind: WatchReminderKind) -> String {
        switch kind {
        case .plants: return "Last watered"
        case .medication: return "Last logged"
        case .custom: return "Last done"
        }
    }

    private func actionTitle(_ kind: WatchReminderKind) -> String {
        switch kind {
        case .plants: return "Watered"
        case .medication: return "Log taken"
        case .custom: return "Done"
        }
    }

    /// A medication's schedule comes from the phone's logging-pattern
    /// inference, not from a repeat interval, so editing the interval here
    /// would write a value nothing reads -- and snoozing has nothing to move.
    private func showsIntervalAndSnooze(_ kind: WatchReminderKind) -> Bool { kind != .medication }

    private func lastDoneText(_ live: ReminderSnapshot) -> String {
        guard let last = live.lastDoneAt else { return "Never" }
        return last.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        // The one resolution per render. `WatchDueStatus` is the same due math
        // the list row used to reach this screen (see ReminderListView), so the
        // two cannot word the same reminder differently.
        let current = live
        let kind = WatchReminderKind(current)
        let due = WatchDueStatus(current)

        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                photoView(kind)

                VStack(alignment: .leading, spacing: 2) {
                    Text(current.name)
                        .font(.title3.bold())
                    if let room = current.room, !room.isEmpty {
                        Text(room)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    // A non-plant reminder has no species card to carry its
                    // detail, so its notes are the only context on the wrist.
                    if kind != .plants, let notes = current.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(lastDoneLabel(kind)): \(lastDoneText(current))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(due.label)
                        .font(.caption.bold())
                        .foregroundStyle(due.isDue ? .red : .primary)
                }

                if let species = species(current, kind: kind) {
                    speciesInfo(species)
                }

                Button {
                    WKInterfaceDevice.current().play(.success)
                    store.send(.done(reminderId: snapshot.id, date: Date()))
                } label: {
                    Label(actionTitle(kind), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

                if showsIntervalAndSnooze(kind) {
                    Stepper(
                        ReminderSchedule.intervalLabel(days: intervalDays),
                        value: $intervalDays, in: ReminderSchedule.minIntervalDays...ReminderSchedule.maxIntervalDays
                    )
                    .onChange(of: intervalDays) { _, newValue in
                        // Debounce: one transferUserInfo per burst of stepper ticks.
                        pendingIntervalSend?.cancel()
                        pendingIntervalSend = Task {
                            guard (try? await Task.sleep(for: .milliseconds(600))) != nil else { return }
                            store.send(.setInterval(reminderId: snapshot.id, days: newValue))
                            pendingIntervalSend = nil
                        }
                    }

                    Button {
                        WKInterfaceDevice.current().play(.click)
                        store.send(.snooze(reminderId: snapshot.id))
                    } label: {
                        Label("Snooze 1 day", systemImage: "moon.zzz.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle(current.name)
        .onDisappear {
            // Flush a still-pending debounced interval so no tick is lost.
            if pendingIntervalSend != nil {
                pendingIntervalSend?.cancel()
                pendingIntervalSend = nil
                store.send(.setInterval(reminderId: snapshot.id, days: intervalDays))
            }
        }
    }

    @ViewBuilder
    private func photoView(_ kind: WatchReminderKind) -> some View {
        // Already decoded by WatchSyncStore — never decode in a body.
        if let uiImage = store.thumbnails[snapshot.id] {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(height: 84)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Image(systemName: kind.symbol)
                .font(.system(size: 36))
                .foregroundStyle(kind.tint)
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
