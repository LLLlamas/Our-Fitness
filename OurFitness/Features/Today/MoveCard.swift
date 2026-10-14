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

    /// One source of truth for the day's burn: `DailyBurn` owns the MET math and
    /// the walk-exclusion rules (logged walks and the Walking live activity are
    /// already counted via steps). This card only rounds for display.
    private var burn: DailyBurn.Breakdown {
        DailyBurn.breakdown(
            steps: todaySteps, sets: todaySets, cardio: todayCardio, pilates: todayPilates,
            activities: todayActivities, bodyWeightLb: profile.weightLb
        )
    }

    private var stepsKcal: Int     { Int(burn.stepsKcal.rounded()) }
    private var setsKcal: Int      { Int(burn.setsKcal.rounded()) }
    private var cardioKcal: Int    { Int(burn.cardioKcal.rounded()) }
    private var pilatesKcal: Int   { Int(burn.pilatesKcal.rounded()) }
    private var activitiesKcal: Int { Int(burn.activitiesKcal.rounded()) }
    /// Sum of the per-source rounded figures, so the Training column always
    /// equals the rows the Training sheet lists underneath it.
    private var trainingMetEstimate: Int { setsKcal + cardioKcal + pilatesKcal + activitiesKcal }

    private var metTotal: Int { burn.total }
    private var weightKg: Int { Int(profile.weightLb * Units.kgPerLb) }

    private var distanceLabel: String {
        unitSystem == .imperial
            ? String(format: "%.1f", walkingDistanceMiles)
            : String(format: "%.1f", walkingDistanceMiles * Units.kmPerMile)
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
                        icon: "sum", title: "OUR TOTAL ESTIMATE",
                        value: "\(metTotal)",
                        sub: "cal · activity estimate",
                        action: { showMetTotalInfo = true }
                    )
                    columnSep
                    metricColumn(
                        icon: "dumbbell.fill", title: "TRAINING ONLY",
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
                profile: profile, metTotal: metTotal,
                trainingMet: trainingMetEstimate,
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
                metTotal: metTotal,
                stepsKcal: stepsKcal, trainingKcal: trainingMetEstimate, weightKg: weightKg
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showExercisesInfo) {
            ExercisesInfoSheet(
                weightKg: weightKg, weightLb: profile.weightLb,
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
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
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
    let trainingMet: Int
    let todaySteps: Int
    let stepsKcal: Int

    @Environment(\.theme) private var theme
    private var weightKg: Int { Int(profile.weightLb * Units.kgPerLb) }

    var body: some View {
        InfoSheetScaffold(title: "Move", subtitle: "MET × WEIGHT × TIME = CALORIES") {
            InfoSection(title: "Two sources, one picture") {
                InfoBody("Apple Health measures what its sensors detect. Our Estimate calculates from what you log — steps + training. They'll rarely match perfectly, and that's fine.")
            }

            InfoSection(title: "Apple Total") {
                VStack(alignment: .leading, spacing: 8) {
                    columnNote(label: "Active energy", detail: "Steps and all movement Apple detects. Misses logged strength and sport sessions. Syncs from Watch every 15–60 min.")
                    columnNote(label: "Distance & Flights", detail: "Foot distance from GPS and floors climbed from the barometer.")
                    columnNote(label: "Heart Rate", detail: "Most recent spot reading — not a daily average.")
                }
            }

            InfoSection(title: "Our Estimate") {
                VStack(alignment: .leading, spacing: 8) {
                    columnNote(label: "Activity total", detail: "Step burn (MET 4.3) + all logged training sessions.")
                    columnNote(label: "Training", detail: "Only logged sessions — strength, cardio, pilates, live activities. The activity Apple's sensors miss.")
                    InfoRow(
                        label: "Today's breakdown",
                        detail: "Steps: ≈\(stepsKcal) cal\nTraining: ≈\(trainingMet) cal\nTotal: ≈\(metTotal) cal"
                    )
                }
            }

            InfoFootnote("Source: Ainsworth BE et al. 2011 Compendium of Physical Activities. Med Sci Sports Exerc.")
        }
    }

    // Unboxed label + detail pair. Only this sheet uses it, so it stays local
    // rather than joining the shared info-sheet vocabulary.
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
        InfoSheetScaffold(title: "apple energy.", subtitle: "ACTIVE ENERGY · FROM YOUR IPHONE + WATCH") {

            InfoSection(title: "Today") {
                VStack(spacing: 6) {
                    if activeKcal == nil {
                        InfoMetricRow(icon: "bolt.fill", name: "No data yet",
                                           detail: "Watch syncs every 15–60 min. Carry your iPhone for iPhone-only tracking.",
                                           value: "-", unit: "cal")
                    } else {
                        InfoMetricRow(
                            icon: "bolt.fill",
                            name: "Active energy",
                            detail: "Movement Apple detected today",
                            value: activeKcal.map { "\($0)" } ?? "-",
                            unit: "cal"
                        )
                        if let kcal = activeKcal {
                            InfoHeroStat(
                                label: "TODAY" + (asOf.map { " · \($0)" } ?? ""),
                                value: "\(kcal) cal"
                            )
                        }
                    }
                }
            }

            InfoSection(title: "What's counted") {
                VStack(alignment: .leading, spacing: 5) {
                    InfoBody("Every calorie burned beyond your resting baseline — walking, workouts, stairs, fidgeting. Measured directly by iPhone and Apple Watch sensors.")
                    InfoBody("✓  All steps and movement Apple can detect\n✗  Doesn't include manually logged training sessions (those are in Our Estimate)")
                }
            }

            InfoSection(title: "vs. Our Estimate") {
                InfoRow(
                    label: "Apple active vs. Our Estimate",
                    detail: "Our Estimate = steps (MET formula) + logged training. Apple active energy = movement its sensors detect. Numbers won't match exactly — that's expected."
                )
            }
        }
    }
}

// MARK: - MET Total info sheet

private struct MetTotalInfoSheet: View {
    let metTotal: Int
    let stepsKcal: Int
    let trainingKcal: Int
    let weightKg: Int

    var body: some View {
        InfoSheetScaffold(title: "our total estimate.", subtitle: "MET FORMULA · ACTIVITY CALORIES") {

            InfoSection(title: "Today's breakdown") {
                VStack(spacing: 6) {
                    InfoMetricRow(
                        icon: "figure.walk",
                        name: "Steps",
                        detail: "MET 4.3 × \(weightKg) kg × step count",
                        value: "~\(stepsKcal)",
                        unit: "cal"
                    )
                    InfoMetricRow(
                        icon: "dumbbell.fill",
                        name: "Training",
                        detail: "Logged strength, cardio, pilates, live sessions",
                        value: "~\(trainingKcal)",
                        unit: "cal"
                    )
                    InfoHeroStat(label: "TOTAL TODAY", value: "~\(metTotal) cal")
                }
            }

            InfoSection(title: "vs. Apple Total") {
                InfoBody("Apple shows active energy from its sensors. Our Estimate uses the Ainsworth MET formula on what you log — step count + training sessions. Numbers won't match exactly; that's expected.")
            }
        }
    }
}

// MARK: - Training (Exercises) info sheet

private struct ExercisesInfoSheet: View {
    let weightKg: Int
    let weightLb: Double
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
        !todayActivities.filter({ $0.activityId != ActivityCatalog.walkingId }).isEmpty
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
        InfoSheetScaffold(title: "training only.", subtitle: "TODAY'S BURN FROM LOGGED SESSIONS") {

            // ── Today's activity ─────────────────────────────────────
            InfoSection(title: "Today's activity") {
                VStack(spacing: 6) {
                    if !hasAnyTraining {
                        InfoBody("No training logged yet. Head to the Workouts tab to get started.")
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
                        let kcal = Int(CalorieEstimator.caloriesForPilates(
                            minutes: Double(session.durationMinutes), bodyWeightLb: weightLb).rounded())
                        activityRow(
                            icon: "figure.mind.and.body", name: "Pilates",
                            detail: "\(session.durationMinutes) min",
                            kcal: kcal, dimmed: false
                        )
                    }

                    // Live sessions (non-walking)
                    ForEach(todayActivities.filter { $0.activityId != ActivityCatalog.walkingId }) { session in
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
                        InfoHeroStat(label: "TOTAL TRAINING BURN",
                                     value: "~\(trainingMetEstimate) cal",
                                     valueSize: 24)

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
                    Bullet("Strength sets — MET 3.5–8.0 by exercise", marker: .check)
                    Bullet("Cardio sessions, non-walk — MET 4.5", marker: .check)
                    Bullet("Pilates sessions — MET 3.0", marker: .check)
                    Bullet("Live sessions (basketball, yoga, etc.) — MET 2.8–11.8", marker: .check)
                    Bullet("Steps — counted in Our Estimate, not here", marker: .cross)
                }
            }

            // ── Collapsible: how it's calculated ─────────────────────
            collapsibleSection(title: "HOW IT'S CALCULATED", isExpanded: $showFormula) {
                VStack(alignment: .leading, spacing: 8) {
                    InfoBody("Formula: MET × your weight (\(weightKg) kg) × hours = calories. MET scores how intense an activity is relative to sitting still (MET 1.0). Walking = 4.3, squats = 5.0, pull-ups = 8.0.")
                    InfoRow(
                        label: "Example",
                        detail: "60 min basketball (MET 8.0) × \(weightKg) kg × 1 hr = \(8 * weightKg) cal"
                    )
                    InfoFootnote("Source: Ainsworth BE et al. 2011 Compendium of Physical Activities. Med Sci Sports Exerc.")
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

    // Only this sheet has collapsible sections, so the disclosure chrome stays
    // local rather than joining the shared info-sheet vocabulary.
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
        InfoSheetScaffold(title: "heart rate.", subtitle: "APPLE HEALTH · MOST RECENT READING") {
            InfoSection(title: "Today") {
                VStack(spacing: 6) {
                    InfoMetricRow(
                        icon: "heart.fill",
                        name: "Latest reading",
                        detail: asOf.map { "as of \($0)" } ?? "Wear your Apple Watch to get a reading.",
                        value: bpm.map { "\($0)" } ?? "-",
                        unit: "bpm"
                    )
                }
            }
            InfoSection(title: "Ranges") {
                VStack(spacing: 6) {
                    InfoRow(label: "Resting",
                            detail: "60–100 bpm is normal. Athletes often sit at 50–70 bpm.")
                    InfoRow(label: "Moderate exercise",
                            detail: "50–70% of your max (≈ 220 − your age)")
                    InfoRow(label: "Vigorous exercise",
                            detail: "70–85% of your max")
                }
            }
            InfoSection(title: "Why it matters") {
                InfoBody("A falling resting heart rate over weeks is one of the clearest signs of improving cardiovascular fitness. Consistent steps and regular cardio are the fastest levers.")
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
            : String(format: "%.2f", miles * Units.kmPerMile)
    }
    private var unitLabel: String { unitSystem == .imperial ? "miles" : "km" }

    var body: some View {
        InfoSheetScaffold(title: "distance.", subtitle: "WALKING + RUNNING · FROM APPLE HEALTH") {
            InfoSection(title: "Today") {
                VStack(spacing: 6) {
                    InfoMetricRow(
                        icon: "figure.walk",
                        name: "Walking + Running",
                        detail: miles > 0 ? "total foot distance today" : "Carry your iPhone or wear your Apple Watch.",
                        value: miles > 0 ? displayValue : "-",
                        unit: unitLabel
                    )
                }
            }
            InfoSection(title: "Benchmarks") {
                VStack(spacing: 6) {
                    InfoRow(label: "2,000 steps ≈ 1 mile",
                            detail: "Exact distance depends on stride length.")
                    InfoRow(label: "10,000 steps ≈ 4–5 miles",
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
        InfoSheetScaffold(title: "flights climbed.", subtitle: "FLOORS · FROM APPLE HEALTH BAROMETER") {
            InfoSection(title: "Today") {
                VStack(spacing: 6) {
                    InfoMetricRow(
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
            InfoSection(title: "Why it matters") {
                InfoBody("Stair climbing (MET 4.0–8.0) activates glutes and quads and spikes heart rate faster than flat walking. Studies link regular stair use to lower all-cause mortality. (Stamatakis et al., Brit J Sports Med 2021)")
            }
        }
    }
}
