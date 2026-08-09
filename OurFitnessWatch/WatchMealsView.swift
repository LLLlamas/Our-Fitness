// One-tap meal logging: the saved templates and frequently-logged foods the
// phone resolved into `MealShortcut`s.
//
// Macros shown here are display-only. Tapping sends the shortcut id back and
// the phone re-resolves the real numbers, so a stale snapshot can never write
// wrong macros into the food log (see Shared/WatchSyncPayload.swift).

import SwiftUI
import WatchKit

struct WatchMealsView: View {
    @EnvironmentObject private var store: WatchSyncStore

    /// Cleared shortly after a tap; just a visual receipt so a second tap
    /// isn't fired because the first looked like it did nothing.
    @State private var justLoggedId: String?
    @State private var clearTask: Task<Void, Never>?

    private var templates: [MealShortcut] {
        store.mealShortcuts.filter { $0.source == "template" }
    }

    private var recents: [MealShortcut] {
        store.mealShortcuts.filter { $0.source != "template" }
    }

    var body: some View {
        Group {
            if store.mealShortcuts.isEmpty {
                emptyState
            } else {
                List {
                    if !templates.isEmpty {
                        Section("Saved meals") {
                            ForEach(templates) { row($0) }
                        }
                    }
                    if !recents.isEmpty {
                        Section("Recent") {
                            ForEach(recents) { row($0) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Meals")
        .onDisappear { clearTask?.cancel() }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No meals yet")
                .font(.headline)
            Text("Saved meals and foods you log often on your phone show up here")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func row(_ shortcut: MealShortcut) -> some View {
        Button {
            log(shortcut)
        } label: {
            HStack(spacing: 8) {
                if let emoji = shortcut.emoji, !emoji.isEmpty {
                    Text(emoji)
                        .font(.title3)
                        .frame(width: 26)
                } else {
                    Image(systemName: "fork.knife")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 26)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(shortcut.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(shortcut.calories) cal · \(shortcut.proteinG)g protein")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if justLoggedId == shortcut.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func log(_ shortcut: MealShortcut) {
        let now = Date()
        WKInterfaceDevice.current().play(.success)
        store.send(.logMeal(
            shortcutId: shortcut.id,
            source: shortcut.source,
            slot: Self.slot(at: now),
            date: now
        ))

        justLoggedId = shortcut.id
        clearTask?.cancel()
        clearTask = Task {
            guard (try? await Task.sleep(for: .seconds(2))) != nil else { return }
            if justLoggedId == shortcut.id { justLoggedId = nil }
        }
    }

    /// Raw values of `Slot` in `OurFitness/Domain/Models.swift`
    /// (pre / breakfast / post-workout / lunch / snack / dinner / other).
    /// Domain isn't compiled into this target, so the strings are literal.
    ///
    /// Cutoffs, deliberately coarse -- the phone can always correct a slot:
    ///   04:00–10:59 breakfast · 11:00–14:59 lunch · 17:00–20:59 dinner
    ///   everything else (afternoon gap + late night) snack
    static func slot(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11:  return "breakfast"
        case 11..<15: return "lunch"
        case 17..<21: return "dinner"
        default:      return "snack"
        }
    }
}
