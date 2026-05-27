import SwiftUI
import SwiftData
import Charts

/// Named ProgressTabView to avoid collision with SwiftUI.ProgressView.
struct ProgressTabView: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var bodyModels: [BodyMetricModel]
    @Query private var markerModels: [HealthMarkerModel]
    @Query private var stepModels: [StepCountModel]
    @Query private var exerciseModels: [ExerciseModel]

    private var body_: [BodyMetricDTO] {
        bodyModels.map(\.snapshot).filter { $0.userId == profile.id }
    }
    private var markers: [HealthMarkerDTO] {
        markerModels.map(\.snapshot).filter { $0.userId == profile.id }
    }
    private var steps: [StepCountDTO] {
        stepModels.map(\.snapshot).filter { $0.userId == profile.id }
    }
    private var exercises: [ExerciseDTO] {
        exerciseModels.map(\.snapshot)
            .filter { $0.availableForMode.contains(profile.mode) }
    }

    private var weightSeries: [Trends.Point] {
        let pts = body_.compactMap { b -> Trends.Point? in
            guard let w = b.weightLb else { return nil }
            return Trends.Point(date: b.date, value: w)
        }
        return Trends.rollingAverage(pts, window: 7)
    }

    private var weeklyDelta: Double { Trends.weeklyWeightDelta(body_, days: 14) }
    private var stepsSeries: [Trends.Point] { Steps.series(steps, days: 30) }

    private var lifters: [(ExerciseDTO, WorkoutSetDTO)] {
        exercises
            .filter { $0.category == .compound || $0.category == .isolation || $0.category == .bodyweight }
            .compactMap { ex in
                let history = Repos.setHistory(ctx, userId: profile.id, exerciseId: ex.id, limit: 200)
                if let pr = Progression.personalRecord(history) { return (ex, pr) }
                return nil
            }
            .sorted { ($0.1.weightLb ?? 0) > ($1.1.weightLb ?? 0) }
            .prefix(8)
            .map { ($0.0, $0.1) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("progress.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Weekly trends > daily pass/fail. Show up, log honestly, watch the lines move.")
                    .font(.callout).foregroundStyle(theme.dim)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    weightCard
                    stepsCard
                }

                if profile.mode == .reset { markersSection }
                prsSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private var weightCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                cardHeader(
                    "Weight",
                    subtitle: String(format: "%@%.2f lb/wk (14d)", weeklyDelta >= 0 ? "+" : "", weeklyDelta)
                )
                if weightSeries.isEmpty {
                    emptyState
                } else {
                    Chart(weightSeries, id: \.date) { p in
                        LineMark(x: .value("Day", p.date), y: .value("Weight", p.value))
                            .foregroundStyle(theme.accent)
                    }
                    .frame(height: 140)
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) }
                }
                QuickAddBody(profile: profile)
            }
        }
    }

    private var stepsCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                let avg7 = Steps.average(steps, days: 7)
                let avg30 = Steps.average(steps, days: 30)
                cardHeader(
                    "Steps · 30d",
                    subtitle: "7d avg \(avg7.formatted()) · 30d avg \(avg30.formatted())"
                )
                if stepsSeries.allSatisfy({ $0.value == 0 }) {
                    emptyState
                } else {
                    Chart(stepsSeries, id: \.date) { p in
                        BarMark(x: .value("Day", p.date), y: .value("Steps", p.value))
                            .foregroundStyle(theme.accent)
                    }
                    .frame(height: 140)
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) }
                }
                Text("Goal: \(profile.computedTargets.stepsDaily.formatted())/day")
                    .font(.caption2).foregroundStyle(theme.dim)
            }
        }
    }

    @ViewBuilder
    private var markersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Markers")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                GridItem(.flexible(), spacing: 14)], spacing: 14) {
                ForEach(HealthMarkerKind.allCases, id: \.self) { kind in
                    markerCard(kind: kind)
                }
            }
        }
    }

    @ViewBuilder
    private func markerCard(kind: HealthMarkerKind) -> some View {
        let series = Trends.markerSeries(markers, kind: kind)
        let (label, unit) = markerLabel(kind)
        Card {
            VStack(alignment: .leading, spacing: 8) {
                cardHeader(
                    label,
                    subtitle: series.last.map { "Latest: \(formattedValue($0.value)) \(unit)" } ?? "No data"
                )
                if series.isEmpty {
                    emptyState
                } else {
                    Chart(series, id: \.date) { p in
                        LineMark(x: .value("Day", p.date), y: .value("Value", p.value))
                            .foregroundStyle(theme.accent2)
                        PointMark(x: .value("Day", p.date), y: .value("Value", p.value))
                            .foregroundStyle(theme.accent2)
                    }
                    .frame(height: 120)
                }
                QuickAddMarker(profile: profile, kind: kind, unit: unit)
            }
        }
    }

    @ViewBuilder
    private var prsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lift PRs")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(theme.text)

            if lifters.isEmpty {
                Text("No sets logged yet. Train tab → log a set to start the PR board.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(lifters, id: \.0.id) { (ex, pr) in
                        HStack {
                            Text(ex.name).font(.callout).foregroundStyle(theme.text)
                            Spacer()
                            Text(pr.weightLb.map { "\(Int($0)) lb × \(pr.reps)" } ?? "\(pr.reps) reps")
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(theme.accent)
                        }
                        .padding(10)
                        .background(theme.card)
                        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func cardHeader(_ title: String, subtitle: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.text)
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(theme.dim)
            }
        }
    }

    private var emptyState: some View {
        Text("No data yet.")
            .font(.caption).foregroundStyle(theme.dim)
            .frame(maxWidth: .infinity, minHeight: 100)
    }

    private func formattedValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v)) : String(format: "%.1f", v)
    }

    private func markerLabel(_ k: HealthMarkerKind) -> (String, String) {
        switch k {
        case .bpSystolic:       return ("BP Systolic", "mmHg")
        case .bpDiastolic:      return ("BP Diastolic", "mmHg")
        case .ldl:              return ("LDL", "mg/dL")
        case .hdl:              return ("HDL", "mg/dL")
        case .triglycerides:    return ("Triglycerides", "mg/dL")
        case .totalCholesterol: return ("Total Cholesterol", "mg/dL")
        case .a1c:              return ("A1c", "%")
        case .fastingGlucose:   return ("Fasting Glucose", "mg/dL")
        case .restingHR:        return ("Resting HR", "bpm")
        }
    }
}

// MARK: - Quick-add sub-views

private struct QuickAddBody: View {
    let profile: ProfileDTO
    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter
    @State private var draft: String = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("weight today (lb)", text: $draft)
                .keyboardType(.decimalPad)
                .padding(8)
                .background(theme.barBg)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
                .font(.system(.caption, design: .monospaced))
            Button {
                guard let n = Double(draft), n > 0 else { return }
                Repos.addBody(ctx, BodyMetricDTO(
                    userId: profile.id, date: Dates.dayKey(), weightLb: n
                ))
                Task { await HealthKitService.shared.writeWeightLb(n) }
                draft = ""
                toasts.show(Toast(title: "Weight logged",
                                  detail: String(format: "%.1f lb", n),
                                  accent: .ok, symbol: "scalemass.fill"))
            } label: {
                Text("Log")
            }
            .tactile(.primary)
        }
    }
}

private struct QuickAddMarker: View {
    let profile: ProfileDTO
    let kind: HealthMarkerKind
    let unit: String

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter
    @State private var draft: String = ""

    var body: some View {
        HStack(spacing: 8) {
            TextField("new reading (\(unit))", text: $draft)
                .keyboardType(.decimalPad)
                .padding(8)
                .background(theme.barBg)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
                .font(.system(.caption, design: .monospaced))
            Button {
                guard let n = Double(draft), n > 0 else { return }
                Repos.addMarker(ctx, HealthMarkerDTO(
                    userId: profile.id, date: Dates.dayKey(),
                    kind: kind, value: n, source: "lab"
                ))
                draft = ""
                toasts.show(Toast(title: "Marker logged",
                                  detail: "\(formattedValue(n)) \(unit)",
                                  accent: .ok, symbol: "heart.text.square.fill"))
            } label: {
                Text("Log")
            }
            .tactile(.primary, fill: theme.accent2)
        }
    }

    private func formattedValue(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(v)) : String(format: "%.1f", v)
    }
}
