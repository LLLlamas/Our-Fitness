// Steps card — the one steps surface. Renders on Today only, embedded at the
// top of `MoveCard` once Health is connected (standalone before that).
//
// ProgressRing + projection + pace-vs-yesterday + 7-day strip + this-week
// active energy / exercise minutes, a weekly streak chip, and milestone toasts.
// The goal changes only the default daily target (and copy tone); every user
// sees the same card, the same two-wheel goal picker and the same info sheet.

import SwiftUI

/// The per-profile steps-goal overrides. The one place these keys are spelled on
/// the phone, so the card's picker and TodayView's streak math can't drift apart.
/// (`WatchSyncService` reads the daily key by name to put the goal on the wrist.)
enum StepsGoalPrefs {
    static func dailyKey(_ profileId: UUID) -> String { "stepsGoal.\(profileId.uuidString)" }
    static func weeklyDaysKey(_ profileId: UUID) -> String { "stepsWeeklyDays.\(profileId.uuidString)" }
    static let defaultWeeklyDays = 5

    /// A stored 0 means "no override" — fall back to the goal's default.
    static func resolve(custom: Int, goalDefault: Int) -> Int {
        custom > 0 ? custom : goalDefault
    }
}

struct StepsCard: View {
    let profile: ProfileDTO
    let steps: Int
    let weeklySeries: [Trends.Point]
    let streakWeeks: Int
    /// 24-element cumulative hourly step totals (today / yesterday) from HealthKit.
    /// Empty when Health has no samples — the pace line then hides itself.
    let intradayToday: [Int]
    let intradayYesterday: [Int]
    /// nil = Health gave us nothing for the window; the stat hides rather than reading 0.
    let activeEnergyKcalThisWeek: Int?
    let exerciseMinutesThisWeek: Int?
    /// Inside `MoveCard`: no card chrome of its own.
    let embedded: Bool

    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @AppStorage private var customGoalRaw: Int
    @AppStorage private var weeklyDaysGoalRaw: Int
    @AppStorage private var firedRaw: String

    @State private var showGoalPicker = false
    @State private var showInfo = false
    @State private var pickerGoal: Int = 10_000
    @State private var pickerDays: Int = StepsGoalPrefs.defaultWeeklyDays

    init(
        profile: ProfileDTO,
        steps: Int,
        weeklySeries: [Trends.Point] = [],
        streakWeeks: Int = 0,
        intradayToday: [Int] = [],
        intradayYesterday: [Int] = [],
        activeEnergyKcalThisWeek: Int? = nil,
        exerciseMinutesThisWeek: Int? = nil,
        embedded: Bool = false
    ) {
        self.profile = profile
        self.steps = steps
        self.weeklySeries = weeklySeries
        self.streakWeeks = streakWeeks
        self.intradayToday = intradayToday
        self.intradayYesterday = intradayYesterday
        self.activeEnergyKcalThisWeek = activeEnergyKcalThisWeek
        self.exerciseMinutesThisWeek = exerciseMinutesThisWeek
        self.embedded = embedded
        let uid = profile.id
        _customGoalRaw = AppStorage(wrappedValue: 0, StepsGoalPrefs.dailyKey(uid))
        _weeklyDaysGoalRaw = AppStorage(
            wrappedValue: StepsGoalPrefs.defaultWeeklyDays, StepsGoalPrefs.weeklyDaysKey(uid)
        )
        _firedRaw = AppStorage(wrappedValue: "", "milestonesFired.\(uid.uuidString).\(Dates.dayKey())")
    }

    private var fitnessGoal: FitnessGoal { profile.fitnessGoal }
    private var defaultGoal: Int { profile.computedTargets.stepsDaily }
    private var goal: Int { StepsGoalPrefs.resolve(custom: customGoalRaw, goalDefault: defaultGoal) }
    private var weeklyDaysGoal: Int { weeklyDaysGoalRaw }
    private var stepsKcal: Int {
        Int(CalorieEstimator.caloriesForSteps(steps: steps, bodyWeightLb: profile.weightLb).rounded())
    }
    private var pct: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(steps) / Double(goal))
    }
    private var ok: Bool { goal > 0 && steps >= goal }
    /// Nothing from Health for today — the count reads as a dash, not a 0.
    private var hasData: Bool { profile.healthGranted && steps > 0 }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(embedded ? "Steps" : "Steps & Cardio")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                infoButton
                Spacer()
                StreakChip(weeks: streakWeeks, tint: theme.accent)
            }

            ringRow

            if hasData, let projection = EncouragementEngine.stepProjection(
                stepsToday: steps, goalSteps: goal, bodyWeightLb: profile.weightLb
            ) {
                ProjectionBar(text: projection)
            }

            paceLine
            weeklyStrip
            secondaryStats
        }
    }

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                Card(padding: 16) { content }
            }
        }
        .onChange(of: steps) { oldValue, newValue in
            let toasted = checkMilestones(steps: newValue)
            // The milestone toast already fires its own haptic — only add the
            // goal-hit one when no toast went out on this change.
            if !toasted && goal > 0 && oldValue < goal && newValue >= goal {
                Haptics.success()
            }
        }
        .onAppear {
            checkMilestones(steps: steps)
        }
        .sheet(isPresented: $showGoalPicker) {
            goalPickerSheet
        }
        .sheet(isPresented: $showInfo) {
            StepsInfoSheet(steps: steps, goal: goal, stepsKcal: stepsKcal, fitnessGoal: fitnessGoal)
        }
    }

    @ViewBuilder
    private var ringRow: some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(pct: hasData ? pct : 0,
                             color: ok ? theme.ok : theme.accent,
                             trackColor: theme.barBg, lineWidth: 12)
                VStack(spacing: 2) {
                    if hasData {
                        AnimatedNumber(
                            Double(steps),
                            font: .system(size: 28, weight: .semibold),
                            color: theme.text
                        )
                    } else {
                        Text("—")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(theme.dim)
                    }
                    goalButton(label: "/ \(goal.formatted())")
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text("Today")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    if ok {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(theme.ok)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                if hasData {
                    // Real numbers + percentage
                    Text("\(steps.formatted()) steps")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(theme.text)
                    Text("\(Int(pct * 100))% of \(goal / 1000)k goal")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ok ? theme.ok : theme.dim)
                    if stepsKcal > 0 {
                        Text("~\(stepsKcal) cal")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.accent)
                    }
                } else {
                    Text("No data from Health yet.")
                        .font(.caption2)
                        .foregroundStyle(theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "Ahead/behind yesterday at this hour" — only when Health returned both days.
    @ViewBuilder
    private var paceLine: some View {
        if intradayToday.count == 24 && intradayYesterday.count == 24 {
            let delta = Movement.stepsDeltaVsYesterday(
                intradayToday: intradayToday,
                intradayYesterday: intradayYesterday,
                currentHour: Calendar.current.component(.hour, from: Date())
            )
            Text(paceText(delta))
                .font(.caption).italic()
                .foregroundStyle(delta >= 0 ? theme.ok : theme.warn)
        }
    }

    private func paceText(_ delta: Int) -> String {
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

    /// Week-to-date Health totals. A missing value hides its cell rather than
    /// reading a misleading 0.
    @ViewBuilder
    private var secondaryStats: some View {
        if activeEnergyKcalThisWeek != nil || exerciseMinutesThisWeek != nil {
            HStack(spacing: 14) {
                if let cal = activeEnergyKcalThisWeek {
                    statCell(label: "Active cal · week", value: cal.formatted())
                }
                if let minutes = exerciseMinutesThisWeek {
                    statCell(label: "Exercise min · week", value: minutes.formatted())
                }
                Spacer(minLength: 0)
            }
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

    // MARK: - Controls

    private var infoButton: some View {
        Button { showInfo = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(theme.dim)
        }
        .tactile(.ghost)
        .accessibilityLabel("Steps health info")
    }

    private func goalButton(label: String) -> some View {
        Button {
            pickerGoal = goal
            pickerDays = weeklyDaysGoal
            showGoalPicker = true
        } label: {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(theme.dim)
                .underline(color: theme.dim.opacity(0.5))
        }
        .tactile(.ghost)
        .accessibilityLabel("Edit daily steps goal")
    }

    // MARK: - Milestones

    /// Returns true when a milestone toast went out (it carries its own haptic).
    @discardableResult
    private func checkMilestones(steps: Int) -> Bool {
        let fired = Movement.decode(firedSet: firedRaw)
        guard let milestone = Movement.shouldFireMilestone(steps: steps, firedSet: fired)
        else { return false }
        toasts.stepMilestone(milestone)
        var updated = fired
        updated.insert(milestone)
        firedRaw = Movement.encode(firedSet: updated)
        return true
    }

    // MARK: - Goal picker sheet

    // One sheet on the shared `GoalPickerSheet` chrome: a daily-target wheel plus
    // the days/week wheel that drives the streak chip.
    private var goalPickerSheet: some View {
        GoalPickerSheet(
            title: "Steps Goals",
            subtitle: "Daily target + how many days/week to hit it. Default is \(defaultGoal.formatted()) steps.",
            wheels: goalWheels,
            resetLabel: "Reset to defaults",
            detents: [.large],
            onReset: {
                customGoalRaw = 0
                weeklyDaysGoalRaw = StepsGoalPrefs.defaultWeeklyDays
                showGoalPicker = false
            },
            onSave: {
                customGoalRaw = pickerGoal
                weeklyDaysGoalRaw = pickerDays
                showGoalPicker = false
            }
        )
    }

    private var goalWheels: [GoalPickerSheet.Wheel] {
        [
            .init(
                id: "daily",
                label: "DAILY GOAL",
                pickerTitle: "Daily goal",
                options: Array(stride(from: 2000, through: 25000, by: 500)),
                optionLabel: { "\($0.formatted()) steps" },
                selection: $pickerGoal,
                height: 130
            ),
            .init(
                id: "weeklyDays",
                label: "DAYS PER WEEK",
                pickerTitle: "Days per week",
                options: Array(1...7),
                optionLabel: { "\($0) day\($0 == 1 ? "" : "s") / week" },
                selection: $pickerDays,
                height: 130
            )
        ]
    }
}

// MARK: - Steps info sheet

// One copy of the fat-grams math and the Tudor-Locke activity categories.
private struct StepsInfoSheet: View {
    let steps: Int
    let goal: Int
    let stepsKcal: Int
    let fitnessGoal: FitnessGoal

    @Environment(\.theme) private var theme

    // Fat burned: at an easy walking pace roughly half your calories come from
    // burning fat (the share drops as you speed up). Source: Achten & Jeukendrup,
    // Nutrition, 2004. ~9 cal per gram of fat.
    private var fatGrams: Int { max(0, Int((Double(stepsKcal) * 0.50 / 9.0).rounded())) }

    // Step category per Tudor-Locke & Bassett (2004) classification, in plain English.
    private var stepCategory: (label: String, description: String) {
        switch steps {
        case 0..<5000:
            return ("Sedentary", "Under 5,000 steps.")
        case 5000..<7500:
            return ("Low active", "5,000–7,499 steps.")
        case 7500..<10000:
            return ("Somewhat active", "7,500–9,999 steps.")
        case 10000..<12500:
            return ("Active", "10,000+ steps.")
        default:
            return ("Highly active", "12,500+ steps.")
        }
    }

    var body: some View {
        InfoSheetScaffold(
            title: "Steps & cardio",
            subtitle: "TODAY · \(steps.formatted()) STEPS"
        ) {
            InfoSection(title: "Your numbers today") {
                VStack(spacing: 8) {
                    InfoRow(label: "Calories burned walking",
                            detail: "≈\(stepsKcal) cal from \(steps.formatted()) steps",
                            emphasis: .label)
                    InfoRow(label: "Roughly how much was fat",
                            detail: "~\(fatGrams)g",
                            emphasis: .label)
                }
            }

            InfoSection(title: "Your activity level") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(stepCategory.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text(stepCategory.description)
                        .font(.callout)
                        .foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
            }

            Text(TargetRationale.stepsWhy(fitnessGoal: fitnessGoal, goal: goal))
                .font(.callout).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
