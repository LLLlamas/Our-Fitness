import XCTest

/// Fixtures are OCR-shaped: one text run per line, in reading order, including
/// the noise Vision actually hands us (% Daily Value columns, dual columns,
/// footnotes). Everything asserted here is a number that was printed.
final class NutritionLabelParserTests: XCTestCase {

    private typealias Parser = NutritionLabelParser
    private typealias Field = NutritionLabelParser.Field

    // MARK: - Fixtures

    /// FDA's standard single-column example panel, with "Calories" and its value
    /// on separate OCR lines.
    private let usPanel = """
    Nutrition Facts
    8 servings per container
    Serving size 2/3 cup (55g)
    Calories
    230
    % Daily Value*
    Total Fat 8g 10%
    Saturated Fat 1g 5%
    Trans Fat 0g
    Cholesterol 0mg 0%
    Sodium 160mg 7%
    Total Carbohydrate 37g 13%
    Dietary Fiber 4g 14%
    Total Sugars 12g
    Includes 10g Added Sugars 20%
    Protein 3g
    Vitamin D 2mcg 10%
    Calcium 260mg 20%
    Iron 8mg 45%
    Potassium 235mg 6%
    * The % Daily Value (DV) tells you how much a nutrient in a serving of food contributes to a daily diet.
    """

    /// Dual-column panel: per serving, then per container. The per-serving column
    /// is printed first, so the first match on each row is the one we want.
    private let dualColumnPanel = """
    Nutrition Facts
    About 2 servings per container
    Serving size 1 cup (240mL)
    Amount per serving    Per container
    Calories 150    300
    Total Fat 8g 10%    16g 21%
    Saturated Fat 5g 25%    10g 50%
    Sodium 140mg 6%    280mg 12%
    Total Carbohydrate 12g 4%    24g 9%
    Dietary Fiber 0g 0%    0g 0%
    Total Sugars 12g    24g
    Protein 8g    16g
    """

    /// EU panel: per 100 g basis, kJ before kcal, decimal commas, salt not sodium.
    private let euPanel = """
    Typical values per 100 g
    Energy 1046 kJ / 250 kcal
    Fat 12,5 g
    of which saturates 3,1 g
    Carbohydrate 20,0 g
    of which sugars 5,0 g
    Fibre 2,5 g
    Protein 15,0 g
    Salt 1,2 g
    """

    /// The suffix-stripping bug this parser replaced turned "140mg" into 0.
    private let milligramPanel = """
    Nutrition Facts
    Serving size 1 package
    Calories 120
    Total Fat 2g
    Sodium 140mg
    Cholesterol 25mg
    Total Carbohydrate 20g
    Protein 5g
    """

    /// Supplement-style panel where every value is printed with a decimal.
    private let decimalPanel = """
    Whey Protein Isolate
    Nutrition Facts
    Serving size 1 scoop (31 g)
    Calories 120.0
    Total Fat 1.5g
    Saturated Fat 0.5g
    Sodium 230.0mg
    Total Carbohydrate 3.5g
    Dietary Fiber 0.5g
    Total Sugars 1.2g
    Protein 24.2g
    """

    private let garbage = """
    BEST BEFORE 12/2026
    Keep refrigerated after opening
    Made in a facility that also handles nuts
    Product of Spain
    """

    // MARK: - US single-column panel

    func test_usPanel_readsEveryPrintedValue() {
        let l = Parser.parse(usPanel)
        XCTAssertTrue(l.isUsable)
        XCTAssertEqual(l.basis, .perServing)
        XCTAssertEqual(l.servingLabel, "2/3 cup (55g)")
        XCTAssertEqual(l.calories, 230)          // number was on the NEXT line
        XCTAssertEqual(l.fatG, 8)
        XCTAssertEqual(l.saturatedFatG, 1)
        XCTAssertEqual(l.cholesterolMg, 0)       // printed zero, not "missing"
        XCTAssertEqual(l.sodiumMg, 160)
        XCTAssertEqual(l.carbsG, 37)
        XCTAssertEqual(l.fiberG, 4)
        XCTAssertEqual(l.totalSugarG, 12)
        XCTAssertEqual(l.addedSugarG, 10)        // "Includes 10g Added Sugars"
        XCTAssertEqual(l.proteinG, 3)
    }

    func test_usPanel_isConsistentAndConfident() {
        let l = Parser.parse(usPanel)
        XCTAssertEqual(l.macrosMatchCalories, true)   // 4·3 + 4·37 + 9·8 = 232 vs 230
        XCTAssertEqual(l.confidence, .high)
        XCTAssertTrue(l.uncertainFields.isEmpty)
    }

    /// No product name on a Nutrition Facts panel — nil, not a nutrient row.
    func test_usPanel_noProductName() {
        XCTAssertNil(Parser.parse(usPanel).foodName)
    }

    /// The % Daily Value footnote must not be mined, and nor must the
    /// "Calories per gram: Fat 9 · Carbohydrate 4 · Protein 4" block.
    func test_footnote_isNotMinedForMacros() {
        let text = """
        Nutrition Facts
        Serving size 1 cup
        Calories 90
        Sodium 300mg
        Calories per gram:
        Fat 9 • Carbohydrate 4 • Protein 4
        """
        let l = Parser.parse(text)
        XCTAssertEqual(l.calories, 90)
        XCTAssertEqual(l.sodiumMg, 300)
        XCTAssertNil(l.fatG)
        XCTAssertNil(l.carbsG)
        XCTAssertNil(l.proteinG)
        XCTAssertNil(l.macrosMatchCalories)   // nothing to check against
    }

    // MARK: - Dual-column panel

    func test_dualColumn_takesPerServingColumn() {
        let l = Parser.parse(dualColumnPanel)
        XCTAssertEqual(l.calories, 150)        // not 300
        XCTAssertEqual(l.fatG, 8)              // not 16
        XCTAssertEqual(l.saturatedFatG, 5)
        XCTAssertEqual(l.sodiumMg, 140)
        XCTAssertEqual(l.carbsG, 12)
        XCTAssertEqual(l.fiberG, 0)            // printed zero
        XCTAssertEqual(l.totalSugarG, 12)
        XCTAssertEqual(l.proteinG, 8)
        XCTAssertNil(l.addedSugarG)            // row absent → nil, not 0
        XCTAssertEqual(l.basis, .perServing)
    }

    // MARK: - EU per-100 g panel

    func test_euPanel_per100gBasisWithKJ() {
        let l = Parser.parse(euPanel)
        XCTAssertEqual(l.basis, .per100g)
        XCTAssertEqual(l.servingLabel, "100 g")
        XCTAssertEqual(l.calories, 250)        // kcal preferred over the 1046 kJ
        XCTAssertEqual(l.fatG, 12.5)           // decimal comma
        XCTAssertEqual(l.saturatedFatG, 3.1)   // "of which saturates"
        XCTAssertEqual(l.carbsG, 20)
        XCTAssertEqual(l.totalSugarG, 5)       // "of which sugars"
        XCTAssertEqual(l.fiberG, 2.5)
        XCTAssertEqual(l.proteinG, 15)
    }

    func test_euPanel_saltConvertsToSodiumAndIsFlagged() {
        let l = Parser.parse(euPanel)
        // 1.2 g salt × 393.4 mg sodium per g salt
        XCTAssertEqual(l.sodiumMg ?? 0, 472.08, accuracy: 0.01)
        XCTAssertTrue(l.uncertainFields.contains(.sodiumMg))
        XCTAssertEqual(l.confidence, .medium)  // consistent, but one derived value
    }

    func test_kilojoulesOnly_convertToCalories() {
        let l = Parser.parse("""
        Nutrition information per 100 g
        Energy 1046 kJ
        Fat 12 g
        Carbohydrate 20 g
        Protein 15 g
        """)
        XCTAssertEqual(l.calories ?? 0, 250, accuracy: 0.001)   // 1046 / 4.184
    }

    // MARK: - Milligram units (the old suffix-stripping bug)

    func test_milligramUnits_areNotLost() {
        let l = Parser.parse(milligramPanel)
        XCTAssertEqual(l.sodiumMg, 140)
        XCTAssertEqual(l.cholesterolMg, 25)
        XCTAssertEqual(l.calories, 120)
        XCTAssertNil(l.fiberG)   // not on this panel
    }

    func test_tokenizer_longestUnitWins() {
        let m = Parser.measures(in: "Sodium 140mg 6%")
        XCTAssertEqual(m.count, 2)
        XCTAssertEqual(m.first, Parser.Measure(value: 140, unit: .milligram))
        XCTAssertEqual(m.last, Parser.Measure(value: 6, unit: .percent))
    }

    func test_tokenizer_thousandsSeparatorAndDecimalComma() {
        XCTAssertEqual(Parser.measures(in: "Sodium 2,000mg").first,
                       Parser.Measure(value: 2000, unit: .milligram))
        XCTAssertEqual(Parser.measures(in: "Fat 2,5 g").first,
                       Parser.Measure(value: 2.5, unit: .gram))
        XCTAssertEqual(Parser.measures(in: "Potassium 1,234.5 mg").first,
                       Parser.Measure(value: 1234.5, unit: .milligram))
    }

    func test_tokenizer_upperBoundIsHalvedAndFlagged() {
        XCTAssertEqual(Parser.measures(in: "Dietary Fiber <1g").first,
                       Parser.Measure(value: 1, unit: .gram, isUpperBound: true))
        let l = Parser.parse("""
        Nutrition Facts
        Calories 100
        Dietary Fiber <1g
        Sodium 50mg
        """)
        XCTAssertEqual(l.fiberG, 0.5)   // midpoint of the "less than 1 g" band
        XCTAssertTrue(l.uncertainFields.contains(.fiberG))
    }

    func test_tokenizer_digitGluedToWordIsNotAValue() {
        // "B12" is part of the nutrient name; only the 2 mcg is a number.
        let m = Parser.measures(in: "Vitamin B12 2mcg 83%")
        XCTAssertEqual(m.first, Parser.Measure(value: 2, unit: .microgram))
    }

    // MARK: - Decimals

    func test_decimals_areNotTruncated() {
        let l = Parser.parse(decimalPanel)
        XCTAssertEqual(l.calories, 120)
        XCTAssertEqual(l.fatG, 1.5)
        XCTAssertEqual(l.saturatedFatG, 0.5)
        XCTAssertEqual(l.sodiumMg, 230)     // "230.0mg" used to parse as 0
        XCTAssertEqual(l.carbsG, 3.5)
        XCTAssertEqual(l.fiberG, 0.5)
        XCTAssertEqual(l.totalSugarG, 1.2)
        XCTAssertEqual(l.proteinG, 24.2)    // not 24
        XCTAssertEqual(l.foodName, "Whey Protein Isolate")
    }

    // MARK: - Garbage / non-label text

    func test_garbage_isNotALabelAndYieldsNothing() {
        XCTAssertFalse(Parser.looksLikeNutritionLabel(garbage))
        let l = Parser.parse(garbage)
        XCTAssertFalse(l.isUsable)
        XCTAssertNil(l.calories)
        XCTAssertNil(l.proteinG)
        XCTAssertNil(l.sodiumMg)
        XCTAssertEqual(l.confidence, .low)
    }

    func test_looksLikeNutritionLabel_gatesAutoCapture() {
        XCTAssertTrue(Parser.looksLikeNutritionLabel(usPanel))
        XCTAssertTrue(Parser.looksLikeNutritionLabel(euPanel))
        XCTAssertTrue(Parser.looksLikeNutritionLabel(dualColumnPanel))
        // An energy word alone isn't a panel.
        XCTAssertFalse(Parser.looksLikeNutritionLabel("Calories burned today: 430"))
        XCTAssertFalse(Parser.looksLikeNutritionLabel(""))
    }

    // MARK: - Consistency check (4/4/9)

    func test_atwaterMismatch_flagsLowConfidence() {
        let l = Parser.parse("""
        Nutrition Facts
        Calories 100
        Total Fat 20g
        Total Carbohydrate 50g
        Protein 30g
        """)
        XCTAssertEqual(l.macrosMatchCalories, false)   // 500 cal of macros vs 100 printed
        XCTAssertEqual(l.confidence, .low)
        XCTAssertTrue(l.uncertainFields.isSuperset(of: [.calories, .proteinG, .carbsG, .fatG]))
    }

    func test_atwaterHelper() {
        XCTAssertEqual(Parser.atwaterCalories(proteinG: 3, carbsG: 37, fatG: 8), 232)
        XCTAssertNil(Parser.atwaterCalories(proteinG: 3, carbsG: nil, fatG: 8))
    }

    // MARK: - Cross-check against a second read

    func test_crossCheck_fillsGapsAndFlagsDisagreement() {
        let parsed = Parser.parse(milligramPanel)
        var ai = parsed
        ai.sodiumMg = 440          // AI misread the sodium row
        ai.fiberG = 3              // AI found a row the tokenizer missed
        let result = Parser.crossCheck(parsed, against: ai)

        XCTAssertEqual(result.merged.sodiumMg, 140)      // parser stays the source of truth
        XCTAssertTrue(result.disagreements.contains(.sodiumMg))
        XCTAssertEqual(result.merged.fiberG, 3)          // gap filled from the cross-check
        XCTAssertTrue(result.filled.contains(.fiberG))
        XCTAssertTrue(result.merged.uncertainFields.isSuperset(of: [.sodiumMg, .fiberG]))
    }

    func test_crossCheck_agreementWithinLabelRounding() {
        let parsed = Parser.parse(usPanel)
        var ai = parsed
        ai.calories = 235          // within the ±10 cal agreement band
        ai.proteinG = 3.4          // within ±1 g
        let result = Parser.crossCheck(parsed, against: ai)
        XCTAssertTrue(result.disagreements.isEmpty)
        XCTAssertEqual(result.merged.confidence, .high)
    }
}
