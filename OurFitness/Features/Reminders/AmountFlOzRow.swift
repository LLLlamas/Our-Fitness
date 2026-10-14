// The "Amount / [field] / fl oz" row, shared by AddReminderSheet's readout and
// ReminderDetailSheet's watering block — the two were byte-identical.
//
// Focus is passed in as a @FocusState.Binding rather than owned here, so the
// parent's keyboard-toolbar Done button (and the detail sheet's
// commit-on-losing-focus) keep working exactly as before.

import SwiftUI

struct AmountFlOzRow: View {
    @Binding var amountFlOz: Double
    @FocusState.Binding var isEditing: Bool

    @Environment(\.theme) private var theme

    /// Non-numeric input leaves the value untouched rather than zeroing it.
    private var textBinding: Binding<String> {
        Binding(
            get: { PlantCatalog.amountLabel(amountFlOz) },
            set: { amountFlOz = Double($0) ?? amountFlOz }
        )
    }

    var body: some View {
        HStack {
            Text("Amount").foregroundStyle(theme.dim)
            Spacer()
            TextField("fl oz", text: textBinding)
                .keyboardType(.decimalPad)
                .focused($isEditing)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(theme.text)
                .frame(width: 56)
            Text("fl oz").foregroundStyle(theme.dim)
        }
    }
}
