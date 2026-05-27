// Circuit Train — stacks the movement cards the user actually engages with
// (Steps & Cardio, Pilates, Cardio session log, Rep counter). No program
// picker, no strength blocks: cardiovascular markers move on volume, not PRs.

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
                Text("Steps, cardio, and Pilates move the markers.")
                    .font(.callout).foregroundStyle(theme.dim)

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

                Card { CardioLogCard(profile: profile) }
                focusFooter(.cardio)

                Card { RepCounterCard(profile: profile) }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
    }

    @ViewBuilder
    private func focusFooter(_ kind: Movement.CircuitFocusKind) -> some View {
        Text(Movement.circuitFocusBlurb(for: kind))
            .font(.caption).italic()
            .foregroundStyle(theme.dim)
            .padding(.horizontal, 4)
    }
}
