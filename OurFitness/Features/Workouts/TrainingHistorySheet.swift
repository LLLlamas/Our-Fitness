import SwiftUI
import SwiftData

// MARK: - Training history sheet

/// Cross-day training history — every logged set/session grouped by day, newest first.
/// This is the home for past workouts. Opened from the Train tab and from
/// Progress. Tapping an exercise row opens `SetHistorySheet` on that day, where
/// its sets are edited, removed, or a forgotten set is added.
struct TrainingHistorySheet: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var setModels: [WorkoutSetModel]
    @Query private var exerciseModels: [ExerciseModel]
    @Query private var cardioModels: [CardioSessionModel]
    @Query private var pilatesModels: [PilatesSessionModel]
    @Query private var activityModels: [ActivitySessionModel]

    /// Exercise + day whose sets are open in `SetHistorySheet`.
    private struct SetsTarget: Identifiable {
        let exercise: ExerciseDTO
        let dayKey: String
        var id: String { "\(exercise.id)|\(dayKey)" }
    }
    @State private var setsTarget: SetsTarget?

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _setModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid },
            sort: \.timestamp, order: .reverse
        )
        _exerciseModels = Query(
            filter: #Predicate<ExerciseModel> { $0.profileId == uid },
            sort: \.name, order: .forward
        )
        _cardioModels = Query(
            filter: #Predicate<CardioSessionModel> { $0.profileId == uid },
            sort: \.date, order: .reverse
        )
        _pilatesModels = Query(
            filter: #Predicate<PilatesSessionModel> { $0.profileId == uid },
            sort: \.date, order: .reverse
        )
        _activityModels = Query(
            filter: #Predicate<ActivitySessionModel> { $0.profileId == uid },
            sort: \.date, order: .reverse
        )
    }

    var body: some View {
        let exercises = exerciseModels.map(\.snapshot)
        let exercisesById = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sessions = TrainingHistory.sessions(sets: setModels.map(\.snapshot), exercises: exercises)
        let sessionsByDay = Dictionary(uniqueKeysWithValues: sessions.map { ($0.dayKey, $0) })
        let cardioByDay = Dictionary(grouping: cardioModels.map(\.snapshot)) { Dates.dayKey($0.date) }
        let pilatesByDay = Dictionary(grouping: pilatesModels.map(\.snapshot)) { Dates.dayKey($0.date) }
        let activitiesByDay = Dictionary(grouping: activityModels.map(\.snapshot)) { Dates.dayKey($0.date) }
        let dayKeys = Set(sessions.map(\.dayKey))
            .union(cardioByDay.keys)
            .union(pilatesByDay.keys)
            .union(activitiesByDay.keys)
            .sorted(by: >)
        ScrollView {
            // Lazy: this list is unbounded by design, and an eager VStack built
            // every day section up front on open.
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training history")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("Every session, newest first · tap an exercise to edit")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                }

                if dayKeys.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No training logged yet.")
                                .font(.callout).foregroundStyle(theme.text)
                            Text("Sets, cardio, Pilates, and live sessions show up here grouped by day.")
                                .font(.caption).foregroundStyle(theme.dim)
                        }
                    }
                } else {
                    // Straight into the enclosing LazyVStack (same spacing): a
                    // second LazyVStack nested in the first is one eager child
                    // from the outer stack's point of view, which defeats it.
                    ForEach(dayKeys, id: \.self) { key in
                        daySection(
                            key,
                            exercisesById: exercisesById,
                            strength: sessionsByDay[key],
                            cardio: cardioByDay[key] ?? [],
                            pilates: pilatesByDay[key] ?? [],
                            activities: activitiesByDay[key] ?? []
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .sheet(item: $setsTarget) { target in
            SetHistorySheet(profile: profile, exercise: target.exercise, dayKey: target.dayKey)
        }
    }

    @ViewBuilder
    private func daySection(
        _ dayKey: String,
        exercisesById: [String: ExerciseDTO],
        strength: TrainingHistory.DaySession?,
        cardio cardioRows: [CardioSessionDTO],
        pilates pilatesRows: [PilatesSessionDTO],
        activities activityRows: [ActivitySessionDTO]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Dates.formatLong(dayKey))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Text(daySummary(strength: strength, cardio: cardioRows, pilates: pilatesRows, activities: activityRows))
                    .font(.caption).foregroundStyle(theme.dim)
            }
            if let strength {
                ForEach(strength.exercises) { line in
                    exerciseLineRow(line, exercise: exercisesById[line.exerciseId], dayKey: dayKey)
                }
            }
            ForEach(cardioRows) { cardioLineRow($0) }
            ForEach(pilatesRows) { pilatesLineRow($0) }
            ForEach(activityRows) { activityLineRow($0) }
        }
        .padding(12)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    private func daySummary(
        strength: TrainingHistory.DaySession?,
        cardio: [CardioSessionDTO],
        pilates: [PilatesSessionDTO],
        activities: [ActivitySessionDTO]
    ) -> String {
        let sessionCount = cardio.count + pilates.count + activities.count
        var parts: [String] = []
        if let strength, strength.totalSets > 0 {
            parts.append("\(strength.totalSets) set\(strength.totalSets == 1 ? "" : "s")")
        }
        if sessionCount > 0 {
            parts.append("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
        }
        let totalCalories = (strength?.totalCalories ?? 0)
            + cardio.reduce(0) { $0 + Int(($1.caloriesEst ?? 0).rounded()) }
            + pilates.reduce(0) {
                $0 + Int(CalorieEstimator.caloriesForPilates(minutes: Double($1.durationMinutes), bodyWeightLb: profile.weightLb).rounded())
            }
            + activities.reduce(0) { $0 + Int(($1.caloriesEst ?? 0).rounded()) }
        if totalCalories > 0 { parts.append("~\(totalCalories) cal") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func exerciseLineRow(
        _ line: TrainingHistory.ExerciseLine, exercise: ExerciseDTO?, dayKey: String
    ) -> some View {
        HStack {
            // A deleted exercise's orphaned sets have nothing to open; the row
            // stays read-only with the remove button.
            Button {
                guard let exercise else { return }
                setsTarget = SetsTarget(exercise: exercise, dayKey: dayKey)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(theme.text)
                        Text(lineDetail(line))
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                    Spacer()
                    if exercise != nil {
                        Image(systemName: "pencil")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.accent)
                    }
                }
                .contentShape(Rectangle())
            }
            .tactile(.ghost)
            .disabled(exercise == nil)
            .accessibilityLabel(exercise == nil ? line.name : "Edit \(line.name) sets")
            Button(role: .destructive) {
                removeLastSet(line)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(theme.warn)
            }
            .tactile(.ghost)
            .accessibilityLabel("Remove a set of \(line.name)")
        }
        .padding(.vertical, 4)
    }

    private func lineDetail(_ line: TrainingHistory.ExerciseLine) -> String {
        if line.isIsometric {
            return "\(line.setCount) hold\(line.setCount == 1 ? "" : "s") · \(holdLabel(line.totalHoldSeconds))"
        }
        var s = "\(line.setCount) set\(line.setCount == 1 ? "" : "s") · \(line.totalReps) rep\(line.totalReps == 1 ? "" : "s")"
        if line.calories > 0 { s += " · ~\(line.calories) cal" }
        return s
    }

    @ViewBuilder
    private func cardioLineRow(_ session: CardioSessionDTO) -> some View {
        sessionLineRow(
            icon: "figure.run",
            title: session.type.label,
            detail: "\(session.durationMinutes) min",
            calories: Int((session.caloriesEst ?? 0).rounded()),
            deleteLabel: "Delete \(session.type.label) session"
        ) {
            return Repos.deleteCardioSession(ctx, id: session.id)
        }
    }

    @ViewBuilder
    private func pilatesLineRow(_ session: PilatesSessionDTO) -> some View {
        let focus = session.focusAreas.first?.label ?? "Pilates"
        let calories = Int(CalorieEstimator.caloriesForPilates(
            minutes: Double(session.durationMinutes),
            bodyWeightLb: profile.weightLb
        ).rounded())
        sessionLineRow(
            icon: "figure.pilates",
            title: "Pilates",
            detail: "\(focus) · \(session.durationMinutes) min",
            calories: calories,
            deleteLabel: "Delete Pilates session"
        ) {
            return Repos.deletePilatesSession(ctx, id: session.id)
        }
    }

    @ViewBuilder
    private func activityLineRow(_ session: ActivitySessionDTO) -> some View {
        let symbol = ActivityCatalog.activity(id: session.activityId)?.symbol ?? "figure.mixed.cardio"
        sessionLineRow(
            icon: symbol,
            title: session.activityName,
            detail: "\(session.durationMinutes) min",
            calories: Int((session.caloriesEst ?? 0).rounded()),
            deleteLabel: "Delete \(session.activityName) session"
        ) {
            return Repos.deleteActivitySession(ctx, id: session.id)
        }
    }

    @ViewBuilder
    private func sessionLineRow(
        icon: String,
        title: String,
        detail: String,
        calories: Int,
        deleteLabel: String,
        onDelete: @escaping () -> Bool
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(calories > 0 ? "\(detail) · ~\(calories) cal" : detail)
                    .font(.caption).foregroundStyle(theme.dim)
            }
            Spacer()
            Button(role: .destructive) {
                guard onDelete() else { return }
                toasts.show(Toast(title: "Session removed", detail: title, accent: .warn, symbol: "trash.fill"))
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(theme.warn)
            }
            .tactile(.ghost)
            .accessibilityLabel(deleteLabel)
        }
        .padding(.vertical, 4)
    }

    private func removeLastSet(_ line: TrainingHistory.ExerciseLine) {
        guard let id = line.setIds.first else { return }
        guard Repos.deleteSet(ctx, id: id) else { return }
        // No Haptics.warn() here — ToastCenter fires the .warn accent's haptic.
        toasts.show(Toast(title: "Set removed", detail: line.name, accent: .warn, symbol: "trash.fill"))
    }

    private func holdLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 90 { return "\(seconds)s" }
        if seconds < 4200 {
            let m = seconds / 60; let s = seconds % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        }
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}
