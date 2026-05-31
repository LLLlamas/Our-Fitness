// Circuit Train — Pilates card.
//
// - Progress ring: sessions this week / weekly goal (editable — tap "/" in ring)
// - "Log Pilates" PressableCard → sheet (duration slider, focus chips, notes)
// - Recent sessions strip with calorie estimates
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
        _sessionModels = Query(
            filter: #Predicate<PilatesSessionModel> { $0.profileId == target },
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
        .sheet(isPresented: $showLogSheet) {
            PilatesLogSheet(profileId: profile.id) { dto in
                Repos.logPilatesSession(ctx, dto)
                toasts.pilatesLogged(minutes: dto.durationMinutes)
            }
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

    @ViewBuilder
    private var recentStrip: some View {
        let recent = Array(sessions.prefix(5))
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent")
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
                    }
                }
            }
        }
    }

    // MARK: - Goal picker sheet

    @ViewBuilder
    private var goalPickerSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly Pilates Goal")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("How many sessions per week to hit your streak.")
                    .font(.caption)
                    .foregroundStyle(theme.dim)
            }
            .padding(.top, 28)
            .padding(.horizontal, 20)

            Picker("Goal", selection: $pickerGoal) {
                ForEach(1...14, id: \.self) { n in
                    Text("\(n) session\(n == 1 ? "" : "s") / week").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .background(theme.card2)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)

            HStack(spacing: 12) {
                Button("Reset to 3") {
                    weeklyGoalRaw = 3
                    showGoalPicker = false
                }
                .tactile(.secondary, fullWidth: true)
                Button("Save") {
                    weeklyGoalRaw = pickerGoal
                    showGoalPicker = false
                    Haptics.success()
                }
                .tactile(.primary, fullWidth: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Log sheet

private struct PilatesLogSheet: View {
    let profileId: UUID
    let onSave: (PilatesSessionDTO) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var duration: Double = 30
    @State private var focusAreas: Set<PilatesFocusArea> = []
    @State private var notes: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("log pilates.")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(theme.text)

                durationSection
                focusSection

                if !focusAreas.isEmpty {
                    recoveryHintSection
                }

                notesSection

                Button {
                    let dto = PilatesSessionDTO(
                        profileId: profileId,
                        durationMinutes: Int(duration),
                        focusAreas: PilatesFocusArea.allCases.filter { focusAreas.contains($0) },
                        notes: notes.isEmpty ? nil : notes
                    )
                    onSave(dto)
                    dismiss()
                } label: {
                    Text("Save session")
                }
                .tactile(.primary, fullWidth: true)
                .disabled(focusAreas.isEmpty)
                .opacity(focusAreas.isEmpty ? 0.6 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Duration")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                Spacer()
                Text("\(Int(duration)) min")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(theme.accent2)
            }
            Slider(value: $duration, in: 5...90, step: 5)
                .tint(theme.accent2)
        }
    }

    @ViewBuilder
    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Focus areas")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            FlowLayout(spacing: 8) {
                ForEach(PilatesFocusArea.allCases, id: \.self) { area in
                    Button {
                        if focusAreas.contains(area) { focusAreas.remove(area) }
                        else { focusAreas.insert(area) }
                    } label: {
                        Text(area.label)
                    }
                    .tactile(.pill, fill: focusAreas.contains(area) ? theme.accent2 : nil)
                }
            }
        }
    }

    @ViewBuilder
    private var recoveryHintSection: some View {
        let hint = Movement.postPilatesHint(areas: Array(focusAreas))
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent2)
                Text("Recovery · rest \(hint.recoveryHours)h")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
            }
            Text("Muscles: \(hint.musclesWorked.joined(separator: ", "))")
                .font(.caption).foregroundStyle(theme.text)
            Text("\(hint.primaryNeed) within \(hint.windowMinutes) min.")
                .font(.caption).foregroundStyle(theme.dim)
            Text("Try: \(hint.recoveryFoods.joined(separator: " · "))")
                .font(.caption).italic().foregroundStyle(theme.dim)
            if !hint.formCues.isEmpty {
                Divider().background(theme.line)
                ForEach(Array(hint.formCues.enumerated()), id: \.offset) { _, cue in
                    Text("· \(cue)")
                        .font(.caption).foregroundStyle(theme.text)
                }
            }
        }
        .padding(12)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes (optional)")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            TextField("How did it feel?", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }
    }
}

// Simple flow layout for chip rows.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(subviews: subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let positions = arrange(subviews: subviews, width: bounds.width).positions
        for (idx, sub) in subviews.enumerated() {
            sub.place(at: CGPoint(x: bounds.minX + positions[idx].x,
                                  y: bounds.minY + positions[idx].y),
                      proposal: .unspecified)
        }
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            maxX = max(maxX, x - spacing)
        }
        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
