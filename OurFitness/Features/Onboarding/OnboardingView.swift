import SwiftUI

struct OnboardingView: View {
    let onCreate: (ProfileDTO) -> Void

    @Environment(\.theme) private var theme

    @State private var name: String = ""
    @State private var mode: Mode = .build
    @State private var sex: Sex = .male
    @State private var heightIn: Double = 67
    @State private var weightLb: Double = 150
    @State private var age: Int = 30
    @State private var activity: ActivityLevel = .moderate
    @State private var lowAppetite: Bool = false
    @State private var restrictionsCsv: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("welcome.")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(theme.text)
                Text("Tell us about yourself. Two minutes. You can change anything later.")
                    .foregroundStyle(theme.dim)
                    .padding(.bottom, 12)

                field("Name") {
                    TextField("Lorenzo", text: $name)
                        .textInputAutocapitalization(.words)
                }

                field("Mode") {
                    HStack(spacing: 8) {
                        modeButton(.build, "Build — gain, fuel, play")
                        modeButton(.reset, "Reset — drop, fix markers")
                    }
                }
                .sensoryFeedback(.selection, trigger: mode)

                HStack(spacing: 12) {
                    field("Sex") {
                        Picker("", selection: $sex) {
                            Text("Male").tag(Sex.male)
                            Text("Female").tag(Sex.female)
                        }.pickerStyle(.segmented)
                    }
                    field("Age") {
                        TextField("30", value: $age, format: .number)
                            .keyboardType(.numberPad)
                    }
                }
                .sensoryFeedback(.selection, trigger: sex)

                HStack(spacing: 12) {
                    field("Height (in)") {
                        TextField("67", value: $heightIn, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    field("Weight (lb)") {
                        TextField("150", value: $weightLb, format: .number)
                            .keyboardType(.decimalPad)
                    }
                }

                field("Activity") {
                    Picker("", selection: $activity) {
                        ForEach(ActivityLevel.allCases, id: \.self) { a in
                            Text(a.label).tag(a)
                        }
                    }.pickerStyle(.menu)
                }
                .sensoryFeedback(.selection, trigger: activity)

                if mode == .build {
                    field("Low appetite?") {
                        Toggle("Bias toward liquids + frequency", isOn: $lowAppetite)
                            .foregroundStyle(theme.text)
                    }
                }

                field("Restrictions (comma-separated, e.g. peanut, tree-nut)") {
                    TextField("none", text: $restrictionsCsv)
                        .textInputAutocapitalization(.never)
                }

                Button(action: submit) {
                    Text("Let's go →")
                }
                .tactile(.primary, fullWidth: true)
                .disabled(!canSubmit)
                .padding(.top, 16)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 36)
        }
        .background(theme.bg.ignoresSafeArea())
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && weightLb > 0 && heightIn > 0 && age > 0
    }

    private func submit() {
        let vitals = Targets.ProfileVitals(
            sex: sex, weightLb: weightLb, heightIn: heightIn, age: age, activity: activity
        )
        let targets = Targets.compute(mode: mode, vitals: vitals)
        let restrictions = restrictionsCsv
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let dto = ProfileDTO(
            name: name.trimmingCharacters(in: .whitespaces),
            mode: mode, sex: sex,
            heightIn: heightIn, weightLb: weightLb, age: age,
            activity: activity,
            lowAppetite: lowAppetite,
            restrictions: restrictions,
            computedTargets: targets
        )
        onCreate(dto)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10)).tracking(2)
                .foregroundStyle(theme.dim)
            content()
                .padding(10)
                .background(theme.card)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }
    }

    @ViewBuilder
    private func modeButton(_ m: Mode, _ label: String) -> some View {
        Button { mode = m } label: {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tactile(.pill, fill: mode == m ? theme.accent : nil)
    }
}
