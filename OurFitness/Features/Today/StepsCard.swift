// Steps card — the one steps surface, mode-aware. Renders on Today only.
//
// Build:   label + hero count + ProgressBar against the daily goal.
// Circuit: ProgressRing + projection + pace-vs-yesterday + 7-day strip +
//          this-week active energy / exercise minutes, and milestone toasts.
//
// Both variants share one goal-picker sheet and one info sheet (one copy of the
// fat-grams math and the walking research copy). Replaced the old split between
// Features/Today/StepsCard.swift and Features/Workouts/Circuit/StepsCardioCard.swift.

import SwiftUI

/// The per-profile steps-goal overrides. Keys live here so the card's picker and
/// TodayView's streak math can't drift apart. (MoveCard still spells the daily
/// key itself — folding it in is a separate change.)
enum StepsGoalPrefs {
    static func dailyKey(_ profileId: UUID) -> String { "stepsGoal.\(profileId.uuidString)" }
    static func weeklyDaysKey(_ profileId: UUID) -> String { "stepsWeeklyDays.\(profileId.uuidString)" }
    static let defaultWeeklyDays = 5

    /// A stored 0 means "no override" — fall back to the mode default.
    static func resolve(custom: Int, modeDefault: Int) -> Int {
        custom > 0 ? custom : modeDefault
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
    let onConnectHealth: () -> Void

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
        onConnectHealth: @escaping () -> Void
    ) {
        self.profile = profile
        self.steps = steps
        self.weeklySeries = weeklySeries
        self.streakWeeks = streakWeeks
        self.intradayToday = intradayToday
        self.intradayYesterday = intradayYesterday
        self.activeEnergyKcalThisWeek = activeEnergyKcalThisWeek
        self.exerciseMinutesThisWeek = exerciseMinutesThisWeek
        self.onConnectHealth = onConnectHealth
        let uid = profile.id
        _customGoalRaw = AppStorage(wrappedValue: 0, StepsGoalPrefs.dailyKey(uid))
        _weeklyDaysGoalRaw = AppStorage(
            wrappedValue: StepsGoalPrefs.defaultWeeklyDays, StepsGoalPrefs.weeklyDaysKey(uid)
        )
        _firedRaw = AppStorage(wrappedValue: "", "milestonesFired.\(uid.uuidString).\(Dates.dayKey())")
    }

    private var mode: Mode { profile.mode }
    private var defaultGoal: Int { profile.computedTargets.stepsDaily }
    private var goal: Int { StepsGoalPrefs.resolve(custom: customGoalRaw, modeDefault: defaultGoal) }
    private var weeklyDaysGoal: Int { weeklyDaysGoalRaw }
    private var stepsKcal: Int {
        Int(CalorieEstimator.caloriesForSteps(steps: steps, bodyWeightLb: profile.weightLb).rounded())
    }
    private var pct: Double {
        guard goal > 0 else { return 0 }
        return min(1, Double(steps) / Double(goal))
    }
    private var ok: Bool { steps >= goal }
    private var hasData: Bool { steps > 0 }

    var body: some View {
        Card(padding: 16) {
            if mode == .circuit {
                circuitBody
            } else {
                buildBody
            }
        }
        .onChange(of: steps) { _, newValue in
            if mode == .circuit { checkMilestones(steps: newValue) }
        }
        .onAppear {
            if mode == .circuit { checkMilestones(steps: steps) }
        }
        .sheet(isPresented: $showGoalPicker) {
            goalPickerSheet.themed(theme.mode)
        }
        .sheet(isPresented: $showInfo) {
            StepsInfoSheet(steps: steps, goal: goal, stepsKcal: stepsKcal, mode: mode)
                .themed(mode)
        }
    }

    // MARK: - Build variant

    @ViewBuilder
    private var buildBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STEPS TODAY")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(theme.dim)
                infoButton
                Spacer()
                // The bar below already prints the goal — this is just the affordance.
                goalButton(label: "Edit goal")
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if profile.healthGranted && hasData {
                    AnimatedNumber(
                        Double(steps),
                        font: .system(size: 44, weight: .regular),
                        color: theme.text
                    )
                    .tweenStat(steps)
                } else {
                    Text("—")
                        .font(.system(size: 44, weight: .regular))
                        .foregroundStyle(theme.dim)
                }
                Spacer()
            }

            if hasData && stepsKcal > 0 {
                Text("~\(stepsKcal) cal burned")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }

            ProgressBar(value: Double(steps), target: Double(goal), label: "steps")

            buildFooter
        }
    }

    @ViewBuilder
    private var buildFooter: some View {
        if !profile.healthGranted {
            Button(action: onConnectHealth) {
                HStack(spacing: 6) {
                    Image(systemName: "heart.text.square")
                    Text("Connect Apple Health")
                }
            }
            .tactile(.pill, fill: theme.accent)
        } else if !hasData {
            HStack(spacing: 6) {
                Image(systemName: "heart.text.square")
                    .foregroundStyle(theme.dim)
                Text("No data from Health yet.")
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: ok ? "checkmark.seal.fill" : "heart.text.square")
                    .foregroundStyle(ok ? theme.ok : theme.dim)
                    .contentTransition(.symbolEffect(.replace))
                Text("Synced from Apple Health")
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
            }
        }
    }

    // MARK: - Circuit variant

    @ViewBuilder
    private var circuitBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Steps & Cardio")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                infoButton
                Spacer()
                StreakChip(weeks: streakWeeks, tint: theme.accent)
            }

            ringRow

            if let projection = EncouragementEngine.stepProjection(
                stepsToday: steps, goalSteps: goal, bodyWeightLb: profile.weightLb
            ) {
                ProjectionBar(text: projection)
            }

            paceLine
            weeklyStrip
            secondaryStats
        }
    }

    @ViewBuilder
    private var ringRow: some View {
        HStack(spacing: 18) {
            ZStack {
                ProgressRing(pct: pct, color: theme.accent, trackColor: theme.barBg, lineWidth: 12)
                VStack(spacing: 2) {
                    AnimatedNumber(
                        Double(steps),
                        font: .system(size: 28, weight: .semibold),
                        color: theme.text
                    )
                    goalButton(label: "/ \(goal.formatted())")
                }
            }
            .frame(width: 110, height: 110)

            VStack(alignment: .leading, spacing: 4) {
                Text("Today")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                // Real numbers + percentage
                Text("\(steps.formatted()) steps")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(theme.text)
                Text("\(Int(pct * 100))% of \(goal / 1000)k goal")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(theme.dim)
                if stepsKcal > 0 {
                    Text("~\(stepsKcal) cal")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(theme.accent)
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

    // MARK: - Shared controls

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

    // MARK: - Milestones (Circuit)

    private func checkMilestones(steps: Int) {
        let fired = Movement.decode(firedSet: firedRaw)
        guard let milestone = Movement.shouldFireMilestone(steps: steps, firedSet: fired)
        else { return }
        toasts.stepMilestone(milestone, mode: mode)
        var updated = fired
        updated.insert(milestone)
        firedRaw = Movement.encode(firedSet: updated)
    }

    // MARK: - Goal picker sheet

    // One sheet for both modes, on the shared `GoalPickerSheet` chrome. The
    // days/week wheel only appears in Circuit, where the streak chip is the
    // thing it drives.
    private var goalPickerSheet: some View {
        GoalPickerSheet(
            title: mode == .circuit ? "Steps Goals" : "Daily Steps Goal",
            subtitle: mode == .circuit
                ? "Daily target + how many days/week to hit it."
                : "Mode default is \(defaultGoal.formatted()) steps.",
            wheels: goalWheels,
            resetLabel: mode == .circuit ? "Reset to defaults" : "Reset to default",
            detents: mode == .circuit ? [.large] : [.medium],
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
        var wheels: [GoalPickerSheet.Wheel] = [
            .init(
                id: "daily",
                // Build has a single wheel, so it needs no label to disambiguate.
                label: mode == .circuit ? "DAILY GOAL" : nil,
                pickerTitle: "Daily goal",
                options: Array(stride(from: 2000, through: 25000, by: 500)),
                optionLabel: { "\($0.formatted()) steps" },
                selection: $pickerGoal,
                height: 130
            )
        ]
        if mode == .circuit {
            wheels.append(
                .init(
                    id: "weeklyDays",
                    label: "DAYS PER WEEK",
                    pickerTitle: "Days per week",
                    options: Array(1...7),
                    optionLabel: { "\($0) day\($0 == 1 ? "" : "s") / week" },
                    selection: $pickerDays,
                    height: 130
                )
            )
        }
        return wheels
    }
}

// MARK: - Steps info sheet

// One copy of the fat-grams math, the Tudor-Locke activity categories, and the
// walking research copy. Circuit adds the cardio-pairing section.
private struct StepsInfoSheet: View {
    let steps: Int
    let goal: Int
    let stepsKcal: Int
    let mode: Mode

    @Environment(\.theme) private var theme

    // Fat burned: at an easy walking pace roughly half your calories come from
    // burning fat (the share drops as you speed up). Source: Achten & Jeukendrup,
    // Nutrition, 2004. ~9 cal per gram of fat.
    private var fatGrams: Int { max(0, Int((Double(stepsKcal) * 0.50 / 9.0).rounded())) }

    // Step category per Tudor-Locke & Bassett (2004) classification, in plain English.
    private var stepCategory: (label: String, description: String) {
        switch steps {
        case 0..<5000:
            return ("Sedentary", "Under 5,000 steps so far. Adding a short daily walk is the single easiest health upgrade you can make.")
        case 5000..<7500:
            return ("Low active", "5,000–7,499 steps. Better than sitting — a 10–15 minute walk gets you over 7,500, where the benefits really start to stack up.")
        case 7500..<10000:
            return ("Somewhat active", "7,500–9,999 steps. You're in the sweet spot — most of walking's health payoff lands right around here.")
        case 10000..<12500:
            return ("Active", "10,000+ steps. Strong, consistent movement that supports your heart and your everyday calorie burn.")
        default:
            return ("Highly active", "12,500+ steps. Excellent — among the most active step counts, linked with the best fitness and longevity numbers.")
        }
    }

    private var sources: String {
        let base = "Sources: Tudor-Locke & Bassett, Sports Med, 2004; Saint-Maurice et al., JAMA, 2020; Hanson & Jones, Br J Sports Med, 2015; Ainsworth et al., 2011 Compendium."
        guard mode == .circuit else { return base }
        return base.replacingOccurrences(
            of: "Ainsworth et al., 2011 Compendium.",
            with: "Kodama et al., Arch Intern Med, 2007; Ainsworth et al., 2011 Compendium."
        )
    }

    var body: some View {
        InfoSheetScaffold(
            title: mode == .circuit ? "Steps & cardio" : "Steps",
            subtitle: "TODAY · \(steps.formatted()) STEPS"
        ) {
            InfoSection(title: "Your numbers today") {
                VStack(spacing: 8) {
                    InfoRow(label: "Calories burned walking",
                            detail: "≈\(stepsKcal) cal from \(steps.formatted()) steps",
                            emphasis: .label)
                    InfoRow(label: "Roughly how much was fat",
                            detail: "~\(fatGrams)g — about half your walking calories come from fat at an easy pace",
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

            InfoSection(title: "Why your \(goal.formatted())-step goal") {
                Text(TargetRationale.stepsWhy(mode: mode, goal: goal))
                    .font(.callout).foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            InfoSection(title: "What walking does for you") {
                VStack(alignment: .leading, spacing: 8) {
                    if mode == .circuit {
                        Bullet("It's your most repeatable daily calorie burn — and the easiest to keep up while you're losing weight.")
                    }
                    Bullet("Every extra 1,000–2,000 steps a day lowers your risk of dying early — with most of the gain showing up by about 7,000–8,000 steps.")
                    Bullet("Walking regularly brings blood pressure down a few points over a couple of months.")
                    Bullet("A single walk improves how your body handles blood sugar for the next day or two.")
                }
            }

            if mode == .circuit {
                InfoSection(title: "Add some cardio") {
                    VStack(alignment: .leading, spacing: 8) {
                        Bullet("Easy, steady cardio — a pace where you can still talk — nudges your 'good' cholesterol (HDL) up a couple of points and lowers the fat in your blood (triglycerides) by about 10–20% over a couple of months.")
                        Bullet("Steps plus a little cardio together do more for your cholesterol and blood pressure than either alone — pair them with the food tips in Nutrition.")
                    }
                }
            }

            InfoFootnote(sources)
        }
    }
}
