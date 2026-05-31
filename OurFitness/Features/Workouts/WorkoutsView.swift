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

    // MARK: - Rep history helpers

    private func repStats(for exercise: ExerciseDTO) -> (today: Int, yesterday: Int, week: Int, todayCal: Double) {
        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let yesterdayStart = cal.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        var isoCal = Calendar(identifier: .iso8601)
        isoCal.firstWeekday = 2
        let weekInterval = isoCal.dateInterval(of: .weekOfYear, for: now)

        var today = 0, yesterday = 0, week = 0
        var todayCal: Double = 0

        for s in mySets where s.exerciseId == exercise.id {
            let ts = s.timestamp
            if ts >= todayStart {
                today += s.reps
                todayCal += s.caloriesEst ?? 0
            } else if ts >= yesterdayStart {
                yesterday += s.reps
            }
            if let w = weekInterval, w.contains(ts) {
                week += s.reps
            }
        }
        return (today, yesterday, week, todayCal)
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
            AddExerciseSheet(profileId: profile.id) { name, lo, hi, tracksWeight in
                Repos.createExercise(
                    ctx, profileId: profile.id, name: name,
                    defaultRepsBottom: lo, defaultRepsTop: hi,
                    tracksWeight: tracksWeight
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
        let stats = repStats(for: ex)
        let info = ExerciseInfo.meta(for: ex)

        PressableCard(action: { activeRepCounter = ex }) {
            VStack(alignment: .leading, spacing: 10) {
                // Name row + info button
                HStack(alignment: .top) {
                    Text(ex.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Button { activeInfo = ex } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(theme.dim)
                    }
                    .tactile(.ghost)
                }

                // Muscles
                Text(info.muscleGroups.prefix(3).joined(separator: " · "))
                    .font(.system(size: 11, weight: .medium)).tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(theme.accent)

                // Rep counters row
                HStack(spacing: 0) {
                    repCell(label: "Today", reps: stats.today,
                            cal: stats.todayCal > 0 ? stats.todayCal : nil)
                    Divider().frame(height: 32).background(theme.line).padding(.horizontal, 8)
                    repCell(label: "Yesterday", reps: stats.yesterday, cal: nil)
                    Divider().frame(height: 32).background(theme.line).padding(.horizontal, 8)
                    repCell(label: "This week", reps: stats.week, cal: nil)
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
}

// MARK: - Add exercise sheet

private struct AddExerciseSheet: View {
    let profileId: UUID
    let onSave: (String, Int, Int, Bool) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var lo: Int = 8
    @State private var hi: Int = 12
    @State private var tracksWeight: Bool = true

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && lo > 0 && hi >= lo
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("add exercise.")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(theme.text)

                TextField("Name (e.g. Pull-ups)", text: $name)
                    .padding(10).background(theme.card)
                    .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                    .foregroundStyle(theme.text)

                HStack(spacing: 10) {
                    numField("Min reps", value: $lo)
                    numField("Max reps", value: $hi)
                }

                Toggle(isOn: $tracksWeight) {
                    Text("Tracks weight")
                        .foregroundStyle(theme.text)
                }
                .tint(theme.accent)

                Button {
                    onSave(name.trimmingCharacters(in: .whitespaces), lo, hi, tracksWeight)
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
    }

    @ViewBuilder
    private func numField(_ label: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9)).tracking(2)
                .foregroundStyle(theme.dim)
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .padding(10).background(theme.card)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
                .font(.system(.callout, design: .monospaced))
        }
    }
}
