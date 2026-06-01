// Water intake — cup presets + daily/weekly aggregation.
// Pure Domain: no SwiftUI/SwiftData. Operates on append-only `WaterEntryDTO`
// logs (persisted via WaterEntryModel / SchemaV4). User-created custom presets
// persist via WaterCupPresetModel / SchemaV5 and decode back into `CupPreset`.

import Foundation

public enum Water {

    /// Icon choices for a cup preset. Pure data — the view maps each case to a
    /// custom-drawn glass (`Components/GlassIcon`) or an SF Symbol. Backed by a
    /// stable raw string so it round-trips through SwiftData (`iconRaw`) and the
    /// custom-preset picker.
    public enum CupIcon: String, Codable, Sendable, CaseIterable, Identifiable {
        case glassSmall  = "glass.small"
        case glassMedium = "glass.medium"
        case glassLarge  = "glass.large"
        case bottle      = "bottle"

        public var id: String { rawValue }

        /// Default label shown in the icon picker.
        public var pickerLabel: String {
            switch self {
            case .glassSmall:  return "Small glass"
            case .glassMedium: return "Medium glass"
            case .glassLarge:  return "Large glass"
            case .bottle:      return "Bottle"
            }
        }
    }

    public struct CupPreset: Identifiable, Sendable, Equatable {
        public let id: String
        public let label: String
        public let flOz: Double
        public let icon: CupIcon
        public let isCustom: Bool
        public init(id: String, label: String, flOz: Double, icon: CupIcon, isCustom: Bool = false) {
            self.id = id; self.label = label; self.flOz = flOz
            self.icon = icon; self.isCustom = isCustom
        }
    }

    /// Built-in tap-to-add presets, in US fluid ounces: small/medium/large glasses
    /// plus a 32 oz bottle. Users add their own sizes alongside these.
    public static let presets: [CupPreset] = [
        CupPreset(id: "glass-small",  label: "Small",  flOz: 8,  icon: .glassSmall),
        CupPreset(id: "glass-medium", label: "Medium", flOz: 12, icon: .glassMedium),
        CupPreset(id: "glass-large",  label: "Large",  flOz: 16, icon: .glassLarge),
        CupPreset(id: "bottle",       label: "Bottle", flOz: 32, icon: .bottle),
    ]

    /// Built-ins first, then the user's custom presets (oldest first).
    public static func allPresets(custom: [WaterCupPresetDTO]) -> [CupPreset] {
        presets + custom
            .sorted { $0.sortOrder == $1.sortOrder ? $0.createdAt < $1.createdAt : $0.sortOrder < $1.sortOrder }
            .map(\.asPreset)
    }

    /// Default daily goal (~2.4 L). User-adjustable.
    public static let defaultGoalFlOz: Double = 80
    public static let goalStepFlOz: Double = 8
    public static let minGoalFlOz: Double = 16
    public static let maxGoalFlOz: Double = 200

    /// Bounds for a user-entered custom size.
    public static let minCustomFlOz: Double = 1
    public static let maxCustomFlOz: Double = 128

    /// Total intake (fl oz) summed per day.
    public static func byDay(_ entries: [WaterEntryDTO]) -> [String: Double] {
        var map: [String: Double] = [:]
        for e in entries { map[e.date, default: 0] += e.flOz }
        return map
    }

    public static func total(_ entries: [WaterEntryDTO], on day: String) -> Double {
        entries.reduce(0) { $0 + ($1.date == day ? $1.flOz : 0) }
    }

    /// Daily series ending today (oldest first) for the weekly strip / charts.
    public static func series(_ entries: [WaterEntryDTO], days: Int, end: Date = Date()) -> [Trends.Point] {
        let map = byDay(entries)
        return Dates.lastNDays(days, end: end).map { Trends.Point(date: $0, value: map[$0] ?? 0) }
    }

    /// Average over the last `days`, counting only days with intake logged.
    public static func average(_ entries: [WaterEntryDTO], days: Int = 7, end: Date = Date()) -> Double {
        let map = byDay(entries)
        let vals = Dates.lastNDays(days, end: end).compactMap { map[$0] }.filter { $0 > 0 }
        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }
}

/// User-created custom water size (e.g. "My tumbler" / 24 oz). Persisted per
/// profile via `WaterCupPresetModel` (SchemaV5) — the same SwiftData treatment as
/// logged reps/steps/meals, not AppStorage.
public struct WaterCupPresetDTO: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var userId: UUID
    public var name: String
    public var flOz: Double
    public var icon: Water.CupIcon
    public var sortOrder: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), userId: UUID, name: String, flOz: Double,
                icon: Water.CupIcon, sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.name = name
        self.flOz = flOz
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }

    public var asPreset: Water.CupPreset {
        Water.CupPreset(id: id.uuidString, label: name, flOz: flOz, icon: icon, isCustom: true)
    }
}
