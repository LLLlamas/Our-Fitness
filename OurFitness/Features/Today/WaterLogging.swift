// The single water-logging path shared by every water surface.
//
// Two controls can log water — the Water card's cup presets (Features/Today/
// WaterCard.swift) and the app-wide floating quick-log button (Features/Today/
// WaterQuickLogButton.swift) — and they have to agree on three things:
//   • the entry write (`Repos.addWater`)
//   • "last amount logged", which drives the floating button's tap = repeat last
//   • the confirmation copy
// They previously disagreed on all three: the card never wrote the last amount,
// so the button repeated a stale size, and the toast copy existed twice.
//
// Lives in Features/ rather than Domain/ because it writes through Repos →
// SwiftData. Domain/Water.swift stays pure (presets, totals, streak).
//
// No explicit Haptics call here: `ToastCenter.show` already fires one for the
// toast's accent (.ok → Haptics.bump()), so adding one would double-tap.

import SwiftUI
import SwiftData

enum WaterLog {

    // MARK: - Per-profile AppStorage keys
    //
    // Shared so the card and the floating button can never drift apart. Plain
    // (non-isolated) string builders so view `init`s can use them to construct
    // their @AppStorage wrappers.

    static func goalStorageKey(_ profileId: UUID) -> String {
        "waterGoalFlOz.\(profileId.uuidString)"
    }

    static func lastAmountStorageKey(_ profileId: UUID) -> String {
        "waterLastFlOz.\(profileId.uuidString)"
    }

    /// Fallback "last amount" before the user has logged anything (a Sip).
    static var defaultLastFlOz: Double { Water.presets.first?.flOz ?? 4 }

    // MARK: - Logging

    /// Log `flOz` of water, remember it as the repeat-last amount, and confirm.
    ///
    /// - Parameters:
    ///   - lastFlOz: binding to the caller's `@AppStorage(lastAmountStorageKey(...))`.
    ///   - day: day key to log against; defaults to today.
    @MainActor
    static func add(_ flOz: Double,
                    for profile: ProfileDTO,
                    on day: String = Dates.dayKey(),
                    context: ModelContext,
                    lastFlOz: Binding<Double>,
                    unitSystem: UnitSystem,
                    toasts: ToastCenter) {
        Repos.addWater(context, WaterEntryDTO(userId: profile.id, date: day, flOz: flOz))
        lastFlOz.wrappedValue = flOz
        toasts.show(Toast(title: "+\(Units.formatVolumeWithUnit(flOz: flOz, system: unitSystem))",
                          detail: "Water logged",
                          accent: .ok, symbol: "drop.fill"))
    }
}
