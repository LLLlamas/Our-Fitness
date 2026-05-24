import SwiftUI
import SwiftData

struct WorkoutsView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var programModels: [ProgramModel]
    @Query private var exerciseModels: [ExerciseModel]

    @State private var programId: String? = nil
    @State private var dayIndex: Int = 0
    @State private var sessionId: UUID? = nil

    private var programs: [ProgramDTO] {
        programModels.map(\.snapshot).filter { $0.modeFit.contains(profile.mode) }
    }
    private var exercisesById: [String: ExerciseDTO] {
        Dictionary(uniqueKeysWithValues: exerciseModels.map(\.snapshot).map { ($0.id, $0) })
    }
    private var program: ProgramDTO? {
        programs.first { $0.id == programId } ?? programs.first
    }
    private var day: ProgramDayDTO? {
        guard let p = program, p.schedule.indices.contains(dayIndex) else { return nil }
        return p.schedule[dayIndex]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("train.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text(profile.mode == .build
                     ? "Hypertrophy bias. Double-progression. Push hard, eat harder."
                     : "Strength + zone-2 cardio. RPE cap 7 — recover hard, lose smart.")
                    .font(.callout).foregroundStyle(theme.dim)

                programRow
                dayRow
                sessionControls

                if let day {
                    ForEach(day.blocks.indices, id: \.self) { i in
                        let spec = day.blocks[i]
                        if let ex = exercisesById[spec.exerciseId], let program {
                            ExerciseBlockView(
                                profile: profile,
                                exercise: ex,
                                spec: spec,
                                scheme: program.progression,
                                sessionId: sessionId
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(theme.bg.ignoresSafeArea())
        .onAppear {
            if programId == nil { programId = programs.first?.id }
        }
        .sensoryFeedback(.selection, trigger: dayIndex)
        .sensoryFeedback(.selection, trigger: programId)
    }

    private var programRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(programs) { p in
                    Button {
                        programId = p.id
                        dayIndex = 0
                    } label: {
                        Text(p.name)
                    }
                    .tactile(.pill, fill: p.id == program?.id ? theme.accent : nil)
                }
            }
        }
    }

    @ViewBuilder
    private var dayRow: some View {
        if let program {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(program.schedule.indices, id: \.self) { i in
                        Button {
                            dayIndex = i
                        } label: {
                            Text(program.schedule[i].label)
                        }
                        .tactile(.pill, fill: i == dayIndex ? theme.accent2 : nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var sessionControls: some View {
        if let day {
            HStack {
                Text(day.label)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                Spacer()
                if let id = sessionId {
                    Button {
                        Repos.endWorkout(ctx, id: id)
                        sessionId = nil
                        Haptics.success()
                        toasts.show(Toast(title: "Session complete.",
                                          detail: "Locked in. Recovery time.",
                                          accent: .win, symbol: "flag.checkered"), for: 2.4)
                    } label: {
                        Text("Finish session")
                    }
                    .tactile(.primary, fill: theme.ok)
                } else {
                    Button {
                        if let p = program {
                            sessionId = Repos.startWorkout(ctx, userId: profile.id, programId: p.id)
                            Haptics.bump()
                        }
                    } label: {
                        Text("Start session")
                    }
                    .tactile(.primary)
                }
            }
        }
    }
}

// MARK: - ExerciseBlockView

private struct ExerciseBlockView: View {
    let profile: ProfileDTO
    let exercise: ExerciseDTO
    let spec: ProgramSetSpec
    let scheme: ProgressionScheme
    let sessionId: UUID?

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @State private var weightStr: String = ""
    @State private var repsStr: String = ""
    @State private var rpeStr: String = ""
    @State private var history: [WorkoutSetDTO] = []

    private var target: Progression.Target {
        Progression.nextTarget(scheme: scheme, spec: spec, history: history)
    }
    private var pr: WorkoutSetDTO? { Progression.personalRecord(history) }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(exercise.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text("\(spec.sets) × \(spec.repsBottom)–\(spec.repsTop)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.dim)
                }
                Text("Next: \(targetDescription) — \(target.notes)")
                    .font(.caption).italic()
                    .foregroundStyle(theme.accent2)
                if let pr {
                    Text("PR: \(pr.weightLb.map { "\(Int($0)) lb × " } ?? "")\(pr.reps) reps")
                        .font(.caption2)
                        .foregroundStyle(theme.dim)
                }

                HStack(spacing: 8) {
                    inputField("Weight", $weightStr).keyboardType(.decimalPad)
                    inputField("Reps", $repsStr).keyboardType(.numberPad)
                    inputField("RPE", $rpeStr).keyboardType(.decimalPad)
                    Button(action: commit) {
                        Text("Log")
                    }
                    .tactile(.primary)
                }

                if !history.isEmpty {
                    HStack(spacing: 8) {
                        Text("RECENT:").font(.caption2).tracking(2).foregroundStyle(theme.dim)
                        ForEach(history.prefix(5)) { s in
                            Text(recentLabel(s))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(theme.dim)
                        }
                    }
                }
            }
        }
        .onAppear { refreshHistory() }
        .onChange(of: spec.exerciseId) { _, _ in refreshHistory() }
    }

    private var targetDescription: String {
        var parts: [String] = []
        if let w = target.targetWeightLb { parts.append("\(Int(w)) lb ×") }
        parts.append("\(target.targetReps)")
        return parts.joined(separator: " ")
    }

    private func recentLabel(_ s: WorkoutSetDTO) -> String {
        let weight = s.weightLb.map { String(Int($0)) } ?? "bw"
        let rpe = s.rpe.map { "@\($0.formatted(.number.precision(.fractionLength(0...1))))" } ?? ""
        return "\(weight)×\(s.reps)\(rpe)"
    }

    @ViewBuilder
    private func inputField(_ label: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 9)).tracking(2)
                .foregroundStyle(theme.dim)
            TextField("", text: binding)
                .padding(8)
                .background(theme.barBg)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
                .font(.system(.callout, design: .monospaced))
        }
    }

    private func commit() {
        guard let reps = Int(repsStr), reps > 0 else { return }
        let weight = Double(weightStr)
        let rpe = Double(rpeStr)

        // Detect PR before insert
        let priorPR = Progression.personalRecord(history)
        let beatsPR: Bool = {
            guard let priorPR else { return weight != nil }
            let priorWeight = priorPR.weightLb ?? 0
            let newWeight = weight ?? 0
            if newWeight > priorWeight { return true }
            if newWeight == priorWeight && reps > priorPR.reps { return true }
            return false
        }()

        let dto = WorkoutSetDTO(
            userId: profile.id, exerciseId: exercise.id, workoutId: sessionId,
            weightLb: weight, reps: reps, rpe: rpe
        )
        Repos.addSet(ctx, dto)
        rpeStr = ""
        refreshHistory()

        if beatsPR {
            toasts.pr(exercise.name, weightLb: weight, reps: reps)
        } else {
            Haptics.bump()
        }
    }

    private func refreshHistory() {
        history = Repos.setHistory(ctx, userId: profile.id, exerciseId: exercise.id, limit: 20)
        if let w = target.targetWeightLb, weightStr.isEmpty { weightStr = String(Int(w)) }
        if repsStr.isEmpty { repsStr = String(target.targetReps) }
    }
}
