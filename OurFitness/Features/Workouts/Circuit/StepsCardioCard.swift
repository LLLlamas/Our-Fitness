// Circuit Train — Steps & Cardio card.
//
// - Progress ring for today's steps vs daily goal
// - Tap "/ goal" in ring centre to open goal picker (daily steps + days/week target)
// - Estimated calories for today's steps (body-weight-scaled MET formula)
// - Milestone toasts at 3k / 5k / 8k / 10k (one-shot per day)
// - "Ahead/behind yesterday at this hour" line
// - 7-day mini-bar strip
// - Weekly days goal: how many days/week to hit the daily step goal

import SwiftUI

struct StepsCardioCard: View {
    let profile: ProfileDTO
    let todaysSteps: Int
    let weeklySeries: [Trends.Point]
    let intradayToday: [Int]
    let intradayYesterday: [Int]
    let activeEnergyKcalThisWeek: Int
    let exerciseMinutesThisWeek: Int
    let streakWeeks: Int

    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter
    @State private var showDeepDive = false
    @State private var showGoalPicker = false
    @State private var showStepsInfo = false
    @State private var pickerGoal: Int = 10_000
    @State private var pickerDays: Int = 5

    @AppStorage private var firedRaw: String
    @AppStorage private var customGoalRaw: Int
    @AppStorage private var weeklyDaysGoalRaw: Int

    init(
        profile: ProfileDTO,
        todaysSteps: Int,
        weeklySeries: [Trends.Point],
        intradayToday: [Int] = [],
        intradayYesterday: [Int] = [],
        activeEnergyKcalThisWeek: Int = 0,
        exerciseMinutesThisWeek: Int = 0,
        streakWeeks: Int = 0
    ) {
        self.profile = profile
        self.todaysSteps = todaysSteps
        self.weeklySeries = weeklySeries
        self.intradayToday = intradayToday
        self.intradayYesterday = intradayYesterday
        self.activeEnergyKcalThisWeek = activeEnergyKcalThisWeek
        self.exerciseMinutesThisWeek = exerciseMinutesThisWeek
        self.streakWeeks = streakWeeks
        let key = "milestonesFired.\(profile.id.uuidString).\(Dates.dayKey())"
        _firedRaw = AppStorage(wrappedValue: "", key)
        _customGoalRaw = AppStorage(wrappedValue: 0, "stepsGoal.\(profile.id.uuidString)")
        _weeklyDaysGoalRaw = AppStorage(wrappedValue: 5, "stepsWeeklyDays.\(profile.id.uuidString)")
    }

    private var goal: Int {
        customGoalRaw > 0 ? customGoalRaw : profile.computedTargets.stepsDaily
    }
    private var weeklyDaysGoal: Int { weeklyDaysGoalRaw }
    private var pct: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(todaysSteps) / Double(goal))
    }
    private var todaysCal: Int {
        Int(CalorieEstimator.caloriesForSteps(steps: todaysSteps, bodyWeightLb: profile.weightLb))
    }

    var body: some View {
        PressableCard(action: { showDeepDive = true }) {
            VStack(alignment: .leading, spacing: 16) {
                header
                ringRow
                if let projection = EncouragementEngine.stepProjection(
                    stepsToday: todaysSteps, goalSteps: goal, bodyWeightLb: profile.weightLb
                ) {
                    ProjectionBar(text: projection)
                }
                deltaLine
                weeklyStrip
                secondaryStats
            }
        }
        .onChange(of: todaysSteps) { _, newValue in checkMilestones(steps: newValue) }
        .onAppear { checkMilestones(steps: todaysSteps) }
        .sheet(isPresented: $showDeepDive) {
            stepsDeepDivePlaceholder.themed(theme.mode)
        }
        .sheet(isPresented: $showGoalPicker) {
            goalPickerSheet.themed(theme.mode)
        }
        .sheet(isPresented: $showStepsInfo) {
            CircuitStepsInfoSheet(profile: profile, goal: goal, todaysSteps: todaysSteps, todaysCal: todaysCal)
                .themed(profile.mode)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Steps & Cardio")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
            Button { showStepsInfo = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.dim)
            }
            .tactile(.ghost)
            .accessibilityLabel("Steps & cardio health info")
            Spacer()
            StreakChip(weeks: streakWeeks, tint: theme.accent)
        }
    }

    @ViewBuilder
    private var ringRow: some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(pct: pct, color: theme.accent, trackColor: theme.barBg, lineWidth: 12)
                VStack(spacing: 2) {
                    AnimatedNumber(
                        Double(todaysSteps),
                        font: .system(size: 28, weight: .semibold),
                        color: theme.text
                    )
                    Button {
                        pickerGoal = goal
                        pickerDays = weeklyDaysGoal
                        showGoalPicker = true
                    } label: {
                        Text("/ \(goal.formatted())")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.dim)
                            .underline(color: theme.dim.opacity(0.5))
                    }
                    .tactile(.ghost)
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                // Real numbers + percentage
                Text("\(todaysSteps.formatted()) steps")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(theme.text)
                Text("\(Int(pct * 100))% of \(goal / 1000)k goal")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.dim)
                if todaysCal > 0 {
                    Text("~\(todaysCal) cal")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.accent)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var deltaLine: some View {
        let hour = Calendar.current.component(.hour, from: Date())
        let delta = Movement.stepsDeltaVsYesterday(
            intradayToday: intradayToday,
            intradayYesterday: intradayYesterday,
            currentHour: hour
        )
        if !intradayToday.isEmpty && !intradayYesterday.isEmpty {
            Text(deltaText(delta))
                .font(.caption).italic()
                .foregroundStyle(delta >= 0 ? theme.ok : theme.warn)
        }
    }

    private func deltaText(_ delta: Int) -> String {
        if delta == 0 { return "Even with yesterday at this hour." }
        let sign = delta > 0 ? "+" : "−"
        return "\(sign)\(abs(delta).formatted()) steps vs this time yesterday."
    }

    @ViewBuilder
    private var weeklyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Last 7 days")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                Spacer()
                Text("Goal \(weeklyDaysGoal) of 7 days")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.dim)
            }
            WeeklyBarStrip(series: weeklySeries, goal: Double(goal))
        }
    }

    @ViewBuilder
    private var secondaryStats: some View {
        HStack(spacing: 14) {
            statCell(label: "Active cal · wk", value: "\(activeEnergyKcalThisWeek)")
            statCell(label: "Exercise min · wk", value: "\(exerciseMinutesThisWeek)")
        }
    }

    @ViewBuilder
    private func statCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(theme.text)
        }
    }

    // MARK: - Milestones

    private func checkMilestones(steps: Int) {
        let fired = Movement.decode(firedSet: firedRaw)
        guard let milestone = Movement.shouldFireMilestone(steps: steps, firedSet: fired)
        else { return }
        toasts.stepMilestone(milestone, mode: profile.mode)
        var updated = fired
        updated.insert(milestone)
        firedRaw = Movement.encode(firedSet: updated)
    }

    // MARK: - Goal picker sheet

    @ViewBuilder
    private var goalPickerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Steps Goals")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Daily target + how many days/week to hit it.")
                    .font(.caption)
                    .foregroundStyle(theme.dim)
            }
            .padding(.top, 28)
            .padding(.horizontal, 20)

            // Daily step goal picker
            VStack(alignment: .leading, spacing: 4) {
                Text("DAILY GOAL")
                    .font(.system(size: 10, weight: .medium)).tracking(2)
                    .foregroundStyle(theme.dim)
                    .padding(.horizontal, 20)
                Picker("Daily goal", selection: $pickerGoal) {
                    ForEach(Array(stride(from: 2000, through: 25000, by: 500)), id: \.self) { val in
                        Text("\(val.formatted()) steps").tag(val)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 130)
                .background(theme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }

            // Weekly days goal
            VStack(alignment: .leading, spacing: 4) {
                Text("DAYS PER WEEK")
                    .font(.system(size: 10, weight: .medium)).tracking(2)
                    .foregroundStyle(theme.dim)
                    .padding(.horizontal, 20)
                Picker("Days per week", selection: $pickerDays) {
                    ForEach(1...7, id: \.self) { d in
                        Text("\(d) day\(d == 1 ? "" : "s") / week").tag(d)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 130)
                .background(theme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }

            HStack(spacing: 12) {
                Button("Reset to defaults") {
                    customGoalRaw = 0
                    weeklyDaysGoalRaw = 5
                    showGoalPicker = false
                }
                .tactile(.secondary, fullWidth: true)
                Button("Save") {
                    customGoalRaw = pickerGoal
                    weeklyDaysGoalRaw = pickerDays
                    showGoalPicker = false
                    Haptics.success()
                }
                .tactile(.primary, fullWidth: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
    }

    // MARK: - Deep-dive placeholder

    @ViewBuilder
    private var stepsDeepDivePlaceholder: some View {
        VStack(spacing: 16) {
            Text("steps.")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(theme.text)
            Text("Hourly chart, week vs. last week, longest streak — coming in the next round.")
                .font(.callout).foregroundStyle(theme.dim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.top, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium])
        .presentationBackground(theme.bg)
    }
}

// MARK: - Circuit steps & cardio info sheet

private struct CircuitStepsInfoSheet: View {
    let profile: ProfileDTO
    let goal: Int
    let todaysSteps: Int
    let todaysCal: Int

    @Environment(\.theme) private var theme

    // At an easy walking pace, roughly half your calories come from fat (~9 cal/g).
    private var fatGrams: Int { max(0, Int((Double(todaysCal) * 0.50 / 9.0).rounded())) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("steps & cardio.")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("CIRCUIT — YOUR MOVEMENT ENGINE")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                infoSection(title: "Your numbers today") {
                    VStack(alignment: .leading, spacing: 8) {
                        metRow(label: "Calories burned walking", detail: "≈\(todaysCal) cal from \(todaysSteps.formatted()) steps")
                        metRow(label: "Roughly how much was fat", detail: "~\(fatGrams)g — about half your walking calories come from fat at an easy pace")
                    }
                }

                infoSection(title: "Why your \(goal.formatted())-step goal") {
                    Text(TargetRationale.stepsWhy(mode: .circuit, goal: goal))
                        .font(.callout).foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }

                infoSection(title: "What walking does for you") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("It's your most repeatable daily calorie burn — and the easiest to keep up while you're losing weight.")
                        bullet("Walking regularly brings blood pressure down a few points over a couple of months.")
                        bullet("Every extra 1,000–2,000 steps a day lowers your risk of dying early, with most of the gain by about 7,000–8,000 steps.")
                        bullet("A single walk improves how your body handles blood sugar for the next day or two.")
                    }
                }

                infoSection(title: "Add some cardio") {
                    bullet("Easy, steady cardio — a pace where you can still talk — nudges your 'good' cholesterol (HDL) up a couple of points and lowers the fat in your blood (triglycerides) by about 10–20% over a couple of months.")
                    bullet("Steps plus a little cardio together do more for your cholesterol and blood pressure than either alone — pair them with the food tips in Nutrition.")
                }

                Text("Sources: Saint-Maurice et al., JAMA, 2020; Hanson & Jones, Br J Sports Med, 2015; Kodama et al., Arch Intern Med, 2007; Ainsworth et al., 2011 Compendium.")
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption).tracking(2).foregroundStyle(theme.dim)
            content()
        }
    }

    @ViewBuilder
    private func metRow(label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
            Text(detail).font(.system(.footnote, design: .monospaced)).foregroundStyle(theme.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·").foregroundStyle(theme.accent).font(.callout)
            Text(text).font(.callout).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
