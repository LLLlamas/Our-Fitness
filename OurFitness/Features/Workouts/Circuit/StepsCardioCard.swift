// Circuit Train — Steps & Cardio card.
//
// - Progress ring for today's steps vs goal
// - Tap "/ goal" in ring center to open goal picker (persists per profile in AppStorage)
// - Milestone toasts at 3k / 5k / 8k / 10k (one-shot per day; gated via @AppStorage)
// - "Ahead/behind yesterday at this hour" line (pure helper in Domain)
// - 7-day mini-bar strip

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
    @State private var pickerGoal: Int = 10_000

    @AppStorage private var firedRaw: String
    @AppStorage private var customGoalRaw: Int

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
    }

    private var goal: Int {
        customGoalRaw > 0 ? customGoalRaw : profile.computedTargets.stepsDaily
    }
    private var pct: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(todaysSteps) / Double(goal))
    }

    var body: some View {
        PressableCard(action: { showDeepDive = true }) {
            VStack(alignment: .leading, spacing: 16) {
                header
                ringRow
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
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Steps & Cardio")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
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
                Text("\(Int(pct * 100))% of \(goal / 1000)k")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(theme.text)
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
        return "\(sign)\(abs(delta)) vs this time yesterday."
    }

    @ViewBuilder
    private var weeklyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            HStack(alignment: .bottom, spacing: 6) {
                let peak = max(Double(goal), weeklySeries.map(\.value).max() ?? 1)
                ForEach(Array(weeklySeries.enumerated()), id: \.offset) { _, point in
                    let h = max(2, CGFloat(point.value / peak) * 36)
                    Rectangle()
                        .fill(point.value >= Double(goal) ? theme.accent : theme.dim.opacity(0.45))
                        .frame(width: 18, height: h)
                }
            }
            .frame(height: 38)
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
        toasts.stepsMilestone(milestone)
        var updated = fired
        updated.insert(milestone)
        firedRaw = Movement.encode(firedSet: updated)
    }

    // MARK: - Goal picker sheet

    @ViewBuilder
    private var goalPickerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Daily Steps Goal")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Tap a goal to set it. Mode default is \(profile.computedTargets.stepsDaily.formatted()).")
                    .font(.caption)
                    .foregroundStyle(theme.dim)
            }
            .padding(.top, 28)
            .padding(.horizontal, 20)

            Picker("Goal", selection: $pickerGoal) {
                ForEach(Array(stride(from: 2000, through: 25000, by: 500)), id: \.self) { val in
                    Text("\(val.formatted()) steps").tag(val)
                }
            }
            .pickerStyle(.wheel)

            HStack(spacing: 12) {
                Button("Reset to default") {
                    customGoalRaw = 0
                    showGoalPicker = false
                }
                .tactile(.secondary, fullWidth: true)
                Button("Save") {
                    customGoalRaw = pickerGoal
                    showGoalPicker = false
                    Haptics.success()
                }
                .tactile(.primary, fullWidth: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}
