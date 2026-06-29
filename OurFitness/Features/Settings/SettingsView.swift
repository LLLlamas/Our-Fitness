import SwiftUI
import SwiftData

struct SettingsView: View {
    let profile: ProfileDTO
    @ObservedObject var health: HealthKitService

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var showModeSwitch = false
    @State private var showEditVitals = false

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial
    @AppStorage("nudge.meal.enabled") private var mealNudgeEnabled: Bool = true
    @AppStorage("nudge.water.enabled") private var waterNudgeEnabled: Bool = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Settings")
                        .font(.system(size: 48, weight: .regular))
                        .foregroundStyle(theme.text)

                    section("Apple Health") {
                        PressableCard(action: connectHealth) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(HealthAccess.statusLabel(healthGranted: profile.healthGranted))
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(theme.text)
                                    Text(profile.healthGranted
                                         ? "Tap to manage per-metric toggles in Settings.app"
                                         : "Tap to grant access")
                                        .font(.caption).foregroundStyle(theme.dim)
                                }
                                Spacer()
                                Image(systemName: profile.healthGranted ? "checkmark.circle.fill" : "heart.text.square")
                                    .foregroundStyle(theme.accent)
                            }
                        }
                    }

                    section("Mode") {
                        modeRow
                    }

                    section("Profile") {
                        labeled("Name", profile.name)
                    }

                    section("Body") {
                        bodyRow
                    }

                    section("Units") {
                        unitsRow
                    }

                    section("Reminders") {
                        remindersSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .scrollHapticTicks()
            }
            .background(theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .tactile(.ghost)
                }
            }
        }
        .themed(profile.mode)
        .sheet(isPresented: $showModeSwitch) {
            // Themed to the destination mode so the sheet previews the palette
            // you're switching into.
            ModeSwitchSheet(profile: profile, onConfirm: switchMode)
                .themed(profile.mode.toggled)
        }
        .sheet(isPresented: $showEditVitals) {
            EditVitalsSheet(profile: profile, unitSystem: unitSystem, onSave: saveVitals)
                .themed(profile.mode)
        }
    }

    @ViewBuilder
    private var modeRow: some View {
        PressableCard(action: { showModeSwitch = true }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.mode.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text("Tap to switch to \(profile.mode.toggled.displayName)")
                        .font(.caption).foregroundStyle(theme.dim)
                }
                Spacer()
                Image(systemName: "arrow.left.arrow.right")
                    .foregroundStyle(theme.accent)
            }
        }
    }

    @ViewBuilder
    private var bodyRow: some View {
        PressableCard(action: { showEditVitals = true }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Units.formatWeight(lb: profile.weightLb, system: unitSystem, decimals: 0)) \(Units.weightUnit(unitSystem)) · \(heightLabel) · \(profile.age) yr")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text("\(profile.sex.rawValue.capitalized) · \(profile.activity.label) · tap to edit")
                        .font(.caption).foregroundStyle(theme.dim)
                }
                Spacer()
                Image(systemName: "pencil")
                    .foregroundStyle(theme.accent)
            }
        }
    }

    @ViewBuilder
    private var unitsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(UnitSystem.allCases, id: \.self) { system in
                    Button { setUnitSystem(system) } label: {
                        Text(system.displayName).frame(maxWidth: .infinity)
                    }
                    .tactile(.pill, fill: unitSystem == system ? theme.accent : nil)
                }
            }
            Text(unitSystem.blurb)
                .font(.caption).foregroundStyle(theme.dim)
        }
    }

    @ViewBuilder
    private var remindersSection: some View {
        VStack(spacing: 1) {
            nudgeToggleRow(
                label: "Meal logging reminder",
                detail: "Nudges you to log meals if you haven't by mid-day or evening.",
                isOn: $mealNudgeEnabled,
                isFirst: true, isLast: false
            )
            nudgeToggleRow(
                label: "Water reminder",
                detail: "Reminds you to drink water if you're behind on your daily goal.",
                isOn: $waterNudgeEnabled,
                isFirst: false, isLast: true
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func nudgeToggleRow(
        label: String,
        detail: String,
        isOn: Binding<Bool>,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.text)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(theme.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.card)
        if !isLast {
            Divider().background(theme.line).padding(.leading, 12)
        }
    }

    private func setUnitSystem(_ system: UnitSystem) {
        guard system != unitSystem else { return }
        unitSystem = system
        Haptics.success()
        toasts.show(Toast(title: "\(system.displayName) units",
                          detail: "Measurements now shown in \(system.displayName.lowercased()).",
                          accent: .win, symbol: "ruler.fill"))
    }

    private var heightLabel: String {
        Units.formatHeight(inches: profile.heightIn, system: unitSystem)
    }

    private func saveVitals(weightLb: Double, heightIn: Double, age: Int, sex: Sex, activity: ActivityLevel) {
        guard Repos.updateVitals(
            ctx, profileId: profile.id,
            weightLb: weightLb, heightIn: heightIn, age: age, sex: sex, activity: activity
        ) != nil else { return }
        Haptics.success()
        toasts.show(Toast(title: "Profile updated",
                          detail: "Targets recomputed from your new numbers.",
                          accent: .win, symbol: "checkmark.circle.fill"))
        showEditVitals = false
    }

    private func switchMode(to newMode: Mode) {
        guard Repos.updateMode(ctx, profileId: profile.id, to: newMode) != nil else { return }
        Haptics.success()
        toasts.show(Toast(title: "Switched to \(newMode.displayName)",
                          detail: "Targets recomputed. Your logs are kept.",
                          accent: .win, symbol: "checkmark.circle.fill"))
        showModeSwitch = false
    }

    private func connectHealth() {
        Task {
            // Always re-request — HealthKit only prompts for types not yet authorized,
            // so this is a no-op when fully granted and picks up any new types added
            // in app updates (e.g. flightsClimbed, distanceWalkingRunning, basalEnergyBurned).
            _ = await health.connectAndPersist(profileId: profile.id, ctx: ctx, toasts: toasts)
            // RootView's .task(id: StepObserverKey) re-fires on grant transition and arms the observer.
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10)).tracking(2)
                .foregroundStyle(theme.dim)
            content()
        }
    }

    @ViewBuilder
    private func labeled(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(theme.dim)
            Spacer()
            Text(v).foregroundStyle(theme.text)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - Shared target compare row

/// `from → to` row used by the mode-switch and edit-vitals previews to show how a
/// change shifts a computed target. Reads the theme from the environment.
private struct TargetCompareRow: View {
    let label: String
    let from: String
    let to: String
    let unit: String

    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Text(label).foregroundStyle(theme.text).font(.callout)
            Spacer()
            Text(from)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(theme.dim)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(theme.dim)
            Text(to)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(theme.accent)
            Text(unit).font(.caption).foregroundStyle(theme.dim)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }
}

// MARK: - Edit vitals sheet

/// Edit the profile's body vitals (weight/height/age/sex/activity) post-onboarding.
/// Weight, height, age, and activity all feed the Mifflin-St Jeor TDEE math, so
/// the sheet previews how the macro/step targets shift before saving. Saving funnels
/// through `Repos.updateVitals`, which recomputes targets — keeping every
/// recommendation surface (calories, protein, water, calorie burn) anchored to the
/// user's real numbers rather than the onboarding snapshot.
private struct EditVitalsSheet: View {
    let profile: ProfileDTO
    let unitSystem: UnitSystem
    let onSave: (_ weightLb: Double, _ heightIn: Double, _ age: Int, _ sex: Sex, _ activity: ActivityLevel) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    // Stored canonically (lb / inches); fields display + parse in `unitSystem`.
    @State private var weightLb: Double
    @State private var heightIn: Double
    @State private var age: Int
    @State private var sex: Sex
    @State private var activity: ActivityLevel
    @FocusState private var fieldFocused: Bool

    init(profile: ProfileDTO,
         unitSystem: UnitSystem,
         onSave: @escaping (Double, Double, Int, Sex, ActivityLevel) -> Void) {
        self.profile = profile
        self.unitSystem = unitSystem
        self.onSave = onSave
        _weightLb = State(initialValue: profile.weightLb)
        _heightIn = State(initialValue: profile.heightIn)
        _age = State(initialValue: profile.age)
        _sex = State(initialValue: profile.sex)
        _activity = State(initialValue: profile.activity)
    }

    // Display bindings: read/write the field in the active unit, but keep the
    // canonical lb/inches state authoritative for the TDEE math + save.
    private var weightDisplay: Binding<Double> {
        Binding(
            get: { Units.weightValue(lb: weightLb, system: unitSystem) },
            set: { weightLb = Units.weightToLb($0, system: unitSystem) }
        )
    }
    private var heightDisplay: Binding<Double> {
        Binding(
            get: { unitSystem == .metric ? heightIn * Units.cmPerInch : heightIn },
            set: { heightIn = Units.lengthToInches($0, system: unitSystem) }
        )
    }

    private var canSave: Bool { weightLb > 0 && heightIn > 0 && age > 0 }

    private var draftVitals: Targets.ProfileVitals {
        Targets.ProfileVitals(sex: sex, weightLb: weightLb, heightIn: heightIn, age: age, activity: activity)
    }
    private var current: MacroTargets { profile.computedTargets }
    private var next: MacroTargets { Targets.compute(mode: profile.mode, vitals: draftVitals) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your body")
                            .font(.system(size: 42, weight: .regular))
                            .foregroundStyle(theme.text)
                        Text("EDIT VITALS")
                            .font(.system(size: 10, weight: .medium)).tracking(2)
                            .foregroundStyle(theme.dim)
                    }

                    numberField("Weight (\(Units.weightUnit(unitSystem)))", value: weightDisplay)
                    numberField("Height (\(unitSystem == .metric ? "cm" : "in"))", value: heightDisplay)
                    intField("Age", value: $age)

                    pickerGroup("Sex") {
                        ForEach(Sex.allCases, id: \.self) { s in
                            Button { sex = s } label: { Text(s.rawValue.capitalized) }
                                .tactile(.pill, fill: sex == s ? theme.accent : nil)
                        }
                    }

                    Text("Activity").font(.caption).tracking(2).foregroundStyle(theme.dim)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ActivityLevel.allCases, id: \.self) { a in
                                Button { activity = a } label: { Text(a.label) }
                                    .tactile(.pill, fill: activity == a ? theme.accent2 : nil)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What changes")
                            .font(.caption).tracking(2).textCase(.uppercase)
                            .foregroundStyle(theme.dim)
                        TargetCompareRow(label: "Calories", from: "\(current.calories)", to: "\(next.calories)", unit: "cal")
                        TargetCompareRow(label: "Protein", from: "\(current.proteinG)", to: "\(next.proteinG)", unit: "g")
                    }

                    Button { onSave(weightLb, heightIn, age, sex, activity) } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .tactile(.primary, fullWidth: true)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.6)

                    Button { dismiss() } label: { Text("Cancel") }
                        .tactile(.ghost)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { fieldFocused = false }
                }
            }
        }
        .presentationDetents([.large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func numberField(_ label: String, value: Binding<Double>) -> some View {
        fieldShell(label) {
            TextField("", value: value, format: .number)
                .keyboardType(.decimalPad)
                .focused($fieldFocused)
        }
    }

    @ViewBuilder
    private func intField(_ label: String, value: Binding<Int>) -> some View {
        fieldShell(label) {
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .focused($fieldFocused)
        }
    }

    @ViewBuilder
    private func fieldShell<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased()).font(.system(size: 10)).tracking(2).foregroundStyle(theme.dim)
            content()
                .padding(10).background(theme.card)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                .foregroundStyle(theme.text)
        }
    }

    @ViewBuilder
    private func pickerGroup<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).tracking(2).foregroundStyle(theme.dim)
            HStack(spacing: 8) { content() }
        }
    }
}

// MARK: - Mode switch sheet

/// Confirms an at-will Build↔Circuit switch, previewing how the recomputed
/// targets shift before applying. Targets come straight from Targets.compute so
/// the preview matches exactly what Repos.updateMode will persist.
private struct ModeSwitchSheet: View {
    let profile: ProfileDTO
    let onConfirm: (Mode) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var newMode: Mode { profile.mode.toggled }

    private var current: MacroTargets { Targets.compute(mode: profile.mode, vitals: profile.vitals) }
    private var next: MacroTargets { Targets.compute(mode: newMode, vitals: profile.vitals) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Switch mode")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("\(profile.mode.displayName.uppercased()) → \(newMode.displayName.uppercased())")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                Text(newMode.blurb)
                    .font(.callout).foregroundStyle(theme.dim)

                VStack(alignment: .leading, spacing: 8) {
                    Text("What changes")
                        .font(.caption).tracking(2).textCase(.uppercase)
                        .foregroundStyle(theme.dim)
                    TargetCompareRow(label: "Calories", from: "\(current.calories)", to: "\(next.calories)", unit: "cal")
                    TargetCompareRow(label: "Protein", from: "\(current.proteinG)", to: "\(next.proteinG)", unit: "g")
                    TargetCompareRow(label: "Steps", from: current.stepsDaily.formatted(), to: next.stepsDaily.formatted(), unit: "/day")
                }

                Text(newMode == .circuit
                     ? "Reset adds the parenting movements (Lifted Baby, Stroller, Carried Baby) to your exercises and folds your workout log into Today."
                     : "Build brings back the Train tab for your own lifts and the rep counter.")
                    .font(.footnote).foregroundStyle(theme.dim)

                Text("Your food, workout, and body logs are kept exactly as they are.")
                    .font(.footnote).foregroundStyle(theme.dim)

                Button {
                    onConfirm(newMode)
                } label: {
                    Text("Switch to \(newMode.displayName)").frame(maxWidth: .infinity)
                }
                .tactile(.primary, fullWidth: true)

                Button { dismiss() } label: { Text("Cancel") }
                    .tactile(.ghost)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
    }
}
