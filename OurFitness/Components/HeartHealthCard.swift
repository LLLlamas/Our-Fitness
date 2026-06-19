// Circuit-only cardiometabolic panel: the four heart-health targets that Targets
// computes for Circuit but that nothing rendered until now — a fiber FLOOR to
// reach and sodium / added-sugar / saturated-fat CAPS to stay under.
//
// Fiber comes from every curated food, so that bar fills as you log. The three
// caps fill from scanned nutrition labels (the camera log) — until then they sit
// low, which for a cap reads as "well under," exactly what you want. The footnote
// makes that honest. Gated to Circuit by the caller; also no-ops if no caps exist.

import SwiftUI

public struct HeartHealthCard: View {
    public let totals: DailyTotals
    public let targets: MacroTargets
    public let profile: ProfileDTO

    @Environment(\.theme) private var theme
    @State private var showInfo = false

    public init(totals: DailyTotals, targets: MacroTargets, profile: ProfileDTO) {
        self.totals = totals
        self.targets = targets
        self.profile = profile
    }

    public var body: some View {
        // Only render when this profile actually has the Circuit caps configured.
        if targets.fiberGMin != nil || targets.sodiumMgMax != nil
            || targets.addedSugarGMax != nil || targets.saturatedFatGMax != nil {
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("HEART-HEALTH TARGETS")
                            .font(.system(size: 10, weight: .medium)).tracking(2)
                            .foregroundStyle(theme.dim)
                        Spacer()
                        Button { showInfo = true } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.dim)
                        }
                        .tactile(.ghost)
                        .accessibilityLabel("Heart-health targets info")
                    }

                    if let fiberMin = targets.fiberGMin {
                        ProgressBar(value: Double(totals.fiberG), target: Double(fiberMin),
                                    label: "Fiber", unit: "g")
                    }
                    if let sodiumMax = targets.sodiumMgMax {
                        ProgressBar(value: Double(totals.sodiumMg), target: Double(sodiumMax),
                                    label: "Sodium", unit: "mg", inverted: true)
                    }
                    if let sugarMax = targets.addedSugarGMax {
                        ProgressBar(value: Double(totals.addedSugarG), target: Double(sugarMax),
                                    label: "Added sugar", unit: "g", inverted: true)
                    }
                    if let satFatMax = targets.saturatedFatGMax {
                        ProgressBar(value: Double(totals.saturatedFatG), target: Double(satFatMax),
                                    label: "Saturated fat", unit: "g", inverted: true)
                    }

                    Text("Fiber fills in as you log. Sodium, added sugar, and saturated fat fill in from scanned nutrition labels — staying low keeps you under your caps.")
                        .font(.caption2)
                        .foregroundStyle(theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .sheet(isPresented: $showInfo) {
                HeartHealthInfoSheet(profile: profile)
                    .themed(profile.mode)
            }
        }
    }
}

// MARK: - Info sheet

private struct HeartHealthInfoSheet: View {
    let profile: ProfileDTO

    @Environment(\.theme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("heart health.")
                        .font(.system(size: 38, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("YOUR CIRCUIT TARGETS")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                Text(TargetRationale.goalLine(for: profile.mode))
                    .font(.callout).foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)

                section("Fiber — reach the floor", TargetRationale.fiberWhy(for: profile))
                section("Sodium — stay under", TargetRationale.sodiumWhy(for: profile))
                section("Added sugar — stay under", TargetRationale.addedSugarWhy(for: profile))
                section("Saturated fat — stay under", TargetRationale.saturatedFatWhy(for: profile))

                Text("These are practical starting targets aligned with DASH and American Heart Association guidance for blood pressure and cholesterol. Individual needs vary — your doctor's advice comes first.")
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption).tracking(2).foregroundStyle(theme.dim)
            Text(body)
                .font(.callout).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
