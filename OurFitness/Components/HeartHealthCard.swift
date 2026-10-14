// Circuit-only cardiometabolic panel: the four heart-health targets that Targets
// computes for Circuit — a fiber FLOOR to reach and sodium / added-sugar /
// saturated-fat CAPS to stay under.
//
// Fiber comes from every curated food, so that bar fills as you log and behaves
// like any other ProgressBar. The three caps do NOT exist in the curated food
// database or the USDA table behind it — only a scanned nutrition label supplies
// them. A progress bar drawn off those totals therefore showed "0 / 1500 mg" and
// coloured itself safely under the cap for someone who had eaten 3,000 mg, which
// is the one reading this mode must never give.
//
// So the caps render off `MacroBudget.capCoverage`, not off the raw total:
//   .none    → no bar, no number: an em-dash against the cap, "not tracked".
//   .partial → a floor figure ("at least 480 / 1500mg"), still no bar — a bar
//              would colour a verdict onto a number we know is incomplete.
//   .full    → the real bar, every logged food measured.
// Gated to Circuit by the caller; also no-ops if no caps exist.

import SwiftUI

public struct HeartHealthCard: View {
    public let totals: DailyTotals
    public let targets: MacroTargets
    public let profile: ProfileDTO
    /// The day's log, used only to tell "no data for what you ate" from "you ate
    /// very little". Omit it and coverage falls back to what the summed totals can
    /// prove, which is never `.full` — see `MacroBudget.capCoverage(totals:)`.
    public let entries: [FoodLogEntryDTO]

    @Environment(\.theme) private var theme
    @State private var showInfo = false

    public init(totals: DailyTotals, targets: MacroTargets, profile: ProfileDTO,
                entries: [FoodLogEntryDTO] = []) {
        self.totals = totals
        self.targets = targets
        self.profile = profile
        self.entries = entries
    }

    private var coverage: MacroBudget.CapCoverage {
        entries.isEmpty
            ? MacroBudget.capCoverage(totals: totals)
            : MacroBudget.capCoverage(entries: entries)
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

                    // Fiber is in every curated food — unchanged, a real bar.
                    if let fiberMin = targets.fiberGMin {
                        ProgressBar(value: Double(totals.fiberG), target: Double(fiberMin),
                                    label: "Fiber", unit: "g")
                    }

                    if let sodiumMax = targets.sodiumMgMax {
                        capRow("Sodium", measured: totals.sodiumMg, cap: sodiumMax, unit: "mg")
                    }
                    if let sugarMax = targets.addedSugarGMax {
                        capRow("Added sugar", measured: totals.addedSugarG, cap: sugarMax, unit: "g")
                    }
                    if let satFatMax = targets.saturatedFatGMax {
                        capRow("Saturated fat", measured: totals.saturatedFatG,
                               cap: satFatMax, unit: "g")
                    }

                    Text(footnote)
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

    // MARK: - Cap rows

    /// One capped nutrient. A real bar only when every logged food was measured;
    /// otherwise a figure we can stand behind, or none at all.
    @ViewBuilder
    private func capRow(_ label: String, measured: Int, cap: Int, unit: String) -> some View {
        switch coverage.level {
        case .full:
            ProgressBar(value: Double(measured), target: Double(cap),
                        label: label, unit: unit, inverted: true)
        case .partial:
            // Floor, not a total: the unmeasured foods can only push it up.
            unmeasuredRow(label, value: "\(measured)+", cap: cap, unit: unit,
                          accessibility: "at least \(measured)\(unit) of \(cap)\(unit)")
        case .none:
            unmeasuredRow(label, value: nil, cap: cap, unit: unit,
                          accessibility: "not tracked, cap \(cap)\(unit)")
        }
    }

    /// Bar-less row in the ProgressBar header's own layout — deliberately no
    /// track and no fill colour, because both would read as a verdict on a
    /// number we can't stand behind. `value == nil` prints an em-dash: no figure
    /// at all, with the cap still visible beside it.
    private func unmeasuredRow(_ label: String, value: String?, cap: Int, unit: String,
                               accessibility: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(2)
                .foregroundStyle(theme.dim)
            Spacer()
            HStack(spacing: 4) {
                Text(value ?? "—")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(value == nil ? theme.dim : theme.text)
                Text("/ \(cap)\(unit)")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.dim)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(accessibility)")
    }

    /// Footnote tracks the rows above it, so it never promises a number the card
    /// isn't showing.
    private var footnote: String {
        let fiberLine = targets.fiberGMin != nil ? "Fiber fills in as you log. " : ""
        switch coverage.level {
        case .full:
            return fiberLine + "Sodium, added sugar, and saturated fat come from the nutrition labels you scanned — staying under the caps is the goal."
        case .partial:
            let missing = coverage.unmeasuredEntries
            let gap = missing > 0
                ? "\(missing) of \(coverage.entryCount) foods you logged carry no label data"
                : "some of the foods you logged carry no label data"
            return fiberLine + "Sodium, added sugar, and saturated fat only come from scanned nutrition labels, and \(gap) — so these three are minimums, not your real intake."
        case .none:
            return fiberLine + "Sodium, added sugar, and saturated fat aren't in the food library, so nothing you logged measured them — scan a nutrition label and they'll start tracking against your caps."
        }
    }
}

// MARK: - Info sheet

private struct HeartHealthInfoSheet: View {
    let profile: ProfileDTO

    @Environment(\.theme) private var theme

    var body: some View {
        InfoSheetScaffold(
            title: "Heart health",
            subtitle: "YOUR CIRCUIT TARGETS",
            titleSize: 38,
            dragIndicator: true
        ) {
            Text(TargetRationale.goalLine(for: profile.mode))
                .font(.callout).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)

            section("Fiber — reach the floor", TargetRationale.fiberWhy(for: profile))
            section("Sodium — stay under", TargetRationale.sodiumWhy(for: profile))
            section("Added sugar — stay under", TargetRationale.addedSugarWhy(for: profile))
            section("Saturated fat — stay under", TargetRationale.saturatedFatWhy(for: profile))

            InfoFootnote("These are practical starting targets aligned with DASH and American Heart Association guidance for blood pressure and cholesterol. Individual needs vary — your doctor's advice comes first.")
        }
    }

    // Every section here is "heading + one paragraph", so this wraps the shared
    // `InfoSection` rather than repeating its content closure four times.
    @ViewBuilder
    private func section(_ title: String, _ body: String) -> some View {
        InfoSection(title: title) {
            Text(body)
                .font(.callout).foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
