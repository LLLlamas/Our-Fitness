import Foundation

/// Typed isometric hold durations: "47", "47s", or "m:ss" ("1:30").
/// Pure Foundation. Not in the watch source list (project.yml): the watch
/// never logs isometrics.
enum HoldDuration {
    /// Longest hold the phone accepts when typed (the live timer auto-stops at 600 s).
    static let maxSeconds = 3600

    /// Seconds for "47", "47s" or "m:ss" (ss 0...59). Nil for empty, negative,
    /// ":30", "1:", "1:75", decimals or anything else. Range (0, maxSeconds) is
    /// the caller's call; this only parses.
    static func parseSeconds(_ text: String) -> Int? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.last == "s" || s.last == "S" {
            s.removeLast()
            s = s.trimmingCharacters(in: .whitespaces)
        }
        guard !s.isEmpty else { return nil }
        func digits(_ t: Substring) -> Int? {
            guard !t.isEmpty, t.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(t)
        }
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            return digits(parts[0])
        case 2:
            guard let m = digits(parts[0]), let sec = digits(parts[1]),
                  parts[1].count == 2, sec <= 59 else { return nil }
            let total = m.multipliedReportingOverflow(by: 60)
            guard !total.overflow else { return nil }
            return total.partialValue + sec
        default:
            return nil
        }
    }

    /// Text for the entry field: "47" under a minute, otherwise "1:30".
    /// Inverse of `parseSeconds` for every non-negative value.
    static func entryText(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
