// Water intake — cup presets + daily/weekly aggregation.
// Pure Domain: no SwiftUI/SwiftData. Operates on append-only `WaterEntryDTO`
// logs (persisted via WaterEntryModel / SchemaV4).

import Foundation

public enum Water {

    public struct CupPreset: Identifiable, Sendable, Equatable {
        public let id: String
        public let label: String
        public let flOz: Double
        public let symbol: String   // SF Symbol name
        public init(id: String, label: String, flOz: Double, symbol: String) {
            self.id = id; self.label = label; self.flOz = flOz; self.symbol = symbol
        }
    }

    /// Tap-to-add cup presets, in US fluid ounces.
    ///   McDonald's: small 16, medium 21, large 30. Owala FreeSip: 32.
    public static let presets: [CupPreset] = [
        CupPreset(id: "cup-small",  label: "Small",  flOz: 16, symbol: "cup.and.saucer"),
        CupPreset(id: "cup-medium", label: "Medium", flOz: 21, symbol: "cup.and.saucer.fill"),
        CupPreset(id: "cup-large",  label: "Large",  flOz: 30, symbol: "takeoutbag.and.cup.and.straw.fill"),
        CupPreset(id: "owala",      label: "Owala",  flOz: 32, symbol: "waterbottle.fill"),
    ]

    /// Default daily goal (~2.4 L). User-adjustable.
    public static let defaultGoalFlOz: Double = 80
    public static let goalStepFlOz: Double = 8
    public static let minGoalFlOz: Double = 16
    public static let maxGoalFlOz: Double = 200

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
