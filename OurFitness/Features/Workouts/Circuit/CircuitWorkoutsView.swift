// Circuit Train — Steps card, Pilates card, inline baby-exercise quick-log.
// No cardio session log (steps already cover daily movement).
// Baby exercises show tap-to-add buttons right on this screen — no sheet needed.

import SwiftUI
import SwiftData

struct CircuitWorkoutsView: View {
    let profile: ProfileDTO

    @Environment(\.theme) private var theme
    @Query private var stepModels: [StepCountModel]

    private var stepsForProfile: [StepCountDTO] {
        stepModels.map(\.snapshot).filter { $0.userId == profile.id }
    }
    private var todaysSteps: Int {
        Steps.stepsForDay(stepsForProfile, day: Dates.dayKey())
    }
    private var weeklySteps: [Trends.Point] {
        Steps.series(stepsForProfile, days: 7)
    }
    private var stepStreakWeeks: Int {
        Movement.stepWeeklyStreak(
            steps: stepsForProfile,
            dailyGoal: profile.computedTargets.stepsDaily
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("train.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)

                StepsCardioCard(
                    profile: profile,
                    todaysSteps: todaysSteps,
                    weeklySeries: weeklySteps,
                    intradayToday: [],
                    intradayYesterday: [],
                    activeEnergyKcalThisWeek: 0,
                    exerciseMinutesThisWeek: 0,
                    streakWeeks: stepStreakWeeks
                )
                focusFooter(.steps)

                Card { PilatesCard(profile: profile) }
                focusFooter(.pilates)

                BabyExercisesCard(profile: profile)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }

    @ViewBuilder
    private func focusFooter(_ kind: Movement.CircuitFocusKind) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(Movement.circuitFocusBlurb(for: kind))
                .font(.caption).italic()
                .foregroundStyle(theme.dim)
            FocusInfoButton(kind: kind)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Focus info button (ⓘ opens full sheet — avoids popover clipping on iPhone)

private struct FocusInfoButton: View {
    let kind: Movement.CircuitFocusKind
    @State private var show = false
    @Environment(\.theme) private var theme

    var body: some View {
        Button { show = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(theme.dim)
        }
        .tactile(.ghost)
        .sheet(isPresented: $show) {
            FocusInfoSheet(kind: kind)
                .themed(theme.mode)
        }
    }
}

private struct FocusInfoSheet: View {
    let kind: Movement.CircuitFocusKind
    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(kind.title.uppercased())
                    .font(.caption).tracking(2)
                    .foregroundStyle(theme.dim)
                Text(kind.infoDetail)
                    .font(.callout)
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                    .background(theme.line)
                Text(kind.citation)
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

private extension Movement.CircuitFocusKind {
    var title: String {
        switch self {
        case .steps:   return "Why steps?"
        case .pilates: return "Why pilates?"
        case .cardio:  return "Why cardio?"
        }
    }

    var infoDetail: String {
        switch self {
        case .steps:
            return "Walking is dose-responsive: every additional 2,000 steps/day reduces cardiovascular mortality risk by ~8–11%. Even modest step increases (3,000–5,000 baseline → 7,000–10,000) measurably lower LDL cholesterol, systolic blood pressure, and fasting insulin — without requiring structured exercise.\n\nMuscles worked: calves, quads, glutes, hip flexors, core stabilisers. Over time: cardiovascular system, metabolic rate."
        case .pilates:
            return "Core and postural strength from Pilates reduces lower-back pain, improves balance, and lowers resting blood pressure through parasympathetic activation. Mind-body practices showing ≥8 weeks of consistent training reduce systolic BP by 4–8 mmHg on average.\n\nMuscles worked: transverse abdominis, obliques, erector spinae, glutes, hip flexors — depends on focus area."
        case .cardio:
            return "Zone-2 cardio (conversational pace) trains mitochondrial density, raises HDL, lowers triglycerides, and improves insulin sensitivity. As little as 150 min/week of moderate-intensity activity reduces cardiovascular disease risk by ~35%.\n\nMuscles worked: heart muscle (cardiac output), lower body (quads, hamstrings, calves), core stabilisers."
        }
    }

    var citation: String {
        switch self {
        case .steps:
            return "Source: Paluch et al., JAMA Network Open, 2021. Steps-per-day and all-cause mortality."
        case .pilates:
            return "Source: Kloubec JA, J Strength Cond Res, 2010; Bernardo LM, Clin J Oncol Nurs, 2007."
        case .cardio:
            return "Source: U.S. Physical Activity Guidelines Advisory Committee, 2018."
        }
    }
}
