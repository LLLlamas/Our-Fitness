// Daily water intake — tap a cup preset to add. Daily progress + 7-day strip.
//
// Backed by SwiftData (WaterEntryModel, append-only like the other logs) via a
// profile-scoped @Query; the daily goal stays in AppStorage as a per-profile
// setting. Undo removes the most recent entry for today.

import SwiftUI
import SwiftData

struct WaterCard: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var entryModels: [WaterEntryModel]
    @AppStorage private var goalFlOz: Double
    @State private var showInfo = false

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        _entryModels = Query(
            filter: #Predicate<WaterEntryModel> { $0.userId == uid },
            sort: \.timestamp, order: .forward
        )
        _goalFlOz = AppStorage(wrappedValue: Water.defaultGoalFlOz, "waterGoalFlOz.\(uid.uuidString)")
    }

    private var entries: [WaterEntryDTO] { entryModels.map(\.snapshot) }
    private var today: String { Dates.dayKey() }
    private var todayOz: Double { Water.total(entries, on: today) }
    private var weekSeries: [Trends.Point] { Water.series(entries, days: 7) }
    private var weekAvg: Double { Water.average(entries, days: 7) }
    private var canUndo: Bool { entries.contains { $0.date == today } }

    // No explicit Haptics — the buttons use `.tactile(...)` (press haptic), and
    // ProgressBar fires a success haptic when the day crosses the goal (outcome).
    private func add(_ oz: Double) {
        Repos.addWater(ctx, WaterEntryDTO(userId: profile.id, date: today, flOz: oz))
        toasts.show(Toast(title: "+\(Int(oz)) oz", detail: "Water logged",
                          accent: .ok, symbol: "drop.fill"))
    }

    private func undoLast() {
        guard let last = entries.filter({ $0.date == today }).max(by: { $0.timestamp < $1.timestamp }) else { return }
        Repos.deleteWater(ctx, id: last.id)
        toasts.show(Toast(title: "Removed", detail: "Last water entry",
                          accent: .warn, symbol: "arrow.uturn.backward"))
    }

    private func adjustGoal(_ delta: Double) {
        goalFlOz = min(Water.maxGoalFlOz, max(Water.minGoalFlOz, goalFlOz + delta))
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("WATER")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                    Spacer()
                    Button { showInfo = true } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.dim)
                    }
                    .tactile(.ghost)
                    .accessibilityLabel("Water goal info")
                }

                ProgressBar(value: todayOz, target: goalFlOz, label: "Water", unit: " oz")

                HStack {
                    if weekAvg > 0 {
                        Text("7-day avg \(Int(weekAvg)) oz")
                            .font(.caption2).foregroundStyle(theme.dim)
                    }
                    Spacer()
                    if canUndo {
                        Button { undoLast() } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.backward")
                                Text("Undo")
                            }
                            .font(.caption)
                        }
                        .tactile(.ghost)
                    }
                }

                presetRow
                goalRow

                if weekSeries.contains(where: { $0.value > 0 }) {
                    weeklyStrip
                }
            }
        }
        .sheet(isPresented: $showInfo) {
            WaterInfoSheet(profile: profile, goalFlOz: goalFlOz)
                .themed(profile.mode)
        }
    }

    private func glassIcon(for presetId: String) -> GlassIcon.GlassSize {
        switch presetId {
        case "cup-small":  return .small
        case "cup-medium": return .medium
        default:           return .large
        }
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            ForEach(Water.presets) { preset in
                Button { add(preset.flOz) } label: {
                    VStack(spacing: 4) {
                        GlassIcon(size: glassIcon(for: preset.id))
                            .frame(height: 36, alignment: .bottom)  // fixed slot, glass sits at bottom
                        Text(preset.label).font(.system(size: 11, weight: .medium))
                        Text("+\(Int(preset.flOz)) oz")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(theme.dim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(theme.accent)
                }
                .tactile(.bump)
                .accessibilityLabel("Add \(preset.label) cup, \(Int(preset.flOz)) ounces")
            }
        }
    }

    private var goalRow: some View {
        HStack(spacing: 10) {
            Text("Goal").font(.caption).foregroundStyle(theme.dim)
            Spacer()
            Button { adjustGoal(-Water.goalStepFlOz) } label: { Image(systemName: "minus") }
                .tactile(.ghost)
                .accessibilityLabel("Lower water goal")
            Text("\(Int(goalFlOz)) oz")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.text)
            Button { adjustGoal(Water.goalStepFlOz) } label: { Image(systemName: "plus") }
                .tactile(.ghost)
                .accessibilityLabel("Raise water goal")
        }
    }

    private var weeklyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 7 days")
                .font(.system(size: 10, weight: .medium)).tracking(2)
                .foregroundStyle(theme.dim)
            WeeklyBarStrip(series: weekSeries, goal: goalFlOz)
        }
    }
}

// MARK: - Custom glass icon

/// A trapezoid glass: slightly wider at the top than the bottom.
private struct DrinkingGlass: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let taper: CGFloat = rect.width * 0.12  // bottom is 12% narrower on each side
        let topLeft   = CGPoint(x: rect.minX,        y: rect.minY)
        let topRight  = CGPoint(x: rect.maxX,        y: rect.minY)
        let botRight  = CGPoint(x: rect.maxX - taper, y: rect.maxY)
        let botLeft   = CGPoint(x: rect.minX + taper, y: rect.maxY)
        p.move(to: topLeft)
        p.addLine(to: topRight)
        p.addLine(to: botRight)
        p.addLine(to: botLeft)
        p.closeSubpath()
        return p
    }
}

/// Stroked glass outline whose height scales with the preset size.
private struct GlassIcon: View {
    let size: GlassSize
    enum GlassSize { case small, medium, large
        var height: CGFloat { switch self { case .small: return 18; case .medium: return 26; case .large: return 34 } }
        var width: CGFloat  { switch self { case .small: return 13; case .medium: return 18; case .large: return 22 } }
    }
    var body: some View {
        DrinkingGlass()
            .stroke(lineWidth: 1.8)
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - Water info sheet

private struct WaterInfoSheet: View {
    let profile: ProfileDTO
    let goalFlOz: Double

    @Environment(\.theme) private var theme

    private var weightKg: Int { Int(profile.weightLb * 0.4536) }

    // ACSM base recommendation: ~0.5 oz per lb bodyweight
    private var baseOz: Int { max(64, Int(profile.weightLb * 0.5)) }

    private var activityBonus: Int {
        switch profile.activity {
        case .sedentary:  return 0
        case .light:      return 8
        case .moderate:   return 16
        case .active:     return 24
        case .veryActive: return 32
        }
    }

    private var recommendedOz: Int { baseOz + activityBonus }
    private var recommendedMl: Int { Int(Double(recommendedOz) * 29.57) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("water.")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(theme.text)
                    Text("PERSONALIZED DAILY GOAL")
                        .font(.system(size: 10, weight: .medium)).tracking(2)
                        .foregroundStyle(theme.dim)
                }

                infoSection(title: "Your recommendation") {
                    VStack(alignment: .leading, spacing: 8) {
                        calcRow(label: "Base (0.5 oz × \(Int(profile.weightLb)) lb)",
                                detail: "\(baseOz) oz / day")
                        calcRow(label: "Activity bonus (\(profile.activity.label))",
                                detail: "+\(activityBonus) oz / day")
                        calcRow(label: "Recommended total",
                                detail: "\(recommendedOz) oz / day · \(recommendedMl) mL")
                        if Int(goalFlOz) < recommendedOz {
                            Text("Your current goal (\(Int(goalFlOz)) oz) is below the recommendation. Consider raising it with the +/− buttons.")
                                .font(.caption)
                                .foregroundStyle(theme.warn)
                                .padding(.top, 4)
                        } else {
                            Text("Your current goal (\(Int(goalFlOz)) oz) meets your recommendation.")
                                .font(.caption)
                                .foregroundStyle(theme.ok)
                                .padding(.top, 4)
                        }
                    }
                }

                infoSection(title: "Why hydration matters") {
                    VStack(alignment: .leading, spacing: 8) {
                        bullet("Losing just 2% of your body weight in fluid can sap your endurance and mood, and may dull your focus.")
                        bullet("Water helps your body absorb nutrients and recover after training.")
                        bullet("Thirst is a good guide for most people — this goal is just a target to aim for, especially on hot or active days.")
                        if profile.mode == .circuit {
                            bullet("Staying topped up makes the higher step counts in Circuit feel easier.")
                        }
                    }
                }

                Text("This goal is a practical starting point (about half an ounce per pound, plus a little for activity). Official guidance (Institute of Medicine, 2005) is roughly 3.7 L for men and 2.7 L for women of total water per day — and that counts the water in your food, too. Individual needs vary.")
                    .font(.caption2)
                    .foregroundStyle(theme.dim)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(theme.bg)
    }

    @ViewBuilder
    private func infoSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption).tracking(2).foregroundStyle(theme.dim)
            content()
        }
    }

    @ViewBuilder
    private func calcRow(label: String, detail: String) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(theme.text)
            Spacer()
            Text(detail).font(.system(.callout, design: .monospaced)).foregroundStyle(theme.accent)
        }
        .padding(10)
        .background(theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("·").foregroundStyle(theme.accent).font(.callout)
            Text(text).font(.callout).foregroundStyle(theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
