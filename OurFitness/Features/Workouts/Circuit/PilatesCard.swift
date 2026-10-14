// Circuit Train — Pilates card.
//
// - Progress ring: sessions this week / weekly goal (editable — tap "/" in ring)
// - "Log Pilates" PressableCard → the shared `LogPastSessionSheet` preselected to
//   Pilates (duration, day, focus chips, notes) — the one manual logging form
// - Today/yesterday sessions strip with calorie estimates
// - Weekly streak indicator (no streak-shame)
// - Info sheet: muscles worked + post-session nutrition hint

import SwiftUI
import SwiftData

struct PilatesCard: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var sessionModels: [PilatesSessionModel]
    @State private var showLogSheet = false
    @State private var showGoalPicker = false
    @State private var pickerGoal: Int = 3

    @AppStorage private var weeklyGoalRaw: Int

    init(profile: ProfileDTO) {
        self.profile = profile
        _weeklyGoalRaw = AppStorage(
            wrappedValue: 3,
            "pilatesWeeklyGoal.\(profile.id.uuidString)"
        )
        let target = profile.id
        let cutoff = Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Dates.startOfYesterday()
        _sessionModels = Query(
            filter: #Predicate<PilatesSessionModel> { $0.profileId == target && $0.date >= cutoff },
            sort: \.date,
            order: .reverse
        )
    }

    private var weeklyGoal: Int { weeklyGoalRaw }
    private var sessions: [PilatesSessionDTO] { sessionModels.map(\.snapshot) }
    private var thisWeek: [PilatesSessionDTO] { Movement.sessionsThisWeek(sessions) }
    private var streakWeeks: Int {
        Movement.pilatesWeeklyStreak(sessions: sessions, goalSessions: weeklyGoal)
    }
    private var weekPct: Double {
        guard weeklyGoal > 0 else { return 0 }
        return min(1, Double(thisWeek.count) / Double(weeklyGoal))
    }
    private var thisWeekCal: Double {
        thisWeek.reduce(0) { acc, s in
            acc + CalorieEstimator.caloriesForPilates(
                minutes: Double(s.durationMinutes),
                bodyWeightLb: profile.weightLb
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            PressableCard(action: { showLogSheet = true }) {
                logCTA
            }
            recentStrip
        }
        // One manual session form app-wide: this opens the shared log sheet
        // (LiveSessionCard.swift) preselected to Pilates, which collects duration,
        // day, focus areas + notes and writes the PilatesSessionDTO itself.
        .sheet(isPresented: $showLogSheet) {
            LogPastSessionSheet(profile: profile, lockedActivityId: ActivityCatalog.pilatesId)
                .themed(theme.mode)
        }
        .sheet(isPresented: $showGoalPicker) {
            goalPickerSheet.themed(theme.mode)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                ProgressRing(pct: weekPct, color: theme.accent2, trackColor: theme.barBg, lineWidth: 7)
                VStack(spacing: 0) {
                    Text("\(thisWeek.count)")
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
                Text("Pilates")
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
            Image(systemName: "figure.pilates")
                .font(.system(size: 22))
                .foregroundStyle(theme.accent2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Log Pilates")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text("Duration + focus areas. Takes 10 seconds.")
                    .font(.caption).foregroundStyle(theme.dim)
            }
            Spacer(minLength: 0)
        }
    }

    private func deleteSession(_ session: PilatesSessionDTO) {
        guard Repos.deletePilatesSession(ctx, id: session.id) else { return }
        toasts.show(Toast(title: "Session removed", detail: "Pilates session deleted.",
                          accent: .warn, symbol: "trash.fill"))
    }

    @ViewBuilder
    private var recentStrip: some View {
        let recent = Array(sessions.filter { Dates.isTodayOrYesterday($0.date) }.prefix(5))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Today & yesterday")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                ForEach(recent) { s in
                    HStack {
                        Text(Dates.formatTimeAgo(s.date))
                            .font(.caption)
                            .foregroundStyle(theme.text)
                        Spacer()
                        if let focus = s.focusAreas.first {
                            Text(focus.label.uppercased())
                                .font(.system(size: 9, weight: .medium)).tracking(2)
                                .foregroundStyle(theme.dim)
                        }
                        let cal = CalorieEstimator.caloriesForPilates(
                            minutes: Double(s.durationMinutes),
                            bodyWeightLb: profile.weightLb
                        )
                        Text("\(s.durationMinutes) min · ~\(Int(cal)) cal")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(theme.accent2)
                        Button(role: .destructive) { deleteSession(s) } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.warn)
                        }
                        .tactile(.ghost)
                        .accessibilityLabel("Delete this pilates session")
                    }
                }
            }
        }
    }

    // MARK: - Goal picker sheet

    // Shared `GoalPickerSheet` chrome — one wheel, no section label, natural
    // wheel height (this card never grew the fixed 130pt well the Steps sheets use).
    private var goalPickerSheet: some View {
        GoalPickerSheet(
            title: "Weekly Pilates Goal",
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
            resetLabel: "Reset to 3",
            detents: [.medium],
            onReset: {
                weeklyGoalRaw = 3
                showGoalPicker = false
            },
            onSave: {
                weeklyGoalRaw = pickerGoal
                showGoalPicker = false
            }
        )
    }
}
