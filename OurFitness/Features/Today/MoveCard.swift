// Apple Health "Move" glance: today's active energy (calories burned) + latest
// heart rate, read live from HealthKit — alongside our own MET-based estimate of
// today's training burn (logged sets + cardio + pilates, excluding steps since
// Apple's active energy already counts those). The science-based number sits next
// to the Watch-measured one. Only shown when the profile granted Health access.

import SwiftUI
import SwiftData

struct MoveCard: View {
    let profile: ProfileDTO
    @ObservedObject var health: HealthKitService

    @Environment(\.theme) private var theme

    @Query private var stepModels: [StepCountModel]
    @Query private var setModels: [WorkoutSetModel]
    @Query private var cardioModels: [CardioSessionModel]
    @Query private var pilatesModels: [PilatesSessionModel]
    @Query private var activityModels: [ActivitySessionModel]

    @State private var appleEnergyKcal: Double = 0
    @State private var appleEnergyDate: Date? = nil
    @State private var restingEnergyKcal: Double = 0
    @State private var bpm: Int? = nil
    @State private var bpmDate: Date? = nil
    @State private var flightsClimbed: Int = 0
    @State private var walkingDistanceMiles: Double = 0
    @State private var showInfo = false
    @State private var showEnergyInfo = false
    @State private var showExercisesInfo = false
    @State private var showHeartRateInfo = false
    @State private var showFlightsInfo = false
    @State private var showDistanceInfo = false

    // Combined Apple Energy: active burn + resting/BMR = total daily expenditure.
    // Shows "-" if neither value has loaded yet (both zero = no Watch data yet today).
    private var combinedEnergyKcal: Int { Int(appleEnergyKcal + restingEnergyKcal) }
    private var hasEnergyData: Bool { !isEnergyStale && (appleEnergyKcal > 0 || restingEnergyKcal > 0) }

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    init(profile: ProfileDTO, health: HealthKitService) {
        self.profile = profile
        self._health = ObservedObject(wrappedValue: health)
        let uid = profile.id
        // Scope each query to today so the fetch stays tiny regardless of history.
        let todayKey = Dates.dayKey()
        let dayStart = Calendar.current.startOfDay(for: Date())
        _stepModels = Query(filter: #Predicate<StepCountModel> { $0.userId == uid && $0.date == todayKey }, sort: \.date)
        _setModels = Query(filter: #Predicate<WorkoutSetModel> { $0.userId == uid && $0.timestamp >= dayStart }, sort: \.timestamp)
        _cardioModels = Query(filter: #Predicate<CardioSessionModel> { $0.profileId == uid && $0.date >= dayStart }, sort: \.date)
        _pilatesModels = Query(filter: #Predicate<PilatesSessionModel> { $0.profileId == uid && $0.date >= dayStart }, sort: \.date)
        _activityModels = Query(filter: #Predicate<ActivitySessionModel> { $0.profileId == uid && $0.date >= dayStart }, sort: \.date)
    }

    private var todaySteps: Int { stepModels.first?.steps ?? 0 }
    private var todaySets: [WorkoutSetDTO] { setModels.map(\.snapshot) }
    private var todayCardio: [CardioSessionDTO] { cardioModels.map(\.snapshot) }
    private var todayPilates: [PilatesSessionDTO] { pilatesModels.map(\.snapshot) }
    private var todayActivities: [ActivitySessionDTO] { activityModels.map(\.snapshot) }

    private var metEstimate: Int {
        DailyBurn.metEstimate(
            steps: todaySteps, sets: todaySets, cardio: todayCardio, pilates: todayPilates,
            activities: todayActivities, bodyWeightLb: profile.weightLb
        )
    }

    private var stepsKcal: Int {
        Int(CalorieEstimator.caloriesForSteps(steps: todaySteps, bodyWeightLb: profile.weightLb).rounded())
    }

    private var setsKcal: Int {
        Int(todaySets.reduce(0.0) { $0 + ($1.caloriesEst ?? 0) }.rounded())
    }
    private var cardioKcal: Int {
        Int(todayCardio.reduce(0.0) { $0 + ($1.type == .walk ? 0 : ($1.caloriesEst ?? 0)) }.rounded())
    }
    private var pilatesKcal: Int {
        Int(todayPilates.reduce(0.0) {
            $0 + CalorieEstimator.caloriesForPilates(minutes: Double($1.durationMinutes), bodyWeightLb: profile.weightLb)
        }.rounded())
    }
    private var activitiesKcal: Int {
        // Exclude the Walking activity — already counted via steps (mirrors DailyBurn).
        Int(todayActivities.reduce(0.0) {
            $0 + ($1.activityId == "activity-walking" ? 0 : ($1.caloriesEst ?? 0))
        }.rounded())
    }

    private var trainingMetEstimate: Int {
        // Reuses the sub-values already computed above — no duplicate reduce closures.
        // Steps excluded: Apple's active energy already counts walking.
        setsKcal + cardioKcal + pilatesKcal + activitiesKcal
    }

    private var weightKg: Int { Int(profile.weightLb * 0.4536) }

    private var distanceLabel: String {
        if unitSystem == .imperial {
            return String(format: "%.1f", walkingDistanceMiles)
        } else {
            return String(format: "%.1f", walkingDistanceMiles * 1.60934)
        }
    }

    private var isEnergyStale: Bool {
        guard let d = appleEnergyDate else { return true }
        return Date().timeIntervalSince(d) > 7 * 86400
    }

    private var isBpmStale: Bool {
        guard let d = bpmDate else { return true }
        return Date().timeIntervalSince(d) > 7 * 86400
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Label("Move", systemImage: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                    }
                    .tactile(.ghost)
                    .accessibilityLabel("About the Move estimate")
                    Spacer()
                }

                // Row 1: Apple Energy (active+resting combined) · MET Estimate · Heart Rate
                HStack(alignment: .top, spacing: 12) {
                    tappableMetricColumn(
                        icon: "flame.fill",
                        title: "APPLE ENERGY",
                        value: hasEnergyData ? "\(combinedEnergyKcal)" : "-",
                        unit: "cal total",
                        subtext: hasEnergyData ? "active + resting" : "need new data",
                        action: { showEnergyInfo = true }
                    )
                    tappableMetricColumn(
                        icon: "dumbbell.fill",
                        title: "MET ESTIMATE",
                        value: "\(metEstimate)",
                        unit: "cal burned",
                        subtext: "steps + training",
                        action: { showExercisesInfo = true }
                    )
                    tappableMetricColumn(
                        icon: "heart.fill",
                        title: "HEART RATE",
                        value: (isBpmStale || bpm == nil) ? "-" : "\(bpm!)",
                        unit: "bpm",
                        subtext: isBpmStale ? "need new data" : asOfText(bpmDate),
                        action: { showHeartRateInfo = true }
                    )
                }

                Divider().background(theme.line).padding(.vertical, 2)

                // Row 2: Distance · Flights
                HStack(alignment: .top, spacing: 12) {
                    tappableMetricColumn(
                        icon: "figure.walk",
                        title: "DISTANCE",
                        value: walkingDistanceMiles > 0 ? distanceLabel : "-",
                        unit: unitSystem == .imperial ? "miles" : "km",
                        subtext: "walking + running",
                        action: { showDistanceInfo = true }
                    )
                    tappableMetricColumn(
                        icon: "arrow.up.circle.fill",
                        title: "FLIGHTS",
                        value: "\(flightsClimbed)",
                        unit: "floors",
                        subtext: "climbed today",
                        action: { showFlightsInfo = true }
                    )
                    // Spacer column to keep row height consistent with row 1.
                    Spacer().frame(maxWidth: .infinity)
                }
            }
        }
        .task(id: profile.id) { await load() }
        .sheet(isPresented: $showInfo) {
            MoveInfoSheet(
                profile: profile,
                metEstimate: metEstimate,
                trainingMet: trainingMetEstimate,
                todaySteps: todaySteps,
                stepsKcal: stepsKcal
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showEnergyInfo) {
            AppleEnergyInfoSheet(
                activeKcal: isEnergyStale ? nil : Int(appleEnergyKcal),
                restingKcal: restingEnergyKcal > 0 ? Int(restingEnergyKcal) : nil,
                asOf: isEnergyStale ? nil : asOfText(appleEnergyDate)
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showExercisesInfo) {
            ExercisesInfoSheet(
                weightKg: weightKg,
                todaySteps: todaySteps,
                stepsKcal: stepsKcal,
                setsKcal: setsKcal,
                cardioKcal: cardioKcal,
                pilatesKcal: pilatesKcal,
                activitiesKcal: activitiesKcal,
                trainingMetEstimate: trainingMetEstimate
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showHeartRateInfo) {
            HeartRateInfoSheet(
                bpm: (isBpmStale || bpm == nil) ? nil : bpm,
                asOf: isBpmStale ? nil : asOfText(bpmDate)
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showDistanceInfo) {
            DistanceInfoSheet(
                miles: walkingDistanceMiles,
                unitSystem: unitSystem
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showFlightsInfo) {
            FlightsClimbedInfoSheet(floors: flightsClimbed)
                .themed(profile.mode)
        }
    }

    private func load() async {
        appleEnergyKcal = await health.activeEnergy()
        appleEnergyDate = await health.latestActiveEnergySampleDate()
        if let hr = await health.latestHeartRateWithDate() {
            bpm = hr.value
            bpmDate = hr.date
        } else {
            bpm = nil
            bpmDate = nil
        }
        flightsClimbed = await health.flightsClimbed()
        walkingDistanceMiles = await health.walkingRunningDistanceMiles()
        restingEnergyKcal = await health.restingEnergy()
    }

    private func asOfText(_ date: Date?) -> String {
        guard let date else { return "need new data" }
        // Delegate the "as of <time/date>" formatting to the tested Domain helper.
        // Returns nil for just-taken readings (< 2 min) — show "just now" instead
        // of a redundant timestamp. The 7-day staleness gate is handled upstream
        // by isEnergyStale / isBpmStale.
        return Freshness.label(for: date) ?? "just now"
    }

    @ViewBuilder
    private func tappableMetricColumn(icon: String, title: String, value: String, unit: String, subtext: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.accent)
                    Text(title)
                        .font(.system(size: 8, weight: .medium)).tracking(1.5)
                        .foregroundStyle(theme.dim)
                }
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.dim)
                Text(subtext)
                    .font(.system(size: 9))
                    .foregroundStyle(theme.dim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tactile(.ghost)
        .accessibilityLabel("\(title) details")
    }
}

// MARK: - Move info sheet

private struct MoveInfoSheet: View {
    let profile: ProfileDTO
    let metEstimate: Int
    let trainingMet: Int
    let todaySteps: Int
    let stepsKcal: Int

    @Environment(\.theme) private var theme

    private var weightKg: Int { Int(profile.weightLb * 0.4536) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("move.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("MET × WEIGHT × TIME = CALORIES")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                section(title: "Two sources, one picture") {
                    Text("The Move card shows two independent views of your day. Apple Health columns are measured by your iPhone and Watch sensors. The MET Estimate is our science-based calculation from what you log. They are separate — logged workouts do not change Apple's measured numbers.")
                        .font(.callout)
                        .foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section(title: "From Apple Health (measured)") {
                    VStack(alignment: .leading, spacing: 8) {
                        columnNote(
                            label: "Apple Energy",
                            detail: "Active + Resting combined — your full daily calorie expenditure as Apple measures it. Tap for the active vs. resting breakdown."
                        )
                        columnNote(
                            label: "Heart Rate",
                            detail: "Most recent reading from your Watch or paired sensor. A snapshot, not a daily average. Tap to see context ranges."
                        )
                        columnNote(
                            label: "Distance",
                            detail: "Walking + running distance from iPhone/Watch GPS and motion sensors. Separate from step count — 2,000 steps ≈ 1 mile depending on stride."
                        )
                        columnNote(
                            label: "Flights Climbed",
                            detail: "Floors of stairs climbed, detected by barometer. One flight ≈ 10 ft / 3 m of elevation. Not counted in steps or distance."
                        )
                        breakdownRow(
                            label: "Active + Resting = total daily burn (TDEE)",
                            detail: "Active covers all movement above rest. Resting covers organ function, temperature, cell repair. Together they are your full daily expenditure — the baseline your nutrition targets are built on."
                        )
                    }
                }

                section(title: "MET Estimate (calculated from your logs)") {
                    VStack(alignment: .leading, spacing: 8) {
                        columnNote(
                            label: "MET Estimate",
                            detail: "Our science-based burn calculated from what you've logged today: steps + strength sets + cardio + pilates + live sessions. Formula: MET × body weight × hours. Tap for the full per-source breakdown."
                        )
                        breakdownRow(
                            label: "Today's MET breakdown",
                            detail: "Steps: MET 4.3 × \(weightKg) kg × \(todaySteps)/7,392 hr ≈ \(stepsKcal) cal\nTraining: MET 3.5–8.0 × \(weightKg) kg × session time ≈ \(trainingMet) cal\nTotal: ≈\(metEstimate) cal"
                        )
                    }
                }

                section(title: "How MET works") {
                    Text("MET (Metabolic Equivalent of Task) scores how hard an activity is relative to sitting still (MET 1). Walking scores 4.3, pilates 3.0, squats 5.0, pull-ups 8.0. Multiply the score by your body weight in kg and the hours you moved: that's the calories burned. Heavier bodies and longer sessions burn more. Source: Ainsworth 2011 Compendium of Physical Activities.")
                        .font(.callout)
                        .foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Source: Ainsworth BE et al. 2011 Compendium of Physical Activities. Med Sci Sports Exerc.")
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
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            content()
        }
    }

    @ViewBuilder
    private func breakdownRow(label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text)
            Text(detail)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(theme.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func columnNote(label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Per-column info sheets

private struct AppleEnergyInfoSheet: View {
    let activeKcal: Int?
    let restingKcal: Int?
    let asOf: String?

    private var combinedKcal: Int? {
        guard let a = activeKcal, let r = restingKcal else { return activeKcal ?? restingKcal }
        return a + r
    }

    var body: some View {
        ColumnInfoScaffold(title: "apple energy.", subtitle: "ACTIVE + RESTING · FROM APPLE HEALTH") {

            ColumnInfoSection(title: "Total today") {
                if let combined = combinedKcal {
                    ColumnBreakdownRow(
                        label: "Active + Resting = \(combined) cal",
                        detail: "\(activeKcal ?? 0) cal active + \(restingKcal ?? 0) cal resting = your full daily calorie expenditure so far"
                    )
                } else {
                    ColumnBreakdownRow(
                        label: "No data yet",
                        detail: "Open the Health app or wear your Apple Watch to load today's energy data."
                    )
                }
            }

            ColumnInfoSection(title: "Active Energy — movement above rest") {
                VStack(alignment: .leading, spacing: 8) {
                    ColumnInfoBody(text: "Every calorie burned beyond your resting baseline — walking, workouts, stairs, fidgeting. Measured directly by iPhone and Apple Watch sensors. This is the ring Apple shows in the Activity app.")
                    if let a = activeKcal, let asOf {
                        ColumnBreakdownRow(
                            label: "Apple measured \(a) cal active",
                            detail: "As of \(asOf). Includes all movement Apple detected — logged and unlogged activity."
                        )
                    }
                    ColumnInfoBody(text: "✓  All steps and walking\n✓  Apple Fitness+ workouts and auto-detected exercise\n✓  Stair climbing, standing activity, spontaneous movement\n✗  Does not include resting/BMR calories")
                }
            }

            ColumnInfoSection(title: "Resting Energy — body at rest (BMR)") {
                VStack(alignment: .leading, spacing: 8) {
                    ColumnInfoBody(text: "Calories your body burns just to stay alive — heart beating, lungs breathing, brain running, temperature regulated. Estimated by Apple Health from your age, height, and weight. No activity required.")
                    if let r = restingKcal {
                        ColumnBreakdownRow(
                            label: "Resting energy today: \(r) cal",
                            detail: "Typically 60–75% of total daily calorie burn for a lightly active person."
                        )
                    }
                    ColumnInfoBody(text: "✓  Heart, lungs, brain, and organ function\n✓  Cell repair and hormone production\n✓  Thermoregulation\n✗  Does not include any movement calories")
                }
            }

            ColumnInfoSection(title: "Active + Resting = your TDEE") {
                ColumnBreakdownRow(
                    label: "Total Daily Energy Expenditure",
                    detail: "This combined number is what your nutrition targets are built around. Build mode adds 400–600 cal on top; Circuit mode runs 300–500 cal below it."
                )
            }

            ColumnInfoSection(title: "Formula-based breakdown") {
                ColumnInfoBody(text: "The MET Estimate column shows our science-based calculation from what you've logged — steps, strength, cardio, pilates, and live sessions. Tap that column for the full per-source breakdown.")
            }
        }
    }
}

private struct ExercisesInfoSheet: View {
    let weightKg: Int
    let todaySteps: Int
    let stepsKcal: Int
    let setsKcal: Int
    let cardioKcal: Int
    let pilatesKcal: Int
    let activitiesKcal: Int
    let trainingMetEstimate: Int

    @Environment(\.theme) private var theme

    private var totalKcal: Int { stepsKcal + trainingMetEstimate }
    // Fat oxidation: ~55% at walking intensity, ~50% for training — blended ~52%
    private var fatGrams: Int { max(0, Int((Double(totalKcal) * 0.52 / 9.0).rounded())) }
    // Sweat loss: training kcal / 50 ≈ oz lost (rough moderate-intensity proxy)
    private var sweatOz: Double { Double(trainingMetEstimate) / 50.0 }

    var body: some View {
        ColumnInfoScaffold(title: "met estimate.", subtitle: "MET × WEIGHT × TIME = CALORIES") {
            ColumnInfoSection(title: "What it is") {
                ColumnInfoBody(text: "Our science-based estimate of your active calorie burn, calculated from everything you've logged today. MET (Metabolic Equivalent of Task) scores how hard an activity is relative to sitting still (MET 1). Multiply by your weight and time to get calories burned.")
            }

            ColumnInfoSection(title: "What's included") {
                VStack(alignment: .leading, spacing: 6) {
                    ColumnInfoBody(text: "✓ Steps — MET 4.3 (walking at ~3.5 mph)")
                    ColumnInfoBody(text: "✓ Strength sets — MET 3.5–8.0 depending on exercise")
                    ColumnInfoBody(text: "✓ Cardio sessions (non-walk) — MET 4.5")
                    ColumnInfoBody(text: "✓ Pilates — MET 3.0 (Ainsworth code 06010)")
                    ColumnInfoBody(text: "✓ Live sessions — MET varies by activity (2.8–11.8)")
                    ColumnInfoBody(text: "✗ Resting/basal energy — see the Resting Energy column")
                    ColumnInfoBody(text: "✗ Unlogged movement — only what you record in the app")
                }
            }

            ColumnInfoSection(title: "The formula") {
                ColumnBreakdownRow(
                    label: "MET × weight (kg) × hours = cal",
                    detail: "Your weight: \(weightKg) kg. Example: a 30-min run at MET 8 → 8 × \(weightKg) × 0.5 = \(8 * weightKg / 2) cal"
                )
            }

            // Steps breakdown — always shown
            ColumnInfoSection(title: "Steps today") {
                ColumnBreakdownRow(
                    label: "MET 4.3 × \(weightKg) kg × \(todaySteps) steps ÷ 7,392 steps/hr",
                    detail: "≈\(stepsKcal) cal from \(todaySteps.formatted()) steps"
                )
            }

            // Strength sets — only if logged
            if setsKcal > 0 {
                ColumnInfoSection(title: "Strength & exercises today") {
                    ColumnBreakdownRow(
                        label: "MET 3.5–8.0 × \(weightKg) kg × session time",
                        detail: "≈\(setsKcal) cal — derived from logged reps, exercise type, and load"
                    )
                }
            }

            // Cardio — only if logged
            if cardioKcal > 0 {
                ColumnInfoSection(title: "Cardio today (non-walk)") {
                    ColumnBreakdownRow(
                        label: "MET 4.5 × \(weightKg) kg × session duration",
                        detail: "≈\(cardioKcal) cal (walk sessions use step MET instead)"
                    )
                }
            }

            // Pilates — only if logged
            if pilatesKcal > 0 {
                ColumnInfoSection(title: "Pilates today") {
                    ColumnBreakdownRow(
                        label: "MET 3.0 × \(weightKg) kg × session duration",
                        detail: "≈\(pilatesKcal) cal — Ainsworth code 06010"
                    )
                }
            }

            // Live sessions — only if logged
            if activitiesKcal > 0 {
                ColumnInfoSection(title: "Live sessions today") {
                    ColumnBreakdownRow(
                        label: "Per-activity MET × \(weightKg) kg × elapsed time",
                        detail: "≈\(activitiesKcal) cal — basketball, swimming, yoga, etc."
                    )
                }
            }

            // Running total
            ColumnInfoSection(title: "Total today") {
                ColumnBreakdownRow(
                    label: "All sources combined",
                    detail: "≈\(totalKcal) cal burned (MET estimate, steps + training)"
                )
            }

            // Bonus
            ColumnInfoSection(title: "Derived estimates") {
                VStack(alignment: .leading, spacing: 8) {
                    ColumnBreakdownRow(
                        label: "Fat burned",
                        detail: "~\(fatGrams) g fat oxidized — at moderate intensity roughly 52% of energy comes from fat (9 cal/g)"
                    )
                    if sweatOz > 0.5 {
                        ColumnBreakdownRow(
                            label: "Estimated sweat loss (training)",
                            detail: String(format: "~%.1f oz / %.0f mL — drink water to replace", sweatOz, sweatOz * 29.57)
                        )
                    }
                }
            }

            ColumnInfoBody(text: "Source: Ainsworth BE et al. 2011 Compendium of Physical Activities. Med Sci Sports Exerc.")
        }
    }
}

private struct HeartRateInfoSheet: View {
    let bpm: Int?
    let asOf: String?

    private var todayText: String {
        if let bpm, let asOf {
            return "\(bpm) bpm \(asOf)."
        }
        return "No recent reading. Wear your Apple Watch to get an updated reading."
    }

    var body: some View {
        ColumnInfoScaffold(title: "heart rate.", subtitle: "APPLE HEALTH · MOST RECENT READING") {
            ColumnInfoSection(title: "What it is") {
                ColumnInfoBody(text: "Your most recent heart rate reading from Apple Health, measured by your Apple Watch optical sensor or a paired chest strap. This is a spot reading — not a daily average or resting rate.")
            }
            ColumnInfoSection(title: "What's included / not included") {
                VStack(alignment: .leading, spacing: 6) {
                    ColumnInfoBody(text: "✓ Most recent beat-per-minute reading from your Watch")
                    ColumnInfoBody(text: "✗ Not a resting heart rate average — that's in Progress → Health Markers")
                    ColumnInfoBody(text: "✗ Not a daily high or low — just the latest sample")
                }
            }
            ColumnInfoSection(title: "Today") {
                ColumnBreakdownRow(label: "Heart rate", detail: todayText)
            }
            ColumnInfoSection(title: "Ranges") {
                VStack(alignment: .leading, spacing: 6) {
                    ColumnBreakdownRow(label: "Resting (at rest)", detail: "60–100 bpm normal; 50–70 bpm common for active people; below 60 bpm can be normal for athletes")
                    ColumnBreakdownRow(label: "Moderate exercise", detail: "50–70% of max heart rate. Max ≈ 220 − your age.")
                    ColumnBreakdownRow(label: "Vigorous exercise", detail: "70–85% of max heart rate.")
                }
            }
            ColumnInfoSection(title: "Why it matters") {
                ColumnInfoBody(text: "A declining resting heart rate over weeks is one of the clearest signs that cardiovascular fitness is improving. Consistent step goals and regular cardio training are the fastest levers.")
            }
        }
    }
}


private struct DistanceInfoSheet: View {
    let miles: Double
    let unitSystem: UnitSystem
    @Environment(\.theme) private var theme

    private var displayValue: String {
        if unitSystem == .imperial {
            return String(format: "%.2f miles", miles)
        } else {
            return String(format: "%.2f km", miles * 1.60934)
        }
    }

    var body: some View {
        ColumnInfoScaffold(title: "distance.", subtitle: "WALKING + RUNNING · FROM APPLE HEALTH") {
            ColumnInfoSection(title: "What it is") {
                ColumnInfoBody(text: "Total distance covered on foot today — walking and running combined — as measured by your iPhone's motion co-processor and accelerometer, or Apple Watch GPS when available.")
            }
            ColumnInfoSection(title: "What's included / not included") {
                VStack(alignment: .leading, spacing: 6) {
                    ColumnInfoBody(text: "✓ All walking distance throughout the day")
                    ColumnInfoBody(text: "✓ Running and jogging")
                    ColumnInfoBody(text: "✗ Cycling, swimming, or other non-foot activities")
                    ColumnInfoBody(text: "✗ Stair climbing — that shows in Flights Climbed separately")
                }
            }
            ColumnInfoSection(title: "Today") {
                ColumnBreakdownRow(
                    label: "Walking + running distance",
                    detail: miles > 0 ? displayValue : "No distance data yet today."
                )
            }
            ColumnInfoSection(title: "Useful benchmarks") {
                VStack(alignment: .leading, spacing: 8) {
                    ColumnBreakdownRow(label: "2,000 steps ≈ 1 mile", detail: "Exact distance depends on stride length — taller people cover more per step.")
                    ColumnBreakdownRow(label: "30-min brisk walk", detail: "≈ 1.5–2.0 miles at ~3.5 mph. That's the walking pace behind the MET 4.3 calorie formula.")
                    ColumnBreakdownRow(label: "Daily goal context", detail: "10,000 steps ≈ 4–5 miles, which is the step count tied to cardiovascular benefits in major epidemiological studies.")
                }
            }
        }
    }
}

private struct FlightsClimbedInfoSheet: View {
    let floors: Int
    @Environment(\.theme) private var theme

    var body: some View {
        ColumnInfoScaffold(title: "flights climbed.", subtitle: "FLOORS · FROM APPLE HEALTH BAROMETER") {
            ColumnInfoSection(title: "What it is") {
                ColumnInfoBody(text: "Floors of stairs climbed today, detected by the barometric pressure sensor in your iPhone or Apple Watch. As you ascend roughly 10 feet (3 meters), one flight is recorded.")
            }
            ColumnInfoSection(title: "What's included / not included") {
                VStack(alignment: .leading, spacing: 6) {
                    ColumnInfoBody(text: "✓ Stairs, escalators going up, ramps with elevation gain")
                    ColumnInfoBody(text: "✓ Detected automatically — no logging needed")
                    ColumnInfoBody(text: "✗ Descending stairs (only ascent counts)")
                    ColumnInfoBody(text: "✗ Not counted in step total or distance — it's a separate metric")
                    ColumnInfoBody(text: "✗ Elevator rides do not register (no step cadence)")
                }
            }
            ColumnInfoSection(title: "Today") {
                ColumnBreakdownRow(
                    label: "Floors climbed",
                    detail: floors > 0 ? "\(floors) flight\(floors == 1 ? "" : "s") — approximately \(floors * 10) ft / \(floors * 3) m of elevation" : "No flights recorded yet today."
                )
            }
            ColumnInfoSection(title: "Why it matters") {
                VStack(alignment: .leading, spacing: 8) {
                    ColumnInfoBody(text: "Stair climbing is a higher-intensity stimulus than flat walking — roughly MET 4.0–8.0 depending on pace. It engages the glutes, quads, and calves under load and elevates heart rate quickly.")
                    ColumnBreakdownRow(
                        label: "Cardiovascular research",
                        detail: "Studies associate regular stair climbing with reduced all-cause mortality and improved VO₂ max compared to elevator use for the same floors. (Stamatakis et al., Brit J Sports Med 2021)"
                    )
                }
            }
        }
    }
}

// MARK: - Shared scaffold for per-column info sheets

private struct ColumnInfoScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }
                content()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
    }
}

private struct ColumnInfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            content()
        }
    }
}

private struct ColumnInfoBody: View {
    let text: String
    @Environment(\.theme) private var theme
    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ColumnBreakdownRow: View {
    let label: String
    let detail: String
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text)
            Text(detail)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(theme.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}
