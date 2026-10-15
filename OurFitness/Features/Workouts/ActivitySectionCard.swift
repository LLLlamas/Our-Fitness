// Train tab — one optional activity section (Pilates, Yoga or Stretching).
//
// The same card for every `TrainSection`; `WorkoutsView` decides which are shown.
// - Progress ring: sessions this week / weekly goal (editable — tap "/" in ring)
// - Weekly streak chip (current week is a grace zone, no streak-shame)
// - "Log <Title>" → the shared `LogPastSessionSheet` locked to the section's
//   activity — the one manual logging form
// - No session list here: today/yesterday sessions sit in the one Train list,
//   `RecentActivitySessions` (LiveSessionCard.swift), with edit/delete
//
// Data source differs by section: Pilates is stored as `PilatesSessionModel`,
// Yoga and Stretching as `ActivitySessionModel` with the section's activity id.
// Each source view owns one predicate-scoped @Query and hands plain entries to
// the shared `ActivitySectionContent`.

import SwiftUI
import SwiftData

struct ActivitySectionCard: View {
    let profile: ProfileDTO
    let section: TrainSection

    var body: some View {
        switch section {
        case .pilates:
            PilatesSectionSource(profile: profile)
        case .yoga, .stretching:
            ActivitySessionSectionSource(profile: profile, section: section)
        }
    }
}

// MARK: - Data sources

/// A logged session as the section card needs it: when, and its burn.
private struct SectionEntry {
    let date: Date
    let cal: Double
}

/// Look-back for the streak; a year covers any realistic run of weeks.
private func sectionCutoff() -> Date {
    Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Dates.startOfYesterday()
}

private struct PilatesSectionSource: View {
    let profile: ProfileDTO
    @Query private var models: [PilatesSessionModel]

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        let cutoff = sectionCutoff()
        _models = Query(
            filter: #Predicate<PilatesSessionModel> { $0.profileId == uid && $0.date >= cutoff },
            sort: \.date,
            order: .reverse
        )
    }

    var body: some View {
        // Pilates rows store no calorie figure; the burn is derived on read.
        let entries = models.map(\.snapshot).map {
            SectionEntry(date: $0.date,
                         cal: CalorieEstimator.caloriesForPilates(
                            minutes: Double($0.durationMinutes),
                            bodyWeightLb: profile.weightLb))
        }
        ActivitySectionContent(profile: profile, section: .pilates, entries: entries)
    }
}

private struct ActivitySessionSectionSource: View {
    let profile: ProfileDTO
    let section: TrainSection
    @Query private var models: [ActivitySessionModel]

    init(profile: ProfileDTO, section: TrainSection) {
        self.profile = profile
        self.section = section
        let uid = profile.id
        let aid = section.activityId
        let cutoff = sectionCutoff()
        _models = Query(
            filter: #Predicate<ActivitySessionModel> {
                $0.profileId == uid && $0.activityId == aid && $0.date >= cutoff
            },
            sort: \.date,
            order: .reverse
        )
    }

    var body: some View {
        // The stored estimate, so the figure matches the Move card's.
        let entries = models.map { SectionEntry(date: $0.date, cal: $0.caloriesEst ?? 0) }
        ActivitySectionContent(profile: profile, section: section, entries: entries)
    }
}

// MARK: - Shared content

private struct ActivitySectionContent: View {
    let profile: ProfileDTO
    let section: TrainSection
    let entries: [SectionEntry]

    @Environment(\.theme) private var theme

    @State private var showLogSheet = false
    @State private var showGoalPicker = false
    @State private var pickerGoal: Int

    @AppStorage private var weeklyGoal: Int

    init(profile: ProfileDTO, section: TrainSection, entries: [SectionEntry]) {
        self.profile = profile
        self.section = section
        self.entries = entries
        _pickerGoal = State(initialValue: section.defaultWeeklyGoal)
        _weeklyGoal = AppStorage(
            wrappedValue: section.defaultWeeklyGoal,
            section.goalKey(profileId: profile.id)
        )
    }

    private var dates: [Date] { entries.map(\.date) }
    private var thisWeekCount: Int { TrainSections.countThisWeek(dates) }
    private var streakWeeks: Int { TrainSections.weeklyStreak(dates, goalSessions: weeklyGoal) }
    private var weekPct: Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(1, Double(thisWeekCount) / Double(weeklyGoal))
    }
    private var thisWeekCal: Double {
        let week = Dates.startOfISOWeek(Date())
        return entries.filter { $0.date >= week }.reduce(0) { $0 + $1.cal }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            PressableCard(action: { showLogSheet = true }) {
                logCTA
            }
        }
        // One manual session form app-wide: the shared log sheet, locked to this
        // section's activity, writes the right DTO for it.
        .sheet(isPresented: $showLogSheet) {
            LogPastSessionSheet(profile: profile, lockedActivityId: section.activityId)
        }
        .sheet(isPresented: $showGoalPicker) {
            goalPickerSheet
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                ProgressRing(pct: weekPct, color: theme.accent2, trackColor: theme.barBg, lineWidth: 7)
                VStack(spacing: 0) {
                    Text("\(thisWeekCount)")
                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.text)
                    Button {
                        pickerGoal = weeklyGoal
                        showGoalPicker = true
                    } label: {
                        Text("/ \(weeklyGoal)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(theme.dim)
                            .underline(color: theme.dim.opacity(0.5))
                    }
                    .tactile(.ghost)
                }
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(section.title)
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                HStack(spacing: 6) {
                    Text("sessions this week")
                        .font(.caption)
                        .foregroundStyle(theme.dim)
                    if thisWeekCal > 0 {
                        Text("· ~\(Int(thisWeekCal)) cal")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(theme.accent2)
                    }
                }
            }
            Spacer()
            StreakChip(weeks: streakWeeks, tint: theme.accent2)
        }
    }

    @ViewBuilder
    private var logCTA: some View {
        HStack(spacing: 12) {
            Image(systemName: section.symbol)
                .font(.system(size: 22))
                .foregroundStyle(theme.accent2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Log \(section.title)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(section.logHint)
                    .font(.caption).foregroundStyle(theme.dim)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Goal picker sheet

    // Shared `GoalPickerSheet` chrome — one wheel, natural wheel height.
    private var goalPickerSheet: some View {
        GoalPickerSheet(
            title: "Weekly \(section.title) Goal",
            subtitle: "How many sessions per week to hit your streak.",
            wheels: [
                .init(
                    id: "weeklySessions",
                    pickerTitle: "Goal",
                    options: Array(1...14),
                    optionLabel: { "\($0) session\($0 == 1 ? "" : "s") / week" },
                    selection: $pickerGoal
                )
            ],
            wheelVerticalPadding: 8,
            resetLabel: "Reset to \(section.defaultWeeklyGoal)",
            detents: [.medium],
            onReset: {
                weeklyGoal = section.defaultWeeklyGoal
                showGoalPicker = false
            },
            onSave: {
                weeklyGoal = pickerGoal
                showGoalPicker = false
            }
        )
    }
}
