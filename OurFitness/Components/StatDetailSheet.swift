// Sheet that opens from a StatCard. Shows: sparkline, recent entries,
// and a "log new value" form. The host view supplies a small descriptor
// so this sheet stays agnostic of which marker/metric it's editing.

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

public struct StatDetailSheet: View {
    public let title: String
    public let unit: String
    public let series: [Trends.Point]
    public let entries: [StatDetailEntry]
    public let placeholder: String
    public let logCopy: String
    public let canLog: Bool
    /// Optional one-line reference range, e.g. "Optimal: <100 mg/dL (NCEP)".
    /// Shown directly under the header. Nil for non-medical metrics.
    public let rangeContext: String?
    /// Receives the parsed numeric value. Caller persists + fires toast.
    public let onSave: (Double) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""

    public init(
        title: String,
        unit: String,
        series: [Trends.Point],
        entries: [StatDetailEntry],
        placeholder: String,
        logCopy: String = "Log",
        canLog: Bool = true,
        rangeContext: String? = nil,
        onSave: @escaping (Double) -> Void
    ) {
        self.title = title
        self.unit = unit
        self.series = series
        self.entries = entries
        self.placeholder = placeholder
        self.logCopy = logCopy
        self.canLog = canLog
        self.rangeContext = rangeContext
        self.onSave = onSave
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                chartSection
                entriesSection
                if canLog { logSection }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(theme.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
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
    private var chartSection: some View {
        if series.isEmpty {
            Text("No data yet.")
                .font(.callout).foregroundStyle(theme.dim)
                .frame(maxWidth: .infinity, minHeight: 120)
                .background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
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
                    HStack {
                        Text(e.dateLabel).foregroundStyle(theme.text)
                        Spacer()
                        Text(e.valueLabel)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(theme.accent)
                    }
                    .padding(10)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Log new value")
                .font(.caption).tracking(2).textCase(.uppercase)
                .foregroundStyle(theme.dim)
            HStack(spacing: 8) {
                TextField(placeholder, text: $draft)
                    .keyboardType(.decimalPad)
                    .padding(10)
                    .background(theme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    .foregroundStyle(theme.text)
                    .font(.system(.callout, design: .monospaced))
                Button {
                    guard let n = Double(draft), n > 0 else { return }
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
