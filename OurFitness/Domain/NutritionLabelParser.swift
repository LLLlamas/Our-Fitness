// Nutrition Facts label parser: OCR'd label text → the numbers that were printed.
//
// Pure Domain (no SwiftUI / SwiftData / Vision) so the camera scanner's entire
// understanding of label layout is unit-testable hostlessly. The view only
// renders, edits, and scales what comes out of here.
//
// Rules this file holds itself to:
//   • Absent ≠ zero. Every nutrient is Optional; nil means "not printed, or not
//     read". The old "0 if not found" made a real 0 g fat indistinguishable from
//     a missed row.
//   • Never invent a number. Values are read, unit-converted (kJ→cal, g↔mg,
//     salt→sodium), or left nil — never estimated.
//   • Longest-unit-first tokenizing, so "140mg" reads as 140 mg instead of the
//     old suffix-stripping order turning it into "140m" → 0.
//   • Nothing is truncated. Doubles stay Doubles; the caller rounds once, at the
//     PerServing boundary.
//
// Unit conversions used (all exact definitions, not estimates):
//   1 kcal = 4.184 kJ · 1 g = 1,000 mg = 1,000,000 mcg
//   1 g salt ≈ 393.4 mg sodium (Na/NaCl molar mass ratio 22.99 / 58.44)

import Foundation

public enum NutritionLabelParser {

    // MARK: - Types

    /// What the column we read represents. EU panels print per 100 g; we report
    /// the basis rather than silently rescaling someone's serving.
    public enum Basis: String, Codable, Sendable {
        case perServing
        case per100g
    }

    public enum Confidence: String, Codable, Sendable {
        case high, medium, low
    }

    /// Addressable nutrient fields, so callers can mark/highlight single values.
    public enum Field: String, CaseIterable, Codable, Sendable {
        case calories, proteinG, carbsG, fatG, saturatedFatG
        case fiberG, totalSugarG, addedSugarG, sodiumMg, cholesterolMg
    }

    public enum Unit: String, Sendable {
        case none, gram, milligram, microgram, kilocalorie, kilojoule, percent
    }

    /// One number read off a line, carrying whatever unit was printed beside it.
    public struct Measure: Equatable, Sendable {
        public var value: Double
        public var unit: Unit
        /// The label printed "<1 g" — the true value is somewhere inside (0, 1).
        public var isUpperBound: Bool

        public init(value: Double, unit: Unit, isUpperBound: Bool = false) {
            self.value = value
            self.unit = unit
            self.isUpperBound = isUpperBound
        }
    }

    /// Everything we could read off one panel. All nutrients optional by design.
    public struct Label: Equatable, Sendable {
        public var foodName: String?
        public var servingLabel: String?
        public var basis: Basis
        public var calories: Double?
        public var proteinG: Double?
        public var carbsG: Double?
        public var fatG: Double?
        public var saturatedFatG: Double?
        public var fiberG: Double?
        public var totalSugarG: Double?
        public var addedSugarG: Double?
        public var sodiumMg: Double?
        public var cholesterolMg: Double?
        /// 4·protein + 4·carbs + 9·fat ≈ printed calories. nil when calories or
        /// any of the three macros is missing, so no check was possible.
        public var macrosMatchCalories: Bool?
        public var confidence: Confidence
        /// Fields a human should re-read: bounded ("<1 g"), printed without a
        /// unit, derived (salt→sodium), filled in by the cross-check, or
        /// contradicted by it.
        public var uncertainFields: Set<Field>

        public init(
            foodName: String? = nil,
            servingLabel: String? = nil,
            basis: Basis = .perServing,
            calories: Double? = nil,
            proteinG: Double? = nil,
            carbsG: Double? = nil,
            fatG: Double? = nil,
            saturatedFatG: Double? = nil,
            fiberG: Double? = nil,
            totalSugarG: Double? = nil,
            addedSugarG: Double? = nil,
            sodiumMg: Double? = nil,
            cholesterolMg: Double? = nil,
            macrosMatchCalories: Bool? = nil,
            confidence: Confidence = .low,
            uncertainFields: Set<Field> = []
        ) {
            self.foodName = foodName
            self.servingLabel = servingLabel
            self.basis = basis
            self.calories = calories
            self.proteinG = proteinG
            self.carbsG = carbsG
            self.fatG = fatG
            self.saturatedFatG = saturatedFatG
            self.fiberG = fiberG
            self.totalSugarG = totalSugarG
            self.addedSugarG = addedSugarG
            self.sodiumMg = sodiumMg
            self.cholesterolMg = cholesterolMg
            self.macrosMatchCalories = macrosMatchCalories
            self.confidence = confidence
            self.uncertainFields = uncertainFields
        }

        public static let empty = Label()

        /// Worth showing a confirm screen for. Matches how the rest of the app
        /// gates saving a food log: no calories, no entry.
        public var isUsable: Bool { (calories ?? 0) > 0 }

        public func value(for field: Field) -> Double? {
            switch field {
            case .calories:      return calories
            case .proteinG:      return proteinG
            case .carbsG:        return carbsG
            case .fatG:          return fatG
            case .saturatedFatG: return saturatedFatG
            case .fiberG:        return fiberG
            case .totalSugarG:   return totalSugarG
            case .addedSugarG:   return addedSugarG
            case .sodiumMg:      return sodiumMg
            case .cholesterolMg: return cholesterolMg
            }
        }

        public mutating func set(_ value: Double?, for field: Field) {
            switch field {
            case .calories:      calories = value
            case .proteinG:      proteinG = value
            case .carbsG:        carbsG = value
            case .fatG:          fatG = value
            case .saturatedFatG: saturatedFatG = value
            case .fiberG:        fiberG = value
            case .totalSugarG:   totalSugarG = value
            case .addedSugarG:   addedSugarG = value
            case .sodiumMg:      sodiumMg = value
            case .cholesterolMg: cholesterolMg = value
            }
        }
    }

    /// Result of reconciling two independent reads of the same panel.
    public struct CrossCheck: Equatable, Sendable {
        /// `primary`'s numbers, plus anything only `other` found.
        public var merged: Label
        /// Fields where both reads had a value and they materially disagree.
        public var disagreements: Set<Field>
        /// Fields `primary` missed and `other` supplied.
        public var filled: Set<Field>

        public init(merged: Label, disagreements: Set<Field> = [], filled: Set<Field> = []) {
            self.merged = merged
            self.disagreements = disagreements
            self.filled = filled
        }
    }

    // MARK: - Entry points

    /// True when the text plausibly IS a nutrition panel. Gates auto-capture so
    /// the live scanner doesn't fire on a cereal box slogan that held still.
    public static func looksLikeNutritionLabel(_ text: String) -> Bool {
        let lower = text.lowercased()
        for header in ["nutrition facts", "nutritional information", "nutrition information",
                       "nutritional values", "typical values"] {
            if lower.contains(header) { return true }
        }
        let hasEnergy = ["calorie", "energy", "kcal", "kj"].contains { lower.contains($0) }
        guard hasEnergy else { return false }
        let nutrients = ["protein", "carbohydrate", "carbs", "fat", "saturate", "sodium",
                         "salt", "fiber", "fibre", "sugar", "cholesterol", "serving size"]
        return nutrients.filter { lower.contains($0) }.count >= 3
    }

    /// Read a panel. Always returns a Label — check `isUsable` before trusting it.
    public static func parse(_ text: String) -> Label {
        let lines = contentLines(text)
        guard !lines.isEmpty else { return .empty }
        let lower = lines.map { $0.lowercased() }

        var uncertain: Set<Field> = []

        // Reads one field and records why it might need a human look.
        func read(_ field: Field, _ keywords: [String], prefer: Unit,
                  excluding: [String] = [], allowNextLine: Bool = false,
                  flagUnitless: Bool = true) -> Double? {
            guard let m = measure(forKeywords: keywords, in: lower, prefer: prefer,
                                  excluding: excluding, allowNextLine: allowNextLine)
            else { return nil }
            if m.isUpperBound || (flagUnitless && m.unit == .none) { uncertain.insert(field) }
            guard let v = convert(m, to: prefer) else { return nil }
            // "<1 g" means the real value sits in (0, 1) — take the midpoint and
            // flag it rather than pretending the printed bound is the value.
            return m.isUpperBound ? v / 2 : v
        }

        // Calories: unit-less on US panels (so don't flag that), kJ-first in the
        // EU, and frequently on the line AFTER the word on a tall US panel.
        let calories = read(.calories, ["calories", "energy", "kcal"],
                            prefer: .kilocalorie,
                            excluding: ["calories from", "calories per gram"],
                            allowNextLine: true, flagUnitless: false)

        let fatG = read(.fatG, ["total fat", "total lipid", "fat"], prefer: .gram,
                        excluding: ["calories from fat", "saturate", "trans", "unsaturated"])
        let satFatG = read(.saturatedFatG,
                           ["saturated fat", "sat fat", "of which saturates", "saturates", "saturated"],
                           prefer: .gram, excluding: ["polyunsaturated", "monounsaturated"])
        let carbsG = read(.carbsG,
                          ["total carbohydrate", "total carb", "carbohydrate", "carbs"],
                          prefer: .gram)
        let fiberG = read(.fiberG, ["dietary fiber", "dietary fibre", "fiber", "fibre"], prefer: .gram)
        let totalSugarG = read(.totalSugarG,
                               ["total sugars", "of which sugars", "total sugar", "sugars", "sugar"],
                               prefer: .gram, excluding: ["added", "includes", "sugar alcohol"])
        let addedSugarG = read(.addedSugarG, ["added sugars", "added sugar", "includes"], prefer: .gram)
        let proteinG = read(.proteinG, ["protein"], prefer: .gram)
        let cholesterolMg = read(.cholesterolMg, ["cholesterol", "cholest"], prefer: .milligram)

        var sodiumMg = read(.sodiumMg, ["sodium"], prefer: .milligram)
        if sodiumMg == nil,
           let salt = measure(forKeywords: ["salt"], in: lower, prefer: .gram),
           let saltG = convert(salt, to: .gram) {
            // EU panels print salt, not sodium.
            sodiumMg = saltG * saltToSodiumMg
            uncertain.insert(.sodiumMg)
        }

        let basis = detectBasis(lower)
        let label = Label(
            foodName: productName(lines),
            servingLabel: servingSize(lines) ?? (basis == .per100g ? "100 g" : nil),
            basis: basis,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            saturatedFatG: satFatG,
            fiberG: fiberG,
            totalSugarG: totalSugarG,
            addedSugarG: addedSugarG,
            sodiumMg: sodiumMg,
            cholesterolMg: cholesterolMg,
            uncertainFields: uncertain
        )
        return validated(label)
    }

    /// Atwater energy from macros. nil unless all three are present.
    public static func atwaterCalories(proteinG: Double?, carbsG: Double?, fatG: Double?) -> Double? {
        guard let p = proteinG, let c = carbsG, let f = fatG else { return nil }
        return 4 * p + 4 * c + 9 * f
    }

    /// Recompute `macrosMatchCalories` and `confidence` from the current values.
    /// Call after editing a Label by hand (e.g. one built from an AI response).
    public static func validated(_ label: Label) -> Label {
        var out = label
        var match: Bool? = nil
        if let expected = atwaterCalories(proteinG: out.proteinG, carbsG: out.carbsG, fatG: out.fatG),
           let printed = out.calories, printed > 0 {
            // Panels round each macro to the nearest gram and calories to the
            // nearest 5–10, and fibre / sugar alcohols aren't full 4 cal/g — so
            // a correct read can still miss by a chunk. Beyond this, something
            // was misread.
            let tolerance = max(25.0, printed * 0.2)
            match = abs(expected - printed) <= tolerance
        }
        out.macrosMatchCalories = match
        if match == false {
            // Any one of the four could be the bad read; flag them all.
            out.uncertainFields.formUnion([.calories, .proteinG, .carbsG, .fatG])
        }

        let haveCore = out.calories != nil && out.proteinG != nil && out.carbsG != nil && out.fatG != nil
        if !out.isUsable || match == false {
            out.confidence = .low
        } else if haveCore, match == true, out.uncertainFields.isEmpty {
            out.confidence = .high
        } else {
            out.confidence = .medium
        }
        return out
    }

    /// Reconcile two reads of the same panel. `primary` wins every contest; the
    /// other read only fills gaps and raises flags.
    public static func crossCheck(_ primary: Label, against other: Label) -> CrossCheck {
        var merged = primary
        var disagreements: Set<Field> = []
        var filled: Set<Field> = []

        for field in Field.allCases {
            let mine = primary.value(for: field)
            let theirs = other.value(for: field)
            switch (mine, theirs) {
            case (nil, .some(let v)):
                merged.set(v, for: field)
                filled.insert(field)
                merged.uncertainFields.insert(field)
            case (.some(let a), .some(let b)):
                if !agrees(a, b, for: field) {
                    disagreements.insert(field)
                    merged.uncertainFields.insert(field)
                }
            default:
                break
            }
        }

        if merged.foodName == nil { merged.foodName = other.foodName }
        if merged.servingLabel == nil { merged.servingLabel = other.servingLabel }

        return CrossCheck(merged: validated(merged), disagreements: disagreements, filled: filled)
    }

    // MARK: - Tokenizer

    /// Every number on a line, with its printed unit. Public for tests.
    public static func measures(in line: String) -> [Measure] {
        let chars = Array(line.lowercased())
        var out: [Measure] = []
        var i = 0
        while i < chars.count {
            guard isDigit(chars[i]) else { i += 1; continue }

            // A digit glued to the tail of a word belongs to that word ("b12").
            if i > 0, chars[i - 1].isLetter {
                while i < chars.count, isDigit(chars[i]) { i += 1 }
                continue
            }

            // "<" / "≤" just before the number (one space allowed) = upper bound.
            var upperBound = false
            var back = i - 1
            while back >= 0, chars[back] == " " { back -= 1 }
            if back >= 0, chars[back] == "<" || chars[back] == "\u{2264}" { upperBound = true }

            var body = ""
            var j = i
            while j < chars.count, isDigit(chars[j]) || chars[j] == "," || chars[j] == "." {
                body.append(chars[j]); j += 1
            }

            // Optional space between the number and its unit, then longest match.
            var k = j
            while k < chars.count, chars[k] == " " { k += 1 }
            var unit = Unit.none
            for (spelling, u) in orderedUnits {
                let sp = Array(spelling)
                guard k + sp.count <= chars.count, Array(chars[k..<(k + sp.count)]) == sp else { continue }
                let after = k + sp.count
                guard after == chars.count || !chars[after].isLetter else { continue }
                unit = u
                j = after
                break
            }

            if let v = numericValue(body) {
                out.append(Measure(value: v, unit: unit, isUpperBound: upperBound))
            }
            i = max(j, i + 1)
        }
        return out
    }

    /// Non-empty, trimmed lines, cut off at the panel's footnote block (the
    /// "Calories per gram: Fat 9 · Carbohydrate 4 · Protein 4" line would
    /// otherwise answer every keyword search with nonsense).
    public static func contentLines(_ text: String) -> [String] {
        var out: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            if footnoteMarkers.contains(where: { lower.contains($0) }) { break }
            out.append(line)
        }
        return out
    }

    // MARK: - Internals

    private static let saltToSodiumMg = 393.4

    private static let footnoteMarkers = [
        "calories per gram", "daily value tells", "dv tells", "value (dv) tells"
    ]

    /// Unit spellings, longest first — the whole point of the rewrite.
    private static let orderedUnits: [(String, Unit)] = [
        ("kilocalories", .kilocalorie), ("kilocalorie", .kilocalorie),
        ("milligrams", .milligram), ("milligram", .milligram),
        ("micrograms", .microgram), ("microgram", .microgram),
        ("kilojoules", .kilojoule), ("kilojoule", .kilojoule),
        ("calories", .kilocalorie), ("calorie", .kilocalorie),
        ("grams", .gram), ("gram", .gram),
        ("kcal", .kilocalorie), ("mcg", .microgram),
        ("cal", .kilocalorie),
        ("\u{00B5}g", .microgram), ("ug", .microgram),
        ("kj", .kilojoule), ("mg", .milligram),
        ("g", .gram), ("%", .percent)
    ]

    private static func isDigit(_ c: Character) -> Bool { c.isASCII && c.isNumber }

    /// "2,000" → 2000 · "2,5" → 2.5 · "1,234.5" → 1234.5
    private static func numericValue(_ raw: String) -> Double? {
        var s = raw
        while let last = s.last, last == "," || last == "." { s.removeLast() }
        guard !s.isEmpty else { return nil }
        let hasComma = s.contains(",")
        let hasDot = s.contains(".")
        if hasComma && hasDot {
            s = s.replacingOccurrences(of: ",", with: "")           // thousands + decimal point
        } else if hasComma {
            let groups = s.split(separator: ",", omittingEmptySubsequences: false)
            if groups.count >= 2, groups.dropFirst().allSatisfy({ $0.count == 3 }) {
                s = s.replacingOccurrences(of: ",", with: "")       // 2,000
            } else {
                s = s.replacingOccurrences(of: ",", with: ".")      // 2,5
            }
        }
        return Double(s)
    }

    private static func convertibleUnits(for prefer: Unit) -> [Unit] {
        switch prefer {
        case .gram:        return [.milligram, .microgram]
        case .milligram:   return [.gram, .microgram]
        case .kilocalorie: return [.kilojoule]
        default:           return []
        }
    }

    private static func convert(_ m: Measure, to unit: Unit) -> Double? {
        switch (m.unit, unit) {
        case (.percent, _):                     return nil
        case (.none, _):                        return m.value
        case (.gram, .gram),
             (.milligram, .milligram),
             (.microgram, .microgram),
             (.kilocalorie, .kilocalorie):      return m.value
        case (.milligram, .gram):               return m.value / 1_000
        case (.microgram, .gram):               return m.value / 1_000_000
        case (.gram, .milligram):               return m.value * 1_000
        case (.microgram, .milligram):          return m.value / 1_000
        case (.kilojoule, .kilocalorie):        return m.value / 4.184
        default:                                return nil
        }
    }

    private static func pick(from measures: [Measure], prefer: Unit) -> Measure? {
        if let exact = measures.first(where: { $0.unit == prefer }) { return exact }
        for alt in convertibleUnits(for: prefer) {
            if let m = measures.first(where: { $0.unit == alt }) { return m }
        }
        return measures.first(where: { $0.unit == .none })
    }

    /// First number matching `prefer` on the first line carrying one of the
    /// keywords. Dual-column panels print per-serving first, so taking the first
    /// match is also what picks the per-serving column.
    private static func measure(forKeywords keywords: [String],
                                in lowerLines: [String],
                                prefer: Unit,
                                excluding: [String] = [],
                                allowNextLine: Bool = false) -> Measure? {
        for keyword in keywords {
            for (idx, line) in lowerLines.enumerated() {
                guard line.contains(keyword) else { continue }
                guard !excluding.contains(where: { line.contains($0) }) else { continue }
                if let m = pick(from: measures(in: line), prefer: prefer) { return m }
                if allowNextLine,
                   let next = lowerLines.dropFirst(idx + 1).first,
                   let m = pick(from: measures(in: next), prefer: prefer) {
                    return m
                }
            }
        }
        return nil
    }

    private static func detectBasis(_ lowerLines: [String]) -> Basis {
        let joined = lowerLines.joined(separator: " ")
        for marker in ["per 100 g", "per 100g", "per 100 ml", "per 100ml", "/100 g", "/100g"] {
            if joined.contains(marker) { return .per100g }
        }
        return .perServing
    }

    private static let headerFragments = [
        "nutrition facts", "nutrition information", "nutritional information",
        "nutritional values", "typical values", "amount per", "daily value",
        "serving size", "servings per", "per container", "per 100", "ingredients",
        "not a significant source"
    ]

    /// Row labels that carry no number of their own (the value OCR'd onto the
    /// next line) — a bare one of these is a panel row, not a product name.
    private static let bareNutrientNames: Set<String> = [
        "calories", "energy", "protein", "fat", "total fat", "saturated fat",
        "trans fat", "cholesterol", "sodium", "salt", "carbohydrate",
        "total carbohydrate", "carbohydrates", "dietary fiber", "fiber", "fibre",
        "sugars", "total sugars", "added sugars", "includes added sugars",
        "vitamin d", "calcium", "iron", "potassium"
    ]

    /// The product name is rarely on the Nutrition Facts panel. Take the first
    /// line that reads like words — no numbers, not a structural header, not a
    /// bare nutrient row label — and otherwise return nil rather than guessing a
    /// nutrient row (the confirm screen has a name field for exactly this).
    private static func productName(_ lines: [String]) -> String? {
        for line in lines {
            guard !line.contains(where: { isDigit($0) }) else { continue }
            guard line.filter({ $0.isLetter }).count >= 3 else { continue }
            let lower = line.lowercased()
            guard !headerFragments.contains(where: { lower.contains($0) }) else { continue }
            guard !bareNutrientNames.contains(rowName(lower)) else { continue }
            return line
        }
        return nil
    }

    /// Letters and single spaces only, so "Protein:" and "• Protein" both
    /// normalise to "protein".
    private static func rowName(_ lower: String) -> String {
        let letters = lower.map { $0.isLetter ? $0 : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    private static func servingSize(_ lines: [String]) -> String? {
        for (idx, line) in lines.enumerated() {
            guard let r = line.range(of: "serving size", options: .caseInsensitive) else { continue }
            let tail = String(line[r.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: ": \t"))
            if !tail.isEmpty { return tail }
            if let next = lines.dropFirst(idx + 1).first { return next }
        }
        return nil
    }

    /// Two reads of the same field are "the same number" within label rounding.
    private static func agrees(_ a: Double, _ b: Double, for field: Field) -> Bool {
        let absolute: Double
        switch field {
        case .calories:                      absolute = 10
        case .sodiumMg, .cholesterolMg:      absolute = 10
        default:                             absolute = 1
        }
        return abs(a - b) <= max(absolute, 0.1 * max(abs(a), abs(b)))
    }
}
