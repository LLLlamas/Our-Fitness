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

    @State private var appleEnergyKcal: Double = 0
    @State private var appleEnergyDate: Date? = nil
    @State private var bpm: Int? = nil
    @State private var bpmDate: Date? = nil
    @State private var showInfo = false
    @State private var showEnergyInfo = false
    @State private var showExercisesInfo = false
    @State private var showHeartRateInfo = false

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
    }

    private var todaySteps: Int { stepModels.first?.steps ?? 0 }
    private var todaySets: [WorkoutSetDTO] { setModels.map(\.snapshot) }
    private var todayCardio: [CardioSessionDTO] { cardioModels.map(\.snapshot) }
    private var todayPilates: [PilatesSessionDTO] { pilatesModels.map(\.snapshot) }

    private var metEstimate: Int {
        DailyBurn.metEstimate(
            steps: todaySteps, sets: todaySets, cardio: todayCardio, pilates: todayPilates,
            bodyWeightLb: profile.weightLb
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

    private var trainingMetEstimate: Int {
        // Reuses the three sub-values already computed above — no duplicate reduce closures.
        // Steps excluded: Apple's active energy already counts walking.
        setsKcal + cardioKcal + pilatesKcal
    }

    private var weightKg: Int { Int(profile.weightLb * 0.4536) }

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

                Text("≈\(metEstimate) cal · steps + training")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.text)

                HStack(alignment: .top, spacing: 12) {
                    tappableMetricColumn(
                        icon: "flame.fill",
                        title: "APPLE ENERGY",
                        value: isEnergyStale ? "-" : "\(Int(appleEnergyKcal))",
                        unit: "cal burned",
                        subtext: isEnergyStale ? "need new data" : asOfText(appleEnergyDate),
                        action: { showEnergyInfo = true }
                    )
                    tappableMetricColumn(
                        icon: "dumbbell.fill",
                        title: "EXERCISES",
                        value: "\(trainingMetEstimate)",
                        unit: "cal burned",
                        subtext: "today's logs",
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
                value: isEnergyStale ? nil : Int(appleEnergyKcal),
                asOf: isEnergyStale ? nil : asOfText(appleEnergyDate)
            )
            .themed(profile.mode)
        }
        .sheet(isPresented: $showExercisesInfo) {
            ExercisesInfoSheet(
                weightKg: weightKg,
                setsKcal: setsKcal,
                cardioKcal: cardioKcal,
                pilatesKcal: pilatesKcal,
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
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()

    private func asOfText(_ date: Date?) -> String {
        guard let date else { return "need new data" }
        let f = Calendar.current.isDateInToday(date) ? Self.timeFormatter : Self.dateFormatter
        return "as of \(f.string(from: date))"
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

                section(title: "What is MET?") {
                    Text("MET (Metabolic Equivalent of Task) is a measure of exercise intensity. 1 MET = rest. Walking is ~4.3 METs; squats ~5.0; pull-ups ~8.0. MET × your weight in kg × hours active = calories burned.")
                        .font(.callout)
                        .foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section(title: "Today's estimate") {
                    VStack(alignment: .leading, spacing: 8) {
                        breakdownRow(
                            label: "Steps",
                            detail: "MET 4.3 × \(weightKg)kg × \(todaySteps)/7392 hr ≈ \(stepsKcal) cal"
                        )
                        breakdownRow(
                            label: "Training",
                            detail: "MET 3.5–8.0 × \(weightKg)kg × session time ≈ \(trainingMet) cal"
                        )
                        breakdownRow(
                            label: "Total",
                            detail: "≈\(metEstimate) cal today (MET estimate)"
                        )
                    }
                }

                section(title: "Columns") {
                    VStack(alignment: .leading, spacing: 8) {
                        columnNote(label: "Apple Energy", detail: "Measured by iPhone/Watch sensors directly.")
                        columnNote(label: "Exercises", detail: "Our science-based estimate from your logged strength exercises, cardio, and pilates — excludes steps to avoid double-counting Apple Energy.")
                        columnNote(label: "Heart Rate", detail: "Your most recent reading from Apple Health.")
                    }
                }

                Text("Source: Ainsworth 2011 Compendium of Physical Activities")
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
    let value: Int?
    let asOf: String?

    private var todayText: String {
        if let value, let asOf {
            return "Apple Health reported \(value) cal burned \(asOf)."
        }
        return "No recent Apple Health data. Open the Health app or wear your Watch to refresh."
    }

    var body: some View {
        ColumnInfoScaffold(title: "apple energy.", subtitle: "MEASURED BY APPLE") {
            ColumnInfoSection(title: "What it is") {
                ColumnInfoBody(text: "Your total active calorie burn for today, measured directly by your iPhone and Apple Watch sensors. This includes all movement: walking, steps, and any other activity Apple detects.")
            }
            ColumnInfoSection(title: "Why it excludes training logs") {
                ColumnInfoBody(text: "Our Exercises estimate excludes steps so the two numbers don't overlap. Apple Energy captures everything; our Exercises column shows only your explicitly logged gym and pilates work.")
            }
            ColumnInfoSection(title: "Today") {
                ColumnBreakdownRow(label: "Apple Energy", detail: todayText)
            }
        }
    }
}

private struct ExercisesInfoSheet: View {
    let weightKg: Int
    let setsKcal: Int
    let cardioKcal: Int
    let pilatesKcal: Int
    let trainingMetEstimate: Int

    var body: some View {
        ColumnInfoScaffold(title: "exercises.", subtitle: "LOGGED ACTIVITY") {
            ColumnInfoSection(title: "What it is") {
                ColumnInfoBody(text: "Your estimated calorie burn from today's explicitly logged exercises, cardio sessions, and pilates — calculated using the MET formula (Metabolic Equivalent of Task × your weight × time). Steps are excluded because Apple Energy already counts walking.")
            }
            ColumnInfoSection(title: "Today's breakdown") {
                VStack(alignment: .leading, spacing: 8) {
                    ColumnBreakdownRow(label: "Strength & exercises",
                                       detail: "MET 3.5–8.0 × \(weightKg)kg × session time ≈ \(setsKcal) cal")
                    ColumnBreakdownRow(label: "Cardio (non-walk)",
                                       detail: "MET 4.5 × \(weightKg)kg × duration ≈ \(cardioKcal) cal")
                    ColumnBreakdownRow(label: "Pilates",
                                       detail: "MET 3.0 × \(weightKg)kg × duration ≈ \(pilatesKcal) cal")
                    ColumnBreakdownRow(label: "Total exercises",
                                       detail: "≈\(trainingMetEstimate) cal burned today")
                }
            }
            ColumnInfoSection(title: "Formula") {
                ColumnInfoBody(text: "Metabolic Equivalent of Task (MET) × body weight in kg × hours active = calories burned. Source: Ainsworth 2011 Compendium of Physical Activities.")
            }
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
        ColumnInfoScaffold(title: "heart rate.", subtitle: "APPLE HEALTH") {
            ColumnInfoSection(title: "What it is") {
                ColumnInfoBody(text: "Your most recent heart rate reading from Apple Health, measured by your Apple Watch or other connected sensor.")
            }
            ColumnInfoSection(title: "Today") {
                ColumnBreakdownRow(label: "Heart rate", detail: todayText)
            }
            ColumnInfoSection(title: "Context") {
                ColumnInfoBody(text: "Resting heart rate of 60–80 bpm is considered optimal. Regular aerobic exercise and consistent step goals lower resting heart rate over weeks.")
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
        .presentationDetents([.medium])
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
