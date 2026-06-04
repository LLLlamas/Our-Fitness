// Apple Health "Move" glance: today's active energy + per-source MET breakdown.
// Training burn is the hero number — accent-colored and large so it pops immediately.

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
    @Query private var exerciseModels: [ExerciseModel]

    @State private var appleEnergyKcal: Double = 0
    @State private var appleEnergyDate: Date? = nil
    @State private var bpm: Int? = nil
    @State private var bpmDate: Date? = nil
    @State private var flightsClimbed: Int = 0
    @State private var walkingDistanceMiles: Double = 0
    @State private var showInfo = false
    @State private var showEnergyInfo = false
    @State private var showMetTotalInfo = false
    @State private var showExercisesInfo = false
    @State private var showHeartRateInfo = false
    @State private var showFlightsInfo = false
    @State private var showDistanceInfo = false

    private var activeEnergyKcal: Int { Int(appleEnergyKcal) }
    private var hasEnergyData: Bool { !isEnergyStale && appleEnergyKcal > 0 }

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial
    @AppStorage private var customStepsGoalRaw: Int

    private var effectiveStepsGoal: Int {
        customStepsGoalRaw > 0 ? customStepsGoalRaw : profile.computedTargets.stepsDaily
    }

    init(profile: ProfileDTO, health: HealthKitService) {
        self.profile = profile
        self._health = ObservedObject(wrappedValue: health)
        let uid = profile.id
        _customStepsGoalRaw = AppStorage(wrappedValue: 0, "stepsGoal.\(uid.uuidString)")
        let todayKey = Dates.dayKey()
        let dayStart = Calendar.current.startOfDay(for: Date())
        _stepModels  = Query(filter: #Predicate<StepCountModel>    { $0.userId    == uid && $0.date      == todayKey }, sort: \.date)
        _setModels   = Query(filter: #Predicate<WorkoutSetModel>    { $0.userId    == uid && $0.timestamp >= dayStart }, sort: \.timestamp)
        _cardioModels  = Query(filter: #Predicate<CardioSessionModel>  { $0.profileId == uid && $0.date >= dayStart }, sort: \.date)
        _pilatesModels = Query(filter: #Predicate<PilatesSessionModel> { $0.profileId == uid && $0.date >= dayStart }, sort: \.date)
        _activityModels = Query(filter: #Predicate<ActivitySessionModel> { $0.profileId == uid && $0.date >= dayStart }, sort: \.date)
        _exerciseModels = Query(filter: #Predicate<ExerciseModel> { $0.profileId == uid }, sort: \.name)
    }

    private var todaySteps: Int     { stepModels.first?.steps ?? 0 }
    private var todaySets: [WorkoutSetDTO]       { setModels.map(\.snapshot) }
    private var todayCardio: [CardioSessionDTO]  { cardioModels.map(\.snapshot) }
    private var todayPilates: [PilatesSessionDTO] { pilatesModels.map(\.snapshot) }
    private var todayActivities: [ActivitySessionDTO] { activityModels.map(\.snapshot) }

    private var exerciseNames: [String: String] {
        Dictionary(uniqueKeysWithValues: exerciseModels.map { ($0.id, $0.name) })
    }

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
        Int(todayActivities.reduce(0.0) {
            $0 + ($1.activityId == "activity-walking" ? 0 : ($1.caloriesEst ?? 0))
        }.rounded())
    }
    private var trainingMetEstimate: Int { setsKcal + cardioKcal + pilatesKcal + activitiesKcal }

    private var metBMR: Int {
        Targets.bmr(sex: profile.sex, weightLb: profile.weightLb,
                    heightIn: profile.heightIn, age: profile.age)
    }
    private var metTotal: Int { metEstimate + metBMR }
    private var weightKg: Int { Int(profile.weightLb * 0.4536) }

    private var distanceLabel: String {
        unitSystem == .imperial
            ? String(format: "%.1f", walkingDistanceMiles)
            : String(format: "%.1f", walkingDistanceMiles * 1.60934)
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
            VStack(alignment: .leading, spacing: 14) {
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

                // Row 1: Apple Total · Our Estimate · Training
                HStack(alignment: .top, spacing: 0) {
                    metricColumn(
                        icon: "flame.fill", title: "APPLE TOTAL",
                        value: hasEnergyData ? "\(activeEnergyKcal)" : "-",
                        sub: hasEnergyData ? "cal · active energy" : "need new data",
                        action: { showEnergyInfo = true }
                    )
                    columnSep
                    metricColumn(
                        icon: "sum", title: "OUR ESTIMATE",
                        value: "\(metTotal)",
                        sub: "cal · all-day total",
                        action: { showMetTotalInfo = true }
                    )
                    columnSep
                    metricColumn(
                        icon: "dumbbell.fill", title: "TRAINING",
                        value: "\(trainingMetEstimate)",
                        sub: trainingMetEstimate > 0 ? "cal burned today" : "no sessions yet",
                        action: { showExercisesInfo = true }
                    )
                }

                Divider().background(theme.line)

                // Row 2: Distance · Flights · Heart Rate
                HStack(alignment: .top, spacing: 0) {
                    metricColumn(
                        icon: "figure.walk", title: "DISTANCE",
                        value: walkingDistanceMiles > 0 ? distanceLabel : "-",
                        sub: unitSystem == .imperial ? "miles today" : "km today",
                        action: { showDistanceInfo = true }
                    )
                    columnSep
                    metricColumn(
                        icon: "arrow.up.circle.fill", title: "FLIGHTS",
                        value: "\(flightsClimbed)",
                        sub: "floors climbed",
                        action: { showFlightsInfo = true }
                    )
                    columnSep
                    metricColumn(
                        icon: "heart.fill", title: "HEART RATE",
                        value: (isBpmStale || bpm == nil) ? "-" : "\(bpm!)",
                        sub: isBpmStale ? "need new data" : "bpm · \(asOfText(bpmDate))",
                        action: { showHeartRateInfo = true }
                    )
                }
            }
        }
        .task(id: profile.id) { await load() }
        .sheet(isPresented: $showInfo) {
            MoveInfoSheet(
                profile: profile, metTotal: metTotal, metBMR: metBMR,
                metActive: metEstimate, trainingMet: trainingMetEstimate,
                todaySteps: todaySteps, stepsKcal: stepsKcal
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showEnergyInfo) {
            AppleEnergyInfoSheet(
                activeKcal: isEnergyStale ? nil : Int(appleEnergyKcal),
                asOf: isEnergyStale ? nil : asOfText(appleEnergyDate)
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showMetTotalInfo) {
            MetTotalInfoSheet(
                metTotal: metTotal, metBMR: metBMR, metActive: metEstimate,
                stepsKcal: stepsKcal, trainingKcal: trainingMetEstimate, weightKg: weightKg
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showExercisesInfo) {
            ExercisesInfoSheet(
                weightKg: weightKg,
                todaySteps: todaySteps, stepsKcal: stepsKcal, stepsGoal: effectiveStepsGoal,
                setsKcal: setsKcal, cardioKcal: cardioKcal,
                pilatesKcal: pilatesKcal, activitiesKcal: activitiesKcal,
                trainingMetEstimate: trainingMetEstimate,
                todaySets: todaySets, todayCardio: todayCardio,
                todayPilates: todayPilates, todayActivities: todayActivities,
                exerciseNames: exerciseNames
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
            DistanceInfoSheet(miles: walkingDistanceMiles, unitSystem: unitSystem)
                .themed(profile.mode)
        }
        .sheet(isPresented: $showFlightsInfo) {
            FlightsClimbedInfoSheet(floors: flightsClimbed)
                .themed(profile.mode)
        }
    }

    // Thin vertical separator between metric columns
    private var columnSep: some View {
        Rectangle()
            .fill(theme.line.opacity(0.6))
            .frame(width: 0.5)
            .padding(.vertical, 2)
    }

    @ViewBuilder
    private func metricColumn(
        icon: String, title: String, value: String, sub: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundStyle(theme.dim)
                    Text(title)
                        .font(.system(size: 8, weight: .semibold)).tracking(1.2)
                        .foregroundStyle(theme.dim)
                }
                Text(value)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.7)
                Text(sub)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.dim)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tactile(.ghost)
        .accessibilityLabel("\(title) details")
    }

    private func load() async {
        appleEnergyKcal = await health.activeEnergy()
        appleEnergyDate = await health.latestActiveEnergySampleDate()
        if let hr = await health.latestHeartRateWithDate() {
            bpm = hr.value; bpmDate = hr.date
        } else {
            bpm = nil; bpmDate = nil
        }
        flightsClimbed = await health.flightsClimbed()
        walkingDistanceMiles = await health.walkingRunningDistanceMiles()
    }

    private func asOfText(_ date: Date?) -> String {
        guard let date else { return "need new data" }
        return Freshness.label(for: date) ?? "just now"
    }
}

// MARK: - Move info sheet

private struct MoveInfoSheet: View {
    let profile: ProfileDTO
    let metTotal: Int
    let metBMR: Int
    let metActive: Int
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
                    Text("Apple Health measures what its sensors detect. Our Estimate calculates from what you log — BMR + steps + training. They'll rarely match perfectly, and that's fine.")
                        .font(.callout).foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section(title: "Apple Total") {
                    VStack(alignment: .leading, spacing: 8) {
                        columnNote(label: "Active energy", detail: "Steps and all movement Apple detects. Misses logged strength and sport sessions. Syncs from Watch every 15–60 min.")
                        columnNote(label: "Distance & Flights", detail: "Foot distance from GPS and floors climbed from the barometer.")
                        columnNote(label: "Heart Rate", detail: "Most recent spot reading — not a daily average.")
                    }
                }

                section(title: "Our Estimate") {
                    VStack(alignment: .leading, spacing: 8) {
                        columnNote(label: "Total (BMR + active)", detail: "Mifflin-St Jeor BMR from your profile + step burn + all logged training.")
                        columnNote(label: "Training", detail: "Only logged sessions — strength, cardio, pilates, live activities. The activity Apple's sensors miss.")
                        breakdownRow(
                            label: "Today's breakdown",
                            detail: "BMR: ≈\(metBMR) cal\nSteps: ≈\(stepsKcal) cal\nTraining: ≈\(trainingMet) cal\nTotal: ≈\(metTotal) cal"
                        )
                    }
                }

                Text("Source: Ainsworth BE et al. 2011 Compendium of Physical Activities. Med Sci Sports Exerc.")
                    .font(.caption2).foregroundStyle(theme.dim)
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
            Text(title).font(.caption).tracking(2).textCase(.uppercase).foregroundStyle(theme.dim)
            content()
        }
    }

    @ViewBuilder
    private func breakdownRow(label: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
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
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
            Text(detail).font(.footnote).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Apple Energy info sheet

private struct AppleEnergyInfoSheet: View {
    let activeKcal: Int?
    let asOf: String?

    var body: some View {
        ColumnInfoScaffold(title: "apple energy.", subtitle: "ACTIVE ENERGY · FROM YOUR IPHONE + WATCH") {

            ColumnInfoSection(title: "Today") {
                VStack(spacing: 6) {
                    if activeKcal == nil {
                        ColumnBigNumberRow(icon: "bolt.fill", name: "No data yet",
                                           detail: "Watch syncs every 15–60 min. Carry your iPhone for iPhone-only tracking.",
                                           value: "-", unit: "cal")
                    } else {
                        ColumnBigNumberRow(
                            icon: "bolt.fill",
                            name: "Active energy",
                            detail: "Movement Apple detected today",
                            value: activeKcal.map { "\($0)" } ?? "-",
                            unit: "cal"
                        )
                        if let kcal = activeKcal {
                            ColumnHeroStat(
                                label: "TODAY" + (asOf.map { " · \($0)" } ?? ""),
                                value: "\(kcal) cal"
                            )
                        }
                    }
                }
            }

            ColumnInfoSection(title: "What's counted") {
                VStack(alignment: .leading, spacing: 5) {
                    ColumnInfoBody(text: "Every calorie burned beyond your resting baseline — walking, workouts, stairs, fidgeting. Measured directly by iPhone and Apple Watch sensors.")
                    ColumnInfoBody(text: "✓  All steps and movement Apple can detect\n✗  Doesn't include BMR/resting calories (those are in Our Estimate)")
                }
            }

            ColumnInfoSection(title: "vs. Our Estimate") {
                ColumnBreakdownRow(
                    label: "Apple active vs. Our Estimate",
                    detail: "Our Estimate = BMR + steps + logged training. Apple active energy = pure movement only. That's why Our Estimate will always be higher."
                )
            }
        }
    }
}

// MARK: - MET Total info sheet

private struct MetTotalInfoSheet: View {
    let metTotal: Int
    let metBMR: Int
    let metActive: Int
    let stepsKcal: Int
    let trainingKcal: Int
    let weightKg: Int

    var body: some View {
        ColumnInfoScaffold(title: "our estimate.", subtitle: "MIFFLIN-ST JEOR + MET · ALL-DAY TOTAL") {

            ColumnInfoSection(title: "Today's breakdown") {
                VStack(spacing: 6) {
                    ColumnBigNumberRow(
                        icon: "moon.zzz.fill",
                        name: "Resting (BMR)",
                        detail: "Mifflin-St Jeor · updates when you edit vitals",
                        value: "~\(metBMR)",
                        unit: "cal"
                    )
                    ColumnBigNumberRow(
                        icon: "figure.walk",
                        name: "Steps",
                        detail: "MET 4.3 × \(weightKg) kg × step count",
                        value: "~\(stepsKcal)",
                        unit: "cal"
                    )
                    ColumnBigNumberRow(
                        icon: "dumbbell.fill",
                        name: "Training",
                        detail: "Logged strength, cardio, pilates, live sessions",
                        value: "~\(trainingKcal)",
                        unit: "cal"
                    )
                    ColumnHeroStat(label: "TOTAL TODAY", value: "~\(metTotal) cal")
                }
            }

            ColumnInfoSection(title: "vs. Apple Total") {
                ColumnInfoBody(text: "Apple shows active energy only — movement its sensors detect. Our Estimate adds BMR (Mifflin-St Jeor) on top. Our Estimate will always read higher than Apple's active number; that's expected, not a discrepancy.")
            }
        }
    }
}

// MARK: - Training (Exercises) info sheet

private struct ExercisesInfoSheet: View {
    let weightKg: Int
    let todaySteps: Int
    let stepsKcal: Int
    let stepsGoal: Int
    let setsKcal: Int
    let cardioKcal: Int
    let pilatesKcal: Int
    let activitiesKcal: Int
    let trainingMetEstimate: Int
    let todaySets: [WorkoutSetDTO]
    let todayCardio: [CardioSessionDTO]
    let todayPilates: [PilatesSessionDTO]
    let todayActivities: [ActivitySessionDTO]
    let exerciseNames: [String: String]

    @Environment(\.theme) private var theme
    @State private var showWhatCounts = false
    @State private var showFormula = false

    private var fatGrams: Int { max(0, Int((Double(trainingMetEstimate) * 0.50 / 9.0).rounded())) }
    private var sweatOz: Double { Double(trainingMetEstimate) / 50.0 }

    private var hasAnyTraining: Bool {
        !todaySets.isEmpty ||
        !todayCardio.filter({ $0.type != .walk }).isEmpty ||
        !todayPilates.isEmpty ||
        !todayActivities.filter({ $0.activityId != "activity-walking" }).isEmpty
    }

    // Grouped strength sets sorted by total calories descending
    private var exerciseGroupRows: [(id: String, name: String, setCount: Int, kcal: Int)] {
        let grouped = Dictionary(grouping: todaySets, by: \.exerciseId)
        return grouped.map { (id, sets) -> (String, String, Int, Int) in
            let name = exerciseNames[id] ?? id
            let kcal = Int(sets.reduce(0.0) { $0 + ($1.caloriesEst ?? 0) }.rounded())
            return (id, name, sets.count, kcal)
        }
        .sorted { $0.3 > $1.3 }
        .map { (id: $0.0, name: $0.1, setCount: $0.2, kcal: $0.3) }
    }

    var body: some View {
        ColumnInfoScaffold(title: "training.", subtitle: "TODAY'S BURN FROM LOGGED SESSIONS") {

            // ── Today's activity ─────────────────────────────────────
            ColumnInfoSection(title: "Today's activity") {
                VStack(spacing: 6) {
                    if !hasAnyTraining {
                        ColumnInfoBody(text: "No training logged yet. Head to the Workouts tab to get started.")
                    }

                    // Strength sets grouped by exercise
                    ForEach(exerciseGroupRows, id: \.id) { row in
                        activityRow(
                            icon: "dumbbell.fill", name: row.name,
                            detail: "\(row.setCount) set\(row.setCount == 1 ? "" : "s")",
                            kcal: row.kcal, dimmed: false
                        )
                    }

                    // Cardio (non-walk)
                    ForEach(todayCardio.filter { $0.type != .walk }) { session in
                        activityRow(
                            icon: cardioIcon(session.type),
                            name: session.type.label,
                            detail: "\(session.durationMinutes) min",
                            kcal: Int((session.caloriesEst ?? 0).rounded()),
                            dimmed: false
                        )
                    }

                    // Pilates sessions
                    ForEach(todayPilates) { session in
                        let kcal = Int((3.0 * Double(weightKg) * Double(session.durationMinutes) / 60.0).rounded())
                        activityRow(
                            icon: "figure.mind.and.body", name: "Pilates",
                            detail: "\(session.durationMinutes) min",
                            kcal: kcal, dimmed: false
                        )
                    }

                    // Live sessions (non-walking)
                    ForEach(todayActivities.filter { $0.activityId != "activity-walking" }) { session in
                        activityRow(
                            icon: "stopwatch.fill",
                            name: session.activityName,
                            detail: "\(session.durationMinutes) min · MET \(String(format: "%.1f", session.met))",
                            kcal: Int((session.caloriesEst ?? 0).rounded()),
                            dimmed: false
                        )
                    }

                    // Steps — reference row, dimmed (counted in MET Total, not here)
                    activityRow(
                        icon: "figure.walk",
                        name: "Steps",
                        detail: "\(todaySteps.formatted()) / \(stepsGoal.formatted()) · in Our Estimate",
                        kcal: stepsKcal, dimmed: true
                    )

                    // Training total + derived stats
                    if trainingMetEstimate > 0 {
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("TOTAL TRAINING BURN")
                                    .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                                    .foregroundStyle(theme.dim)
                                Text("~\(trainingMetEstimate) cal")
                                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        .padding(.top, 4)

                        HStack(spacing: 16) {
                            statPill(label: "fat burned", value: "≈\(fatGrams) g")
                            if sweatOz > 0.5 {
                                statPill(label: "sweat estimate", value: String(format: "≈%.1f oz", sweatOz))
                            }
                            Spacer()
                        }
                    }
                }
            }

            // ── Collapsible: what's counted ───────────────────────────
            collapsibleSection(title: "WHAT'S COUNTED", isExpanded: $showWhatCounts) {
                VStack(alignment: .leading, spacing: 5) {
                    bulletRow(check: true,  text: "Strength sets — MET 3.5–8.0 by exercise")
                    bulletRow(check: true,  text: "Cardio sessions, non-walk — MET 4.5")
                    bulletRow(check: true,  text: "Pilates sessions — MET 3.0")
                    bulletRow(check: true,  text: "Live sessions (basketball, yoga, etc.) — MET 2.8–11.8")
                    bulletRow(check: false, text: "Steps — counted in Our Estimate, not here")
                    bulletRow(check: false, text: "Resting/BMR — counted in Our Estimate")
                }
            }

            // ── Collapsible: how it's calculated ─────────────────────
            collapsibleSection(title: "HOW IT'S CALCULATED", isExpanded: $showFormula) {
                VStack(alignment: .leading, spacing: 8) {
                    ColumnInfoBody(text: "Formula: MET × your weight (\(weightKg) kg) × hours = calories. MET scores how intense an activity is relative to sitting still (MET 1.0). Walking = 4.3, squats = 5.0, pull-ups = 8.0.")
                    ColumnBreakdownRow(
                        label: "Example",
                        detail: "60 min basketball (MET 8.0) × \(weightKg) kg × 1 hr = \(8 * weightKg) cal"
                    )
                    Text("Source: Ainsworth BE et al. 2011 Compendium of Physical Activities. Med Sci Sports Exerc.")
                        .font(.caption2).foregroundStyle(theme.dim)
                }
            }
        }
    }

    // MARK: Row helpers

    @ViewBuilder
    private func activityRow(icon: String, name: String, detail: String, kcal: Int, dimmed: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(dimmed ? theme.dim : theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(dimmed ? theme.dim : theme.text)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.dim)
            }
            Spacer()
            if kcal > 0 {
                Text("~\(kcal) cal")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(dimmed ? theme.dim : theme.accent)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(dimmed ? theme.card : theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(dimmed ? RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(theme.line, lineWidth: 0.5) : nil)
    }

    @ViewBuilder
    private func statPill(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .medium)).tracking(1)
                .foregroundStyle(theme.dim)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func bulletRow(check: Bool, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(check ? "✓" : "✗")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(check ? theme.ok : theme.dim)
            Text(text)
                .font(.callout).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func collapsibleSection<Content: View>(
        title: String, isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    Spacer()
                    Image(systemName: isExpanded.wrappedValue ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.dim)
                }
                .padding(.vertical, 10)
            }
            .tactile(.ghost)

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity)
                    .padding(.bottom, 4)
            }
        }
    }

    private func cardioIcon(_ type: CardioType) -> String {
        switch type {
        case .walk:       return "figure.walk"
        case .run:        return "figure.run"
        case .bike:       return "bicycle"
        case .swim:       return "water.waves"
        case .elliptical: return "figure.elliptical"
        case .other:      return "heart.circle.fill"
        }
    }
}

// MARK: - Heart Rate info sheet

private struct HeartRateInfoSheet: View {
    let bpm: Int?
    let asOf: String?

    var body: some View {
        ColumnInfoScaffold(title: "heart rate.", subtitle: "APPLE HEALTH · MOST RECENT READING") {
            ColumnInfoSection(title: "Today") {
                VStack(spacing: 6) {
                    ColumnBigNumberRow(
                        icon: "heart.fill",
                        name: "Latest reading",
                        detail: asOf.map { "as of \($0)" } ?? "Wear your Apple Watch to get a reading.",
                        value: bpm.map { "\($0)" } ?? "-",
                        unit: "bpm"
                    )
                }
            }
            ColumnInfoSection(title: "Ranges") {
                VStack(spacing: 6) {
                    ColumnBreakdownRow(label: "Resting",
                                       detail: "60–100 bpm is normal. Athletes often sit at 50–70 bpm.")
                    ColumnBreakdownRow(label: "Moderate exercise",
                                       detail: "50–70% of your max (≈ 220 − your age)")
                    ColumnBreakdownRow(label: "Vigorous exercise",
                                       detail: "70–85% of your max")
                }
            }
            ColumnInfoSection(title: "Why it matters") {
                ColumnInfoBody(text: "A falling resting heart rate over weeks is one of the clearest signs of improving cardiovascular fitness. Consistent steps and regular cardio are the fastest levers.")
            }
        }
    }
}

// MARK: - Distance info sheet

private struct DistanceInfoSheet: View {
    let miles: Double
    let unitSystem: UnitSystem
    @Environment(\.theme) private var theme

    private var displayValue: String {
        unitSystem == .imperial
            ? String(format: "%.2f", miles)
            : String(format: "%.2f", miles * 1.60934)
    }
    private var unitLabel: String { unitSystem == .imperial ? "miles" : "km" }

    var body: some View {
        ColumnInfoScaffold(title: "distance.", subtitle: "WALKING + RUNNING · FROM APPLE HEALTH") {
            ColumnInfoSection(title: "Today") {
                VStack(spacing: 6) {
                    ColumnBigNumberRow(
                        icon: "figure.walk",
                        name: "Walking + Running",
                        detail: miles > 0 ? "total foot distance today" : "Carry your iPhone or wear your Apple Watch.",
                        value: miles > 0 ? displayValue : "-",
                        unit: unitLabel
                    )
                }
            }
            ColumnInfoSection(title: "Benchmarks") {
                VStack(spacing: 6) {
                    ColumnBreakdownRow(label: "2,000 steps ≈ 1 mile",
                                       detail: "Exact distance depends on stride length.")
                    ColumnBreakdownRow(label: "10,000 steps ≈ 4–5 miles",
                                       detail: "The step count linked to cardiovascular benefits in major studies.")
                }
            }
        }
    }
}

// MARK: - Flights Climbed info sheet

private struct FlightsClimbedInfoSheet: View {
    let floors: Int
    @Environment(\.theme) private var theme

    var body: some View {
        ColumnInfoScaffold(title: "flights climbed.", subtitle: "FLOORS · FROM APPLE HEALTH BAROMETER") {
            ColumnInfoSection(title: "Today") {
                VStack(spacing: 6) {
                    ColumnBigNumberRow(
                        icon: "arrow.up.circle.fill",
                        name: "Floors climbed",
                        detail: floors > 0
                            ? "≈ \(floors * 10) ft / \(floors * 3) m elevation"
                            : "Detected automatically as you ascend ~10 feet.",
                        value: floors > 0 ? "\(floors)" : "-",
                        unit: "floors"
                    )
                }
            }
            ColumnInfoSection(title: "Why it matters") {
                ColumnInfoBody(text: "Stair climbing (MET 4.0–8.0) activates glutes and quads and spikes heart rate faster than flat walking. Studies link regular stair use to lower all-cause mortality. (Stamatakis et al., Brit J Sports Med 2021)")
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
            Text(title).font(.caption).tracking(2).textCase(.uppercase).foregroundStyle(theme.dim)
            content()
        }
    }
}

private struct ColumnInfoBody: View {
    let text: String
    @Environment(\.theme) private var theme
    var body: some View {
        Text(text).font(.callout).foregroundStyle(theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// Row with a large number on the right — used across all info sheets for per-item stats.
private struct ColumnBigNumberRow: View {
    let icon: String
    let name: String
    var detail: String = ""
    let value: String
    var unit: String = "cal"
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.dim)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// Full-width hero total — large accent number, right-aligned label + value stack.
private struct ColumnHeroStat: View {
    let label: String
    let value: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold)).tracking(1.5)
                    .foregroundStyle(theme.dim)
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.top, 4)
    }
}

private struct ColumnBreakdownRow: View {
    let label: String
    let detail: String
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
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
