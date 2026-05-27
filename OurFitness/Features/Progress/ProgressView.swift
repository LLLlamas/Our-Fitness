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

    @State private var activeStat: StatKind?

    private var body_: [BodyMetricDTO] {
        bodyModels.map(\.snapshot)
            .filter { $0.userId == profile.id }
            .sorted { $0.date < $1.date }
    }
    private var markers: [HealthMarkerDTO] {
        markerModels.map(\.snapshot).filter { $0.userId == profile.id }
    }
    private var steps: [StepCountDTO] {
        stepModels.map(\.snapshot).filter { $0.userId == profile.id }
    }

    private var visibleStats: [StatKind] {
        StatKind.allCases.filter { $0.isRelevant(for: profile.mode) }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("progress.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Weekly trends > daily pass/fail. Show up, log honestly, watch the lines move.")
                    .font(.callout).foregroundStyle(theme.dim)

                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(visibleStats, id: \.self) { kind in
                        statCard(for: kind)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(item: $activeStat) { kind in
            detailSheet(for: kind)
                .themed(theme.mode)
        }
    }

    // MARK: - Cards

    @ViewBuilder
    private func statCard(for kind: StatKind) -> some View {
        let value = kind.displayValue(body: body_, markers: markers, steps: steps)
        let trend = kind.trendChip(body: body_, markers: markers, steps: steps)
        let tint  = statusTint(for: kind)
        StatCard(
            title: kind.title,
            value: value,
            unit: kind.unit,
            trend: trend,
            valueAccent: tint,
            action: { activeStat = kind }
        )
    }

    /// Maps the marker's RangeStatus to a Theme color. Returns nil for stats
    /// without a medical reference range (weight, body fat, waist, steps)
    /// so they fall back to the default text color.
    private func statusTint(for kind: StatKind) -> Color? {
        let status: HealthRanges.RangeStatus
        switch kind {
        case .bp:
            let sys = latestMarkerValue(.bpSystolic)
            let dia = latestMarkerValue(.bpDiastolic)
            guard sys != nil || dia != nil else { return nil }
            status = HealthRanges.bpStatus(systolic: sys, diastolic: dia)
        case .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose, .restingHR:
            guard let mk = kind.markerKind,
                  let v = latestMarkerValue(mk) else { return nil }
            status = HealthRanges.status(for: mk, value: v)
        case .weight, .bodyFat, .waist, .stepsAvg:
            return nil
        }
        switch status {
        case .optimal:    return theme.ok
        case .borderline: return theme.accent2
        case .high:       return theme.warn
        case .unknown:    return nil
        }
    }

    private func latestMarkerValue(_ kind: HealthMarkerKind) -> Double? {
        markers.filter { $0.kind == kind }
            .sorted { $0.date < $1.date }
            .last?.value
    }

    // MARK: - Detail sheets

    @ViewBuilder
    private func detailSheet(for kind: StatKind) -> some View {
        switch kind {
        case .stepsAvg:
            stepsDetail
        case .bp:
            bpDetail
        case .weight:
            WeightLogSheet(
                profile: profile,
                metrics: body_,
                onSave: { value in save(kind: .weight, value: value) }
            )
            .environmentObject(toasts)
        default:
            StatDetailSheet(
                title: kind.title,
                unit: kind.unit,
                series: kind.series(body: body_, markers: markers, steps: steps),
                entries: kind.entries(body: body_, markers: markers),
                placeholder: kind.placeholder,
                canLog: kind.canLog,
                rangeContext: kind.markerKind.map(HealthRanges.context(for:)),
                onSave: { value in
                    save(kind: kind, value: value)
                }
            )
        }
    }

    @ViewBuilder
    private var stepsDetail: some View {
        StatDetailSheet(
            title: "Steps",
            unit: "steps · daily",
            series: Steps.series(steps, days: 30),
            entries: steps
                .sorted { $0.date > $1.date }
                .prefix(10)
                .map { s in
                    StatDetailEntry(
                        id: s.id.uuidString,
                        dateLabel: s.date,
                        valueLabel: s.steps.formatted()
                    )
                },
            placeholder: "",
            canLog: false,
            onSave: { _ in }
        )
    }

    @ViewBuilder
    private var bpDetail: some View {
        BPDetailSheet(profile: profile, markers: markers)
            .environmentObject(toasts)
    }

    // MARK: - Save

    private func save(kind: StatKind, value: Double) {
        let today = Dates.dayKey()
        switch kind {
        case .weight:
            Repos.addBody(ctx, BodyMetricDTO(
                userId: profile.id, date: today, weightLb: value
            ))
            Task { await HealthKitService.shared.writeWeightLb(value) }
            toasts.show(Toast(title: "Weight logged",
                              detail: String(format: "%.1f lb", value),
                              accent: .ok, symbol: "scalemass.fill"))
        case .bodyFat:
            Repos.addBody(ctx, BodyMetricDTO(
                userId: profile.id, date: today, bodyFatPct: value
            ))
            toasts.show(Toast(title: "Body fat logged",
                              detail: String(format: "%.1f %%", value),
                              accent: .ok, symbol: "scalemass.fill"))
        case .waist:
            Repos.addBody(ctx, BodyMetricDTO(
                userId: profile.id, date: today, waistIn: value
            ))
            toasts.show(Toast(title: "Waist logged",
                              detail: String(format: "%.1f in", value),
                              accent: .ok, symbol: "ruler"))
        case .restingHR, .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            guard let markerKind = kind.markerKind else { return }
            Repos.addMarker(ctx, HealthMarkerDTO(
                userId: profile.id, date: today,
                kind: markerKind, value: value, source: "manual"
            ))
            toasts.show(Toast(title: "\(kind.title) logged",
                              detail: "\(formattedValue(value)) \(kind.unit)",
                              accent: .ok, symbol: "heart.text.square.fill"))
        case .bp, .stepsAvg:
            break
        }
    }
}

// MARK: - StatKind

enum StatKind: String, CaseIterable, Identifiable {
    case weight, bodyFat, waist, restingHR, stepsAvg
    case bp, ldl, hdl, totalCholesterol, a1c, fastingGlucose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight:           return "Weight"
        case .bodyFat:          return "Body Fat"
        case .waist:            return "Waist"
        case .restingHR:        return "Resting HR"
        case .stepsAvg:         return "Steps · 7d avg"
        case .bp:               return "BP"
        case .ldl:              return "LDL"
        case .hdl:              return "HDL"
        case .totalCholesterol: return "Total Chol."
        case .a1c:              return "A1c"
        case .fastingGlucose:   return "Fasting Gluc."
        }
    }

    var unit: String {
        switch self {
        case .weight:           return "lb"
        case .bodyFat:          return "%"
        case .waist:            return "in"
        case .restingHR:        return "bpm"
        case .stepsAvg:         return "steps"
        case .bp:               return "mmHg"
        case .ldl, .hdl, .totalCholesterol, .fastingGlucose: return "mg/dL"
        case .a1c:              return "%"
        }
    }

    var placeholder: String {
        switch self {
        case .weight:           return "weight (lb)"
        case .bodyFat:          return "body fat (%)"
        case .waist:            return "waist (in)"
        case .restingHR:        return "resting HR (bpm)"
        case .ldl, .hdl, .totalCholesterol, .fastingGlucose: return "value (mg/dL)"
        case .a1c:              return "A1c (%)"
        case .bp, .stepsAvg:    return ""
        }
    }

    var canLog: Bool {
        self != .stepsAvg
    }

    var markerKind: HealthMarkerKind? {
        switch self {
        case .restingHR:        return .restingHR
        case .ldl:              return .ldl
        case .hdl:              return .hdl
        case .totalCholesterol: return .totalCholesterol
        case .a1c:              return .a1c
        case .fastingGlucose:   return .fastingGlucose
        default:                return nil
        }
    }

    func isRelevant(for mode: Mode) -> Bool {
        switch self {
        case .weight, .bodyFat, .waist, .stepsAvg:
            return true
        case .restingHR, .bp, .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            return mode == .circuit
        }
    }

    func displayValue(
        body: [BodyMetricDTO],
        markers: [HealthMarkerDTO],
        steps: [StepCountDTO]
    ) -> String? {
        switch self {
        case .weight:
            return body.compactMap(\.weightLb).last.map { formattedValue($0) }
        case .bodyFat:
            return body.compactMap(\.bodyFatPct).last.map { formattedValue($0) }
        case .waist:
            return body.compactMap(\.waistIn).last.map { formattedValue($0) }
        case .restingHR:
            return latestMarker(.restingHR, in: markers).map { formattedValue($0) }
        case .stepsAvg:
            let avg = Steps.average(steps, days: 7)
            return avg > 0 ? avg.formatted() : nil
        case .bp:
            let s = latestMarker(.bpSystolic, in: markers)
            let d = latestMarker(.bpDiastolic, in: markers)
            if let s, let d { return "\(Int(s))/\(Int(d))" }
            return nil
        case .ldl:
            return latestMarker(.ldl, in: markers).map { formattedValue($0) }
        case .hdl:
            return latestMarker(.hdl, in: markers).map { formattedValue($0) }
        case .totalCholesterol:
            return latestMarker(.totalCholesterol, in: markers).map { formattedValue($0) }
        case .a1c:
            return latestMarker(.a1c, in: markers).map { formattedValue($0) }
        case .fastingGlucose:
            return latestMarker(.fastingGlucose, in: markers).map { formattedValue($0) }
        }
    }

    func trendChip(
        body: [BodyMetricDTO],
        markers: [HealthMarkerDTO],
        steps: [StepCountDTO]
    ) -> String? {
        switch self {
        case .weight:
            let delta = Trends.weeklyWeightDelta(body, days: 14)
            guard abs(delta) > 0.01 else { return nil }
            return String(format: "%@%.2f/wk", delta >= 0 ? "+" : "", delta)
        case .stepsAvg:
            let avg30 = Steps.average(steps, days: 30)
            return avg30 > 0 ? "30d \(avg30.formatted())" : nil
        default:
            return nil
        }
    }

    func series(
        body: [BodyMetricDTO],
        markers: [HealthMarkerDTO],
        steps: [StepCountDTO]
    ) -> [Trends.Point] {
        switch self {
        case .weight:
            let pts = body.compactMap { b -> Trends.Point? in
                guard let w = b.weightLb else { return nil }
                return Trends.Point(date: b.date, value: w)
            }
            return Trends.rollingAverage(pts, window: 7)
        case .bodyFat:
            return body.compactMap { b in
                b.bodyFatPct.map { Trends.Point(date: b.date, value: $0) }
            }
        case .waist:
            return body.compactMap { b in
                b.waistIn.map { Trends.Point(date: b.date, value: $0) }
            }
        case .restingHR:
            return Trends.markerSeries(markers, kind: .restingHR)
        case .stepsAvg:
            return Steps.series(steps, days: 30)
        case .bp:
            return Trends.markerSeries(markers, kind: .bpSystolic)
        case .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            guard let k = markerKind else { return [] }
            return Trends.markerSeries(markers, kind: k)
        }
    }

    func entries(
        body: [BodyMetricDTO],
        markers: [HealthMarkerDTO]
    ) -> [StatDetailEntry] {
        switch self {
        case .weight:
            return body.compactMap { b -> StatDetailEntry? in
                guard let w = b.weightLb else { return nil }
                return StatDetailEntry(id: b.id.uuidString, dateLabel: b.date,
                                       valueLabel: String(format: "%.1f lb", w))
            }
            .reversed()
            .prefix(10)
            .map { $0 }
        case .bodyFat:
            return body.compactMap { b -> StatDetailEntry? in
                guard let v = b.bodyFatPct else { return nil }
                return StatDetailEntry(id: b.id.uuidString, dateLabel: b.date,
                                       valueLabel: String(format: "%.1f %%", v))
            }
            .reversed()
            .prefix(10)
            .map { $0 }
        case .waist:
            return body.compactMap { b -> StatDetailEntry? in
                guard let v = b.waistIn else { return nil }
                return StatDetailEntry(id: b.id.uuidString, dateLabel: b.date,
                                       valueLabel: String(format: "%.1f in", v))
            }
            .reversed()
            .prefix(10)
            .map { $0 }
        case .restingHR, .ldl, .hdl, .totalCholesterol, .a1c, .fastingGlucose:
            guard let k = markerKind else { return [] }
            return markers
                .filter { $0.kind == k }
                .sorted { $0.date > $1.date }
                .prefix(10)
                .map { m in
                    StatDetailEntry(id: m.id.uuidString, dateLabel: m.date,
                                    valueLabel: "\(formattedValue(m.value)) \(unit)")
                }
        case .bp:
            return markers
                .filter { $0.kind == .bpSystolic || $0.kind == .bpDiastolic }
                .sorted { $0.date > $1.date }
                .prefix(10)
                .map { m in
                    let label = m.kind == .bpSystolic ? "sys" : "dia"
                    return StatDetailEntry(id: m.id.uuidString, dateLabel: m.date,
                                           valueLabel: "\(Int(m.value)) \(label)")
                }
        case .stepsAvg:
            return []
        }
    }

    private func latestMarker(_ kind: HealthMarkerKind, in markers: [HealthMarkerDTO]) -> Double? {
        markers.filter { $0.kind == kind }
            .sorted { $0.date < $1.date }
            .last?.value
    }
}

private func formattedValue(_ v: Double) -> String {
    v.truncatingRemainder(dividingBy: 1) == 0
        ? String(Int(v)) : String(format: "%.1f", v)
}

// MARK: - BP sheet (composite)

private struct BPDetailSheet: View {
    let profile: ProfileDTO
    let markers: [HealthMarkerDTO]

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var systolicDraft: String = ""
    @State private var diastolicDraft: String = ""

    private var systolicSeries: [Trends.Point] {
        Trends.markerSeries(markers, kind: .bpSystolic)
    }
    private var diastolicSeries: [Trends.Point] {
        Trends.markerSeries(markers, kind: .bpDiastolic)
    }

    private var recent: [HealthMarkerDTO] {
        markers
            .filter { $0.kind == .bpSystolic || $0.kind == .bpDiastolic }
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("bp.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("MMHG · SYSTOLIC / DIASTOLIC")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                    Text(HealthRanges.bpContext)
                        .font(.footnote)
                        .foregroundStyle(theme.dim)
                        .padding(.top, 4)
                }

                if systolicSeries.isEmpty && diastolicSeries.isEmpty {
                    Text("No data yet.")
                        .font(.callout).foregroundStyle(theme.dim)
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .background(theme.card)
                        .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                } else {
                    Chart {
                        ForEach(systolicSeries, id: \.date) { p in
                            LineMark(x: .value("Day", p.date),
                                     y: .value("Systolic", p.value),
                                     series: .value("Series", "sys"))
                                .foregroundStyle(theme.accent)
                        }
                        ForEach(diastolicSeries, id: \.date) { p in
                            LineMark(x: .value("Day", p.date),
                                     y: .value("Diastolic", p.value),
                                     series: .value("Series", "dia"))
                                .foregroundStyle(theme.accent2)
                        }
                    }
                    .frame(height: 160)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent entries")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    if recent.isEmpty {
                        Text("Nothing logged yet.")
                            .font(.callout).foregroundStyle(theme.dim)
                    } else {
                        ForEach(recent) { m in
                            HStack {
                                Text(m.date).foregroundStyle(theme.text)
                                Spacer()
                                Text("\(Int(m.value)) \(m.kind == .bpSystolic ? "sys" : "dia")")
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(theme.accent)
                            }
                            .padding(10)
                            .background(theme.card)
                            .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Log new reading")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    HStack(spacing: 8) {
                        TextField("systolic", text: $systolicDraft)
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(theme.card)
                            .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                            .foregroundStyle(theme.text)
                            .font(.system(.callout, design: .monospaced))
                        Text("/").foregroundStyle(theme.dim)
                        TextField("diastolic", text: $diastolicDraft)
                            .keyboardType(.decimalPad)
                            .padding(10)
                            .background(theme.card)
                            .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                            .foregroundStyle(theme.text)
                            .font(.system(.callout, design: .monospaced))
                        Button { save() } label: { Text("Log") }
                            .tactile(.primary)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let sys = Double(systolicDraft), sys > 0,
              let dia = Double(diastolicDraft), dia > 0 else { return }
        let today = Dates.dayKey()
        Repos.addMarker(ctx, HealthMarkerDTO(
            userId: profile.id, date: today,
            kind: .bpSystolic, value: sys, source: "manual"
        ))
        Repos.addMarker(ctx, HealthMarkerDTO(
            userId: profile.id, date: today,
            kind: .bpDiastolic, value: dia, source: "manual"
        ))
        toasts.show(Toast(title: "BP logged",
                          detail: "\(Int(sys))/\(Int(dia)) mmHg",
                          accent: .ok, symbol: "heart.text.square.fill"))
        systolicDraft = ""
        diastolicDraft = ""
        dismiss()
    }
}

// MARK: - Weight sheet (wheel picker)

/// Dedicated weight-log sheet. Forked from the generic StatDetailSheet flow so
/// the brief's wheel-picker spec (90–350 lb, 0.5 lb increments) can live here
/// without infecting every other stat that's happy with a text field.
private struct WeightLogSheet: View {
    let profile: ProfileDTO
    let metrics: [BodyMetricDTO]
    let onSave: (Double) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var draftHalfLb: Int = 0  // weight in 0.5-lb increments; seeded in onAppear

    // 90.0 … 350.0 in 0.5 steps → 521 values
    private let minHalfLb = 180   // 90.0 lb
    private let maxHalfLb = 700   // 350.0 lb

    private var weightSeries: [Trends.Point] {
        let pts = metrics.compactMap { b -> Trends.Point? in
            guard let w = b.weightLb else { return nil }
            return Trends.Point(date: b.date, value: w)
        }
        return Trends.rollingAverage(pts, window: 7)
    }

    private var recentEntries: [StatDetailEntry] {
        metrics.compactMap { b -> StatDetailEntry? in
            guard let w = b.weightLb else { return nil }
            return StatDetailEntry(id: b.id.uuidString, dateLabel: b.date,
                                   valueLabel: String(format: "%.1f lb", w))
        }
        .reversed()
        .prefix(10)
        .map { $0 }
    }

    private var draftLb: Double {
        Double(draftHalfLb) * 0.5
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("weight.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("LB · 7-DAY AVERAGE")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                chartSection
                entriesSection
                logSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear { seedDraft() }
    }

    @ViewBuilder
    private var chartSection: some View {
        if weightSeries.isEmpty {
            VStack(spacing: 8) {
                Text("No weight logged yet.")
                    .font(.callout).foregroundStyle(theme.dim)
                Text("Spin the wheel below and tap Log to start your trend.")
                    .font(.footnote).foregroundStyle(theme.dim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(16)
            .background(theme.card)
            .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
        } else {
            Chart(weightSeries, id: \.date) { p in
                LineMark(x: .value("Day", p.date), y: .value("Weight", p.value))
                    .foregroundStyle(theme.accent)
                PointMark(x: .value("Day", p.date), y: .value("Weight", p.value))
                    .foregroundStyle(theme.accent)
            }
            .frame(height: 160)
        }
    }

    @ViewBuilder
    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent entries")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            if recentEntries.isEmpty {
                Text("Nothing logged yet.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                ForEach(recentEntries) { e in
                    HStack {
                        Text(e.dateLabel).foregroundStyle(theme.text)
                        Spacer()
                        Text(e.valueLabel)
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

    @ViewBuilder
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log new weight")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)

            HStack {
                Spacer()
                Text(String(format: "%.1f", draftLb))
                    .font(.system(size: 48, weight: .regular, design: .monospaced))
                    .foregroundStyle(theme.accent)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: draftHalfLb)
                Text("lb")
                    .font(.system(size: 18, design: .monospaced))
                    .foregroundStyle(theme.dim)
                    .padding(.leading, 4)
                Spacer()
            }

            Picker("Weight", selection: $draftHalfLb) {
                ForEach(minHalfLb...maxHalfLb, id: \.self) { half in
                    Text(String(format: "%.1f", Double(half) * 0.5))
                        .tag(half)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .background(theme.card)
            .overlay(Rectangle().stroke(theme.line, lineWidth: 1))

            Button {
                onSave(draftLb)
                dismiss()
            } label: {
                Text("Log weight").frame(maxWidth: .infinity)
            }
            .tactile(.primary)
        }
    }

    /// Seed the wheel to the most recent logged weight, otherwise the profile
    /// weight, otherwise a sensible centre (170 lb).
    private func seedDraft() {
        let lb: Double
        if let last = metrics.compactMap(\.weightLb).last {
            lb = last
        } else if profile.weightLb > 0 {
            lb = profile.weightLb
        } else {
            lb = 170
        }
        let half = Int((lb * 2).rounded())
        draftHalfLb = max(minHalfLb, min(maxHalfLb, half))
    }
}
