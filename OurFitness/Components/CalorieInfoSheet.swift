// Shared "what's a calorie / how we estimate burn" explainer.
//
// One combined sheet with two plain-language sections — calories, then the MET
// math behind our burn estimate — surfaced by a small ⓘ on calorie/burn
// surfaces (the Move card, workout figures). Reuses the same medium-detent,
// themed-sheet pattern as MacroInfoSheet so the info affordance feels uniform.
//
// Calorie copy says "cal" everywhere else in the UI; this sheet is the one place
// we're allowed to spell out the kcal equivalence.

import SwiftUI

public struct CalorieInfoSheet: View {
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section(
                    "What's a calorie?",
                    "“cal” is the everyday unit on food labels — the energy in what you "
                    + "eat and what you burn. One “cal” here equals one kilocalorie (kcal), "
                    + "the scientific unit, so the number you see matches the one on the "
                    + "back of the packet. We write it as “cal” throughout the app to keep "
                    + "things familiar."
                )
                section(
                    "How we estimate burn (MET)",
                    "A MET is simply a multiple of resting energy: sitting still is 1 MET, "
                    + "and brisk walking is about 4.3 METs — roughly four times the energy. "
                    + "We turn that into calories with a standard formula:\n\n"
                    + "calories ≈ MET × your body weight × time\n\n"
                    + "Because it uses the weight in your profile, a heavier body shows a "
                    + "higher burn for the same activity. We add up your steps and logged "
                    + "training this way for the “MET estimate”."
                )
                section(
                    "Two numbers on the Move card",
                    "Apple Health’s active energy is measured by your Watch or iPhone for "
                    + "the whole day. Our MET estimate is calculated from your steps and "
                    + "logged training, so a science-based figure sits right beside the "
                    + "measured one. They won’t match exactly — that’s expected."
                )
                Text("MET values: Ainsworth BE et al., 2011 Compendium of Physical Activities.")
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func section(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption).tracking(2)
                .foregroundStyle(theme.dim)
            Text(body)
                .font(.callout)
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Drop-in ⓘ button that opens `CalorieInfoSheet`. Keeps the calorie/burn
/// surfaces to a single line. Follows the tactile + medium-detent info-button
/// rules (ghost button, `.sheet`, never a popover).
public struct CalorieInfoButton: View {
    @State private var show = false
    @Environment(\.theme) private var theme
    private let size: CGFloat

    public init(size: CGFloat = 11) { self.size = size }

    public var body: some View {
        Button { show = true } label: {
            Image(systemName: "info.circle")
                .font(.system(size: size))
                .foregroundStyle(theme.dim)
        }
        .tactile(.ghost)
        .accessibilityLabel("About calories and burn estimates")
        .sheet(isPresented: $show) {
            CalorieInfoSheet().themed(theme.mode)
        }
    }
}
