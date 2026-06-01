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
