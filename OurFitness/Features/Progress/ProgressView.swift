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
    private var foodLogs: [FoodLogEntryDTO] { foodModels.map(\.snapshot) }
    private var cardio: [CardioSessionDTO] { cardioModels.map(\.snapshot) }
    private var pilates: [PilatesSessionDTO] { pilatesModels.map(\.snapshot) }
    private var activities: [ActivitySessionDTO] { activityModels.map(\.snapshot) }

    // MARK: - Energy balance (intake vs activity burn)

    private var energyRows: [EnergyBalance.DayBalance] {
        EnergyBalance.byDay(
            days: 30,
            foodLogs: foodLogs, steps: steps, sets: sets,
            cardio: cardio, pilates: pilates, activities: activities,
            bodyWeightLb: profile.weightLb
        )
    }

    private var targetCalories: Int { profile.computedTargets.calories }

    /// Today's intake/burn for the card readout — the last (newest) row.
    private var todayBalance: EnergyBalance.DayBalance? { energyRows.last }

    /// The enabled tracker set: mode defaults until the user customizes, then
    /// whatever they chose (including the empty "none" state).
    private var enabledSet: Set<String> {
        if enabledStatsRaw.isEmpty {
            return Set(StatKind.allCases.filter { $0.isRelevant(for: profile.mode) }.map(\.rawValue))
        }
        if enabledStatsRaw == "none" { return [] }
        return Set(enabledStatsRaw.split(separator: ",").map(String.init))
    }

    private var visibleStats: [StatKind] {
        StatKind.allCases.filter { enabledSet.contains($0.rawValue) }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("progress.")
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
                            statCard(for: kind)
                        }
                    }
                }

                // Calorie intake vs activity burn — shown for both modes.
                energyBalanceCard
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
            EditTrackersSheet(enabled: enabledSet, mode: profile.mode) { newSet in
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
    }

    // MARK: - Energy balance card

    @ViewBuilder
    private var energyBalanceCard: some View {
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

    @ViewBuilder
    private func statCard(for kind: StatKind) -> some View {
        let value = kind.displayValue(body: body_, markers: markers, steps: steps, sets: sets, profile: profile, system: unitSystem)
        let trend = kind.trendChip(body: body_, markers: markers, steps: steps, sets: sets, profile: profile, system: unitSystem)
        let tint  = statusTint(for: kind)
        StatCard(
            title: kind.title,
            value: value,
            unit: kind.unit(system: unitSystem),
            trend: trend,
            valueAccent: tint,
            action: { activeStat = kind }
        )
    }

    private func statusTint(for kind: StatKind) -> Color? {
        let status: HealthRanges.RangeStatus
        switch kind {
        case .bp:
            let sys = latestMarkerValue(.bpSystolic)
            let dia = latestMarkerValue(.bpDiastolic)
            guard sys != nil || dia != nil else { return nil }
            status = HealthRanges.bpStatus(systolic: sys, diastolic: dia)
        case .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose, .restingHR:
            guard let mk = kind.markerKind,
                  let v = latestMarkerValue(mk) else { return nil }
            status = HealthRanges.status(for: mk, value: v)
        case .bmi:
            guard let w = body_.compactMap(\.weightLb).last else { return nil }
            let bmi = BodyComposition.bmi(weightLb: w, heightIn: profile.heightIn)
            if bmi < 18.5 || bmi >= 25 { return theme.warn }
            return theme.ok
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

    private func latestMarkerValue(_ kind: HealthMarkerKind) -> Double? {
        markers.filter { $0.kind == kind }
            .sorted { $0.date < $1.date }
            .last?.value
    }

    // MARK: - Detail sheets

    @ViewBuilder
    private func detailSheet(for kind: StatKind) -> some View {
        switch kind {
        case .stepsAvg:
            stepsDetail
        case .bp:
            bpDetail
        case .weight:
            WeightLogSheet(
                profile: profile,
                metrics: body_,
                unitSystem: unitSystem,
                onSave: { value in save(kind: .weight, value: value) }
            )
            .environmentObject(toasts)
        case .bodyFat:
            BodyFatDetailSheet(
                profile: profile,
                metrics: body_,
                unitSystem: unitSystem,
                onSave: { value in save(kind: .bodyFat, value: value) }
            )
            .environmentObject(toasts)
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
                    latestMarkerValue(mk).map { TargetRationale.markerMeaning(kind: mk, value: $0, mode: profile.mode) }
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
            placeholder: "",
            canLog: false,
            onSave: { _ in }
        )
    }

    @ViewBuilder
    private var bpDetail: some View {
        BPDetailSheet(profile: profile, markers: markers)
            .environmentObject(toasts)
    }

    @ViewBuilder
    private var trainingVolumeDetail: some View {
        StatDetailSheet(
            title: "Training",
            unit: "sets · weekly",
            series: StatKind.trainingVolume.series(body: [], markers: [], steps: [], sets: sets),
            entries: [],
            placeholder: "",
            canLog: false,
            onSave: { _ in }
        )
    }

    // MARK: - Save

    private func save(kind: StatKind, value: Double) {
        let today = Dates.dayKey()
        switch kind {
        case .weight:
            Repos.addBody(ctx, BodyMetricDTO(
                userId: profile.id, date: today, weightLb: value
            ))
            // Re-point the profile (the source recommendations read) at this weight
            // and recompute targets so calorie/protein/water goals track current weight.
            Repos.syncCurrentWeight(ctx, profileId: profile.id)
            Task { await HealthKitService.shared.writeWeightLb(value) }
            toasts.show(Toast(title: "Weight logged",
                              detail: Units.formatWeightWithUnit(lb: value, system: unitSystem),
                              accent: .ok, symbol: "scalemass.fill"))
        case .bodyFat:
            Repos.addBody(ctx, BodyMetricDTO(
                userId: profile.id, date: today, bodyFatPct: value
            ))
            toasts.show(Toast(title: "Body fat logged",
                              detail: String(format: "%.1f %%", value),
                              accent: .ok, symbol: "scalemass.fill"))
        case .waist:
            Repos.addBody(ctx, BodyMetricDTO(
                userId: profile.id, date: today, waistIn: value
            ))
            toasts.show(Toast(title: "Waist logged",
                              detail: Units.formatLengthWithUnit(inches: value, system: unitSystem),
                              accent: .ok, symbol: "ruler"))
        case .restingHR, .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            guard let markerKind = kind.markerKind else { return }
            Repos.addMarker(ctx, HealthMarkerDTO(
                userId: profile.id, date: today,
                kind: markerKind, value: value, source: "manual"
            ))
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
        case .trainingVolume:   return "sets · this wk"
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

    func isRelevant(for mode: Mode) -> Bool {
        switch self {
        case .weight, .bodyFat, .waist, .bmi, .stepsAvg, .trainingVolume:
            return true
        case .restingHR, .bp, .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            return mode == .circuit
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
            return latestMarker(.restingHR, in: markers).map { formattedValue($0) }
        case .stepsAvg:
            let avg = Steps.average(steps, days: 7)
            return avg > 0 ? avg.formatted() : nil
        case .trainingVolume:
            let thisWeekSets = setsThisWeek(sets)
            return thisWeekSets > 0 ? "\(thisWeekSets)" : nil
        case .bp:
            let s = latestMarker(.bpSystolic, in: markers)
            let d = latestMarker(.bpDiastolic, in: markers)
            if let s, let d { return "\(Int(s))/\(Int(d))" }
            return nil
        case .ldl:
            return latestMarker(.ldl, in: markers).map { formattedValue($0) }
        case .hdl:
            return latestMarker(.hdl, in: markers).map { formattedValue($0) }
        case .totalCholesterol:
            return latestMarker(.totalCholesterol, in: markers).map { formattedValue($0) }
        case .a1c:
            return latestMarker(.a1c, in: markers).map { formattedValue($0) }
        case .fastingGlucose:
            return latestMarker(.fastingGlucose, in: markers).map { formattedValue($0) }
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
            let this = setsThisWeek(sets)
            let last = setsLastWeek(sets)
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
            return trainingVolumeSeries(sets)
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

    private func latestMarker(_ kind: HealthMarkerKind, in markers: [HealthMarkerDTO]) -> Double? {
        markers.filter { $0.kind == kind }
            .sorted { $0.date < $1.date }
            .last?.value
    }
}

private func formattedValue(_ v: Double) -> String {
    v.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(v)) : String(format: "%.1f", v)
}

// MARK: - Training volume helpers

private func setsThisWeek(_ sets: [WorkoutSetDTO]) -> Int {
    let cal = Calendar.current
    guard let weekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) else { return 0 }
    let key = Dates.dayKey(weekStart)
    return sets.filter { Dates.dayKey($0.timestamp) >= key }.count
}

private func setsLastWeek(_ sets: [WorkoutSetDTO]) -> Int {
    let cal = Calendar.current
    guard let thisWeekStart = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())),
          let lastWeekStart = cal.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart) else { return 0 }
    let thisKey = Dates.dayKey(thisWeekStart)
    let lastKey = Dates.dayKey(lastWeekStart)
    return sets.filter { Dates.dayKey($0.timestamp) >= lastKey && Dates.dayKey($0.timestamp) < thisKey }.count
}

private func trainingVolumeSeries(_ sets: [WorkoutSetDTO]) -> [Trends.Point] {
    let cal = Calendar.current
    guard let cutoff = cal.date(byAdding: .weekOfYear, value: -12, to: Date()) else { return [] }
    let cutoffKey = Dates.dayKey(cutoff)
    var weekCounts: [String: Double] = [:]
    for s in sets where Dates.dayKey(s.timestamp) >= cutoffKey {
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: s.timestamp)
        guard let weekStart = cal.date(from: comps) else { continue }
        let key = Dates.dayKey(weekStart)
        weekCounts[key, default: 0] += 1
    }
    return weekCounts.map { Trends.Point(date: $0.key, value: $0.value) }
        .sorted { $0.date < $1.date }
}

// MARK: - BMI detail sheet

private struct BMIDetailSheet: View {
    let profile: ProfileDTO
    let metrics: [BodyMetricDTO]

    @Environment(\.theme) private var theme

    private var bmiSeries: [Trends.Point] {
        guard profile.heightIn > 0 else { return [] }
        return metrics.compactMap { b -> Trends.Point? in
            guard let w = b.weightLb else { return nil }
            let bmi = BodyComposition.bmi(weightLb: w, heightIn: profile.heightIn)
            return Trends.Point(date: b.date, value: bmi)
        }
    }

    private var currentBMI: Double? {
        guard let w = metrics.compactMap(\.weightLb).last, profile.heightIn > 0 else { return nil }
        return BodyComposition.bmi(weightLb: w, heightIn: profile.heightIn)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("bmi.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("BODY MASS INDEX · COMPUTED FROM LOGGED WEIGHTS")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                if let bmi = currentBMI {
                    let (label, detail) = BodyComposition.bmiCategory(bmi)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(String(format: "%.1f", bmi))
                            .font(.system(size: 48, weight: .semibold, design: .monospaced))
                            .foregroundStyle(bmi < 18.5 || bmi >= 25 ? theme.warn : theme.ok)
                        Text(label)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(theme.text)
                    }
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(theme.dim)
                }

                if bmiSeries.count >= 2 {
                    Chart(bmiSeries, id: \.date) { p in
                        LineMark(x: .value("Day", p.date), y: .value("BMI", p.value))
                            .foregroundStyle(theme.accent)
                        PointMark(x: .value("Day", p.date), y: .value("BMI", p.value))
                            .foregroundStyle(theme.accent)
                    }
                    .frame(height: 140)
                }

                // Reference ranges
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reference ranges")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    bmiRange(label: "Underweight", range: "< 18.5")
                    bmiRange(label: "Healthy", range: "18.5 – 24.9")
                    bmiRange(label: "Overweight", range: "25.0 – 29.9")
                    bmiRange(label: "Obese", range: "≥ 30.0")
                }

                Text("BMI is a screening tool, not a diagnostic. It doesn't distinguish muscle from fat — a muscular person may score \"Overweight\" with excellent body composition. Use alongside Body Fat % and Waist for a fuller picture.")
                    .font(.footnote)
                    .foregroundStyle(theme.dim)

                Text("Computed from your logged weights and the height you set in your profile. Log weight regularly to see the trend line.")
                    .font(.footnote)
                    .foregroundStyle(theme.dim)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func bmiRange(label: String, range: String) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.text).font(.callout)
            Spacer()
            Text(range)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(theme.accent)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - Body fat detail sheet

private struct BodyFatDetailSheet: View {
    let profile: ProfileDTO
    let metrics: [BodyMetricDTO]
    let unitSystem: UnitSystem
    let onSave: (Double) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @State private var showGuide = false
    @FocusState private var draftFocused: Bool

    private var latestBF: Double? { metrics.compactMap(\.bodyFatPct).last }
    private var latestWeight: Double? { metrics.compactMap(\.weightLb).last }

    private var bfSeries: [Trends.Point] {
        metrics.compactMap { b in
            b.bodyFatPct.map { Trends.Point(date: b.date, value: $0) }
        }
    }

    private var composition: (fat: Double, lean: Double)? {
        guard let w = latestWeight, let bf = latestBF else { return nil }
        return (
            BodyComposition.fatMassLb(weightLb: w, bodyFatPct: bf),
            BodyComposition.leanMassLb(weightLb: w, bodyFatPct: bf)
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("body fat.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("% · FAT MASS · LEAN MASS")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                // Current value with real lbs breakdown
                if let bf = latestBF {
                    let (label, detail) = BodyComposition.bodyFatCategory(pct: bf, sex: profile.sex)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(String(format: "%.1f%%", bf))
                                .font(.system(size: 48, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.text)
                            Text(label)
                                .font(.system(size: 18, weight: .regular))
                                .foregroundStyle(theme.accent)
                        }
                        Text(detail)
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

                if bfSeries.count >= 2 {
                    Chart(bfSeries, id: \.date) { p in
                        LineMark(x: .value("Day", p.date), y: .value("BF%", p.value))
                            .foregroundStyle(theme.accent)
                        PointMark(x: .value("Day", p.date), y: .value("BF%", p.value))
                            .foregroundStyle(theme.accent)
                    }
                    .frame(height: 140)
                }

                // Reference ranges by sex
                referenceSection

                // Log
                logSection

                // Measurement guide (expandable)
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
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
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
    private var referenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reference ranges (\(profile.sex == .male ? "men" : "women"))")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            let ranges: [(String, String)] = profile.sex == .male
                ? [("Essential", "< 6%"), ("Athletic", "6–13%"), ("Fitness", "14–17%"), ("Acceptable", "18–24%"), ("High", "≥ 25%")]
                : [("Essential", "< 14%"), ("Athletic", "14–20%"), ("Fitness", "21–24%"), ("Acceptable", "25–31%"), ("High", "≥ 32%")]
            ForEach(ranges, id: \.0) { pair in
                HStack {
                    Text(pair.0).foregroundStyle(theme.text).font(.callout)
                    Spacer()
                    Text(pair.1)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(theme.accent)
                }
                .padding(10)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
            }
        }
    }

    @ViewBuilder
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log body fat %")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            HStack(spacing: 8) {
                TextField("e.g. 18.5", text: $draft)
                    .keyboardType(.decimalPad)
                    .focused($draftFocused)
                    .padding(10)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    .foregroundStyle(theme.text)
                    .font(.system(.callout, design: .monospaced))
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { draftFocused = false }
                        }
                    }
                Button {
                    if let v = Double(draft), v > 0, v < 70 {
                        onSave(v)
                        draft = ""
                        dismiss()
                    }
                } label: { Text("Log") }
                    .tactile(.primary)
            }
        }
    }
}

// MARK: - BP sheet (composite)

private struct BPDetailSheet: View {
    let profile: ProfileDTO
    let markers: [HealthMarkerDTO]

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var systolicDraft: String = ""
    @State private var diastolicDraft: String = ""

    private var systolicSeries: [Trends.Point] {
        Trends.markerSeries(markers, kind: .bpSystolic)
    }
    private var diastolicSeries: [Trends.Point] {
        Trends.markerSeries(markers, kind: .bpDiastolic)
    }

    private var recent: [HealthMarkerDTO] {
        markers
            .filter { $0.kind == .bpSystolic || $0.kind == .bpDiastolic }
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0 }
    }

    private var latestSystolic: Double? {
        markers.filter { $0.kind == .bpSystolic }.sorted { $0.date < $1.date }.last?.value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("bp.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("MMHG · SYSTOLIC / DIASTOLIC")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                    Text(HealthRanges.bpContext)
                        .font(.footnote)
                        .foregroundStyle(theme.dim)
                        .padding(.top, 4)
                }

                if let sys = latestSystolic {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.accent)
                            .padding(.top, 2)
                        Text(TargetRationale.markerMeaning(kind: .bpSystolic, value: sys, mode: profile.mode))
                            .font(.callout)
                            .foregroundStyle(theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                }

                if systolicSeries.isEmpty && diastolicSeries.isEmpty {
                    Text("No data yet.")
                        .font(.callout).foregroundStyle(theme.dim)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                } else {
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent entries")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    if recent.isEmpty {
                        Text("Nothing logged yet.")
                            .font(.callout).foregroundStyle(theme.dim)
                    } else {
                        ForEach(recent) { m in
                            HStack {
                                Text(m.date).foregroundStyle(theme.text)
                                Spacer()
                                Text("\(Int(m.value)) \(m.kind == .bpSystolic ? "sys" : "dia")")
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                            }
                            .padding(10)
                            .background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Log new reading")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    HStack(spacing: 8) {
                        TextField("systolic", text: $systolicDraft)
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                            .foregroundStyle(theme.text)
                            .font(.system(.callout, design: .monospaced))
                        Text("/").foregroundStyle(theme.dim)
                        TextField("diastolic", text: $diastolicDraft)
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                            .foregroundStyle(theme.text)
                            .font(.system(.callout, design: .monospaced))
                        Button { save() } label: { Text("Log") }
                            .tactile(.primary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
    }

    private func save() {
        guard let sys = Double(systolicDraft), sys > 0,
              let dia = Double(diastolicDraft), dia > 0 else { return }
        let today = Dates.dayKey()
        Repos.addMarker(ctx, HealthMarkerDTO(
            userId: profile.id, date: today,
            kind: .bpSystolic, value: sys, source: "manual"
        ))
        Repos.addMarker(ctx, HealthMarkerDTO(
            userId: profile.id, date: today,
            kind: .bpDiastolic, value: dia, source: "manual"
        ))
        toasts.show(Toast(title: "BP logged",
                          detail: "\(Int(sys))/\(Int(dia)) mmHg",
                          accent: .ok, symbol: "heart.text.square.fill"))
        systolicDraft = ""
        diastolicDraft = ""
        dismiss()
    }
}

// MARK: - Weight sheet (wheel picker)

/// Dedicated weight-log sheet. Wheel picker (90–350 lb, 0.5 lb increments).
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

    private var weightSeries: [Trends.Point] {
        let pts = metrics.compactMap { b -> Trends.Point? in
            guard let w = b.weightLb else { return nil }
            return Trends.Point(date: b.date, value: Units.weightValue(lb: w, system: unitSystem))
        }
        return Trends.rollingAverage(pts, window: 7)
    }

    private var recentEntries: [StatDetailEntry] {
        metrics.compactMap { b -> StatDetailEntry? in
            guard let w = b.weightLb else { return nil }
            return StatDetailEntry(id: b.id.uuidString, dateLabel: b.date,
                                   valueLabel: Units.formatWeightWithUnit(lb: w, system: unitSystem))
        }
        .reversed()
        .prefix(10)
        .map { $0 }
    }

    private var draftLb: Double {
        Double(draftHalfLb) * 0.5
    }

    /// The draft weight in the active unit, for the big readout + wheel rows.
    private func displayWeight(halfLb: Int) -> String {
        Units.formatWeight(lb: Double(halfLb) * 0.5, system: unitSystem)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("weight.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("\(Units.weightUnit(unitSystem).uppercased()) · 7-DAY AVERAGE")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                chartSection
                entriesSection
                logSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
        .onAppear { seedDraft() }
    }

    @ViewBuilder
    private var chartSection: some View {
        if weightSeries.isEmpty {
            VStack(spacing: 8) {
                Text("No weight logged yet.")
                    .font(.callout).foregroundStyle(theme.dim)
                Text("Spin the wheel below and tap Log to start your trend.")
                    .font(.footnote).foregroundStyle(theme.dim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(16)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        } else {
            Chart(weightSeries, id: \.date) { p in
                LineMark(x: .value("Day", p.date), y: .value("Weight", p.value))
                    .foregroundStyle(theme.accent)
                PointMark(x: .value("Day", p.date), y: .value("Weight", p.value))
                    .foregroundStyle(theme.accent)
            }
            .frame(height: 160)
        }
    }

    @ViewBuilder
    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent entries")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            if recentEntries.isEmpty {
                Text("Nothing logged yet.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                ForEach(recentEntries) { e in
                    HStack {
                        Text(e.dateLabel).foregroundStyle(theme.text)
                        Spacer()
                        Text(e.valueLabel)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(theme.accent)
                    }
                    .padding(10)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log new weight")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)

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
