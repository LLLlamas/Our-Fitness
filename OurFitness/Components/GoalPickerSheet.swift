// The one goal-picker sheet: title + subtitle, one or two wheels in a card
// well, then Reset / Save.
//
// Steps (Build + Circuit) and Pilates each had their own copy of this layout.
// Circuit steps is the widest variant — two wheels (daily target + days/week),
// per-wheel all-caps labels and a `.large` detent — so the API is "a list of
// wheels" rather than a fixed one/two shape.
//
// Copy stays at the call site: the title, subtitle, wheel labels, option
// wording and the Reset button's label are all caller-supplied, because the
// shipped wording differs per card ("Reset to default" / "Reset to defaults" /
// "Reset to 3"). The success haptic on Save is part of the chrome and fires
// here, once.

import SwiftUI

public struct GoalPickerSheet: View {

    /// One wheel in the sheet. All the app's goals are integers, so the
    /// selection is an `Int` binding rather than a generic.
    public struct Wheel: Identifiable {
        public let id: String
        /// Small all-caps label above the wheel. `nil` renders no label row —
        /// the single-wheel sheets don't need one.
        public let label: String?
        /// The `Picker`'s own title; not drawn by `.wheel` style, but it is what
        /// VoiceOver reads.
        public let pickerTitle: String
        public let options: [Int]
        public let optionLabel: (Int) -> String
        public let selection: Binding<Int>
        /// Fixed wheel height. `nil` lets the wheel take its natural height
        /// (the Pilates sheet shipped that way).
        public let height: CGFloat?

        public init(
            id: String,
            label: String? = nil,
            pickerTitle: String,
            options: [Int],
            optionLabel: @escaping (Int) -> String,
            selection: Binding<Int>,
            height: CGFloat? = nil
        ) {
            self.id = id
            self.label = label
            self.pickerTitle = pickerTitle
            self.options = options
            self.optionLabel = optionLabel
            self.selection = selection
            self.height = height
        }
    }

    public let title: String
    public let subtitle: String
    public let wheels: [Wheel]
    /// Vertical padding around each wheel well: 4 on Steps, 8 on Pilates.
    public let wheelVerticalPadding: CGFloat
    public let resetLabel: String
    public let onReset: () -> Void
    public let onSave: () -> Void
    public let detents: Set<PresentationDetent>

    @Environment(\.theme) private var theme

    public init(
        title: String,
        subtitle: String,
        wheels: [Wheel],
        wheelVerticalPadding: CGFloat = 4,
        resetLabel: String,
        detents: Set<PresentationDetent> = [.medium],
        onReset: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.wheels = wheels
        self.wheelVerticalPadding = wheelVerticalPadding
        self.resetLabel = resetLabel
        self.detents = detents
        self.onReset = onReset
        self.onSave = onSave
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(theme.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(theme.dim)
            }
            .padding(.top, 28)
            .padding(.horizontal, 20)

            ForEach(wheels) { wheel in
                VStack(alignment: .leading, spacing: 4) {
                    if let label = wheel.label {
                        Text(label)
                            .font(.system(size: 10, weight: .medium)).tracking(2)
                            .foregroundStyle(theme.dim)
                            .padding(.horizontal, 20)
                    }
                    Picker(wheel.pickerTitle, selection: wheel.selection) {
                        ForEach(wheel.options, id: \.self) { value in
                            Text(wheel.optionLabel(value)).tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: wheel.height)
                    .background(theme.card2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.vertical, wheelVerticalPadding)
                }
            }

            HStack(spacing: 12) {
                Button(resetLabel) { onReset() }
                    .tactile(.secondary, fullWidth: true)
                Button("Save") {
                    onSave()
                    Haptics.success()
                }
                .tactile(.primary, fullWidth: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.bg)
    }
}
