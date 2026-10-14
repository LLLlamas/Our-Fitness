import SwiftUI
import SwiftData
import Charts

/// Named ProgressTabView to avoid collision with SwiftUI.ProgressView.
struct ProgressTabView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    // Profile-scoped at the query level — never fetch another profile's rows.
    @Query private var bodyModels: [BodyMetricModel]
    @Query private var markerModels: [HealthMarkerModel]
    @Query private var stepModels: [StepCountModel]
    @Query private var setModels: [WorkoutSetModel]
    // Energy-balance card inputs. Scoped per-profile like everything else.
    @Query private var foodModels: [FoodLogEntryModel]
    @Query private var cardioModels: [CardioSessionModel]
    @Query private var pilatesModels: [PilatesSessionModel]
    @Query private var activityModels: [ActivitySessionModel]

    @State private var activeStat: StatKind?
    @State private var showEditTrackers = false
    @State private var showEnergyBalance = false
    @State private var showTrainingHistory = false

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    /// Per-profile custom tracker visibility. Empty = use the mode defaults;
    /// "none" = customized to show nothing; otherwise a CSV of StatKind raw values.
    /// IMPORTANT: never add a StatKind whose rawValue is "none" — it collides with the sentinel.
    @AppStorage private var enabledStatsRaw: String

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _enabledStatsRaw = AppStorage(wrappedValue: "", "progressStats.\(uid.uuidString)")
        _bodyModels = Query(
            filter: #Predicate<BodyMetricModel> { $0.userId == uid },
            sort: \.date, order: .forward
        )
        _markerModels = Query(
            filter: #Predicate<HealthMarkerModel> { $0.userId == uid },
            sort: \.date, order: .forward
        )
        // Date-ascending like bodyModels — the `Steps.*` helpers index by day so
        // order is irrelevant to them, and stepsDetail re-sorts for display.
        _stepModels = Query(
            filter: #Predicate<StepCountModel> { $0.userId == uid },
            sort: \.date, order: .forward
        )
        _setModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid },
            sort: \.timestamp, order: .forward
        )
        // Food uses userId; cardio/pilates/activities use profileId (mirrors MoveCard).
        _foodModels = Query(
            filter: #Predicate<FoodLogEntryModel> { $0.userId == uid },
            sort: \.timestamp, order: .forward
        )
        _cardioModels = Query(
            filter: #Predicate<CardioSessionModel> { $0.profileId == uid },
            sort: \.date, order: .forward
        )
        _pilatesModels = Query(
            filter: #Predicate<PilatesSessionModel> { $0.profileId == uid },
            sort: \.date, order: .forward
        )
        _activityModels = Query(
            filter: #Predicate<ActivitySessionModel> { $0.profileId == uid },
            sort: \.date, order: .forward
        )
    }

    // Body metrics arrive date-ascending from the query (consumers take `.last`).
    private var body_: [BodyMetricDTO] { bodyModels.map(\.snapshot) }
    private var markers: [HealthMarkerDTO] { markerModels.map(\.snapshot) }
    private var steps: [StepCountDTO] { stepModels.map(\.snapshot) }
    private var sets: [WorkoutSetDTO] { setModels.map(\.snapshot) }

    private var targetCalories: Int { profile.computedTargets.calories }

    /// The enabled tracker set: mode defaults until the user customizes, then
    /// whatever they chose (including the empty "none" state).
    ///
    /// The default is deliberately small — only trackers the app can fill in
    /// itself — plus any tracker that already holds data, so a profile that has
    /// been logging waist or labs without ever opening Edit trackers keeps those
    /// cards. Once the user customizes, the stored CSV wins outright.
    private func enabledSet(body: [BodyMetricDTO], markers: [HealthMarkerDTO]) -> Set<String> {
        if enabledStatsRaw.isEmpty {
            var set = Set(StatKind.allCases.filter { $0.isRelevant(for: profile.mode) }.map(\.rawValue))
            for kind in StatKind.allCases where !set.contains(kind.rawValue) {
                if kind.hasLoggedData(body: body, markers: markers) { set.insert(kind.rawValue) }
            }
            return set
        }
        if enabledStatsRaw == "none" { return [] }
        return Set(enabledStatsRaw.split(separator: ",").map(String.init))
    }

    private func visibleStats(in enabled: Set<String>) -> [StatKind] {
        StatKind.allCases
            .filter { enabled.contains($0.rawValue) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func persistEnabled(_ set: Set<String>) {
        if set.isEmpty {
            enabledStatsRaw = "none"
        } else {
            enabledStatsRaw = StatKind.allCases
                .filter { set.contains($0.rawValue) }
                .map(\.rawValue)
                .joined(separator: ",")
        }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        let body_ = self.body_
        let markers = self.markers
        let steps = self.steps
        let sets = self.sets
        let cardio = cardioModels.map(\.snapshot)
        let pilates = pilatesModels.map(\.snapshot)
        let activities = activityModels.map(\.snapshot)
        let energyRows = EnergyBalance.byDay(
            days: 30,
            foodLogs: foodModels.map(\.snapshot), steps: steps, sets: sets,
            cardio: cardio, pilates: pilates, activities: activities,
            bodyWeightLb: profile.weightLb
        )
        let enabled = enabledSet(body: body_, markers: markers)
        let visibleStats = visibleStats(in: enabled)
        // The card only needs "how many days" and "which was last", so take the
        // day keys straight off the sets. `TrainingHistory.sessions` buckets by
        // the same `Dates.dayKey($0.timestamp)` but also groups, accumulates and
        // sorts every exercise line — a full history rebuild (plus a second
        // unbounded exercise-name query) on every pass of this tab, all to
        // produce a count. The sheet still builds the real sessions when opened.
        let trainingHistoryDays = Set(
            sets.map { Dates.dayKey($0.timestamp) }
            + cardio.map { Dates.dayKey($0.date) }
            + pilates.map { Dates.dayKey($0.date) }
            + activities.map { Dates.dayKey($0.date) }
        )
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Progress")
                        .font(.system(size: 56, weight: .regular))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Button { showEditTrackers = true } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .tactile(.ghost)
                    .accessibilityLabel("Edit trackers")
                }
                Text("Weekly trends > daily pass/fail. Show up, log honestly, watch the lines move.")
                    .font(.callout).foregroundStyle(theme.dim)

                if visibleStats.isEmpty {
                    Text("No trackers shown. Tap the sliders above to add some.")
                        .font(.callout).foregroundStyle(theme.dim)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(visibleStats, id: \.self) { kind in
                            statCard(for: kind, body: body_, markers: markers, steps: steps, sets: sets)
                        }
                    }
                    // A hidden tracker's card is also the only place to log that
                    // value, so keep one quiet line pointing at the rest.
                    if visibleStats.count < StatKind.allCases.count {
                        Button { showEditTrackers = true } label: {
                            Text("Add a tracker — body fat, waist, blood pressure, labs")
                                .font(.footnote)
                                .foregroundStyle(theme.dim)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .tactile(.ghost)
                    }
                }

                // Calorie intake vs activity burn — shown for both modes.
                energyBalanceCard(energyRows: energyRows)

                // Cross-day training history; Today/Train only keep the daily surface short.
                if !trainingHistoryDays.isEmpty {
                    // Lexicographic max on yyyy-MM-dd is the most recent day.
                    trainingHistoryCard(dayCount: trainingHistoryDays.count,
                                        lastDay: trainingHistoryDays.max())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .scrollHapticTicks()
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(item: $activeStat) { kind in
            detailSheet(for: kind)
                .themed(profile.mode)
        }
        .sheet(isPresented: $showEditTrackers) {
            EditTrackersSheet(enabled: enabled, mode: profile.mode) { newSet in
                persistEnabled(newSet)
            }
            .themed(profile.mode)
        }
        .sheet(isPresented: $showEnergyBalance) {
            EnergyBalanceDetailSheet(
                rows: energyRows,
                targetCalories: targetCalories
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showTrainingHistory) {
            TrainingHistorySheet(profile: profile)
                .themed(profile.mode)
        }
    }

    // MARK: - Training history card

    @ViewBuilder
    private func trainingHistoryCard(dayCount: Int, lastDay: String?) -> some View {
        PressableCard(action: { showTrainingHistory = true }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Label("Training history", systemImage: "dumbbell.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.dim)
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    metric(label: "DAYS LOGGED", value: dayCount, accent: theme.text)
                    Spacer()
                    Text(lastDay.map { "last · \(Dates.formatShort($0))" } ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.dim)
                }
            }
        }
    }

    // MARK: - Energy balance card

    @ViewBuilder
    private func energyBalanceCard(energyRows: [EnergyBalance.DayBalance]) -> some View {
        let todayBalance = energyRows.last
        let intake = todayBalance?.intake ?? 0
        let burned = todayBalance?.burned ?? 0
        PressableCard(action: { showEnergyBalance = true }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Label("Energy Balance", systemImage: "fork.knife")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.dim)
                }

                // Intake-vs-target bar inherits the reveal animation.
                ProgressBar(
                    value: Double(intake),
                    target: Double(max(targetCalories, 1)),
                    label: "Calories in",
                    unit: " cal"
                )

                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    metric(label: "TARGET", value: targetCalories, accent: theme.text)
                    metric(label: "BURNED", value: burned, accent: theme.accent2)
                    Spacer()
                    Text("today · tap for trend")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.dim)
                }
            }
        }
    }

    @ViewBuilder
    private func metric(label: String, value: Int, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold)).tracking(1.2)
                .foregroundStyle(theme.dim)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                Text("cal")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.dim)
            }
        }
    }

    // MARK: - Cards

    /// Takes the four snapshot arrays rather than reading the computed
    /// properties, which each rebuild DTOs from the whole unbounded query. This
    /// is called once per visible tracker and used to read them TWICE per call —
    /// at 13 trackers that was ~104 full rebuilds of the user's entire body,
    /// marker, step and set history for one pass of the grid.
    @ViewBuilder
    private func statCard(
        for kind: StatKind,
        body body_: [BodyMetricDTO],
        markers: [HealthMarkerDTO],
        steps: [StepCountDTO],
        sets: [WorkoutSetDTO]
    ) -> some View {
        let value = kind.displayValue(body: body_, markers: markers, steps: steps, sets: sets, profile: profile, system: unitSystem)
        let trend = kind.trendChip(body: body_, markers: markers, steps: steps, sets: sets, profile: profile, system: unitSystem)
        let tint  = statusTint(for: kind, body: body_, markers: markers)
        StatCard(
            title: kind.title,
            value: value,
            unit: kind.unit(system: unitSystem),
            trend: trend,
            valueAccent: tint,
            action: { activeStat = kind }
        )
    }

    private func statusTint(for kind: StatKind, body body_: [BodyMetricDTO], markers: [HealthMarkerDTO]) -> Color? {
        let status: HealthRanges.RangeStatus
        switch kind {
        case .bp:
            let sys = latestMarkerValue(.bpSystolic, in: markers)
            let dia = latestMarkerValue(.bpDiastolic, in: markers)
            guard sys != nil || dia != nil else { return nil }
            status = HealthRanges.bpStatus(systolic: sys, diastolic: dia)
        case .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose, .restingHR:
            guard let mk = kind.markerKind,
                  let v = latestMarkerValue(mk, in: markers) else { return nil }
            status = HealthRanges.status(for: mk, value: v)
        case .bmi:
            guard let w = body_.compactMap(\.weightLb).last else { return nil }
            let bmi = BodyComposition.bmi(weightLb: w, heightIn: profile.heightIn)
            return bmiIsHealthy(bmi) ? theme.ok : theme.warn
        case .weight, .bodyFat, .waist, .stepsAvg, .trainingVolume:
            return nil
        }
        switch status {
        case .optimal:    return theme.ok
        case .borderline: return theme.accent2
        case .high:       return theme.warn
        case .unknown:    return nil
        }
    }

    // MARK: - Detail sheets

    @ViewBuilder
    private func detailSheet(for kind: StatKind) -> some View {
        switch kind {
        case .stepsAvg:
            stepsDetail
        case .bp:
            BPDetailSheet(profile: profile, markers: markers, unitSystem: unitSystem)
        case .weight:
            WeightLogSheet(
                profile: profile,
                metrics: body_,
                unitSystem: unitSystem,
                onSave: { value in save(kind: .weight, value: value) }
            )
        case .bodyFat:
            BodyFatDetailSheet(
                profile: profile,
                metrics: body_,
                unitSystem: unitSystem,
                onSave: { value in save(kind: .bodyFat, value: value) }
            )
        case .bmi:
            BMIDetailSheet(profile: profile, metrics: body_)
        case .trainingVolume:
            trainingVolumeDetail
        default:
            StatDetailSheet(
                title: kind.title,
                unit: kind.unit(system: unitSystem),
                series: kind.series(body: body_, markers: markers, steps: steps, sets: sets, system: unitSystem),
                entries: kind.entries(body: body_, markers: markers, system: unitSystem),
                placeholder: kind.placeholder(system: unitSystem),
                canLog: kind.canLog,
                rangeContext: kind.markerKind.map(HealthRanges.context(for:)),
                personalNote: kind.markerKind.flatMap { mk in
                    latestMarkerValue(mk, in: markers).map { TargetRationale.markerMeaning(kind: mk, value: $0, mode: profile.mode) }
                },
                onSave: { value in
                    // Waist is entered in the active unit; convert back to canonical inches.
                    let canonical = kind == .waist
                        ? Units.lengthToInches(value, system: unitSystem)
                        : value
                    save(kind: kind, value: canonical)
                }
            )
        }
    }

    @ViewBuilder
    private var stepsDetail: some View {
        StatDetailSheet(
            title: "Steps",
            unit: "steps · daily",
            series: Steps.series(steps, days: 30),
            entries: steps
                .sorted { $0.date > $1.date }
                .prefix(10)
                .map { s in
                    StatDetailEntry(
                        id: s.id.uuidString,
                        dateLabel: s.date,
                        valueLabel: s.steps.formatted()
                    )
                },
            canLog: false
        )
    }

    @ViewBuilder
    private var trainingVolumeDetail: some View {
        StatDetailSheet(
            title: "Training",
            unit: "sets · weekly",
            series: TrainingHistory.weeklySetCounts(sets),
            canLog: false,
            showsEntries: false,
            minChartPoints: 2,
            emptyChartText: "Not enough logged weeks yet.",
            emptyChartDetail: "Log sets for two weeks to see the volume trend. Individual sessions live in Training history."
        )
    }

    // MARK: - Save

    private func save(kind: StatKind, value: Double) {
        let today = Dates.dayKey()
        switch kind {
        case .weight:
            guard Repos.addBody(ctx, BodyMetricDTO(
                userId: profile.id, date: today, weightLb: value
            )) else { return }
            // Re-point the profile (the source recommendations read) at this weight
            // and recompute targets so calorie/protein/water goals track current weight.
            Repos.syncCurrentWeight(ctx, profileId: profile.id)
            Task { await HealthKitService.shared.writeWeightLb(value) }
            toasts.show(Toast(title: "Weight logged",
                              detail: Units.formatWeightWithUnit(lb: value, system: unitSystem),
                              accent: .ok, symbol: "scalemass.fill"))
        case .bodyFat:
            guard Repos.addBody(ctx, BodyMetricDTO(
                userId: profile.id, date: today, bodyFatPct: value
            )) else { return }
            toasts.show(Toast(title: "Body fat logged",
                              detail: String(format: "%.1f %%", value),
                              accent: .ok, symbol: "scalemass.fill"))
        case .waist:
            guard Repos.addBody(ctx, BodyMetricDTO(
                userId: profile.id, date: today, waistIn: value
            )) else { return }
            toasts.show(Toast(title: "Waist logged",
                              detail: Units.formatLengthWithUnit(inches: value, system: unitSystem),
                              accent: .ok, symbol: "ruler"))
        case .restingHR, .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            guard let markerKind = kind.markerKind else { return }
            guard Repos.addMarker(ctx, HealthMarkerDTO(
                userId: profile.id, date: today,
                kind: markerKind, value: value, source: "manual"
            )) else { return }
            toasts.show(Toast(title: "\(kind.title) logged",
                              detail: "\(formattedValue(value)) \(kind.unit(system: unitSystem))",
                              accent: .ok, symbol: "heart.text.square.fill"))
        case .bp, .stepsAvg, .bmi, .trainingVolume:
            break
        }
    }
}

// MARK: - StatKind

enum StatKind: String, CaseIterable, Identifiable {
    case weight, bodyFat, waist, bmi, restingHR, stepsAvg
    case trainingVolume
    case bp, ldl, hdl, totalCholesterol, a1c, fastingGlucose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight:           return "Weight"
        case .bodyFat:          return "Body Fat"
        case .waist:            return "Waist"
        case .bmi:              return "BMI"
        case .restingHR:        return "Resting HR"
        case .stepsAvg:         return "Steps · 7d avg"
        case .trainingVolume:   return "Training"
        case .bp:               return "BP"
        case .ldl:              return "LDL"
        case .hdl:              return "HDL"
        case .totalCholesterol: return "Total Chol."
        case .a1c:              return "A1c"
        case .fastingGlucose:   return "Fasting Gluc."
        }
    }

    func unit(system: UnitSystem = .imperial) -> String {
        switch self {
        case .weight:           return Units.weightUnit(system)
        case .bodyFat:          return "% body fat"
        case .waist:            return Units.lengthUnit(system)
        case .bmi:              return "BMI"
        case .restingHR:        return "bpm"
        case .stepsAvg:         return "steps"
        case .trainingVolume:   return "sets · this week"
        case .bp:               return "mmHg"
        case .ldl, .hdl, .totalCholesterol, .fastingGlucose: return "mg/dL"
        case .a1c:              return "%"
        }
    }

    func placeholder(system: UnitSystem = .imperial) -> String {
        switch self {
        case .weight:           return "weight (\(Units.weightUnit(system)))"
        case .bodyFat:          return "body fat (%)"
        case .waist:            return "waist (\(Units.lengthUnit(system)))"
        case .restingHR:        return "resting HR (bpm)"
        case .ldl, .hdl, .totalCholesterol, .fastingGlucose: return "value (mg/dL)"
        case .a1c:              return "A1c (%)"
        case .bmi, .bp, .stepsAvg, .trainingVolume: return ""
        }
    }

    var canLog: Bool {
        self != .stepsAvg && self != .bmi && self != .trainingVolume
    }

    var markerKind: HealthMarkerKind? {
        switch self {
        case .restingHR:        return .restingHR
        case .ldl:              return .ldl
        case .hdl:              return .hdl
        case .totalCholesterol: return .totalCholesterol
        case .a1c:              return .a1c
        case .fastingGlucose:   return .fastingGlucose
        default:                return nil
        }
    }

    /// Shown by default on a fresh profile. The bar is "can the app fill this in
    /// on its own?" — anything needing calipers, a tape measure, a cuff, or a
    /// blood draw starts hidden so first open isn't a wall of dashes. Every
    /// tracker is still one tap away in Edit trackers.
    func isRelevant(for mode: Mode) -> Bool {
        switch self {
        case .weight, .stepsAvg, .trainingVolume:
            // Weight: in-app wheel + Health sync. Steps: Health. Sets: in-app.
            return true
        case .restingHR, .bp:
            // Circuit is the cardiovascular mode: resting HR arrives from Health,
            // and blood pressure is the one marker that's cheap to self-measure.
            return mode == .circuit
        case .bmi:
            // Derived from weight + profile height — the Weight card already
            // shows that number and a more useful lb/week trend.
            return false
        case .bodyFat, .waist, .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            // Equipment or a lab panel. Real metrics, but empty for most people.
            return false
        }
    }

    /// True when this tracker already has something to show. Used so the default
    /// set keeps a card a profile has been filling in before the defaults shrank.
    func hasLoggedData(body: [BodyMetricDTO], markers: [HealthMarkerDTO]) -> Bool {
        switch self {
        case .weight:
            return body.contains { $0.weightLb != nil }
        case .bodyFat:
            return body.contains { $0.bodyFatPct != nil }
        case .waist:
            return body.contains { $0.waistIn != nil }
        case .bp:
            return markers.contains { $0.kind == .bpSystolic || $0.kind == .bpDiastolic }
        case .restingHR, .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            guard let k = markerKind else { return false }
            return markers.contains { $0.kind == k }
        case .bmi, .stepsAvg, .trainingVolume:
            // Derived or always-on: nothing of their own is "logged".
            return false
        }
    }

    func displayValue(
        body: [BodyMetricDTO],
        markers: [HealthMarkerDTO],
        steps: [StepCountDTO],
        sets: [WorkoutSetDTO] = [],
        profile: ProfileDTO? = nil,
        system: UnitSystem = .imperial
    ) -> String? {
        switch self {
        case .weight:
            return body.compactMap(\.weightLb).last.map { Units.formatWeight(lb: $0, system: system) }
        case .bodyFat:
            return body.compactMap(\.bodyFatPct).last.map { String(format: "%.1f%%", $0) }
        case .waist:
            return body.compactMap(\.waistIn).last.map { Units.formatLength(inches: $0, system: system) }
        case .bmi:
            guard let p = profile,
                  let w = body.compactMap(\.weightLb).last,
                  p.heightIn > 0 else { return nil }
            let bmi = BodyComposition.bmi(weightLb: w, heightIn: p.heightIn)
            return String(format: "%.1f", bmi)
        case .restingHR:
            return latestMarkerValue(.restingHR, in: markers).map { formattedValue($0) }
        case .stepsAvg:
            let avg = Steps.average(steps, days: 7)
            return avg > 0 ? avg.formatted() : nil
        case .trainingVolume:
            let thisWeekSets = TrainingHistory.setsInWeek(sets)
            return thisWeekSets > 0 ? "\(thisWeekSets)" : nil
        case .bp:
            let s = latestMarkerValue(.bpSystolic, in: markers)
            let d = latestMarkerValue(.bpDiastolic, in: markers)
            if let s, let d { return "\(Int(s))/\(Int(d))" }
            return nil
        case .ldl:
            return latestMarkerValue(.ldl, in: markers).map { formattedValue($0) }
        case .hdl:
            return latestMarkerValue(.hdl, in: markers).map { formattedValue($0) }
        case .totalCholesterol:
            return latestMarkerValue(.totalCholesterol, in: markers).map { formattedValue($0) }
        case .a1c:
            return latestMarkerValue(.a1c, in: markers).map { formattedValue($0) }
        case .fastingGlucose:
            return latestMarkerValue(.fastingGlucose, in: markers).map { formattedValue($0) }
        }
    }

    func trendChip(
        body: [BodyMetricDTO],
        markers: [HealthMarkerDTO],
        steps: [StepCountDTO],
        sets: [WorkoutSetDTO] = [],
        profile: ProfileDTO? = nil,
        system: UnitSystem = .imperial
    ) -> String? {
        switch self {
        case .weight:
            let delta = Trends.weeklyWeightDelta(body, days: 14)
            guard abs(delta) > 0.01 else { return nil }
            let displayDelta = Units.weightValue(lb: delta, system: system)
            return String(format: "%@%.2f %@/wk", displayDelta >= 0 ? "+" : "", displayDelta, Units.weightUnit(system))
        case .bodyFat:
            // Show real fat and lean mass (in the active unit) alongside %
            guard let w = body.compactMap(\.weightLb).last,
                  let bf = body.compactMap(\.bodyFatPct).last else { return nil }
            let fat = BodyComposition.fatMassLb(weightLb: w, bodyFatPct: bf)
            let lean = BodyComposition.leanMassLb(weightLb: w, bodyFatPct: bf)
            let u = Units.weightUnit(system)
            return "\(Units.formatWeight(lb: fat, system: system, decimals: 0)) \(u) fat · \(Units.formatWeight(lb: lean, system: system, decimals: 0)) \(u) lean"
        case .bmi:
            guard let p = profile,
                  let w = body.compactMap(\.weightLb).last,
                  p.heightIn > 0 else { return nil }
            let bmi = BodyComposition.bmi(weightLb: w, heightIn: p.heightIn)
            return BodyComposition.bmiCategory(bmi).label
        case .stepsAvg:
            let avg30 = Steps.average(steps, days: 30)
            return avg30 > 0 ? "30d \(avg30.formatted())" : nil
        case .trainingVolume:
            let this = TrainingHistory.setsInWeek(sets)
            let last = TrainingHistory.setsInWeek(sets, weeksAgo: 1)
            guard last > 0 || this > 0 else { return nil }
            let delta = this - last
            return String(format: "%@%d vs last wk", delta >= 0 ? "+" : "", delta)
        default:
            return nil
        }
    }

    func series(
        body: [BodyMetricDTO],
        markers: [HealthMarkerDTO],
        steps: [StepCountDTO],
        sets: [WorkoutSetDTO] = [],
        system: UnitSystem = .imperial
    ) -> [Trends.Point] {
        switch self {
        case .weight:
            let pts = body.compactMap { b -> Trends.Point? in
                guard let w = b.weightLb else { return nil }
                return Trends.Point(date: b.date, value: Units.weightValue(lb: w, system: system))
            }
            return Trends.rollingAverage(pts, window: 7)
        case .bodyFat:
            return body.compactMap { b in
                b.bodyFatPct.map { Trends.Point(date: b.date, value: $0) }
            }
        case .waist:
            return body.compactMap { b in
                b.waistIn.map { Trends.Point(date: b.date, value: system == .metric ? $0 * Units.cmPerInch : $0) }
            }
        case .restingHR:
            return Trends.markerSeries(markers, kind: .restingHR)
        case .stepsAvg:
            return Steps.series(steps, days: 30)
        case .trainingVolume:
            return TrainingHistory.weeklySetCounts(sets)
        case .bp:
            return Trends.markerSeries(markers, kind: .bpSystolic)
        case .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            guard let k = markerKind else { return [] }
            return Trends.markerSeries(markers, kind: k)
        case .bmi:
            // BMI computed from each weight entry against profile height.
            // Height is static per profile so we can safely use it here.
            return []
        }
    }

    func entries(
        body: [BodyMetricDTO],
        markers: [HealthMarkerDTO],
        system: UnitSystem = .imperial
    ) -> [StatDetailEntry] {
        switch self {
        case .weight:
            return body.compactMap { b -> StatDetailEntry? in
                guard let w = b.weightLb else { return nil }
                return StatDetailEntry(id: b.id.uuidString, dateLabel: b.date,
                                       valueLabel: Units.formatWeightWithUnit(lb: w, system: system))
            }
            .reversed()
            .prefix(10)
            .map { $0 }
        case .bodyFat:
            return body.compactMap { b -> StatDetailEntry? in
                guard let v = b.bodyFatPct else { return nil }
                return StatDetailEntry(id: b.id.uuidString, dateLabel: b.date,
                                       valueLabel: String(format: "%.1f %%", v))
            }
            .reversed()
            .prefix(10)
            .map { $0 }
        case .waist:
            return body.compactMap { b -> StatDetailEntry? in
                guard let v = b.waistIn else { return nil }
                return StatDetailEntry(id: b.id.uuidString, dateLabel: b.date,
                                       valueLabel: Units.formatLengthWithUnit(inches: v, system: system))
            }
            .reversed()
            .prefix(10)
            .map { $0 }
        case .restingHR, .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            guard let k = markerKind else { return [] }
            return markers
                .filter { $0.kind == k }
                .sorted { $0.date > $1.date }
                .prefix(10)
                .map { m in
                    StatDetailEntry(id: m.id.uuidString, dateLabel: m.date,
                                    valueLabel: "\(formattedValue(m.value)) \(unit(system: system))")
                }
        case .bp:
            return markers
                .filter { $0.kind == .bpSystolic || $0.kind == .bpDiastolic }
                .sorted { $0.date > $1.date }
                .prefix(10)
                .map { m in
                    let label = m.kind == .bpSystolic ? "sys" : "dia"
                    return StatDetailEntry(id: m.id.uuidString, dateLabel: m.date,
                                           valueLabel: "\(Int(m.value)) \(label)")
                }
        case .stepsAvg, .bmi, .trainingVolume:
            return []
        }
    }

}

private func formattedValue(_ v: Double) -> String {
    v.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(v)) : String(format: "%.1f", v)
}

/// Latest logged value for a marker kind, or nil. This is the one place the
/// Progress tab turns a marker history into "the current number".
///
/// Deliberately not `Trends.markerSeries(...).last`: that filters, maps and
/// sorts the whole marker history, and this is called a dozen times per Progress
/// pass — twice for blood pressure alone. Taking the max by date is the same
/// answer in one pass, with no per-call re-sort of every marker ever logged.
private func latestMarkerValue(_ kind: HealthMarkerKind, in markers: [HealthMarkerDTO]) -> Double? {
    markers.lazy.filter { $0.kind == kind }.max { $0.date < $1.date }?.value
}

/// Single reading of the BMI thresholds — `BodyComposition.bmiCategory` owns the
/// 18.5 / 25 boundaries, so neither the card tint nor the sheet restates them.
private func bmiIsHealthy(_ bmi: Double) -> Bool {
    BodyComposition.bmiCategory(bmi).label == "Healthy"
}

// MARK: - BMI detail sheet

/// BMI is derived (logged weight + profile height), so there is nothing to log —
/// just the headline, the trend, and the reference table.
private struct BMIDetailSheet: View {
    let profile: ProfileDTO
    let metrics: [BodyMetricDTO]

    @Environment(\.theme) private var theme

    /// Printed bound + a probe value inside it. The *labels* come from
    /// `BodyComposition.bmiCategory`, which owns these boundaries, so the table
    /// can't drift from the category the headline shows.
    private static let bands: [(String, Double)] = [
        ("< 18.5", 17), ("18.5 – 24.9", 22), ("25.0 – 29.9", 27), ("≥ 30.0", 32),
    ]

    private var bmiSeries: [Trends.Point] {
        guard profile.heightIn > 0 else { return [] }
        return metrics.compactMap { b -> Trends.Point? in
            guard let w = b.weightLb else { return nil }
            return Trends.Point(date: b.date,
                                value: BodyComposition.bmi(weightLb: w, heightIn: profile.heightIn))
        }
    }

    private var currentBMI: Double? {
        guard let w = metrics.compactMap(\.weightLb).last, profile.heightIn > 0 else { return nil }
        return BodyComposition.bmi(weightLb: w, heightIn: profile.heightIn)
    }

    var body: some View {
        StatDetailSheet(
            title: "BMI",
            unit: "body mass index · computed from logged weights",
            series: bmiSeries,
            canLog: false,
            showsEntries: false,
            minChartPoints: 2,
            emptyChartText: "Not enough weigh-ins yet.",
            emptyChartDetail: "Log weight twice and your BMI trend appears here.",
            detents: [.large],
            headline: { headline },
            footer: { footer }
        )
    }

    @ViewBuilder
    private var headline: some View {
        if let bmi = currentBMI {
            let category = BodyComposition.bmiCategory(bmi)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%.1f", bmi))
                        .font(.system(size: 48, weight: .semibold, design: .monospaced))
                        .foregroundStyle(bmiIsHealthy(bmi) ? theme.ok : theme.warn)
                    Text(category.label)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(theme.text)
                }
                Text(category.detail)
                    .font(.callout)
                    .foregroundStyle(theme.dim)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reference ranges")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            ForEach(Self.bands, id: \.0) { band in
                StatDetailRow(label: BodyComposition.bmiCategory(band.1).label, value: band.0)
            }
        }

        Text("BMI is a screening tool, not a diagnostic. It doesn't distinguish muscle from fat — a muscular person may score \"Overweight\" with excellent body composition. Use alongside Body Fat % and Waist for a fuller picture. Computed from your logged weights and the height you set in your profile.")
            .font(.footnote)
            .foregroundStyle(theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Body fat detail sheet

private struct BodyFatDetailSheet: View {
    let profile: ProfileDTO
    let metrics: [BodyMetricDTO]
    let unitSystem: UnitSystem
    let onSave: (Double) -> Void

    @Environment(\.theme) private var theme
    @State private var showGuide = false

    private var latestBF: Double? { metrics.compactMap(\.bodyFatPct).last }
    private var latestWeight: Double? { metrics.compactMap(\.weightLb).last }

    private var composition: (fat: Double, lean: Double)? {
        guard let w = latestWeight, let bf = latestBF else { return nil }
        return (
            BodyComposition.fatMassLb(weightLb: w, bodyFatPct: bf),
            BodyComposition.leanMassLb(weightLb: w, bodyFatPct: bf)
        )
    }

    /// Printed bound + a probe value inside it, per sex. Labels come from
    /// `BodyComposition.bodyFatCategory` so the table and the headline agree.
    private var bands: [(String, Double)] {
        profile.sex == .male
            ? [("< 6%", 3), ("6–13%", 10), ("14–17%", 16), ("18–24%", 20), ("≥ 25%", 30)]
            : [("< 14%", 10), ("14–20%", 17), ("21–24%", 22), ("25–31%", 28), ("≥ 32%", 35)]
    }

    var body: some View {
        StatDetailSheet(
            title: "Body fat",
            unit: "% · fat mass · lean mass",
            series: StatKind.bodyFat.series(body: metrics, markers: [], steps: [], system: unitSystem),
            placeholder: "e.g. 18.5",
            logTitle: "Log body fat %",
            showsEntries: false,
            minChartPoints: 2,
            emptyChartText: "Not enough readings yet.",
            emptyChartDetail: "Log body fat twice and the trend appears here.",
            detents: [.large],
            validate: { $0 > 0 && $0 < 70 },
            onSave: onSave,
            headline: { headline },
            footer: { footer }
        )
    }

    @ViewBuilder
    private var headline: some View {
        if let bf = latestBF {
            let category = BodyComposition.bodyFatCategory(pct: bf, sex: profile.sex)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(String(format: "%.1f%%", bf))
                        .font(.system(size: 48, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                    Text(category.label)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(theme.accent)
                }
                Text(category.detail)
                    .font(.callout)
                    .foregroundStyle(theme.dim)
                if let c = composition {
                    HStack(spacing: 16) {
                        compCell(label: "Fat mass", value: Units.formatWeightWithUnit(lb: c.fat, system: unitSystem))
                        compCell(label: "Lean mass", value: Units.formatWeightWithUnit(lb: c.lean, system: unitSystem))
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func compCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            Text(value)
                .font(.system(.title3, design: .monospaced))
                .foregroundStyle(theme.text)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reference ranges (\(profile.sex == .male ? "men" : "women"))")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            ForEach(bands, id: \.0) { band in
                StatDetailRow(
                    label: BodyComposition.bodyFatCategory(pct: band.1, sex: profile.sex).label,
                    value: band.0
                )
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Button {
                showGuide.toggle()
            } label: {
                HStack {
                    Text("How to measure body fat")
                        .font(.callout)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Image(systemName: showGuide ? "chevron.up" : "chevron.down")
                        .foregroundStyle(theme.dim)
                }
            }
            .tactile(.ghost)

            if showGuide {
                Text(BodyComposition.measurementGuide)
                    .font(.callout)
                    .foregroundStyle(theme.dim)
            }
        }
        .padding(12)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - BP sheet (composite)

private struct BPDetailSheet: View {
    let profile: ProfileDTO
    let markers: [HealthMarkerDTO]
    let unitSystem: UnitSystem

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var systolicDraft: String = ""
    @State private var diastolicDraft: String = ""
    @FocusState private var fieldFocused: Bool

    private var systolicSeries: [Trends.Point] { Trends.markerSeries(markers, kind: .bpSystolic) }
    private var diastolicSeries: [Trends.Point] { Trends.markerSeries(markers, kind: .bpDiastolic) }

    var body: some View {
        StatDetailSheet(
            title: "Blood pressure",
            unit: "mmHg · systolic / diastolic",
            // Readings are always saved as a systolic+diastolic pair, so the
            // systolic series alone decides whether there is anything to chart.
            series: systolicSeries,
            entries: StatKind.bp.entries(body: [], markers: markers, system: unitSystem),
            logTitle: "Log new reading",
            rangeContext: HealthRanges.bpContext,
            personalNote: latestMarkerValue(.bpSystolic, in: markers).map {
                TargetRationale.markerMeaning(kind: .bpSystolic, value: $0, mode: profile.mode)
            },
            chartOverride: { dualChart },
            logOverride: { logRow }
        )
    }

    private var dualChart: some View {
        Chart {
            ForEach(systolicSeries, id: \.date) { p in
                LineMark(x: .value("Day", p.date),
                         y: .value("Systolic", p.value),
                         series: .value("Series", "sys"))
                    .foregroundStyle(theme.accent)
            }
            ForEach(diastolicSeries, id: \.date) { p in
                LineMark(x: .value("Day", p.date),
                         y: .value("Diastolic", p.value),
                         series: .value("Series", "dia"))
                    .foregroundStyle(theme.accent2)
            }
        }
        .frame(height: 160)
    }

    @ViewBuilder
    private var logRow: some View {
        HStack(spacing: 8) {
            field("systolic", text: $systolicDraft)
            Text("/").foregroundStyle(theme.dim)
            field("diastolic", text: $diastolicDraft)
            Button { save() } label: { Text("Log") }
                .tactile(.primary)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { fieldFocused = false }
            }
        }
    }

    @ViewBuilder
    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .focused($fieldFocused)
            .padding(10)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
            .foregroundStyle(theme.text)
            .font(.system(.callout, design: .monospaced))
    }

    private func save() {
        guard let sys = Double(systolicDraft), sys > 0,
              let dia = Double(diastolicDraft), dia > 0 else { return }
        let today = Dates.dayKey()
        guard Repos.addMarker(ctx, HealthMarkerDTO(
            userId: profile.id, date: today,
            kind: .bpSystolic, value: sys, source: "manual"
        )) else { return }
        guard Repos.addMarker(ctx, HealthMarkerDTO(
            userId: profile.id, date: today,
            kind: .bpDiastolic, value: dia, source: "manual"
        )) else { return }
        toasts.show(Toast(title: "BP logged",
                          detail: "\(Int(sys))/\(Int(dia)) mmHg",
                          accent: .ok, symbol: "heart.text.square.fill"))
        systolicDraft = ""
        diastolicDraft = ""
        dismiss()
    }
}

// MARK: - Weight sheet (wheel picker)

/// Dedicated weight-log sheet. Wheel picker (90–350 lb, 0.5 lb increments) in
/// place of the shared sheet's text field; everything else is the shared sheet.
private struct WeightLogSheet: View {
    let profile: ProfileDTO
    let metrics: [BodyMetricDTO]
    let unitSystem: UnitSystem
    let onSave: (Double) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    // Canonical wheel domain: 90.0 … 350.0 lb in 0.5 lb steps. The wheel rows
    // and big readout display in the active unit; save sends canonical lb.
    @State private var draftHalfLb: Int = 0
    private let minHalfLb = 180   // 90.0 lb
    private let maxHalfLb = 700   // 350.0 lb

    private var draftLb: Double { Double(draftHalfLb) * 0.5 }

    /// The draft weight in the active unit, for the big readout + wheel rows.
    private func displayWeight(halfLb: Int) -> String {
        Units.formatWeight(lb: Double(halfLb) * 0.5, system: unitSystem)
    }

    var body: some View {
        StatDetailSheet(
            title: "Weight",
            unit: "\(Units.weightUnit(unitSystem)) · 7-day average",
            series: StatKind.weight.series(body: metrics, markers: [], steps: [], system: unitSystem),
            entries: StatKind.weight.entries(body: metrics, markers: [], system: unitSystem),
            logTitle: "Log new weight",
            emptyChartText: "No weight logged yet.",
            emptyChartDetail: "Spin the wheel below and tap Log to start your trend.",
            logOverride: { wheelLog }
        )
        .onAppear { seedDraft() }
    }

    @ViewBuilder
    private var wheelLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Text(displayWeight(halfLb: draftHalfLb))
                    .font(.system(size: 48, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: draftHalfLb)
                Text(Units.weightUnit(unitSystem))
                    .font(.system(size: 18, design: .monospaced))
                    .foregroundStyle(theme.dim)
                    .padding(.leading, 4)
                Spacer()
            }

            Picker("Weight", selection: $draftHalfLb) {
                ForEach(minHalfLb...maxHalfLb, id: \.self) { half in
                    Text(displayWeight(halfLb: half))
                        .tag(half)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))

            Button {
                onSave(draftLb)
                dismiss()
            } label: {
                Text("Log weight").frame(maxWidth: .infinity)
            }
            .tactile(.primary)
        }
    }

    private func seedDraft() {
        let lb: Double
        if let last = metrics.compactMap(\.weightLb).last {
            lb = last
        } else if profile.weightLb > 0 {
            lb = profile.weightLb
        } else {
            lb = 170
        }
        let half = Int((lb * 2).rounded())
        draftHalfLb = max(minHalfLb, min(maxHalfLb, half))
    }
}


// MARK: - Training history sheet

/// Cross-day training history — every logged set/session grouped by day, newest first.
/// This is the home for past workouts (Today/Train only show today/yesterday).
private struct TrainingHistorySheet: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var setModels: [WorkoutSetModel]
    @Query private var exerciseModels: [ExerciseModel]
    @Query private var cardioModels: [CardioSessionModel]
    @Query private var pilatesModels: [PilatesSessionModel]
    @Query private var activityModels: [ActivitySessionModel]

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _setModels = Query(
            filter: #Predicate<WorkoutSetModel> { $0.userId == uid },
            sort: \.timestamp, order: .reverse
        )
        _exerciseModels = Query(
            filter: #Predicate<ExerciseModel> { $0.profileId == uid },
            sort: \.name, order: .forward
        )
        _cardioModels = Query(
            filter: #Predicate<CardioSessionModel> { $0.profileId == uid },
            sort: \.date, order: .reverse
        )
        _pilatesModels = Query(
            filter: #Predicate<PilatesSessionModel> { $0.profileId == uid },
            sort: \.date, order: .reverse
        )
        _activityModels = Query(
            filter: #Predicate<ActivitySessionModel> { $0.profileId == uid },
            sort: \.date, order: .reverse
        )
    }

    var body: some View {
        let sessions = TrainingHistory.sessions(sets: setModels.map(\.snapshot), exercises: exerciseModels.map(\.snapshot))
        let sessionsByDay = Dictionary(uniqueKeysWithValues: sessions.map { ($0.dayKey, $0) })
        let cardioByDay = Dictionary(grouping: cardioModels.map(\.snapshot)) { Dates.dayKey($0.date) }
        let pilatesByDay = Dictionary(grouping: pilatesModels.map(\.snapshot)) { Dates.dayKey($0.date) }
        let activitiesByDay = Dictionary(grouping: activityModels.map(\.snapshot)) { Dates.dayKey($0.date) }
        let dayKeys = Set(sessions.map(\.dayKey))
            .union(cardioByDay.keys)
            .union(pilatesByDay.keys)
            .union(activitiesByDay.keys)
            .sorted(by: >)
        ScrollView {
            // Lazy: this list is unbounded by design, and an eager VStack built
            // every day section up front on open.
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Training history")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("Every session, newest first")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                }

                if dayKeys.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No training logged yet.")
                                .font(.callout).foregroundStyle(theme.text)
                            Text("Sets, cardio, Pilates, and live sessions show up here grouped by day.")
                                .font(.caption).foregroundStyle(theme.dim)
                        }
                    }
                } else {
                    // Straight into the enclosing LazyVStack (same spacing): a
                    // second LazyVStack nested in the first is one eager child
                    // from the outer stack's point of view, which defeats it.
                    ForEach(dayKeys, id: \.self) { key in
                        daySection(
                            key,
                            strength: sessionsByDay[key],
                            cardio: cardioByDay[key] ?? [],
                            pilates: pilatesByDay[key] ?? [],
                            activities: activitiesByDay[key] ?? []
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func daySection(
        _ dayKey: String,
        strength: TrainingHistory.DaySession?,
        cardio cardioRows: [CardioSessionDTO],
        pilates pilatesRows: [PilatesSessionDTO],
        activities activityRows: [ActivitySessionDTO]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Dates.formatLong(dayKey))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.text)
                Spacer()
                Text(daySummary(strength: strength, cardio: cardioRows, pilates: pilatesRows, activities: activityRows))
                    .font(.caption).foregroundStyle(theme.dim)
            }
            if let strength {
                ForEach(strength.exercises) { line in exerciseLineRow(line) }
            }
            ForEach(cardioRows) { cardioLineRow($0) }
            ForEach(pilatesRows) { pilatesLineRow($0) }
            ForEach(activityRows) { activityLineRow($0) }
        }
        .padding(12)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    private func daySummary(
        strength: TrainingHistory.DaySession?,
        cardio: [CardioSessionDTO],
        pilates: [PilatesSessionDTO],
        activities: [ActivitySessionDTO]
    ) -> String {
        let sessionCount = cardio.count + pilates.count + activities.count
        var parts: [String] = []
        if let strength, strength.totalSets > 0 {
            parts.append("\(strength.totalSets) set\(strength.totalSets == 1 ? "" : "s")")
        }
        if sessionCount > 0 {
            parts.append("\(sessionCount) session\(sessionCount == 1 ? "" : "s")")
        }
        let totalCalories = (strength?.totalCalories ?? 0)
            + cardio.reduce(0) { $0 + Int(($1.caloriesEst ?? 0).rounded()) }
            + pilates.reduce(0) {
                $0 + Int(CalorieEstimator.caloriesForPilates(minutes: Double($1.durationMinutes), bodyWeightLb: profile.weightLb).rounded())
            }
            + activities.reduce(0) { $0 + Int(($1.caloriesEst ?? 0).rounded()) }
        if totalCalories > 0 { parts.append("~\(totalCalories) cal") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func exerciseLineRow(_ line: TrainingHistory.ExerciseLine) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(lineDetail(line))
                    .font(.caption).foregroundStyle(theme.dim)
            }
            Spacer()
            Button(role: .destructive) {
                removeLastSet(line)
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(theme.warn)
            }
            .tactile(.ghost)
            .accessibilityLabel("Remove a set of \(line.name)")
        }
        .padding(.vertical, 4)
    }

    private func lineDetail(_ line: TrainingHistory.ExerciseLine) -> String {
        if line.isIsometric {
            return "\(line.setCount) hold\(line.setCount == 1 ? "" : "s") · \(holdLabel(line.totalHoldSeconds))"
        }
        var s = "\(line.setCount) set\(line.setCount == 1 ? "" : "s") · \(line.totalReps) rep\(line.totalReps == 1 ? "" : "s")"
        if line.calories > 0 { s += " · ~\(line.calories) cal" }
        return s
    }

    @ViewBuilder
    private func cardioLineRow(_ session: CardioSessionDTO) -> some View {
        sessionLineRow(
            icon: "figure.run",
            title: session.type.label,
            detail: "\(session.durationMinutes) min",
            calories: Int((session.caloriesEst ?? 0).rounded()),
            deleteLabel: "Delete \(session.type.label) session"
        ) {
            guard Repos.deleteCardioSession(ctx, id: session.id) else { return }
        }
    }

    @ViewBuilder
    private func pilatesLineRow(_ session: PilatesSessionDTO) -> some View {
        let focus = session.focusAreas.first?.label ?? "Pilates"
        let calories = Int(CalorieEstimator.caloriesForPilates(
            minutes: Double(session.durationMinutes),
            bodyWeightLb: profile.weightLb
        ).rounded())
        sessionLineRow(
            icon: "figure.pilates",
            title: "Pilates",
            detail: "\(focus) · \(session.durationMinutes) min",
            calories: calories,
            deleteLabel: "Delete Pilates session"
        ) {
            guard Repos.deletePilatesSession(ctx, id: session.id) else { return }
        }
    }

    @ViewBuilder
    private func activityLineRow(_ session: ActivitySessionDTO) -> some View {
        let symbol = ActivityCatalog.activity(id: session.activityId)?.symbol ?? "figure.mixed.cardio"
        sessionLineRow(
            icon: symbol,
            title: session.activityName,
            detail: "\(session.durationMinutes) min",
            calories: Int((session.caloriesEst ?? 0).rounded()),
            deleteLabel: "Delete \(session.activityName) session"
        ) {
            guard Repos.deleteActivitySession(ctx, id: session.id) else { return }
        }
    }

    @ViewBuilder
    private func sessionLineRow(
        icon: String,
        title: String,
        detail: String,
        calories: Int,
        deleteLabel: String,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(calories > 0 ? "\(detail) · ~\(calories) cal" : detail)
                    .font(.caption).foregroundStyle(theme.dim)
            }
            Spacer()
            Button(role: .destructive) {
                onDelete()
                toasts.show(Toast(title: "Session removed", detail: title, accent: .warn, symbol: "trash.fill"))
            } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(theme.warn)
            }
            .tactile(.ghost)
            .accessibilityLabel(deleteLabel)
        }
        .padding(.vertical, 4)
    }

    private func removeLastSet(_ line: TrainingHistory.ExerciseLine) {
        guard let id = line.setIds.first else { return }
        guard Repos.deleteSet(ctx, id: id) else { return }
        // No Haptics.warn() here — ToastCenter fires the .warn accent's haptic.
        toasts.show(Toast(title: "Set removed", detail: line.name, accent: .warn, symbol: "trash.fill"))
    }

    private func holdLabel(_ seconds: Int) -> String {
        guard seconds > 0 else { return "—" }
        if seconds < 90 { return "\(seconds)s" }
        if seconds < 4200 {
            let m = seconds / 60; let s = seconds % 60
            return s > 0 ? "\(m)m \(s)s" : "\(m)m"
        }
        let h = seconds / 3600; let m = (seconds % 3600) / 60
        return m > 0 ? "\(h)h \(m)m" : "\(h)h"
    }
}
