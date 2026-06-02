// Live Sessions — a calm, timestamp-anchored timer for duration-based activities
// (basketball, pilates, soccer, swimming, etc.).
//
// Flow:
//   LiveSessionCard  → entry point (Today / Train). Resumes an in-progress
//                      session if one survives backgrounding or an app kill.
//   ActivityPicker   → pick an activity + expected duration, then Start.
//   LiveSessionRunner→ big elapsed timer vs. expected, gentle over-time state,
//                      live calorie readout, End / +5 min.
//
// Source of truth is the persisted `LiveSessionState.startDate`; elapsed time is
// always now − startDate, so the timer is correct after the app is suspended or
// relaunched. See Services/LiveSessionService.swift for the persistence + local
// notification rationale (and the explicit-action authorization rule).

import SwiftUI
import SwiftData

struct LiveSessionCard: View {
    let profile: ProfileDTO

    @Environment(\.theme) private var theme

    @State private var showPicker = false
    @State private var runner: RunnerSession?
    // Bumped when a session ends so the recent list re-queries.
    @State private var refreshToken = UUID()

    /// Identifiable wrapper so `.sheet(item:)` can drive the runner. Keeps the
    /// Domain `LiveSessionState` free of an `Identifiable` conformance.
    private struct RunnerSession: Identifiable {
        let id = UUID()
        let state: LiveSessionState
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let active = LiveSessionStore.active(for: profile.id) {
                resumeCard(active)
            } else {
                startCard
            }
            RecentActivitySessions(profile: profile, refreshToken: refreshToken)
        }
        .onAppear {
            // Resume detection only — no permission requests here (see service docs).
            // Reading persisted state on appear/foreground is what makes a session
            // "continue" after the app was backgrounded or killed.
            refreshToken = UUID()
        }
        .sheet(isPresented: $showPicker) {
            ActivityPicker(profile: profile) { state in
                runner = RunnerSession(state: state)
            }
            .themed(profile.mode)
        }
        .sheet(item: $runner, onDismiss: { refreshToken = UUID() }) { wrapped in
            LiveSessionRunner(profile: profile, initial: wrapped.state)
                .themed(profile.mode)
        }
    }

    @ViewBuilder
    private var startCard: some View {
        PressableCard(action: { showPicker = true }) {
            HStack(spacing: 12) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Start a live session")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text("Time a game, swim, or class — we log the calories when you finish.")
                        .font(.caption).foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private func resumeCard(_ state: LiveSessionState) -> some View {
        PressableCard(action: { runner = RunnerSession(state: state) }) {
            HStack(spacing: 12) {
                Image(systemName: "stopwatch.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(state.activityName) in progress")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.text)
                    Text("Tap to resume — started \(Dates.formatTimeAgo(state.startDate)).")
                        .font(.caption).foregroundStyle(theme.dim)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent.opacity(0.6))
            }
        }
    }
}

// MARK: - Activity picker

private struct ActivityPicker: View {
    let profile: ProfileDTO
    let onStart: (LiveSessionState) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var selectedId: String?
    @State private var expectedMinutes: Int = 30
    @State private var customMET: Double = ActivityCatalog.otherDefaultMET

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

    private var selected: Activity? {
        guard let id = selectedId else { return nil }
        return ActivityCatalog.activity(id: id)
    }

    private var isOther: Bool { selectedId == ActivityCatalog.otherId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("live session.")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(theme.text)

                Text("PICK AN ACTIVITY")
                    .font(.system(size: 10, weight: .medium)).tracking(2)
                    .foregroundStyle(theme.dim)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ActivityCatalog.all) { activity in
                        activityTile(activity)
                    }
                }

                if selected != nil {
                    durationSection
                    if isOther {
                        intensitySection
                    }
                    Button {
                        start()
                    } label: {
                        Text("Start")
                    }
                    .tactile(.primary, fullWidth: true)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func activityTile(_ activity: Activity) -> some View {
        let isSel = selectedId == activity.id
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedId = activity.id
                if activity.id == ActivityCatalog.otherId { customMET = ActivityCatalog.otherDefaultMET }
            }
            Haptics.selection()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: activity.symbol)
                    .font(.system(size: 26))
                    .foregroundStyle(isSel ? theme.bg : theme.accent)
                Text(activity.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSel ? theme.bg : theme.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 92)
            .padding(8)
            .background(isSel ? theme.accent : theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSel ? theme.accent : theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(activity.name)
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    @ViewBuilder
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXPECTED TIME")
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)

            HStack(spacing: 8) {
                ForEach(ActivityCatalog.durationPresets, id: \.self) { mins in
                    Button {
                        expectedMinutes = mins
                        Haptics.selection()
                    } label: {
                        Text("\(mins) min")
                    }
                    .tactile(.pill, fill: expectedMinutes == mins ? theme.accent : nil)
                }
            }

            HStack {
                Text("\(expectedMinutes) min")
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(theme.text)
                    .contentTransition(.numericText())
                Spacer()
                Button {
                    expectedMinutes = max(5, expectedMinutes - 5)
                    Haptics.bump()
                } label: { Text("−5") }
                .tactile(.bump)
                Button {
                    expectedMinutes = min(240, expectedMinutes + 5)
                    Haptics.bump()
                } label: { Text("+5") }
                .tactile(.bump)
            }
            .padding(10)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var intensitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("INTENSITY")
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(intensityLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.text)
                    Spacer()
                    Text(String(format: "%.1f MET", customMET))
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(theme.accent)
                }
                Slider(value: $customMET, in: 2...12, step: 0.5)
                    .tint(theme.accent)
                Text("How hard it feels — light (2), moderate (5), or intense (10+). Drives the calorie estimate.")
                    .font(.caption2).foregroundStyle(theme.dim)
            }
            .padding(10)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        }
    }

    private var intensityLabel: String {
        switch customMET {
        case ..<3.5:  return "Light"
        case ..<6.0:  return "Moderate"
        case ..<8.5:  return "Vigorous"
        default:      return "Intense"
        }
    }

    private func start() {
        guard let activity = selected else { return }
        let met = isOther ? customMET : activity.met
        let state = LiveSessionState(
            activityId: activity.id,
            activityName: activity.name,
            met: met,
            expectedMinutes: expectedMinutes,
            profileId: profile.id
        )
        // TODO (Phase 2): ActivityKit Live Activity for Lock Screen / Dynamic
        // Island. Needs a separate Widget Extension target + project.yml changes
        // + on-device verification. The timestamp anchor + local notification
        // already guarantee the session survives backgrounding and relaunch.
        LiveSessionStore.save(state)
        Task {
            // Permission is requested ONLY here, from the explicit Start tap.
            // A denial does not block the session — it just means no end ping.
            await LiveSessionNotifier.requestAuthorizationIfNeeded()
            LiveSessionNotifier.schedule(activityName: activity.name, expectedMinutes: expectedMinutes, from: state.startDate)
        }
        Haptics.success()
        dismiss()
        onStart(state)
    }
}

// MARK: - Live session runner

private struct LiveSessionRunner: View {
    let profile: ProfileDTO
    let initial: LiveSessionState

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var state: LiveSessionState
    @State private var ended = false

    init(profile: ProfileDTO, initial: LiveSessionState) {
        self.profile = profile
        self.initial = initial
        _state = State(initialValue: initial)
    }

    private var activity: Activity? { ActivityCatalog.activity(id: state.activityId) }
    private var symbol: String { activity?.symbol ?? "figure.mixed.cardio" }
    private var expectedSeconds: Int { state.expectedMinutes * 60 }

    var body: some View {
        // TimelineView ticks the on-screen display once a second; the SOURCE OF
        // TRUTH stays state.startDate, so the readout is correct even after the
        // app was suspended (TimelineView simply resumes against the real clock).
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = state.elapsedSeconds(now: context.date)
            let overtime = elapsed > expectedSeconds
            let pct = expectedSeconds > 0 ? Double(elapsed) / Double(expectedSeconds) : 0
            let liveCal = Int(CalorieEstimator.caloriesForActivity(
                met: state.met, minutes: Double(elapsed) / 60.0, bodyWeightLb: profile.weightLb
            ).rounded())

            ScrollView {
                VStack(spacing: 24) {
                    header

                    ZStack {
                        ProgressRing(
                            pct: min(1, pct),
                            color: overtime ? theme.accent2 : theme.accent,
                            trackColor: theme.barBg,
                            lineWidth: 14
                        )
                        .frame(width: 240, height: 240)

                        VStack(spacing: 6) {
                            Image(systemName: symbol)
                                .font(.system(size: 30))
                                .foregroundStyle(overtime ? theme.accent2 : theme.accent)
                            Text(timeString(elapsed))
                                .font(.system(size: 52, weight: .semibold, design: .monospaced))
                                .foregroundStyle(theme.text)
                                .contentTransition(.numericText())
                            Text(overtime
                                 ? "of \(state.expectedMinutes) min planned"
                                 : "of \(state.expectedMinutes) min")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.dim)
                        }
                    }
                    .padding(.top, 8)

                    statusLine(overtime: overtime, liveCal: liveCal)

                    controls
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.activityName.lowercased() + ".")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("LIVE SESSION")
                    .font(.system(size: 10, weight: .medium)).tracking(2)
                    .foregroundStyle(theme.dim)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func statusLine(overtime: Bool, liveCal: Int) -> some View {
        VStack(spacing: 6) {
            Text("≈ \(liveCal) cal")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.accent)
                .contentTransition(.numericText())
            Text(overtime
                 ? "Past your planned time — finish when ready."
                 : "Keep it steady. We'll let you know at \(state.expectedMinutes) min.")
                .font(.callout)
                .foregroundStyle(theme.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 10) {
            Button {
                end()
            } label: {
                Text("End session")
            }
            .tactile(.primary, fullWidth: true)

            HStack(spacing: 10) {
                Button {
                    adjustExpected(by: 5)
                } label: {
                    Label("+5 min", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .tactile(.secondary, fullWidth: true)

                Button {
                    adjustExpected(by: -5)
                } label: {
                    Label("−5 min", systemImage: "minus")
                        .frame(maxWidth: .infinity)
                }
                .tactile(.secondary, fullWidth: true)
            }
        }
    }

    private func timeString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// Adjust the planned time and reschedule the end notification relative to the
    /// original start anchor, so the ping lands at the new expected mark.
    private func adjustExpected(by delta: Int) {
        let newExpected = max(5, min(240, state.expectedMinutes + delta))
        guard newExpected != state.expectedMinutes else { return }
        state.expectedMinutes = newExpected
        LiveSessionStore.save(state)
        LiveSessionNotifier.schedule(
            activityName: state.activityName,
            expectedMinutes: newExpected,
            from: state.startDate
        )
        Haptics.bump()
    }

    private func end() {
        guard !ended else { return }
        ended = true

        let elapsedSeconds = state.elapsedSeconds()
        let actualMinutes = max(1, Int((Double(elapsedSeconds) / 60.0).rounded()))
        let cal = CalorieEstimator.caloriesForActivity(
            met: state.met, minutes: Double(elapsedSeconds) / 60.0, bodyWeightLb: profile.weightLb
        )

        let dto = ActivitySessionDTO(
            profileId: profile.id,
            date: state.startDate,
            activityId: state.activityId,
            activityName: state.activityName,
            met: state.met,
            durationMinutes: actualMinutes,
            expectedMinutes: state.expectedMinutes,
            caloriesEst: cal
        )
        Repos.logActivitySession(ctx, dto)

        LiveSessionNotifier.cancel()
        LiveSessionStore.clear()

        toasts.show(Toast(
            title: "\(state.activityName) logged",
            detail: "\(actualMinutes) min · ~\(Int(cal.rounded())) cal",
            accent: .win, symbol: "checkmark.seal.fill"
        ), for: 2.4)

        dismiss()
    }
}

// MARK: - Recent sessions

/// Compact list of recently completed live sessions, profile-scoped at the query
/// level. Re-queries when `refreshToken` changes (i.e. after a session ends).
private struct RecentActivitySessions: View {
    let profile: ProfileDTO
    let refreshToken: UUID

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var models: [ActivitySessionModel]

    init(profile: ProfileDTO, refreshToken: UUID) {
        self.profile = profile
        self.refreshToken = refreshToken
        let uid = profile.id
        _models = Query(
            filter: #Predicate<ActivitySessionModel> { $0.profileId == uid },
            sort: \.date, order: .reverse
        )
    }

    private var sessions: [ActivitySessionDTO] { Array(models.map(\.snapshot).prefix(5)) }

    var body: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent sessions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.dim)
                ForEach(sessions) { sessionRow($0) }
            }
            .id(refreshToken)
        }
    }

    @ViewBuilder
    private func sessionRow(_ s: ActivitySessionDTO) -> some View {
        let symbol = ActivityCatalog.activity(id: s.activityId)?.symbol ?? "figure.mixed.cardio"
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16))
                .foregroundStyle(theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.activityName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.text)
                Text("\(s.durationMinutes) min · \(Dates.formatTimeAgo(s.date))")
                    .font(.caption).foregroundStyle(theme.dim)
            }
            Spacer()
            if let c = s.caloriesEst, c > 0 {
                Text("~\(Int(c.rounded())) cal")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
            Button(role: .destructive) {
                Repos.deleteActivitySession(ctx, id: s.id)
                Haptics.warn()
                toasts.show(Toast(title: "Session removed", detail: s.activityName,
                                  accent: .warn, symbol: "trash.fill"))
            } label: {
                Image(systemName: "trash").foregroundStyle(theme.warn)
            }
            .tactile(.ghost)
            .accessibilityLabel("Delete \(s.activityName) session")
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}
