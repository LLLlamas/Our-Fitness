// Today glance: calories, macros, steps, water -- plus the water quick-log,
// which is the one thing this screen exists to make faster than the phone.
//
// Every number is read straight off `store.today` (TodaySnapshot). The phone
// folds its SwiftData logs and sends finished figures, so nothing here
// computes anything beyond formatting and a percentage for the bars.

import SwiftUI
import WatchKit

struct WatchTodayView: View {
    @EnvironmentObject private var store: WatchSyncStore

    private struct WaterPreset: Identifiable {
        let label: String
        let flOz: Double
        var id: String { label }
    }

    /// Mirrors `Domain/Water.swift` -> `Water.presets`, which is the source of
    /// truth. That file is NOT compiled into the watch target, so the four
    /// amounts are duplicated here by hand -- change them there first.
    private let waterPresets: [WaterPreset] = [
        WaterPreset(label: "Sip", flOz: 4),
        WaterPreset(label: "S", flOz: 8),
        WaterPreset(label: "M", flOz: 16),
        WaterPreset(label: "L", flOz: 32),
    ]

    private var today: TodaySnapshot { store.today }

    var body: some View {
        Group {
            if store.hasSynced {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        caloriesSection
                        macrosRow
                        stepsSection
                        waterSection
                    }
                    .padding(.horizontal, 2)
                }
            } else {
                notSyncedState
            }
        }
        .navigationTitle("Today")
    }

    // MARK: - Not synced

    // Zeros would read as real data ("you've eaten nothing today"), so an
    // un-synced watch says so plainly instead of showing a screen of them.
    private var notSyncedState: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Not synced yet")
                .font(.headline)
            Text("Open Our Fitness on your iPhone")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Calories

    private var caloriesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(today.caloriesConsumed)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                Text("/ \(today.caloriesTarget) cal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction(Double(today.caloriesConsumed), of: Double(today.caloriesTarget)))
                .progressViewStyle(.linear)
                .tint(.orange)
        }
    }

    // MARK: - Macros

    private var macrosRow: some View {
        HStack(spacing: 0) {
            macroCell("Protein", today.proteinG, today.proteinTargetG)
            macroCell("Carbs", today.carbsG, today.carbsTargetG)
            macroCell("Fat", today.fatG, today.fatTargetG)
        }
    }

    private func macroCell(_ title: String, _ value: Int, _ target: Int) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("\(value)g")
                .font(.footnote.bold())
            Text("/ \(target)g")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label("Steps", systemImage: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(today.steps.formatted()) / \(today.stepsGoal.formatted())")
                    .font(.caption.bold())
            }
            ProgressView(value: fraction(Double(today.steps), of: Double(today.stepsGoal)))
                .progressViewStyle(.linear)
                .tint(.green)
        }
    }

    // MARK: - Water

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Water", systemImage: "drop.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Text("\(ozText(today.waterFlOz)) / \(ozText(today.waterGoalFlOz)) oz")
                    .font(.caption.bold())
            }
            ProgressView(value: fraction(today.waterFlOz, of: today.waterGoalFlOz))
                .progressViewStyle(.linear)
                .tint(.blue)

            // Tap-to-repeat, mirroring the phone's quick-log FAB.
            if let last = today.waterLastFlOz, last > 0 {
                Button {
                    logWater(last)
                } label: {
                    Label("Again \(ozText(last)) oz", systemImage: "arrow.counterclockwise")
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }

            // 2x2 so each preset keeps a full-width-half tap target on a 40mm.
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    presetButton(waterPresets[0])
                    presetButton(waterPresets[1])
                }
                HStack(spacing: 4) {
                    presetButton(waterPresets[2])
                    presetButton(waterPresets[3])
                }
            }
        }
    }

    private func presetButton(_ preset: WaterPreset) -> some View {
        Button {
            logWater(preset.flOz)
        } label: {
            VStack(spacing: 0) {
                Text(preset.label)
                    .font(.footnote.bold())
                Text("\(ozText(preset.flOz)) oz")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private func logWater(_ flOz: Double) {
        WKInterfaceDevice.current().play(.success)
        store.send(.logWater(flOz: flOz, date: Date()))
    }

    // MARK: - Formatting

    /// 0...1 fill for a progress bar, safe when the phone hasn't sent a goal.
    private func fraction(_ value: Double, of total: Double) -> Double {
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    /// Whole ounces read better on a wrist; only show a decimal if there is one.
    private func ozText(_ flOz: Double) -> String {
        flOz == flOz.rounded() ? "\(Int(flOz))" : String(format: "%.1f", flOz)
    }
}
