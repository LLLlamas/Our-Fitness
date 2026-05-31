import SwiftUI
import SwiftData

struct WorkoutsView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme

    var body: some View {
        BuildWorkoutsView(profile: profile)
            .background(theme.bg.ignoresSafeArea())
    }
}

// MARK: - Build mode

private struct BuildWorkoutsView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var exerciseModels: [ExerciseModel]
    @Query private var setModels: [WorkoutSetModel]

    @State private var showAddSheet = false
    @State private var activeRepCounter: ExerciseDTO?
    @State private var activeInfo: ExerciseDTO?

    private var myExercises: [ExerciseDTO] {
        let target = profile.id
        return exerciseModels.map(\.snapshot)
            .filter { $0.profileId == target }
            .sorted { $0.name < $1.name }
    }

    private var mySets: [WorkoutSetDTO] {
        setModels.map(\.snapshot).filter { $0.userId == profile.id }
    }

    // MARK: - Stats helpers

    private struct ExerciseStats {
        var todayReps: Int = 0
        var yesterdayReps: Int = 0
        var weekReps: Int = 0
        var todayCal: Double = 0
        var todayHoldSec: Int = 0
        var weekHoldSec: Int = 0
    }

    private func exerciseStats(for exercise: ExerciseDTO) -> ExerciseStats {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        var isoCal = Calendar(identifier: .iso8601)
        isoCal.firstWeekday = 2
        let weekInterval = isoCal.dateInterval(of: .weekOfYear, for: now)

        var stats = ExerciseStats()
        for s in mySets where s.exerciseId == exercise.id {
            let ts = s.timestamp
            let inToday = ts >= todayStart
            let inYesterday = !inToday && ts >= yesterdayStart
            let inWeek = weekInterval?.contains(ts) ?? false

            if inToday {
                if exercise.isIsometric {
                    stats.todayHoldSec += s.holdSeconds ?? 0
                }
                stats.todayReps += s.reps
                stats.todayCal += s.caloriesEst ?? 0
            } else if inYesterday {
                stats.yesterdayReps += s.reps
            }
            if inWeek {
                stats.weekReps += s.reps
                if exercise.isIsometric {
                    stats.weekHoldSec += s.holdSeconds ?? 0
                }
            }
        }
        return stats
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("train.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Hypertrophy bias. Add your lifts, count reps, watch the numbers climb.")
                    .font(.callout).foregroundStyle(theme.dim)

                HStack {
                    Text("Your exercises")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Button { showAddSheet = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add")
                        }
                    }
                    .tactile(.pill, fill: theme.accent)
                }

                if myExercises.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No exercises yet.")
                                .font(.callout).foregroundStyle(theme.text)
                            Text("Tap Add to build your list. Each entry tracks reps, calories, and muscle history.")
                                .font(.caption).foregroundStyle(theme.dim)
                        }
                    }
                } else {
                    ForEach(myExercises) { ex in
                        exerciseCard(ex)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .sheet(isPresented: $showAddSheet) {
            AddExerciseSheet(profileId: profile.id) { name, lo, hi, tracksWeight, isIsometric in
                Repos.createExercise(
                    ctx, profileId: profile.id, name: name,
                    defaultRepsBottom: lo, defaultRepsTop: hi,
                    tracksWeight: tracksWeight,
                    isIsometric: isIsometric
                )
                Haptics.bump()
                toasts.show(Toast(title: name, detail: "Exercise added", accent: .win, symbol: "plus.circle.fill"))
            }
            .themed(profile.mode)
        }
        .sheet(item: $activeRepCounter) { ex in
            RepCounterSheet(profile: profile, exercise: ex)
                .themed(profile.mode)
        }
        .sheet(item: $activeInfo) { ex in
            BuildExerciseInfoSheet(exercise: ex, profile: profile)
                .themed(profile.mode)
        }
    }

    @ViewBuilder
    private func exerciseCard(_ ex: ExerciseDTO) -> some View {
        let stats = exerciseStats(for: ex)
        let info = ExerciseInfo.meta(for: ex)

        PressableCard(action: { activeRepCounter = ex }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(theme.text)
                        if ex.isIsometric {
                            Text("Isometric")
                                .font(.system(size: 10, weight: .medium)).tracking(1)
                                .textCase(.uppercase)
                                .foregroundStyle(theme.accent.opacity(0.7))
                        }
                    }
                    Spacer()
                    Button { activeInfo = ex } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(theme.dim)
                    }
                    .tactile(.ghost)
                }

                Text(info.muscleGroups.prefix(3).joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium)).tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.accent)

                HStack(spacing: 0) {
                    if ex.isIsometric {
                        holdCell(label: "Today", seconds: stats.todayHoldSec,
                                 holds: stats.todayReps, cal: stats.todayCal > 0 ? stats.todayCal : nil)
                        Divider().frame(height: 32).background(theme.line).padding(.horizontal, 8)
                        holdCell(label: "This week", seconds: stats.weekHoldSec,
                                 holds: stats.weekReps, cal: nil)
                    } else {
                        repCell(label: "Today", reps: stats.todayReps,
                                cal: stats.todayCal > 0 ? stats.todayCal : nil)
                        Divider().frame(height: 32).background(theme.line).padding(.horizontal, 8)
                        repCell(label: "Yesterday", reps: stats.yesterdayReps, cal: nil)
                        Divider().frame(height: 32).background(theme.line).padding(.horizontal, 8)
                        repCell(label: "This week", reps: stats.weekReps, cal: nil)
                    }
                    Spacer()
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(theme.accent.opacity(0.5))
                        .font(.system(size: 16))
                }
            }
        }
    }

    @ViewBuilder
    private func repCell(label: String, reps: Int, cal: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(1.5)
                .foregroundStyle(theme.dim)
            Text(reps > 0 ? "\(reps)" : "—")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(reps > 0 ? theme.text : theme.dim)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: reps)
            if let c = cal, c > 0 {
                Text("~\(Int(c)) cal")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
        }
    }

    @ViewBuilder
    private func holdCell(label: String, seconds: Int, holds: Int, cal: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(1.5)
                .foregroundStyle(theme.dim)
            Text(holdLabel(seconds))
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(seconds > 0 ? theme.text : theme.dim)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: seconds)
            if holds > 0 {
                Text("\(holds) hold\(holds == 1 ? "" : "s")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
            if let c = cal, c > 0 {
                Text("~\(Int(c)) cal")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
        }
    }
}

// MARK: - Add exercise sheet

private struct AddExerciseSheet: View {
    let profileId: UUID
    let onSave: (String, Int, Int, Bool, Bool) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var tracksWeight: Bool = true
    @State private var isIsometric: Bool = false
    @FocusState private var nameFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("add exercise.")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(theme.text)

                TextField("Name (e.g. Pull-ups)", text: $name)
                    .padding(10).background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    .foregroundStyle(theme.text)
                    .focused($nameFocused)

                Toggle(isOn: $tracksWeight) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tracks weight")
                            .foregroundStyle(theme.text)
                        Text("Shows a weight field when logging")
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                }
                .tint(theme.accent)
                .disabled(isIsometric)
                .opacity(isIsometric ? 0.4 : 1)

                Toggle(isOn: $isIsometric) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Isometric hold")
                            .foregroundStyle(theme.text)
                        Text("Plank, dead hang, wall sit — counts seconds, not reps")
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                }
                .tint(theme.accent)
                .onChange(of: isIsometric) { _, on in
                    if on { tracksWeight = false }
                }

                Button {
                    onSave(name.trimmingCharacters(in: .whitespaces), 8, 12, tracksWeight, isIsometric)
                    dismiss()
                } label: {
                    Text("Save")
                }
                .tactile(.primary, fullWidth: true)
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.6)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { nameFocused = false }
            }
        }
    }
}
