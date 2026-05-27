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
        _sessionModels = Query(
            filter: #Predicate<CardioSessionModel> { $0.profileId == target },
            sort: \.date,
            order: .reverse
        )
    }

    private var sessions: [CardioSessionDTO] { sessionModels.map(\.snapshot) }
    private var recent: [CardioSessionDTO] { Array(sessions.prefix(5)) }
    private var minutesThisWeek: Int {
        let cal = Calendar(identifier: .iso8601)
        guard let week = cal.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return sessions.filter { week.contains($0.date) }
            .reduce(0) { $0 + $1.durationMinutes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Cardio")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text)
                Spacer()
                Text("\(minutesThisWeek) min · wk")
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
                    Text("Recent")
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("log cardio.")
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
                        distanceMiles: Double(distanceStr),
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
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
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
            Text("Distance (mi, optional)")
                .font(.caption).tracking(2).foregroundStyle(theme.dim)
            TextField("", text: $distanceStr)
                .keyboardType(.decimalPad)
                .padding(10).background(theme.card)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
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
                .padding(10).background(theme.card)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
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
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }
    }
}
