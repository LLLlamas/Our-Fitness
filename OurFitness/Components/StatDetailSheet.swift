// Sheet that opens from a StatCard. Shows: header, optional headline block,
// sparkline, recent entries, and a "log new value" form. The host view supplies
// a small descriptor so this sheet stays agnostic of which marker/metric it's
// editing.
//
// Metric-specific bits come in as slots (`headline`, `chartOverride`,
// `logOverride`, `footer`) rather than as whole bespoke sheets — Weight's wheel
// picker, Blood pressure's two-series chart and two-field form, and Body fat's
// composition block + reference tables all plug in here, so the chrome
// (header / empty state / entries list / card styling) exists exactly once.

import SwiftUI
import Charts

public struct StatDetailEntry: Identifiable, Equatable {
    public let id: String
    public let dateLabel: String
    public let valueLabel: String
    public init(id: String, dateLabel: String, valueLabel: String) {
        self.id = id
        self.dateLabel = dateLabel
        self.valueLabel = valueLabel
    }
}

/// One label/value row in the detail-sheet idiom. Used by the recent-entries
/// list and by the reference-range tables in the Progress sheets, so the row
/// chrome is defined once.
public struct StatDetailRow: View {
    public let label: String
    public let value: String

    @Environment(\.theme) private var theme

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(theme.text)
            Spacer()
            Text(value)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(theme.accent)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

public struct StatDetailSheet<Headline: View, ChartOverride: View, LogOverride: View, Footer: View>: View {
    public let title: String
    public let unit: String
    public let series: [Trends.Point]
    public let entries: [StatDetailEntry]
    public let placeholder: String
    public let logTitle: String
    public let logCopy: String
    public let canLog: Bool
    /// False for computed metrics (BMI, training volume) that have no entry list
    /// of their own — avoids an empty "Recent entries · nothing logged" block.
    public let showsEntries: Bool
    /// Points required before the chart is drawn. 2 for metrics where a single
    /// dot says nothing (body fat, BMI).
    public let minChartPoints: Int
    public let emptyChartText: String
    public let emptyChartDetail: String?
    /// Optional one-line reference range, e.g. "Optimal: <100 mg/dL (NCEP)".
    /// Shown directly under the header. Nil for non-medical metrics.
    public let rangeContext: String?
    /// Optional plain-English "what your latest number means + what moves it",
    /// personalized to the user's value and goal. Shown in a card under the chart.
    public let personalNote: String?
    public let detents: Set<PresentationDetent>
    /// Rejects a parsed draft before it reaches `onSave` (default: any positive).
    public let validate: (Double) -> Bool
    /// Receives the parsed numeric value. Caller persists + fires toast.
    public let onSave: (Double) -> Void

    private let headline: Headline
    private let chartOverride: ChartOverride
    private let logOverride: LogOverride
    private let footer: Footer

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    @FocusState private var fieldFocused: Bool

    public init(
        title: String,
        unit: String,
        series: [Trends.Point] = [],
        entries: [StatDetailEntry] = [],
        placeholder: String = "",
        logTitle: String = "Log new value",
        logCopy: String = "Log",
        canLog: Bool = true,
        showsEntries: Bool = true,
        minChartPoints: Int = 1,
        emptyChartText: String = "No data yet.",
        emptyChartDetail: String? = nil,
        rangeContext: String? = nil,
        personalNote: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        validate: @escaping (Double) -> Bool = { $0 > 0 },
        onSave: @escaping (Double) -> Void = { _ in },
        @ViewBuilder headline: () -> Headline = { EmptyView() },
        @ViewBuilder chartOverride: () -> ChartOverride = { EmptyView() },
        @ViewBuilder logOverride: () -> LogOverride = { EmptyView() },
        @ViewBuilder footer: () -> Footer = { EmptyView() }
    ) {
        self.title = title
        self.unit = unit
        self.series = series
        self.entries = entries
        self.placeholder = placeholder
        self.logTitle = logTitle
        self.logCopy = logCopy
        self.canLog = canLog
        self.showsEntries = showsEntries
        self.minChartPoints = minChartPoints
        self.emptyChartText = emptyChartText
        self.emptyChartDetail = emptyChartDetail
        self.rangeContext = rangeContext
        self.personalNote = personalNote
        self.detents = detents
        self.validate = validate
        self.onSave = onSave
        self.headline = headline()
        self.chartOverride = chartOverride()
        self.logOverride = logOverride()
        self.footer = footer()
    }

    /// A slot the host left empty. Checked on the type, not the value.
    private var hasChartOverride: Bool { ChartOverride.self != EmptyView.self }
    private var hasLogOverride: Bool { LogOverride.self != EmptyView.self }

    public var body: some View {
        // The keyboard toolbar belongs to the built-in decimal field. Hosts that
        // supply their own log form own their own focus state (and toolbar), so
        // adding one here too would stack a dead "Done" on top of theirs.
        Group {
            if hasLogOverride {
                scroll
            } else {
                scroll.toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { fieldFocused = false }
                    }
                }
            }
        }
        .presentationDetents(detents)
        .presentationBackground(theme.bg)
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                headline
                if let personalNote { noteCard(personalNote) }
                chartSection
                if showsEntries { entriesSection }
                if canLog { logSection }
                footer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.lowercased() + ".")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(theme.text)
            Text(unit.uppercased())
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            if let rangeContext {
                Text(rangeContext)
                    .font(.footnote)
                    .foregroundStyle(theme.dim)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func noteCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.fill")
                .font(.system(size: 11))
                .foregroundStyle(theme.accent)
                .padding(.top, 2)
            Text(text)
                .font(.callout)
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private var chartSection: some View {
        if series.count < max(1, minChartPoints) {
            VStack(spacing: 8) {
                Text(emptyChartText)
                    .font(.callout).foregroundStyle(theme.dim)
                if let emptyChartDetail {
                    Text(emptyChartDetail)
                        .font(.footnote).foregroundStyle(theme.dim)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 120)
            .padding(16)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        } else if hasChartOverride {
            chartOverride
        } else {
            Chart(series, id: \.date) { p in
                LineMark(x: .value("Day", p.date), y: .value("Value", p.value))
                    .foregroundStyle(theme.accent)
                PointMark(x: .value("Day", p.date), y: .value("Value", p.value))
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
            if entries.isEmpty {
                Text("Nothing logged yet.")
                    .font(.callout).foregroundStyle(theme.dim)
            } else {
                ForEach(entries) { e in
                    StatDetailRow(label: e.dateLabel, value: e.valueLabel)
                }
            }
        }
    }

    @ViewBuilder
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(logTitle)
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            if hasLogOverride {
                logOverride
            } else {
                HStack(spacing: 8) {
                    TextField(placeholder, text: $draft)
                        .keyboardType(.decimalPad)
                        .focused($fieldFocused)
                        .padding(10)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                        .foregroundStyle(theme.text)
                        .font(.system(.callout, design: .monospaced))
                    Button {
                        guard let n = Double(draft), validate(n) else { return }
                        onSave(n)
                        draft = ""
                        dismiss()
                    } label: {
                        Text(logCopy)
                    }
                    .tactile(.primary)
                }
            }
        }
    }
}
