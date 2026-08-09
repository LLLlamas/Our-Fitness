// Quick-log rows for the watch's Train tab — the wrist mirror of the phone's
// Features/Workouts/Circuit/BabyExercisesCard.swift.
//
// One row per movement the phone pushed: name, what's logged today, and a +1
// (or +1 min for a duration movement, matching how BabyExercisesCard splits
// reps from minutes). Swipe a row leading-edge to undo its last set.
//
// NO CALORIE MATH HERE, DELIBERATELY. The phone recomputes calories from the
// real ExerciseDTO (its load, its kind, ExerciseInfo's MET) when it applies the
// action — see BabyExercisesCard.logActivity. Estimating on the wrist from the
// thin QuickLogExercise projection would produce a second, disagreeing number.
// Please don't "helpfully" add CalorieEstimator here.
//
// Renders as Section rows inside WatchTrainView's List (swipeActions needs to
// be on a real List row), so this view intentionally has no List of its own.

import SwiftUI
import WatchKit

struct WatchQuickLogView: View {
    @EnvironmentObject private var store: WatchSyncStore

    var body: some View {
        Section("Quick log") {
            if store.quickLogExercises.isEmpty {
                emptyState
            } else {
                ForEach(store.quickLogExercises) { exercise in
                    QuickLogRow(exercise: exercise)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No movements yet")
                .font(.headline)
            Text(store.hasSynced
                 ? "Add movements on your phone"
                 : "Open OurFitness on your phone to sync")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct QuickLogRow: View {
    @EnvironmentObject private var store: WatchSyncStore
    let exercise: QuickLogExercise

    /// Duration movements log a minute at a time, rep movements a rep at a time
    /// — same unit split as BabyExercisesCard. Either way the wire amount is 1.
    private var buttonTitle: String { exercise.isDuration ? "+1 min" : "+1" }

    private var countLabel: String {
        guard exercise.loggedToday > 0 else { return "not logged yet" }
        return exercise.isDuration
            ? "\(exercise.loggedToday) min today"
            : "\(exercise.loggedToday) rep\(exercise.loggedToday == 1 ? "" : "s") today"
    }

    private var loadLabel: String {
        guard let lb = exercise.loadLb, lb > 0 else { return "" }
        return " · \(Int(lb.rounded())) lb"
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(countLabel + loadLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                WKInterfaceDevice.current().play(.success)
                store.send(.logQuickSet(exerciseId: exercise.id, amount: 1, date: Date()))
            } label: {
                Text(buttonTitle)
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .accessibilityLabel("Log \(buttonTitle) \(exercise.name)")
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading) {
            // Only meaningful once something is on today's log; the phone drops
            // the action harmlessly if its own count has already gone to zero.
            if exercise.loggedToday > 0 {
                Button {
                    WKInterfaceDevice.current().play(.click)
                    store.send(.undoQuickSet(exerciseId: exercise.id, date: Date()))
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .tint(.orange)
            }
        }
    }
}
