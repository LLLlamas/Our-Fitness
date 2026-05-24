// Trend math: rolling averages, weekly weight delta, marker stall detection.

import Foundation

public enum Trends {

    public struct Point: Equatable, Sendable {
        public var date: String
        public var value: Double
        public init(date: String, value: Double) {
            self.date = date
            self.value = value
        }
    }

    /// Trailing simple moving average.
    public static func rollingAverage(_ points: [Point], window: Int) -> [Point] {
        guard window > 1 else { return points }
        var out: [Point] = []
        out.reserveCapacity(points.count)
        for i in points.indices {
            let start = max(0, i - window + 1)
            let slice = points[start...i]
            let avg = slice.reduce(0.0) { $0 + $1.value } / Double(slice.count)
            out.append(Point(date: points[i].date, value: avg))
        }
        return out
    }

    /// lb / week over last `days` from weight history. Positive = gaining.
    public static func weeklyWeightDelta(_ body: [BodyMetricDTO], days: Int = 14) -> Double {
        let weighed = body
            .filter { $0.weightLb != nil }
            .sorted { $0.date < $1.date }
        guard weighed.count >= 2,
              let last = weighed.last,
              let lastDate = Dates.date(fromDayKey: last.date)
        else { return 0 }

        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -days, to: lastDate) else { return 0 }
        let cutoffKey = Dates.dayKey(cutoff)
        let inWindow = weighed.filter { $0.date >= cutoffKey }
        guard inWindow.count >= 2,
              let first = inWindow.first,
              let firstDate = Dates.date(fromDayKey: first.date),
              let firstW = first.weightLb,
              let lastW = last.weightLb
        else { return 0 }

        let dayDiff = max(1, Calendar.current.dateComponents([.day], from: firstDate, to: lastDate).day ?? 1)
        let lbDiff = lastW - firstW
        return (lbDiff / Double(dayDiff)) * 7
    }

    /// Series of points for plotting a marker over time. Ascending by date.
    public static func markerSeries(_ markers: [HealthMarkerDTO], kind: HealthMarkerKind) -> [Point] {
        markers
            .filter { $0.kind == kind }
            .map { Point(date: $0.date, value: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// Weeks since the marker last moved meaningfully (default ≥5% drift).
    public static func weeksStalled(
        _ markers: [HealthMarkerDTO],
        kind: HealthMarkerKind,
        driftPct: Double = 0.05
    ) -> Int {
        let series = markerSeries(markers, kind: kind)
        guard let latest = series.last, series.count >= 2 else { return 0 }

        for i in stride(from: series.count - 2, through: 0, by: -1) {
            let p = series[i]
            let driftAbs = abs(latest.value - p.value) / max(1, p.value)
            if driftAbs >= driftPct {
                return weeksBetween(p.date, latest.date)
            }
        }
        // Never moved enough across whole history.
        return weeksBetween(series.first!.date, latest.date)
    }

    private static func weeksBetween(_ a: String, _ b: String) -> Int {
        let days = Dates.daysBetween(a, b)
        return max(0, days / 7)
    }
}
