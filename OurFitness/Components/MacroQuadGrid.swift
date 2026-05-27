import SwiftUI

public struct MacroQuadGrid: View {
    public let totals: DailyTotals
    public let targets: MacroTargets

    public init(totals: DailyTotals, targets: MacroTargets) {
        self.totals = totals
        self.targets = targets
    }

    public var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2),
            spacing: 14
        ) {
            ProgressBar(value: Double(totals.calories), target: Double(targets.calories), label: "Calories")
            ProgressBar(value: Double(totals.proteinG), target: Double(targets.proteinG), label: "Protein", unit: "g")
            ProgressBar(value: Double(totals.carbsG),   target: Double(targets.carbsG),   label: "Carbs",   unit: "g")
            ProgressBar(value: Double(totals.fatG),     target: Double(targets.fatG),     label: "Fat",     unit: "g")
        }
    }
}
