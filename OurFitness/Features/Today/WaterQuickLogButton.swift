// App-wide floating water quick-log button.
//
// A fixed bottom-right control for logging water from any tab:
//   • TAP            → logs the SAME amount you logged last (defaults to a Sip).
//   • PRESS & HOLD   → the screen dims to focus and the four cup presets fan out
//                      from the button; slide toward one and release to log it
//                      (release near the center cancels). Modelled on the
//                      hold-a-button / flick-to-choose radial from console games.
//
// Self-contained: it owns its own water @Query (today's total, for the progress
// ring), the per-profile goal + last-amount in AppStorage, and logs through the
// same `Repos.addWater` path the Water card uses. Numbers are never invented.

import SwiftUI
import SwiftData

struct WaterQuickLogButton: View {
    let profile: ProfileDTO

    @Environment(\.modelContext) private var ctx
    @Environment(\.theme) private var theme
    @EnvironmentObject private var toasts: ToastCenter

    @Query private var entryModels: [WaterEntryModel]
    @AppStorage private var goalFlOz: Double
    @AppStorage private var lastFlOz: Double
    @AppStorage(UnitSystem.storageKey) private var unitSystem: UnitSystem = .imperial

    @State private var isOpen = false
    @State private var fingerDown = false
    @State private var highlighted: Int? = nil
    @State private var openWork: DispatchWorkItem?

    // Layout constants (tunable).
    private let fabSize: CGFloat = 60
    private let itemSize: CGFloat = 54
    private let radius: CGFloat = 108        // fan distance from the button center
    private let deadzone: CGFloat = 34       // finger within this of center = no selection
    private let holdDelay: TimeInterval = 0.22   // separates a deliberate hold from a tap

    init(profile: ProfileDTO) {
        self.profile = profile
        let uid = profile.id
        let dayStart = Calendar.current.startOfDay(for: Date())
        _entryModels = Query(
            filter: #Predicate<WaterEntryModel> { $0.userId == uid && $0.timestamp >= dayStart },
            sort: \.timestamp, order: .forward
        )
        _goalFlOz = AppStorage(wrappedValue: Water.defaultGoalFlOz, "waterGoalFlOz.\(uid.uuidString)")
        _lastFlOz = AppStorage(wrappedValue: Water.presets.first?.flOz ?? 4, "waterLastFlOz.\(uid.uuidString)")
    }

    private var todayOz: Double {
        let today = Dates.dayKey()
        return entryModels.reduce(0) { acc, model in
            let entry = model.snapshot
            return acc + (entry.date == today ? entry.flOz : 0)
        }
    }
    private var pct: Double { goalFlOz > 0 ? min(1, todayOz / goalFlOz) : 0 }
    private var presets: [Water.CupPreset] { Water.presets }

    var body: some View {
        // Outer ZStack respects the safe area so the button can sit a fixed gap above
        // the tab bar (a sibling overlay doesn't inherit the TabView's bar inset). The
        // dimming scrim ignores the safe area separately so it covers the whole screen.
        ZStack(alignment: .bottomTrailing) {
            if isOpen { scrim }

            ZStack {
                if isOpen {
                    ForEach(Array(presets.enumerated()), id: \.element.id) { idx, preset in
                        wedge(preset, index: idx)
                    }
                }
                fab
            }
            .padding(.trailing, 22)
            .padding(.bottom, 64)   // clears the ~49pt tab bar; tune if it overlaps
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .animation(.spring(response: 0.34, dampingFraction: 0.74), value: isOpen)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: highlighted)
    }

    // MARK: - Dimming scrim

    private var scrim: some View {
        Color.black.opacity(0.38)
            .ignoresSafeArea()
            .transition(.opacity)
            .allowsHitTesting(false)   // the live drag owns all touches; scrim is purely visual
    }

    // MARK: - The button

    private var fab: some View {
        ZStack {
            Circle()
                .fill(theme.card)
                .overlay(ProgressRing(pct: pct, color: theme.accent,
                                      trackColor: theme.accent.opacity(0.18), lineWidth: 3.5)
                    .padding(2.5))
            Image(systemName: "drop.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(theme.accent)
        }
        .frame(width: fabSize, height: fabSize)
        .shadow(color: .black.opacity(isOpen ? 0.28 : 0.18), radius: isOpen ? 12 : 7, y: 4)
        .scaleEffect(isOpen ? 1.08 : 1.0)
        .contentShape(Circle())
        .gesture(dragGesture)
        .accessibilityElement()
        .accessibilityLabel("Log water")
        .accessibilityValue("\(Int(todayOz)) of \(Int(goalFlOz)) ounces today")
        .accessibilityHint("Double-tap to log your last amount. Use actions to pick a cup size.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { logLast() }
        .modifier(PresetAccessibilityActions(presets: presets, unitSystem: unitSystem) { logAmount($0) })
    }

    // MARK: - Radial wedges

    @ViewBuilder
    private func wedge(_ preset: Water.CupPreset, index: Int) -> some View {
        let isHi = highlighted == index
        VStack(spacing: 2) {
            Image(systemName: "drop.fill")
                .font(.system(size: dropSize(for: preset), weight: .semibold))
            Text(preset.label)
                .font(.system(size: 10, weight: .bold))
            Text(Units.formatVolumeWithUnit(flOz: preset.flOz, system: unitSystem))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .opacity(0.85)
        }
        .foregroundStyle(isHi ? Color.white : theme.accent)
        .frame(width: itemSize, height: itemSize)
        .background(
            Circle().fill(isHi ? theme.accent : theme.card)
                .overlay(Circle().stroke(theme.accent.opacity(isHi ? 0 : 0.5), lineWidth: 1.5))
        )
        .shadow(color: .black.opacity(0.2), radius: isHi ? 8 : 4, y: 2)
        .scaleEffect(isHi ? 1.16 : 1.0)
        .offset(offset(for: index))
        .transition(.scale(scale: 0.2).combined(with: .opacity))
    }

    private func dropSize(for preset: Water.CupPreset) -> CGFloat {
        switch preset.id {
        case "cup-sip":    return 12
        case "cup-small":  return 15
        case "cup-medium": return 18
        default:           return 21
        }
    }

    /// Fan the presets across the upper-left quarter (12 o'clock → 9 o'clock) so they
    /// stay on-screen from a bottom-right anchor. Screen coords: +x right, +y down.
    private func offset(for index: Int) -> CGSize {
        let count = max(1, presets.count - 1)
        let deg = 270.0 - Double(index) * (90.0 / Double(count))   // 270=up … 180=left
        let r = deg * .pi / 180
        return CGSize(width: radius * cos(r), height: radius * sin(r))
    }

    // MARK: - Gesture (tap = repeat last · hold + slide = pick)

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !fingerDown {
                    fingerDown = true
                    scheduleOpen()
                }
                if isOpen { updateHighlight(to: value.location) }
            }
            .onEnded { _ in
                cancelOpen()
                if isOpen {
                    if let h = highlighted { logAmount(presets[h].flOz) }
                    else { Haptics.tap() }   // released at center → cancel
                    withAnimation { isOpen = false }
                } else {
                    logLast()                // quick tap before the radial opened
                }
                fingerDown = false
                highlighted = nil
            }
    }

    private func scheduleOpen() {
        let work = DispatchWorkItem {
            guard fingerDown else { return }
            Haptics.bump()
            withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) { isOpen = true }
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + holdDelay, execute: work)
    }

    private func cancelOpen() { openWork?.cancel(); openWork = nil }

    /// Highlight the preset nearest the finger (forgiving "flick toward it" select),
    /// or none when the finger is inside the dead-zone around the center.
    private func updateHighlight(to location: CGPoint) {
        let center = CGPoint(x: fabSize / 2, y: fabSize / 2)
        let v = CGVector(dx: location.x - center.x, dy: location.y - center.y)
        guard hypot(v.dx, v.dy) > deadzone else {
            if highlighted != nil { highlighted = nil }
            return
        }
        var best = 0
        var bestDist = CGFloat.greatestFiniteMagnitude
        for i in presets.indices {
            let o = offset(for: i)
            let d = hypot(v.dx - o.width, v.dy - o.height)
            if d < bestDist { bestDist = d; best = i }
        }
        if highlighted != best {
            highlighted = best
            Haptics.selection()
        }
    }

    // MARK: - Logging

    private func logLast() {
        logAmount(lastFlOz > 0 ? lastFlOz : (Water.presets.first?.flOz ?? 4))
    }

    private func logAmount(_ oz: Double) {
        Repos.addWater(ctx, WaterEntryDTO(userId: profile.id, date: Dates.dayKey(), flOz: oz))
        lastFlOz = oz
        Haptics.success()
        toasts.show(Toast(title: "+\(Units.formatVolumeWithUnit(flOz: oz, system: unitSystem))",
                          detail: "Water logged", accent: .ok, symbol: "drop.fill"))
    }
}

/// VoiceOver path for the radial: each preset becomes a named custom action so the
/// hold-and-slide gesture has a non-gestural equivalent.
private struct PresetAccessibilityActions: ViewModifier {
    let presets: [Water.CupPreset]
    let unitSystem: UnitSystem
    let log: (Double) -> Void

    func body(content: Content) -> some View {
        presets.reduce(AnyView(content)) { view, preset in
            AnyView(view.accessibilityAction(named: Text("Log \(preset.label), \(Units.formatVolumeWithUnit(flOz: preset.flOz, system: unitSystem))")) {
                log(preset.flOz)
            })
        }
    }
}
