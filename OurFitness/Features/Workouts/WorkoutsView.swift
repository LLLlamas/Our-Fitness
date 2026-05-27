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
    @State private var showAddSheet = false
    @State private var activeRepCounter: ExerciseDTO?

    private var myExercises: [ExerciseDTO] {
        let target = profile.id
        return exerciseModels.map(\.snapshot)
            .filter { $0.profileId == target }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("train.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Hypertrophy bias. Add your lifts, count reps, log sets.")
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
                            Text("Tap Add to build your list. Each entry remembers its rep range and whether it tracks weight.")
                                .font(.caption).foregroundStyle(theme.dim)
                        }
                    }
                } else {
                    ForEach(myExercises) { ex in
                        PressableCard(action: { activeRepCounter = ex }) {
                            exerciseRow(ex)
                        }
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
    }

    @ViewBuilder
    private func exerciseRow(_ ex: ExerciseDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ex.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.text)
                if let r = ex.defaultRepRange, r.count == 2 {
                    Text("\(r[0])–\(r[1]) reps · \(ex.category == .compound ? "with weight" : "bodyweight")")
                        .font(.caption).foregroundStyle(theme.dim)
                }
            }
            Spacer()
            Image(systemName: "hand.tap.fill")
                .foregroundStyle(theme.accent)
        }
    }
}

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

                TextField("Name (e.g. Bench Press)", text: $name)
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
