// Circuit Train — Pilates card.
//
// - "Log Pilates" PressableCard → sheet (duration slider, focus chips, notes)
// - Recent sessions strip (last 5)
// - Weekly frequency vs goal (default 3x/wk)
// - Weekly streak indicator (no streak-shame: missing weeks slide to 0)

import SwiftUI
import SwiftData

struct PilatesCard: View {
    let profile: ProfileDTO
    let weeklyGoal: Int

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var sessionModels: [PilatesSessionModel]
    @State private var showLogSheet = false

    init(profile: ProfileDTO, weeklyGoal: Int = 3) {
        self.profile = profile
        self.weeklyGoal = weeklyGoal
        let target = profile.id
        _sessionModels = Query(
            filter: #Predicate<PilatesSessionModel> { $0.profileId == target },
            sort: \.date,
            order: .reverse
        )
    }

    private var sessions: [PilatesSessionDTO] { sessionModels.map(\.snapshot) }
    private var thisWeek: [PilatesSessionDTO] { Movement.sessionsThisWeek(sessions) }
    private var streakWeeks: Int {
        Movement.pilatesWeeklyStreak(sessions: sessions, goalSessions: weeklyGoal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            PressableCard(action: { showLogSheet = true }) {
                logCTA
            }
            weeklyProgress
            recentStrip
        }
        .sheet(isPresented: $showLogSheet) {
            PilatesLogSheet(profileId: profile.id) { dto in
                Repos.logPilatesSession(ctx, dto)
                // toasts.pilatesLogged already fires the outcome haptic via
                // ToastCenter.fireHaptic(for: .ok); don't double-tap.
                toasts.pilatesLogged(minutes: dto.durationMinutes)
            }
            .themed(theme.mode)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Pilates")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)
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
    private var weeklyProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.caption).tracking(2).textCase(.uppercase)
                    .foregroundStyle(theme.dim)
                Spacer()
                Text("\(thisWeek.count) / \(weeklyGoal)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.text)
            }
            HStack(spacing: 6) {
                ForEach(0..<weeklyGoal, id: \.self) { idx in
                    Rectangle()
                        .fill(idx < thisWeek.count ? theme.accent2 : theme.barBg)
                        .frame(height: 6)
                }
            }
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
                        Text("\(s.durationMinutes) min")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(theme.accent2)
                    }
                }
            }
        }
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
                notesSection

                Button {
                    let dto = PilatesSessionDTO(
                        profileId: profileId,
                        durationMinutes: Int(duration),
                        focusAreas: PilatesFocusArea.allCases
                            .filter { focusAreas.contains($0) },
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
                        if focusAreas.contains(area) {
                            focusAreas.remove(area)
                        } else {
                            focusAreas.insert(area)
                        }
                    } label: {
                        Text(area.label)
                    }
                    .tactile(.pill, fill: focusAreas.contains(area) ? theme.accent2 : nil)
                }
            }
        }
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
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }
    }
}

// Simple flow layout for chip rows. Local to this file — only consumer.
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
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            maxX = max(maxX, x - spacing)
        }
        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
