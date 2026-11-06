import SwiftUI
import SwiftData
import UserNotifications

struct SettingsView: View {
    let profile: ProfileDTO
    @ObservedObject var health: HealthKitService

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var toasts: ToastCenter

    @State private var showTargets = false
    @State private var showEditVitals = false

    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial
    @AppStorage("nudge.meal.enabled") private var mealNudgeEnabled: Bool = true
    @AppStorage("nudge.water.enabled") private var waterNudgeEnabled: Bool = true
    @AppStorage("nudge.stall.enabled") private var stallNudgeEnabled: Bool = true
    @AppStorage private var mealRemindersEnabled: Bool

    init(profile: ProfileDTO, health: HealthKitService) {
        self.profile = profile
        self.health = health
        // Opt-in: default OFF. Same key MealReminderService reads.
        _mealRemindersEnabled = AppStorage(
            wrappedValue: false,
            MealReminderService.enabledKey(for: profile.id)
        )
    }

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

                    section("Daily targets") {
                        targetsRow
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

                    section("Nudges") {
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
        .sheet(isPresented: $showTargets) {
            TargetsSheet(profile: profile, onSave: saveTargets)
        }
        .sheet(isPresented: $showEditVitals) {
            EditVitalsSheet(profile: profile, unitSystem: unitSystem, onSave: saveVitals)
        }
    }

    @ViewBuilder
    private var targetsRow: some View {
        let t = profile.computedTargets
        PressableCard(action: { showTargets = true }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(t.calories.formatted()) cal · \(t.proteinG)g protein")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text("\((t.plan ?? profile.fitnessGoal.defaultPlan).displayName) · \(t.carbsG)g carbs · \(t.fatG)g fat · tap to edit")
                        .font(.caption).foregroundStyle(theme.dim)
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
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
                label: "In-app meal nudge",
                detail: "Nudges you to log meals if you haven't by mid-day or evening.",
                isOn: $mealNudgeEnabled,
                isFirst: true, isLast: false
            )
            nudgeToggleRow(
                label: "Meal logging reminders",
                detail: mealRemindersCaption,
                isOn: $mealRemindersEnabled,
                isFirst: false, isLast: false
            )
            nudgeToggleRow(
                label: "Water reminder",
                detail: "Reminds you to drink water if you're behind on your daily goal.",
                isOn: $waterNudgeEnabled,
                isFirst: false, isLast: false
            )
            nudgeToggleRow(
                label: "Keep-going nudge",
                detail: "A once-a-day prompt if your steps, workouts, or a tracked number have gone quiet.",
                isOn: $stallNudgeEnabled,
                isFirst: false, isLast: true
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        .onChange(of: mealRemindersEnabled) { _, enabled in
            guard enabled else {
                MealReminderService.cancelAll()
                return
            }
            // The toggle is the explicit user action — the only place meal
            // reminders may ask for notification permission.
            Task {
                let allowed = await MealReminderService.enable(ctx, userId: profile.id)
                if !allowed {
                    toasts.show(Toast(title: "Notifications are off",
                                      detail: "Allow notifications for Our Fitness in iOS Settings to get meal reminders.",
                                      accent: .info, symbol: "bell.slash"))
                }
            }
        }
    }

    /// Off: what the feature does. On: the learned times, or that it's still
    /// learning — never invented default times.
    private var mealRemindersCaption: String {
        let intro = "A notification about an hour after you usually log breakfast, lunch or dinner, if it isn't logged yet."
        guard mealRemindersEnabled else { return intro }
        let learned = MealReminderService.learnedTimes(ctx, userId: profile.id)
        guard !learned.isEmpty else {
            return intro + " Still learning your routine — once a meal is logged on \(MealLogPattern.minDays) different days, its reminder starts."
        }
        let times = learned
            .map { "\($0.slot.label) \(MealLogPattern.clockLabel(minuteOfDay: $0.minuteOfDay))" }
            .joined(separator: " · ")
        return intro + " Usual times: \(times)."
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
        toasts.show(Toast(title: "Profile updated",
                          detail: "Targets recomputed from your new numbers.",
                          accent: .win, symbol: "checkmark.circle.fill"))
        showEditVitals = false
    }

    private func saveTargets(plan: TargetPlan, custom: MacroTargets?) {
        guard let updated = Repos.updateTargets(ctx, profileId: profile.id, plan: plan, custom: custom)
        else { return }
        // A suggested plan brings its step goal with it: clear the Steps ring's
        // override so the plan's default shows. Custom targets leave steps alone.
        if plan != .custom {
            UserDefaults.standard.set(0, forKey: StepsGoalPrefs.dailyKey(profile.id))
        }
        toasts.show(Toast(title: "Targets saved",
                          detail: "\(updated.computedTargets.calories.formatted()) cal · \(updated.computedTargets.proteinG)g protein a day.",
                          accent: .win, symbol: "checkmark.circle.fill"))
        showTargets = false
    }

    private func connectHealth() {
        Task {
            // Always re-request — HealthKit only prompts for types not yet authorized,
            // so this is a no-op when fully granted and picks up any new types added
            // in app updates (e.g. flightsClimbed, distanceWalkingRunning).
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

/// `from → to` row used by the edit-vitals preview to show how a
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
    private var next: MacroTargets {
        Targets.recompute(current, fitnessGoal: profile.fitnessGoal, vitals: draftVitals)
    }

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

// MARK: - Daily targets sheet

/// Set the profile's daily targets. Three suggestions (maintain / lose / gain)
/// are computed from the user's own vitals by `Targets.compute(plan:)`, exactly
/// what `Repos.updateTargets` will persist; tapping one fills the fields. Editing
/// any field turns the draft into custom targets, which stay as typed when weight
/// changes. Carbs always fill the calories protein and fat leave. Targets change
/// numbers only — every tab, card and log stays the same.
private struct TargetsSheet: View {
    let profile: ProfileDTO
    let onSave: (_ plan: TargetPlan, _ custom: MacroTargets?) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var plan: TargetPlan
    @State private var calories: Int
    @State private var proteinG: Int
    @State private var fatG: Int
    @FocusState private var fieldFocused: Bool

    init(profile: ProfileDTO, onSave: @escaping (TargetPlan, MacroTargets?) -> Void) {
        self.profile = profile
        self.onSave = onSave
        let t = profile.computedTargets
        _plan = State(initialValue: t.plan ?? profile.fitnessGoal.defaultPlan)
        _calories = State(initialValue: t.calories)
        _proteinG = State(initialValue: t.proteinG)
        _fatG = State(initialValue: t.fatG)
    }

    private var maintenance: Int { Targets.tdee(profile.vitals) }
    private func suggestion(_ p: TargetPlan) -> MacroTargets { Targets.compute(plan: p, vitals: profile.vitals) }
    private var carbsG: Int { Targets.carbsFilling(calories: calories, proteinG: proteinG, fatG: fatG) }
    private var canSave: Bool { calories >= Targets.calorieFloor && proteinG > 0 && fatG > 0 }

    /// A field edit makes the draft custom (unless the value is unchanged).
    private func edited(_ value: Binding<Int>) -> Binding<Int> {
        Binding(
            get: { value.wrappedValue },
            set: { new in
                guard new != value.wrappedValue else { return }
                value.wrappedValue = new
                plan = .custom
            }
        )
    }

    private func pick(_ p: TargetPlan) {
        let t = suggestion(p)
        Haptics.selection()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            plan = p
            calories = t.calories
            proteinG = t.proteinG
            fatG = t.fatG
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Daily targets")
                            .font(.system(size: 42, weight: .regular))
                            .foregroundStyle(theme.text)
                        Text("SUGGESTED FROM YOUR BODY · OR SET YOUR OWN")
                            .font(.system(size: 10, weight: .medium)).tracking(2)
                            .foregroundStyle(theme.dim)
                    }

                    Text("You burn about \(maintenance.formatted()) calories a day at your weight, height, age and activity. That's your maintenance number.")
                        .font(.callout).foregroundStyle(theme.dim)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Suggestions")
                            .font(.caption).tracking(2).textCase(.uppercase)
                            .foregroundStyle(theme.dim)
                        ForEach(TargetPlan.suggestions, id: \.self) { p in
                            suggestionCard(p)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Your numbers")
                                .font(.caption).tracking(2).textCase(.uppercase)
                                .foregroundStyle(theme.dim)
                            Spacer()
                            if plan == .custom {
                                Text("CUSTOM").font(.system(size: 10, weight: .medium)).tracking(2)
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        intField("Calories", unit: "cal", value: edited($calories))
                        intField("Protein", unit: "g", value: edited($proteinG))
                        intField("Fat", unit: "g", value: edited($fatG))
                        HStack {
                            Text("Carbs").foregroundStyle(theme.text).font(.callout)
                            Spacer()
                            Text("\(carbsG)")
                                .font(.system(.callout, design: .monospaced))
                                .foregroundStyle(theme.text)
                                .contentTransition(.numericText())
                            Text("g · fills the rest").font(.caption).foregroundStyle(theme.dim)
                        }
                        .padding(10)
                        .background(theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
                    }

                    Text(plan == .custom
                         ? "Custom targets stay as you set them when your weight changes. Change your step goal by tapping the Steps ring on Today."
                         : "Suggested targets update on their own as your weight changes. Saving also sets your daily step goal to \(suggestion(plan).stepsDaily.formatted()).")
                        .font(.footnote).foregroundStyle(theme.dim)

                    Button {
                        onSave(plan, plan == .custom
                               ? Targets.custom(calories: calories, proteinG: proteinG, fatG: fatG,
                                                stepsDaily: profile.computedTargets.stepsDaily)
                               : nil)
                    } label: {
                        Text("Save targets").frame(maxWidth: .infinity)
                    }
                    .tactile(.primary, fullWidth: true)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.6)

                    if calories < Targets.calorieFloor {
                        Text("Calories can't go below \(Targets.calorieFloor.formatted()) a day.")
                            .font(.footnote).foregroundStyle(theme.dim)
                    }

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
    private func suggestionCard(_ p: TargetPlan) -> some View {
        let t = suggestion(p)
        let selected = plan == p
        PressableCard(action: { pick(p) }) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.displayName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(theme.text)
                    Text(p.blurb)
                        .font(.caption).foregroundStyle(theme.dim)
                    Text("\(t.calories.formatted()) cal · \(t.proteinG)g protein · \(t.stepsDaily.formatted()) steps")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.accent)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? theme.accent : theme.dim)
            }
        }
    }

    @ViewBuilder
    private func intField(_ label: String, unit: String, value: Binding<Int>) -> some View {
        HStack {
            Text(label).foregroundStyle(theme.text).font(.callout)
            Spacer()
            TextField("", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: 100)
                .focused($fieldFocused)
            Text(unit).font(.caption).foregroundStyle(theme.dim)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
        .foregroundStyle(theme.text)
    }
}
