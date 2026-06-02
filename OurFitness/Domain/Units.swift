// Metric ⇄ Imperial (US) unit conversion + display formatting.
//
// Canonical internal storage stays IMPERIAL everywhere (lb, inches, fl oz,
// miles) exactly as the rest of the app persists it — this module converts
// ONLY at the UI boundary: `format*` turns a canonical imperial value into a
// display string for the active system, and `parse*` turns a string the user
// typed (in the displayed unit) back into canonical imperial before it is
// persisted. No SwiftData/SwiftUI here (Domain stays framework-free); views
// read the chosen `UnitSystem` from @AppStorage and call these helpers.
//
// Energy (calories) is deliberately NOT handled here — the app says "cal" in
// both systems and never shows kilojoules.

import Foundation

public enum UnitSystem: String, CaseIterable, Codable, Sendable {
    case imperial
    case metric

    /// Persisted under this app-wide @AppStorage key (one profile per install,
    /// so app-wide scope is correct). Default is `.imperial` — today's behavior.
    public static let storageKey = "unitSystem"

    public var displayName: String {
        switch self {
        case .imperial: return "Imperial"
        case .metric:   return "Metric"
        }
    }

    /// Short tagline for the Settings control, naming the units in play.
    public var blurb: String {
        switch self {
        case .imperial: return "Pounds, feet/inches, fl oz, miles"
        case .metric:   return "Kilograms, centimetres, millilitres, kilometres"
        }
    }
}

public enum Units {

    // MARK: - Conversion constants

    public static let lbPerKg = 2.2046226218
    public static let kgPerLb = 0.45359237
    public static let cmPerInch = 2.54
    public static let mlPerFlOz = 29.5735295625
    public static let kmPerMile = 1.609344

    // MARK: - Weight (canonical: pounds)

    /// Display label for the weight unit in the active system ("lb" / "kg").
    public static func weightUnit(_ system: UnitSystem) -> String {
        system == .metric ? "kg" : "lb"
    }

    /// Format a canonical weight (lb) for display, without a unit suffix.
    /// Imperial rounds to 0.1 lb; metric converts to kg rounded to 0.1.
    public static func formatWeight(lb: Double, system: UnitSystem, decimals: Int = 1) -> String {
        let value = system == .metric ? lb * kgPerLb : lb
        return String(format: "%.\(decimals)f", value)
    }

    /// Format a canonical weight (lb) with its unit suffix, e.g. "72.5 kg".
    public static func formatWeightWithUnit(lb: Double, system: UnitSystem, decimals: Int = 1) -> String {
        "\(formatWeight(lb: lb, system: system, decimals: decimals)) \(weightUnit(system))"
    }

    /// Convert a canonical weight (lb) into the active system's numeric value.
    public static func weightValue(lb: Double, system: UnitSystem) -> Double {
        system == .metric ? lb * kgPerLb : lb
    }

    /// Convert a value the user entered (in the active system's unit) back to
    /// canonical pounds.
    public static func weightToLb(_ displayValue: Double, system: UnitSystem) -> Double {
        system == .metric ? displayValue * lbPerKg : displayValue
    }

    /// Parse a user-entered weight string (in the active unit) → canonical lb.
    public static func parseWeightToLb(_ text: String, system: UnitSystem) -> Double? {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        return weightToLb(v, system: system)
    }

    // MARK: - Length / body circumference (canonical: inches)

    /// Display label for a circumference / generic length ("in" / "cm").
    public static func lengthUnit(_ system: UnitSystem) -> String {
        system == .metric ? "cm" : "in"
    }

    /// Format a canonical length (inches) without a unit suffix. Imperial keeps
    /// `decimals` precision in inches; metric converts to cm rounded to whole.
    public static func formatLength(inches: Double, system: UnitSystem, decimals: Int = 1) -> String {
        if system == .metric {
            return String(format: "%.0f", inches * cmPerInch)
        }
        return String(format: "%.\(decimals)f", inches)
    }

    /// Format a canonical length (inches) with its unit suffix.
    public static func formatLengthWithUnit(inches: Double, system: UnitSystem, decimals: Int = 1) -> String {
        "\(formatLength(inches: inches, system: system, decimals: decimals)) \(lengthUnit(system))"
    }

    /// Convert a user-entered length (in the active unit) back to canonical inches.
    public static func lengthToInches(_ displayValue: Double, system: UnitSystem) -> Double {
        system == .metric ? displayValue / cmPerInch : displayValue
    }

    public static func parseLengthToInches(_ text: String, system: UnitSystem) -> Double? {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces)) else { return nil }
        return lengthToInches(v, system: system)
    }

    // MARK: - Height (canonical: inches; imperial shows ft-in, metric shows cm)

    /// Height display label. Imperial uses a composite ft-in glyph so there is
    /// no single suffix; metric is "cm".
    public static func heightUnit(_ system: UnitSystem) -> String {
        system == .metric ? "cm" : "ft-in"
    }

    /// Format a canonical height (inches). Imperial → `5'7"`, metric → `170 cm`.
    public static func formatHeight(inches: Double, system: UnitSystem) -> String {
        if system == .metric {
            return "\(Int((inches * cmPerInch).rounded())) cm"
        }
        let total = Int(inches.rounded())
        return "\(total / 12)'\(total % 12)\""
    }

    // MARK: - Volume (canonical: US fluid ounces)

    /// Display label for volume ("oz" / "mL").
    public static func volumeUnit(_ system: UnitSystem) -> String {
        system == .metric ? "mL" : "oz"
    }

    /// Format a canonical volume (fl oz) for display, without a unit suffix.
    /// Imperial shows whole ounces; metric converts to mL rounded to nearest 10.
    public static func formatVolume(flOz: Double, system: UnitSystem) -> String {
        if system == .metric {
            let ml = (flOz * mlPerFlOz / 10).rounded() * 10
            return String(format: "%.0f", ml)
        }
        return String(format: "%.0f", flOz)
    }

    /// Format a canonical volume (fl oz) with its unit suffix, e.g. "2370 mL".
    public static func formatVolumeWithUnit(flOz: Double, system: UnitSystem) -> String {
        "\(formatVolume(flOz: flOz, system: system)) \(volumeUnit(system))"
    }

    /// Convert a canonical volume (fl oz) into the active system's numeric value.
    public static func volumeValue(flOz: Double, system: UnitSystem) -> Double {
        system == .metric ? flOz * mlPerFlOz : flOz
    }

    /// A natural goal-adjust step in the active system, returned in canonical
    /// fl oz. Imperial steps by the supplied fl oz; metric steps by ~250 mL so
    /// the +/- buttons feel native without changing stored semantics.
    public static func goalStepFlOz(_ imperialStepFlOz: Double, system: UnitSystem) -> Double {
        system == .metric ? 250.0 / mlPerFlOz : imperialStepFlOz
    }

    // MARK: - Distance (canonical: miles)

    public static func distanceUnit(_ system: UnitSystem) -> String {
        system == .metric ? "km" : "mi"
    }

    /// Convert a user-entered distance (in the active unit) back to canonical miles.
    public static func distanceToMiles(_ displayValue: Double, system: UnitSystem) -> Double {
        system == .metric ? displayValue / kmPerMile : displayValue
    }

    public static func parseDistanceToMiles(_ text: String, system: UnitSystem) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let v = Double(trimmed) else { return nil }
        return distanceToMiles(v, system: system)
    }
}
