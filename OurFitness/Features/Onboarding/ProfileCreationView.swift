// First-launch + add-profile flow. Collects vitals, computes targets, persists
// the profile, then offers Apple Health connection as a final step before
// handing off to the shell.

import SwiftUI
import SwiftData

struct ProfileCreationView: View {
    let onCreate: (ProfileDTO) -> Void

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var step: Step = .vitals
    @State private var name: String = ""
    @State private var mode: Mode = .build
    @State private var sex: Sex = .male
    @State private var heightIn: Double = 67
    @State private var weightLb: Double = 150
    @State private var age: Int = 30
    @State private var activity: ActivityLevel = .moderate
    @State private var requesting = false
    @State private var created: ProfileDTO?

    private enum Step { case vitals, connectHealth }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && heightIn > 0 && weightLb > 0 && age > 0
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(step == .vitals ? "new profile." : "connect health.")
                    .font(.system(size: 48, weight: .regular))
                    .foregroundStyle(theme.text)

                switch step {
                case .vitals:        vitalsForm
                case .connectHealth: connectStep
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .themed(mode)
    }

    // MARK: - Vitals

    @ViewBuilder
    private var vitalsForm: some View {
        labeledField("Name") {
            TextField("e.g. Lorenzo", text: $name)
                .textInputAutocapitalization(.words)
                .padding(10)
                .background(theme.card)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }

        Text("Mode").font(.caption).tracking(2).foregroundStyle(theme.dim)
        ForEach(Mode.allCases, id: \.self) { m in
            PressableCard(action: { mode = m }) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: mode == m ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(m.displayName)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text(modeBlurb(m))
                            .font(.callout).foregroundStyle(theme.dim)
                    }
                    Spacer(minLength: 0)
                }
            }
        }

        Text("Sex").font(.caption).tracking(2).foregroundStyle(theme.dim).padding(.top, 4)
        HStack(spacing: 8) {
            ForEach(Sex.allCases, id: \.self) { s in
                Button {
                    sex = s
                } label: {
                    Text(s.rawValue.capitalized)
                }
                .tactile(.pill, fill: sex == s ? theme.accent : nil)
            }
        }

        labeledField("Height (in)") {
            TextField("", value: $heightIn, format: .number)
                .keyboardType(.decimalPad)
                .padding(10).background(theme.card)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }

        labeledField("Weight (lb)") {
            TextField("", value: $weightLb, format: .number)
                .keyboardType(.decimalPad)
                .padding(10).background(theme.card)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }

        labeledField("Age") {
            TextField("", value: $age, format: .number)
                .keyboardType(.numberPad)
                .padding(10).background(theme.card)
                .overlay(Rectangle().stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }

        Text("Activity").font(.caption).tracking(2).foregroundStyle(theme.dim).padding(.top, 4)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityLevel.allCases, id: \.self) { a in
                    Button {
                        activity = a
                    } label: {
                        Text(a.label)
                    }
                    .tactile(.pill, fill: activity == a ? theme.accent2 : nil)
                }
            }
        }

        Button {
            submit()
        } label: {
            Text("Create profile")
        }
        .tactile(.primary, fullWidth: true)
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.6)
        .padding(.top, 8)
    }

    private func submit() {
        let dto = Repos.createProfile(
            ctx,
            name: name.trimmingCharacters(in: .whitespaces),
            mode: mode, sex: sex,
            heightIn: heightIn, weightLb: weightLb, age: age,
            activity: activity
        )
        created = dto
        step = .connectHealth
    }

    // MARK: - Connect Health step

    @ViewBuilder
    private var connectStep: some View {
        Text("Steps, weight, resting heart rate, and active energy sync from Apple Health — including Apple Watch. You'll toggle each metric in the system sheet.")
            .font(.callout).foregroundStyle(theme.dim)
            .padding(.bottom, 8)

        Button {
            Task { await connect(grant: true) }
        } label: {
            Text(requesting ? "Opening Apple Health…" : "Connect Apple Health")
        }
        .tactile(.primary, fullWidth: true)
        .disabled(requesting)

        Button {
            finish(granted: false)
        } label: {
            Text("Skip for now")
        }
        .tactile(.ghost)
        .padding(.top, 4)
    }

    private func connect(grant: Bool) async {
        requesting = true
        let result = await HealthKitService.shared.requestAuthorization()
        requesting = false
        finish(granted: result.isGranted)
    }

    private func finish(granted: Bool) {
        guard let dto = created else { return }
        if granted {
            Repos.setHealthGranted(ctx, profileId: dto.id, granted: true)
        }
        onCreate(dto)
        dismiss()
    }

    // MARK: - Helpers

    @ViewBuilder
    private func labeledField<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 10)).tracking(2)
                .foregroundStyle(theme.dim)
            content()
        }
    }

    private func modeBlurb(_ m: Mode) -> String {
        switch m {
        case .build:   return "Gain lean mass, fuel hoops. Calorie surplus + hypertrophy."
        case .circuit: return "Drop weight, fix the markers. Steps, cardio, Pilates."
        }
    }
}
