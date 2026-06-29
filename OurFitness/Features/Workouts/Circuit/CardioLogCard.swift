// Circuit Train — Cardio session log.
// Log walks/runs/bikes/etc. with duration + optional distance/RPE.

import SwiftUI
import SwiftData

struct CardioLogCard: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var sessionModels: [CardioSessionModel]
    @State private var showLogSheet = false

    init(profile: ProfileDTO) {
        self.profile = profile
        let target = profile.id
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Dates.startOfYesterday()
        let cutoff = min(weekStart, Dates.startOfYesterday())
        _sessionModels = Query(
            filter: #Predicate<CardioSessionModel> { $0.profileId == target && $0.date >= cutoff },
            sort: \.date,
            order: .reverse
        )
    }

    private var sessions: [CardioSessionDTO] { sessionModels.map(\.snapshot) }
    private var recent: [CardioSessionDTO] {
        Array(sessions.filter { Dates.isTodayOrYesterday($0.date) }.prefix(5))
    }
    private var minutesThisWeek: Int {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2  // Monday-anchored, matches Movement.sessionsThisWeek
        guard let week = cal.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return sessions.filter { week.contains($0.date) }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    private func deleteSession(_ session: CardioSessionDTO) {
        Repos.deleteCardioSession(ctx, id: session.id)
        toasts.show(Toast(title: "Session removed", detail: "Cardio session deleted.",
                          accent: .warn, symbol: "trash.fill"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cardio")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                Spacer()
                Text("\(minutesThisWeek) min · week")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }

            PressableCard(action: { showLogSheet = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 22))
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Log a session")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text("Type, duration, optional distance + RPE.")
                            .font(.caption).foregroundStyle(theme.dim)
                    }
                    Spacer(minLength: 0)
                }
            }

            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Today & yesterday")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    ForEach(recent) { s in
                        HStack {
                            Text(s.type.label).foregroundStyle(theme.text)
                            Spacer()
                            Text(Dates.formatTimeAgo(s.date))
                                .font(.system(size: 9, weight: .medium)).tracking(2)
                                .foregroundStyle(theme.dim)
                            Text("\(s.durationMinutes) min")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(theme.accent)
                            Button(role: .destructive) { deleteSession(s) } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 12))
                                    .foregroundStyle(theme.warn)
                            }
                            .tactile(.ghost)
                            .accessibilityLabel("Delete this cardio session")
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .sheet(isPresented: $showLogSheet) {
            CardioLogSheet(profileId: profile.id, bodyWeightLb: profile.weightLb, loadLb: nil) { dto in
                Repos.logCardio(ctx, dto)
                toasts.show(Toast(title: "Cardio logged",
                                  detail: "\(dto.type.label) · \(dto.durationMinutes) min",
                                  accent: .ok, symbol: "checkmark"))
            }
            .themed(theme.mode)
        }
    }
}

private struct CardioLogSheet: View {
    let profileId: UUID
    let bodyWeightLb: Double
    let loadLb: Double?
    let onSave: (CardioSessionDTO) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var type: CardioType = .walk
    @State private var duration: Double = 30
    @State private var distanceStr: String = ""
    @State private var rpeStr: String = ""
    @State private var notes: String = ""
    @FocusState private var focusedField: Bool

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Log cardio")
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(theme.text)

                typeSection
                durationSection
                distanceSection
                rpeSection
                notesSection

                Button {
                    let kcal = CalorieEstimator.caloriesForDuration(
                        minutes: duration,
                        loadLb: loadLb,
                        bodyWeightLb: bodyWeightLb
                    )
                    let dto = CardioSessionDTO(
                        profileId: profileId, type: type,
                        durationMinutes: Int(duration),
                        distanceMiles: Units.parseDistanceToMiles(distanceStr, system: unitSystem),
                        rpe: Double(rpeStr),
                        notes: notes.isEmpty ? nil : notes,
                        caloriesEst: kcal
                    )
                    onSave(dto)
                    dismiss()
                } label: {
                    Text("Save session")
                }
                .tactile(.primary, fullWidth: true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = false }
            }
        }
    }

    @ViewBuilder
    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type").font(.caption).tracking(2).foregroundStyle(theme.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CardioType.allCases, id: \.self) { t in
                        Button { type = t } label: { Text(t.label) }
                            .tactile(.pill, fill: type == t ? theme.accent : nil)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Duration")
                    .font(.caption).tracking(2).foregroundStyle(theme.dim)
                Spacer()
                Text("\(Int(duration)) min")
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(theme.accent)
            }
            Slider(value: $duration, in: 5...120, step: 5)
                .tint(theme.accent)
        }
    }

    @ViewBuilder
    private var distanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Distance (\(Units.distanceUnit(unitSystem)), optional)")
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            TextField("", text: $distanceStr)
                .keyboardType(.decimalPad)
                .focused($focusedField)
                .padding(10).background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }
    }

    @ViewBuilder
    private var rpeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Perceived effort (1–10, optional)")
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            TextField("", text: $rpeStr)
                .keyboardType(.decimalPad)
                .focused($focusedField)
                .padding(10).background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notes (optional)")
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            TextField("How did it feel?", text: $notes, axis: .vertical)
                .lineLimit(2...4)
                .padding(10).background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }
    }
}
