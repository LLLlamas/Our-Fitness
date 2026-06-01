// Apple Health "Move" glance: today's active energy (calories burned) + latest
// heart rate, read live from HealthKit — alongside our own MET-based estimate of
// today's burn (steps + logged training), so the science-based number sits next
// to the Watch-measured one. Only shown when the profile granted Health access.

import SwiftUI
import SwiftData

struct MoveCard: View {
    let profile: ProfileDTO
    @ObservedObject var health: HealthKitService
    /// Bumped by TodayView on appear + pull-to-refresh so the card re-reads the
    /// latest active energy / heart rate (reads only — never re-auth).
    let refreshTick: Int

    @Environment(\.theme) private var theme

    @Query private var stepModels: [StepCountModel]
    @Query private var setModels: [WorkoutSetModel]
    @Query private var cardioModels: [CardioSessionModel]
    @Query private var pilatesModels: [PilatesSessionModel]

    @State private var kcal: Double = 0
    @State private var bpm: Int?
    @State private var bpmDate: Date?

    init(profile: ProfileDTO, health: HealthKitService, refreshTick: Int = 0) {
        self.profile = profile
        self._health = ObservedObject(wrappedValue: health)
        self.refreshTick = refreshTick
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

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Label("Move", systemImage: "flame.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    CalorieInfoButton()
                    Spacer()
                    Text("APPLE HEALTH")
                        .font(.system(size: 9, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    metric(value: "\(Int(kcal))", unit: "cal burned", symbol: "flame.fill")
                    if let bpm {
                        metric(value: "\(bpm)", unit: "bpm", symbol: "heart.fill")
                    }
                }

                // Heart rate is a point-in-time read (not live); show how fresh it
                // is once it's meaningfully stale.
                if bpm != nil, let date = bpmDate, let label = Freshness.label(for: date) {
                    Label(label, systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.dim)
                }

                // Our MET-based estimate, side by side with the Watch figure.
                HStack(spacing: 6) {
                    Image(systemName: "function").font(.system(size: 11)).foregroundStyle(theme.dim)
                    Text("MET estimate: ≈\(metEstimate) cal")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.text)
                    Text("(steps + training)")
                        .font(.caption2).foregroundStyle(theme.dim)
                }
                // The Apple-Health-vs-MET explanation now lives behind the ⓘ in
                // the header (CalorieInfoSheet) rather than as an always-on blurb.
            }
        }
        .task(id: refreshTick) { await load() }
    }

    private func load() async {
        kcal = await health.activeEnergy()
        if let sample = await health.latestHeartRateSample() {
            bpm = sample.bpm
            bpmDate = sample.date
        } else {
            bpm = nil
            bpmDate = nil
        }
    }

    @ViewBuilder
    private func metric(value: String, unit: String, symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(theme.accent)
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 24, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.system(size: 10))
                    .foregroundStyle(theme.dim)
            }
        }
    }
}
