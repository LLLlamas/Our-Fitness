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

    /// Tap-to-add cup presets, in US fluid ounces. `symbol` maps to the custom
    /// glass icon by id in WaterCard, so the strings are placeholders.
    public static let presets: [CupPreset] = [
        CupPreset(id: "cup-sip",    label: "Sip", flOz: 4,  symbol: "glass-sip"),
        CupPreset(id: "cup-small",  label: "S",   flOz: 8,  symbol: "glass-small"),
        CupPreset(id: "cup-medium", label: "M",   flOz: 16, symbol: "glass-medium"),
        CupPreset(id: "cup-large",  label: "L",   flOz: 32, symbol: "glass-large"),
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

    /// Consecutive days ending at `end` on which intake met or exceeded `goalFlOz`.
    /// Today is grace-zone: if today hasn't hit goal yet the streak is preserved from yesterday.
    public static func streak(_ entries: [WaterEntryDTO], goalFlOz: Double, end: Date = Date()) -> Int {
        guard goalFlOz > 0 else { return 0 }
        let map = byDay(entries)
        var n = 0
        let cal = Calendar.current
        var cursor = cal.startOfDay(for: end)
        let todayKey = Dates.dayKey(end)
        while true {
            let key = Dates.dayKey(cursor)
            if (map[key] ?? 0) >= goalFlOz {
                n += 1
            } else if key == todayKey {
                // grace: not yet hit today — preserve streak from yesterday
            } else {
                break
            }
            if n >= 365 { break }   // runaway guard, capped at one year
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }
}
