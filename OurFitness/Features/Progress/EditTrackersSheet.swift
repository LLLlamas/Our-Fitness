// Add/remove any progress tracker. Mode defaults are pre-checked, but every
// StatKind is available to either mode — toggling persists per-profile
// (see ProgressTabView.enabledStatsRaw). Changes apply live as you toggle.

import SwiftUI

struct EditTrackersSheet: View {
    let mode: Mode
    let onChange: (Set<String>) -> Void

    @Environment(\.theme) private var theme
    @State private var enabled: Set<String>

    init(enabled: Set<String>, mode: Mode, onChange: @escaping (Set<String>) -> Void) {
        self._enabled = State(initialValue: enabled)
        self.mode = mode
        self.onChange = onChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("trackers.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("SHOW OR HIDE ANY METRIC")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                ForEach(StatKind.allCases) { kind in
                    row(kind)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func row(_ kind: StatKind) -> some View {
        let isOn = enabled.contains(kind.rawValue)
        Button {
            if isOn { enabled.remove(kind.rawValue) } else { enabled.insert(kind.rawValue) }
            onChange(enabled)
            Haptics.selection()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.text)
                    if kind.isRelevant(for: mode) {
                        Text("Default for \(mode.displayName)")
                            .font(.caption2).foregroundStyle(theme.dim)
                    }
                }
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? theme.accent : theme.dim)
            }
            .padding(12)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        }
        .tactile(.ghost)
        .accessibilityLabel("\(kind.title), \(isOn ? "shown" : "hidden")")
    }
}
